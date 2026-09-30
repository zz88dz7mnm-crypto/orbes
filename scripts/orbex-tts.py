#!/usr/bin/env python3
# ORBEX — helper de voz de Orbi (Kokoro, local).
#
# Partes adaptadas de OpenJarvis `src/openjarvis/speech/kokoro_tts.py`
# (Copyright 2025 The OpenJarvis Authors, Apache License 2.0; ver THIRD_PARTY_NOTICES.md).
# Cambios: proceso de larga vida que habla JSON por stdin/stdout, un solo KModel compartido,
# salida a archivos WAV temporales, modo --selftest para el instalador, CPU por defecto.
#
# Protocolo (una línea JSON por pedido y por respuesta; stdout lleva SOLO el protocolo):
#   arranque  → {"ready": true}             (o {"ready": false, "error": "..."} y sale)
#   pedido    ← {"text": "¡Hola!", "voice": "ef_dora", "speed": 1.0}
#   respuesta → {"ok": true, "path": "/…/orbex-tts-1.wav", "duration": 1.23}
#               {"ok": false, "error": "..."}
#   pedido    ← {"cmd": "ping"}   → {"ok": true}
# Sale solo cuando se cierra stdin (la app terminó).

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import threading
from collections import OrderedDict

# stdout real solo para el protocolo; todo lo que imprima Kokoro/torch va a stderr.
_PROTO = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
os.dup2(2, 1)
sys.stdout = sys.stderr

SAMPLE_RATE = 24000
DEFAULT_VOICE = "ef_dora"

# Prefijo de la voz → lang_code de Kokoro (como en OpenJarvis).
_VOICE_PREFIX_TO_LANG = {
    "a": "a", "b": "b", "z": "z", "j": "j", "f": "f",
    "i": "i", "p": "p", "h": "h", "e": "e",
}


def _lang_for_voice(voice_id: str) -> str:
    if not voice_id:
        return "e"
    return _VOICE_PREFIX_TO_LANG.get(voice_id[:1], "e")


class KokoroVoice:
    """Un KModel compartido y un LRU chico de KPipeline por idioma (idea de OpenJarvis)."""

    def __init__(self, device: str = "cpu", max_pipelines: int = 3) -> None:
        self._device = device
        self._max = max_pipelines
        self._model = None
        self._pipelines: "OrderedDict[str, object]" = OrderedDict()
        self._lock = threading.RLock()

    def _ensure_model(self):
        if self._model is not None:
            return self._model
        from kokoro import KModel

        device = self._device
        if device == "auto":
            try:
                import torch
                if getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
                    device = "mps"
                else:
                    device = "cpu"
            except ImportError:
                device = "cpu"
        self._model = KModel().to(device).eval()
        return self._model

    def _pipeline(self, lang_code: str):
        with self._lock:
            p = self._pipelines.get(lang_code)
            if p is not None:
                self._pipelines.move_to_end(lang_code)
                return p
            from kokoro import KPipeline

            p = KPipeline(lang_code=lang_code, model=self._ensure_model())
            self._pipelines[lang_code] = p
            if len(self._pipelines) > self._max:
                self._pipelines.popitem(last=False)
            return p

    def synthesize(self, text: str, voice: str, speed: float):
        import numpy as np

        lang = _lang_for_voice(voice)
        with self._lock:
            pipeline = self._pipeline(lang)
            chunks = []
            for _, _, audio in pipeline(text, voice=voice, speed=speed):
                if audio is None:
                    continue
                if hasattr(audio, "detach"):
                    audio = audio.detach().cpu().numpy()
                chunks.append(audio)
        if not chunks:
            return None
        return np.concatenate(chunks)


def _write_wav(path: str, samples) -> float:
    import soundfile as sf

    sf.write(path, samples, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    return float(len(samples)) / SAMPLE_RATE


def _send(obj) -> None:
    _PROTO.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _PROTO.flush()


def _serve(engine: KokoroVoice, outdir: str, warm_voice: str) -> int:
    os.makedirs(outdir, exist_ok=True)
    try:
        # Calentar: carga el modelo y la voz para que el primer pedido sea rápido.
        engine.synthesize("Hola.", warm_voice, 1.0)
    except Exception as exc:  # noqa: BLE001
        _send({"ready": False, "error": f"{type(exc).__name__}: {exc}"})
        return 1
    _send({"ready": True})

    counter = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            _send({"ok": False, "error": "JSON inválido"})
            continue
        if req.get("cmd") == "ping":
            _send({"ok": True})
            continue
        text = str(req.get("text", "")).strip()
        voice = str(req.get("voice") or DEFAULT_VOICE)
        try:
            speed = float(req.get("speed", 1.0))
        except (TypeError, ValueError):
            speed = 1.0
        speed = min(max(speed, 0.5), 2.0)
        if not text:
            _send({"ok": False, "error": "texto vacío"})
            continue
        try:
            samples = engine.synthesize(text, voice, speed)
            if samples is None:
                _send({"ok": False, "error": "sin audio"})
                continue
            counter += 1
            path = os.path.join(outdir, f"orbex-tts-{os.getpid()}-{counter}.wav")
            duration = _write_wav(path, samples)
            _send({"ok": True, "path": path, "duration": duration})
        except Exception as exc:  # noqa: BLE001
            _send({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
    return 0


def _selftest(engine: KokoroVoice, voice: str, out: str) -> int:
    samples = engine.synthesize("¡Hola! Soy Orbi. Ya puedo hablar con vos.", voice, 1.0)
    if samples is None:
        print("Kokoro no devolvió audio.", file=sys.stderr)
        return 1
    duration = _write_wav(out, samples)
    _send({"ok": True, "path": out, "duration": duration})
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Helper de voz de ORBEX (Kokoro)")
    ap.add_argument("--outdir", default=os.path.join(tempfile.gettempdir(), "orbex-voz"))
    ap.add_argument("--voice", default=DEFAULT_VOICE)
    ap.add_argument("--device", default=os.environ.get("ORBEX_TTS_DEVICE", "cpu"))
    ap.add_argument("--selftest", action="store_true", help="sintetiza una frase y sale")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "orbex-voz-prueba.wav"))
    args = ap.parse_args()

    try:
        import kokoro  # noqa: F401
        import soundfile  # noqa: F401
    except ImportError as exc:
        msg = f"Falta un paquete ({exc}). Corré scripts/instalar-voz.sh."
        if args.selftest:
            print(msg, file=sys.stderr)
        else:
            _send({"ready": False, "error": msg})
        return 2

    engine = KokoroVoice(device=args.device)
    if args.selftest:
        try:
            return _selftest(engine, args.voice, args.out)
        except Exception as exc:  # noqa: BLE001
            print(f"Error: {type(exc).__name__}: {exc}", file=sys.stderr)
            return 1
    return _serve(engine, args.outdir, args.voice)


if __name__ == "__main__":
    sys.exit(main())
