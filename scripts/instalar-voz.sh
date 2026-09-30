#!/bin/bash
# ORBEX — instala la voz natural de Orbi (Kokoro, local, sin internet al hablar).
#
#   ./scripts/instalar-voz.sh          # pregunta antes de instalar cosas con Homebrew
#   ./scripts/instalar-voz.sh --si     # responde "sí" a todo
#
# Qué hace (se puede correr las veces que quieras; lo que ya está, lo saltea):
#   1. busca Python 3.10–3.12 (Kokoro todavía no anda con 3.13); si falta, ofrece instalarlo con Homebrew
#   2. ofrece instalar espeak-ng con Homebrew si no está (lo usa Kokoro para el español)
#   3. crea el entorno en ~/Library/Application Support/ORBEX/voz/venv e instala kokoro + soundfile
#   4. copia el helper (scripts/orbex-tts.py) a esa carpeta
#   5. la primera vez descarga el modelo (~330 MB) y prueba la voz "ef_dora"
# Compatible con el bash 3.2 de macOS.

set -u

SI=0
for arg in "$@"; do
    case "$arg" in
        --si|-y|--yes) SI=1 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Opción desconocida: $arg (usá --si o --help)"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SRC="$SCRIPT_DIR/orbex-tts.py"
DEST="$HOME/Library/Application Support/ORBEX/voz"
VENV="$DEST/venv"
VOZ="ef_dora"

paso() { printf '\n\033[1;35m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
aviso(){ printf '  \033[33m!\033[0m %s\n' "$1"; }
falla(){ printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

preguntar() {
    # preguntar "¿Texto?" → 0 si dice que sí
    if [ "$SI" -eq 1 ]; then return 0; fi
    printf '  %s [s/N] ' "$1"
    read -r resp
    case "$resp" in
        s|S|si|SI|Si|sí|Sí|y|Y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

version_ok() {
    # version_ok /ruta/python → 0 si es 3.10, 3.11 o 3.12
    "$1" -c 'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)' >/dev/null 2>&1
}

BREW=""
if command -v brew >/dev/null 2>&1; then
    BREW="$(command -v brew)"
elif [ -x /opt/homebrew/bin/brew ]; then
    BREW=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
    BREW=/usr/local/bin/brew
fi

echo "Voz natural de Orbi (Kokoro)"
echo "Todo queda en: $DEST"

[ -f "$HELPER_SRC" ] || falla "No encuentro $HELPER_SRC (corré el script desde la carpeta de ORBEX)."

# 1. Python ---------------------------------------------------------------
paso "Python 3.10–3.12"
buscar_python() {
    for v in 3.12 3.11 3.10; do
        for p in "/opt/homebrew/bin/python$v" "/usr/local/bin/python$v" "$(command -v "python$v" 2>/dev/null)"; do
            if [ -n "$p" ] && [ -x "$p" ] && version_ok "$p"; then echo "$p"; return 0; fi
        done
    done
    p="$(command -v python3 2>/dev/null)"
    if [ -n "$p" ] && version_ok "$p"; then echo "$p"; return 0; fi
    return 1
}

PY=""
if [ -x "$VENV/bin/python" ] && version_ok "$VENV/bin/python"; then
    ok "El entorno ya existe ($("$VENV/bin/python" --version 2>&1))"
else
    PY="$(buscar_python || true)"
    if [ -z "$PY" ]; then
        aviso "No encontré Python 3.10–3.12 (Kokoro no anda con el 3.9 de macOS ni con 3.13)."
        if [ -n "$BREW" ] && preguntar "¿Instalo Python 3.12 con Homebrew?"; then
            "$BREW" install python@3.12 || falla "No se pudo instalar Python con Homebrew."
            PY="$(buscar_python || true)"
        fi
        [ -n "$PY" ] || falla "Instalá Python 3.12 (por ejemplo: brew install python@3.12) y volvé a correr este script."
    fi
    ok "Uso $PY ($("$PY" --version 2>&1))"
fi

# 2. espeak-ng ------------------------------------------------------------
paso "espeak-ng (pronunciación en español)"
if command -v espeak-ng >/dev/null 2>&1 || [ -x /opt/homebrew/bin/espeak-ng ] || [ -x /usr/local/bin/espeak-ng ]; then
    ok "espeak-ng ya está"
elif [ -n "$BREW" ]; then
    if preguntar "¿Instalo espeak-ng con Homebrew?"; then
        "$BREW" install espeak-ng || aviso "No se pudo instalar espeak-ng; Kokoro va a intentar con el que trae incluido."
    else
        aviso "Sigo sin espeak-ng; Kokoro va a intentar con el que trae incluido."
    fi
else
    aviso "No hay Homebrew; sigo sin espeak-ng (Kokoro trae uno incluido)."
fi

# 3. Entorno + paquetes ---------------------------------------------------
paso "Entorno de Python y paquetes (kokoro, soundfile)"
mkdir -p "$DEST" || falla "No pude crear $DEST"
if [ ! -x "$VENV/bin/python" ] || ! version_ok "$VENV/bin/python"; then
    rm -rf "$VENV"
    "$PY" -m venv "$VENV" || falla "No pude crear el entorno en $VENV"
    ok "Entorno creado"
fi
if "$VENV/bin/python" -c 'import kokoro, soundfile' >/dev/null 2>&1; then
    ok "kokoro y soundfile ya están instalados"
else
    "$VENV/bin/python" -m pip install --quiet --upgrade pip || aviso "No pude actualizar pip (sigo igual)."
    "$VENV/bin/python" -m pip install --quiet "kokoro>=0.9.4" soundfile \
        || falla "Falló pip install kokoro soundfile (¿hay internet?)."
    ok "Paquetes instalados"
fi

# 4. Helper ---------------------------------------------------------------
paso "Helper de voz"
if [ -f "$DEST/orbex-tts.py" ] && cmp -s "$HELPER_SRC" "$DEST/orbex-tts.py"; then
    ok "El helper ya está al día"
else
    cp "$HELPER_SRC" "$DEST/orbex-tts.py" || falla "No pude copiar el helper."
    chmod +x "$DEST/orbex-tts.py"
    ok "Helper copiado"
fi

# 5. Modelo + prueba ------------------------------------------------------
paso "Modelo y prueba de voz ($VOZ)"
if [ -f "$DEST/.instalado" ]; then
    ok "Ya estaba probado ($(cat "$DEST/.instalado"))"
else
    echo "  La primera vez descarga el modelo (~330 MB); puede tardar unos minutos…"
fi
PRUEBA="$DEST/prueba.wav"
if PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" "$VENV/bin/python" "$DEST/orbex-tts.py" \
        --selftest --voice "$VOZ" --out "$PRUEBA" >/dev/null; then
    date "+%Y-%m-%d %H:%M" > "$DEST/.instalado"
    ok "La voz anda"
    if command -v afplay >/dev/null 2>&1 && preguntar "¿Querés escucharla?"; then
        afplay "$PRUEBA" || true
    fi
    rm -f "$PRUEBA"
else
    rm -f "$DEST/.instalado"
    falla "La prueba falló. Mirá el error de arriba y volvé a correr el script."
fi

echo
echo "Listo. En ORBEX: Configuración › Voz de Orbi › \"Volver a comprobar\" y elegí Kokoro (o Automático)."
