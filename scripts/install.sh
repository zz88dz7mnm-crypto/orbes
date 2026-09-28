#!/usr/bin/env bash
# install.sh — un solo comando: compila ORBEX, arma dist/ORBEX.app y dist/ORBEX.dmg,
# la instala en Aplicaciones y la abre.
#
# Uso (desde la carpeta del proyecto, después de bajar y descomprimir el ZIP):
#
#     ./scripts/install.sh
#
# Si el ZIP perdió los permisos de ejecución ("permission denied"), corré:
#
#     bash scripts/install.sh
#
# Requisitos: macOS 14+ y las Xcode Command Line Tools (xcode-select --install) o Xcode.
# Compatible con el bash 3.2 que trae macOS.

# Si lo corren con `sh` o `zsh`, volver a arrancar con bash.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

set -euo pipefail

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\n[aviso] %s\n' "$*" >&2; }
die()  { printf '\n[error] %s\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ORBEX"
EXECUTABLE="Orbex"
BUNDLE_ID="com.orbex.ORBEX"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"

if [ "$(uname -s)" != "Darwin" ]; then
    die "ORBEX es una app de macOS: este script tiene que correr en una Mac."
fi

# Devolver los permisos de ejecución a los scripts (el ZIP a veces los pierde).
chmod +x "$ROOT"/scripts/*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. Compilar y armar la app + el dmg
# ---------------------------------------------------------------------------
bash "$ROOT/scripts/build-app.sh"
[ -d "$APP" ] || die "No se armó $APP. Mirá los errores de arriba."

if ! bash "$ROOT/scripts/make-dmg.sh"; then
    warn "No se pudo generar el .dmg (sigo con la instalación igual)."
fi

# ---------------------------------------------------------------------------
# 2. Cerrar ORBEX si está abierto
# ---------------------------------------------------------------------------
orbex_running() { pgrep -x "$EXECUTABLE" >/dev/null 2>&1; }

quit_orbex() {
    orbex_running || return 0
    step "Cerrando la versión de ORBEX que está abierta"
    # Pedirle que se cierre bien; si no responde en ~5 s, cerrarla a la fuerza.
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
# 3. Copiar a Aplicaciones (o a ~/Aplicaciones si no hay permiso)
# ---------------------------------------------------------------------------
# Copia la app a "$1/ORBEX.app" reemplazando la anterior. Devuelve 1 si no pudo.
install_into() {
    local dir="$1"
    local dest="$dir/$APP_NAME.app"
    mkdir -p "$dir" 2>/dev/null || return 1
    [ -w "$dir" ] || return 1
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        rm -rf "$dest" 2>/dev/null || return 1
    fi
    ditto "$APP" "$dest" 2>/dev/null || { rm -rf "$dest" 2>/dev/null; return 1; }
    return 0
}

# ¿Es una copia de ORBEX (mismo bundle id)? Para no borrar nada ajeno.
is_orbex_bundle() {
    local id
    id="$(defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
    [ "$id" = "$BUNDLE_ID" ]
}

step "Instalando $APP_NAME.app"
SYSTEM_APPS="/Applications"
USER_APPS="$HOME/Applications"
if install_into "$SYSTEM_APPS"; then
    DEST_DIR="$SYSTEM_APPS"
    OTHER_DIR="$USER_APPS"
else
    info "No tengo permiso para escribir en $SYSTEM_APPS; la instalo en $USER_APPS."
    install_into "$USER_APPS" || die "No pude copiar la app a $USER_APPS."
    DEST_DIR="$USER_APPS"
    OTHER_DIR="$SYSTEM_APPS"
fi
DEST="$DEST_DIR/$APP_NAME.app"
info "Instalada en: $DEST"

# Evitar dos copias de ORBEX (Spotlight e "iniciar con la Mac" podrían abrir la vieja).
OTHER="$OTHER_DIR/$APP_NAME.app"
if [ -d "$OTHER" ] && is_orbex_bundle "$OTHER"; then
    if rm -rf "$OTHER" 2>/dev/null; then
        info "Borré una copia vieja en: $OTHER"
    else
        warn "Quedó una copia vieja en $OTHER y no tengo permiso para borrarla.
         Borrala a mano (arrastrala a la Papelera) para no tener dos ORBEX."
    fi
fi

# Quitar la cuarentena (evita el aviso de "app descargada de internet").
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

# Registrar la app nueva en LaunchServices (para Spotlight y "Abrir con").
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 4. Abrir ORBEX
# ---------------------------------------------------------------------------
step "Abriendo ORBEX"
if ! open "$DEST"; then
    warn "No pude abrir ORBEX automáticamente. Abrilo desde $DEST_DIR."
fi

# ---------------------------------------------------------------------------
# 5. Resumen
# ---------------------------------------------------------------------------
printf '\n'
printf '==========================================================\n'
printf '  ORBEX quedó instalado.\n'
printf '==========================================================\n'
printf '  App:  %s\n' "$DEST"
if [ -f "$DMG" ]; then
    printf '  DMG:  %s\n' "$DMG"
    printf '        (para compartirla: abrís el .dmg y arrastrás ORBEX a Aplicaciones)\n'
fi
cat <<'EOF'

  Próximos pasos:
  1. Buscá a ORBEX en el notch (arriba al centro de la pantalla) y en la
     barra de menús. No aparece en el Dock: es una app de barra de menús.
  2. La primera vez te pregunta si querés un acceso directo en el Escritorio
     y si querés que inicie con la Mac.
  3. Si macOS dice que "no se puede verificar al desarrollador" (la app no
     está notarizada): Ajustes del Sistema → Privacidad y seguridad →
     "Abrir igualmente".
  4. Cada vez que reinstalás, macOS puede volver a pedir permisos
     (micrófono, automatización): la firma es local, sin certificado.

  Para desinstalar:  ./scripts/uninstall.sh
EOF
