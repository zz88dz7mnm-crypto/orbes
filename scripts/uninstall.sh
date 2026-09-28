#!/usr/bin/env bash
# uninstall.sh — desinstala ORBEX.
#
# Uso:
#     ./scripts/uninstall.sh          pregunta antes de borrar
#     ./scripts/uninstall.sh -y       sin preguntar (conserva tus datos y ajustes)
#     ./scripts/uninstall.sh --all    borra también datos, ajustes y claves del Keychain
#     ./scripts/uninstall.sh -y --all todo, sin preguntar
#
# Qué hace: cierra ORBEX, quita los hooks de Claude Code/Codex y el acceso directo
# del Escritorio (con la propia app), y borra ORBEX.app de Aplicaciones.
# Con --all (o si decís que sí): ~/Library/Application Support/ORBEX, las
# preferencias (com.orbex.ORBEX) y las claves guardadas en el Keychain.
# Compatible con el bash 3.2 que trae macOS.

# Si lo corren con `sh` o `zsh`, volver a arrancar con bash.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -euo pipefail

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\n[aviso] %s\n' "$*" >&2; }
die()  { printf '\n[error] %s\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="ORBEX"
EXECUTABLE="Orbex"
BUNDLE_ID="com.orbex.ORBEX"
SUPPORT_DIR="$HOME/Library/Application Support/ORBEX"
DESKTOP_LINK="$HOME/Desktop/ORBEX"
SYSTEM_APP="/Applications/$APP_NAME.app"
USER_APP="$HOME/Applications/$APP_NAME.app"

ASSUME_YES=0
DELETE_DATA=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        --all) DELETE_DATA=1 ;;
        -h|--help)
            sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Opción desconocida: $arg (usá -y, --all o -h)" ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ]; then
    die "ORBEX es una app de macOS: este script tiene que correr en una Mac."
fi

# Pregunta sí/no. Devuelve 0 si la respuesta es sí.
ask() {
    local answer=""
    if [ ! -t 0 ]; then
        return 1
    fi
    printf '%s [s/N] ' "$1"
    read -r answer || return 1
    case "$answer" in
        s|S|si|SI|Si|sí|SÍ|Sí|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 0. Confirmar
# ---------------------------------------------------------------------------
printf 'Esto va a desinstalar ORBEX:\n'
printf '  - cerrar la app\n'
printf '  - quitar los hooks de Claude Code/Codex y el acceso directo del Escritorio\n'
printf '  - borrar ORBEX.app de /Applications y de ~/Applications\n'
if [ "$DELETE_DATA" = 1 ]; then
    printf '  - borrar tus datos, ajustes y claves guardadas (--all)\n'
fi

if [ "$ASSUME_YES" = 0 ]; then
    if [ ! -t 0 ]; then
        die "No hay terminal para confirmar. Usá: ./scripts/uninstall.sh -y"
    fi
    if ! ask "¿Seguimos?"; then
        printf 'Cancelado. No se borró nada.\n'
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# 1. Cerrar ORBEX
# ---------------------------------------------------------------------------
orbex_running() { pgrep -x "$EXECUTABLE" >/dev/null 2>&1; }

quit_orbex() {
    orbex_running || return 0
    step "Cerrando ORBEX"
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 &
    local osa_pid=$! tries=0
    while orbex_running && [ "$tries" -lt 10 ]; do
        sleep 0.5
        tries=$((tries + 1))
    done
    kill "$osa_pid" >/dev/null 2>&1 || true
    wait "$osa_pid" >/dev/null 2>&1 || true
    if orbex_running; then
        pkill -x "$EXECUTABLE" >/dev/null 2>&1 || true
        sleep 1
    fi
    if orbex_running; then
        pkill -9 -x "$EXECUTABLE" >/dev/null 2>&1 || true
        sleep 0.5
    fi
    return 0
}
quit_orbex

# ---------------------------------------------------------------------------
# 2. Hooks y acceso directo (los quita la propia app)
# ---------------------------------------------------------------------------
# Corre un comando con tiempo límite (en segundos). Si se pasa, lo mata y devuelve 124.
run_with_timeout() {
    local secs="$1"
    shift
    "$@" &
    local pid=$! ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((secs * 2)) ]; then
            kill "$pid" 2>/dev/null || true
            sleep 0.5
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 0.5
        ticks=$((ticks + 1))
    done
    wait "$pid"
}

APP_BIN=""
for candidate in "$SYSTEM_APP" "$USER_APP" "$ROOT/dist/$APP_NAME.app"; do
    if [ -x "$candidate/Contents/MacOS/$EXECUTABLE" ]; then
        APP_BIN="$candidate/Contents/MacOS/$EXECUTABLE"
        break
    fi
done

if [ -n "$APP_BIN" ]; then
    step "Quitando los hooks de Claude Code/Codex"
    run_with_timeout 20 "$APP_BIN" --uninstall-hooks \
        || warn "No se pudieron quitar los hooks automáticamente.
         Revisá ~/.claude/settings.json y borrá las entradas que mencionen orbex-hook."

    step "Quitando el acceso directo del Escritorio"
    run_with_timeout 20 "$APP_BIN" --remove-shortcut \
        || warn "La app no pudo quitar el acceso directo; lo intento a mano."
else
    warn "No encontré ORBEX.app, así que no pude quitar los hooks con la app."
    if [ -f "$HOME/.claude/settings.json" ] && grep -q "orbex-hook" "$HOME/.claude/settings.json" 2>/dev/null; then
        warn "$HOME/.claude/settings.json todavía menciona orbex-hook: borrá esas entradas a mano
         (o reinstalá ORBEX y desactivá los hooks desde Configuración)."
    fi
fi

# Acceso directo del Escritorio: solo si es un alias/enlace (nunca una carpeta de verdad).
if [ -L "$DESKTOP_LINK" ] || [ -f "$DESKTOP_LINK" ]; then
    if rm -f "$DESKTOP_LINK" 2>/dev/null; then
        info "Borrado: $DESKTOP_LINK"
    else
        warn "No pude borrar $DESKTOP_LINK (¿permiso de la Terminal para el Escritorio?). Borralo a mano."
    fi
elif [ -d "$DESKTOP_LINK" ]; then
    warn "$DESKTOP_LINK es una carpeta, no el acceso directo de ORBEX: no la toco."
fi

# ---------------------------------------------------------------------------
# 3. Borrar la app
# ---------------------------------------------------------------------------
step "Borrando ORBEX.app"
REMOVED_ANY=0
for candidate in "$SYSTEM_APP" "$USER_APP"; do
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
        if rm -rf "$candidate" 2>/dev/null; then
            info "Borrada: $candidate"
            REMOVED_ANY=1
        else
            warn "No tengo permiso para borrar $candidate. Probá con:
         sudo rm -rf \"$candidate\""
        fi
    fi
done
[ "$REMOVED_ANY" = 1 ] || info "No había ORBEX.app instalada en /Applications ni en ~/Applications."

# ---------------------------------------------------------------------------
# 4. Datos, ajustes y claves (opcional)
# ---------------------------------------------------------------------------
if [ "$DELETE_DATA" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
    printf '\n'
    if ask "¿Borrar también tus datos (notas, memoria, temporizadores), ajustes y claves guardadas?"; then
        DELETE_DATA=1
    fi
fi

if [ "$DELETE_DATA" = 1 ]; then
    step "Borrando datos y ajustes"
    for path in \
        "$SUPPORT_DIR" \
        "$HOME/Library/Caches/$BUNDLE_ID" \
        "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
        "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"; do
        if [ -e "$path" ]; then
            if rm -rf "$path" 2>/dev/null; then
                info "Borrado: $path"
            else
                warn "No pude borrar $path."
            fi
        fi
    done

    if defaults delete "$BUNDLE_ID" >/dev/null 2>&1; then
        info "Borradas las preferencias ($BUNDLE_ID)."
    fi
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist" 2>/dev/null || true

    step "Borrando claves del Keychain (servicio $BUNDLE_ID)"
    KEYS=0
    while [ "$KEYS" -lt 100 ] && security delete-generic-password -s "$BUNDLE_ID" >/dev/null 2>&1; do
        KEYS=$((KEYS + 1))
    done
    info "Claves borradas: $KEYS"
else
    info "Tus datos quedan en: $SUPPORT_DIR"
    info "(para borrarlos después: ./scripts/uninstall.sh --all)"
fi

printf '\nORBEX quedó desinstalado.\n'
printf 'Si lo habías puesto para iniciar con la Mac y todavía aparece en\n'
printf 'Ajustes del Sistema → General → Ítems de inicio, quitalo de ahí.\n'
