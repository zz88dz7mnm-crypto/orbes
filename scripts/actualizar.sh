#!/usr/bin/env bash
# actualizar.sh — instala esta versión de ORBEX ENCIMA de la anterior y limpia sus restos.
#
# Uso (desde la carpeta NUEVA del proyecto, ya descomprimida):
#
#     bash scripts/actualizar.sh            # pregunta antes de borrar cosas opcionales
#     bash scripts/actualizar.sh --si       # responde "sí" a todo (menos a borrar tus datos)
#
# Qué hace:
#   1. Cierra ORBEX (y Coucou/NotchBuddy si quedó alguno abierto).
#   2. Borra la app vieja (/Applications/ORBEX.app, ~/Applications/ORBEX.app) y compilados viejos.
#   3. Quita hooks viejos de Coucou/NotchBuddy (nb-hook) de ~/.claude/settings.json
#      con backup fechado y mostrando el diff antes de escribir.
#   4. Compila e instala la versión nueva con scripts/install.sh.
#   5. Ofrece borrar la carpeta vieja del proyecto que descargaste antes.
# Tus datos (notas, memoria, timers, ajustes, claves del Keychain) NO se tocan: solo si lo pedís.
#
# Compatible con el bash 3.2 de macOS.

if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\n[aviso] %s\n' "$*" >&2; }
die()  { printf '\n[error] %s\n' "$*" >&2; exit 1; }

YES=0
for a in "$@"; do case "$a" in --si|--yes|-y) YES=1 ;; esac; done

ask() { # ask "pregunta" → 0 si sí
    if [ "$YES" = 1 ]; then return 0; fi
    local r; printf '%s [s/N] ' "$1"; read -r r || r=""
    case "$r" in s|S|si|SI|sí|Sí|y|Y) return 0 ;; *) return 1 ;; esac
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[ "$(uname -s)" = "Darwin" ] || die "Esto tiene que correr en una Mac."
chmod +x "$ROOT"/scripts/*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. Cerrar lo que esté abierto
# ---------------------------------------------------------------------------
step "Cerrando ORBEX (y Coucou si estaba abierto)"
for name in Orbex ORBEX Coucou NotchBuddy; do
    if pgrep -x "$name" >/dev/null 2>&1; then
        osascript -e "quit app \"$name\"" >/dev/null 2>&1 || true
        sleep 1
        pkill -x "$name" >/dev/null 2>&1 || true
        info "cerrado: $name"
    fi
done

# ---------------------------------------------------------------------------
# 2. App vieja y compilados viejos
# ---------------------------------------------------------------------------
step "Borrando la app vieja y compilados viejos"
for app in "/Applications/ORBEX.app" "$HOME/Applications/ORBEX.app"; do
    if [ -d "$app" ]; then
        rm -rf "$app" 2>/dev/null || sudo rm -rf "$app"
        info "borrada: $app"
    fi
done
rm -rf "$ROOT/.build" "$ROOT/dist" 2>/dev/null || true
info "limpios: .build y dist de esta carpeta"
# Acceso directo viejo del Escritorio (la app nueva lo vuelve a crear si lo tenías activado).
[ -L "$HOME/Desktop/ORBEX" ] && rm -f "$HOME/Desktop/ORBEX" && info "acceso directo viejo quitado"

# Coucou/NotchBuddy instalado aparte (opcional: puede que lo quieras conservar).
for app in "/Applications/Coucou.app" "$HOME/Applications/Coucou.app"; do
    if [ -d "$app" ] && ask "Encontré $app (Coucou). ¿Lo borro?"; then
        rm -rf "$app" 2>/dev/null || sudo rm -rf "$app"
        info "borrada: $app"
    fi
done

# ---------------------------------------------------------------------------
# 3. Hooks viejos de Coucou/NotchBuddy en ~/.claude/settings.json
# ---------------------------------------------------------------------------
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q "nb-hook\|NotchBuddy\|/coucou/" "$SETTINGS"; then
    step "Hay hooks viejos de Coucou/NotchBuddy en $SETTINGS"
    TMP="$(mktemp)"
    /usr/bin/python3 - "$SETTINGS" "$TMP" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
old = ("nb-hook", "NotchBuddy", "/coucou/")
hooks = data.get("hooks", {})
for event in list(hooks):
    groups = []
    for g in hooks[event]:
        hs = [h for h in g.get("hooks", []) if not any(o in str(h.get("command", "")) for o in old)]
        if hs:
            g["hooks"] = hs
            groups.append(g)
    if groups: hooks[event] = groups
    else: del hooks[event]
if not hooks: data.pop("hooks", None)
json.dump(data, open(dst, "w"), indent=2, ensure_ascii=False)
PY
    diff -u "$SETTINGS" "$TMP" || true
    if ask "¿Aplico este cambio? (se guarda un backup con fecha)"; then
        cp "$SETTINGS" "$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$TMP" "$SETTINGS"
        info "hooks viejos quitados (backup guardado al lado)"
    else
        info "no toqué $SETTINGS"
    fi
    rm -f "$TMP"
fi
# Scripts viejos de Coucou
if [ -d "$HOME/.claude/coucou" ] && ask "¿Borro la carpeta vieja ~/.claude/coucou (relé de Coucou)?"; then
    rm -rf "$HOME/.claude/coucou"; info "borrada ~/.claude/coucou"
fi

# ---------------------------------------------------------------------------
# 4. Instalar la versión nueva
# ---------------------------------------------------------------------------
step "Compilando e instalando la versión nueva"
bash "$ROOT/scripts/install.sh"

# ---------------------------------------------------------------------------
# 5. Carpeta vieja del proyecto
# ---------------------------------------------------------------------------
step "Carpeta vieja del proyecto"
CANDIDATES=""
for d in "$HOME/Downloads" "$HOME/Descargas" "$HOME/Desktop" "$HOME/Documents"; do
    [ -d "$d" ] || continue
    for c in "$d"/orbes* "$d"/ORBEX* "$d"/orbex*; do
        [ -d "$c" ] || continue
        [ -f "$c/Package.swift" ] || continue
        [ "$(cd "$c" && pwd)" = "$ROOT" ] && continue
        CANDIDATES="$CANDIDATES
$c"
    done
done
if [ -n "$CANDIDATES" ]; then
    OLDIFS="$IFS"; IFS='
'
    for c in $CANDIDATES; do
        IFS="$OLDIFS"
        [ -n "$c" ] || continue
        if ask "¿Borro la versión vieja descargada en $c?"; then
            rm -rf "$c"; info "borrada: $c"
        fi
    done
    IFS="$OLDIFS"
else
    info "no encontré otra carpeta del proyecto (listo)."
fi
for z in "$HOME/Downloads"/orbes*.zip "$HOME/Descargas"/orbes*.zip; do
    [ -f "$z" ] && ask "¿Borro el ZIP viejo $z?" && rm -f "$z" && info "borrado: $z"
done

step "¡Listo! ORBEX actualizado. Tus notas, memoria y ajustes siguen donde estaban."
