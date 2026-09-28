#!/usr/bin/env bash
# make-dmg.sh — genera dist/ORBEX.dmg a partir de dist/ORBEX.app.
#
# Uso:  ./scripts/make-dmg.sh        (o: bash scripts/make-dmg.sh)
#
# Si todavía no existe dist/ORBEX.app, primero corre scripts/build-app.sh.
# El .dmg trae la app y un atajo a /Applications: se abre y se arrastra.
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
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"

if [ "$(uname -s)" != "Darwin" ]; then
    die "El .dmg se arma con hdiutil: este script tiene que correr en una Mac."
fi

if [ ! -d "$APP" ]; then
    info "No encontré $APP; la armo primero."
    bash "$ROOT/scripts/build-app.sh"
fi
[ -d "$APP" ] || die "No existe $APP. Corré ./scripts/build-app.sh y mirá los errores."

step "Preparando el contenido del .dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/orbex-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# ditto conserva la firma y los permisos del paquete.
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

step "Creando $DMG"
rm -f "$DMG"
# hdiutil a veces falla con "Resource busy" (Spotlight u otro montaje): reintentar.
ok=0
for attempt in 1 2 3; do
    if hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"; then
        ok=1
        break
    fi
    if [ "$attempt" -lt 3 ]; then
        warn "hdiutil falló (intento $attempt de 3); reintento en 3 s..."
        sleep 3
    fi
done
[ "$ok" = 1 ] || die "No se pudo crear $DMG."

step "Listo: $DMG"
info "Para instalar desde el .dmg: abrilo y arrastrá ORBEX a Aplicaciones."
