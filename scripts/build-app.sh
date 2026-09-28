#!/usr/bin/env bash
# build-app.sh — compila ORBEX y arma dist/ORBEX.app (sin instalar nada).
#
# Uso:  ./scripts/build-app.sh        (o: bash scripts/build-app.sh)
#
# Requisitos: macOS 14+ y las Xcode Command Line Tools (xcode-select --install) o Xcode.
# Compatible con el bash 3.2 que trae macOS.
#
# Resultado:
#   dist/ORBEX.app/
#     Contents/Info.plist            ← scripts/Info.plist
#     Contents/PkgInfo               ← "APPL????"
#     Contents/MacOS/Orbex           ← producto `Orbex` (la app)
#     Contents/Helpers/orbex-hook    ← producto `orbex-hook` (relé de hooks)
#     Contents/Resources/AppIcon.icns← dibujado por scripts/make-icon.swift
# Firma ad hoc (sin certificado): alcanza para correrla en tu Mac.

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
HOOK="orbex-hook"
BUNDLE_ID="com.orbex.ORBEX"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
PLIST_SRC="$ROOT/scripts/Info.plist"
ICON_SCRIPT="$ROOT/scripts/make-icon.swift"
ICON_CACHE_DIR="$ROOT/.build/orbex-icon"
ICON_CACHE="$ICON_CACHE_DIR/AppIcon.icns"

# ---------------------------------------------------------------------------
# 1. Chequeos
# ---------------------------------------------------------------------------
step "Revisando herramientas"

if [ "$(uname -s)" != "Darwin" ]; then
    die "ORBEX es una app de macOS: este script tiene que correr en una Mac."
fi

# /usr/bin/swift existe siempre (es un atajo que pide instalar las herramientas),
# así que primero preguntamos si hay herramientas de desarrollo instaladas.
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    die "No encontré Swift. Instalá las herramientas de desarrollo de Apple con:

        xcode-select --install

    (o instalá Xcode desde el App Store) y volvé a correr este script."
fi

if ! SWIFT_VERSION="$(swift --version 2>&1)"; then
    die "Swift está instalado pero no responde. Probá con:

        xcode-select --install
        sudo xcode-select --reset

    Si tenés Xcode, abrilo una vez para aceptar la licencia."
fi
printf '%s\n' "$SWIFT_VERSION" | sed 's/^/    /'
info "Carpeta del proyecto: $ROOT"

[ -f "$ROOT/Package.swift" ] || die "No encontré Package.swift en $ROOT."
[ -f "$PLIST_SRC" ] || die "No encontré $PLIST_SRC."

# ---------------------------------------------------------------------------
# 2. Compilar (release)
# ---------------------------------------------------------------------------
step "Compilando $EXECUTABLE (release). La primera vez tarda un par de minutos..."
swift build -c release --product "$EXECUTABLE" \
    || die "Falló la compilación de $EXECUTABLE. Mirá los errores de arriba."

step "Compilando $HOOK (release)"
swift build -c release --product "$HOOK" \
    || die "Falló la compilación de $HOOK. Mirá los errores de arriba."

BIN_PATH="$(swift build -c release --show-bin-path)"
[ -x "$BIN_PATH/$EXECUTABLE" ] || die "No encontré el binario $BIN_PATH/$EXECUTABLE."
[ -x "$BIN_PATH/$HOOK" ] || die "No encontré el binario $BIN_PATH/$HOOK."
info "Binarios en: $BIN_PATH"

# ---------------------------------------------------------------------------
# 3. Armar el paquete .app
# ---------------------------------------------------------------------------
step "Armando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"

cp "$BIN_PATH/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$BIN_PATH/$HOOK" "$APP/Contents/Helpers/$HOOK"
chmod 755 "$APP/Contents/MacOS/$EXECUTABLE" "$APP/Contents/Helpers/$HOOK"

cp "$PLIST_SRC" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist" >/dev/null \
        || die "scripts/Info.plist no es un plist válido (plutil -lint scripts/Info.plist)."
fi

# ---------------------------------------------------------------------------
# 4. Ícono (si falla, la app anda igual con el ícono genérico)
# ---------------------------------------------------------------------------
step "Generando el ícono"
ICON_OK=0
if [ -f "$ICON_CACHE" ] && [ "$ICON_CACHE" -nt "$ICON_SCRIPT" ]; then
    if cp "$ICON_CACHE" "$APP/Contents/Resources/AppIcon.icns"; then
        ICON_OK=1
        info "Reusando el ícono ya generado (.build/orbex-icon/AppIcon.icns)."
    fi
fi

# Dibuja el .iconset: primero con el intérprete (`swift archivo.swift`); si falla
# (algunas versiones de las Command Line Tools tienen problemas con el JIT),
# lo compila con swiftc y corre el binario.
render_iconset() {
    local out="$1" tmp="$2"
    if swift "$ICON_SCRIPT" "$out"; then
        return 0
    fi
    info "El intérprete de Swift falló; pruebo compilando el script..."
    rm -rf "$out"
    swiftc -O "$ICON_SCRIPT" -o "$tmp/make-icon" && "$tmp/make-icon" "$out"
}

if [ "$ICON_OK" = 0 ]; then
    ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/orbex-icon.XXXXXX")"
    if render_iconset "$ICON_TMP/AppIcon.iconset" "$ICON_TMP" \
        && iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
        ICON_OK=1
        mkdir -p "$ICON_CACHE_DIR"
        cp "$APP/Contents/Resources/AppIcon.icns" "$ICON_CACHE" 2>/dev/null || true
        info "Ícono listo."
    else
        rm -f "$APP/Contents/Resources/AppIcon.icns"
        warn "No se pudo generar el ícono (sigo sin ícono; la app funciona igual).
         Para probarlo aparte: swift scripts/make-icon.swift /tmp/AppIcon.iconset"
    fi
    rm -rf "$ICON_TMP"
fi

# ---------------------------------------------------------------------------
# 5. Firma ad hoc (primero el ayudante, después la app)
# ---------------------------------------------------------------------------
step "Firmando (ad hoc, sin certificado)"
# Sacar atributos extendidos (Finder info, cuarentena del zip) que rompen codesign.
xattr -cr "$APP" 2>/dev/null || true

SIGN_OK=1
codesign --force --sign - --timestamp=none \
    --identifier "$BUNDLE_ID.$HOOK" \
    "$APP/Contents/Helpers/$HOOK" || SIGN_OK=0
codesign --force --sign - --timestamp=none \
    "$APP" || SIGN_OK=0

if [ "$SIGN_OK" = 1 ] && codesign --verify --strict "$APP" >/dev/null 2>&1; then
    info "Firma verificada."
else
    warn "La firma ad hoc falló o no verifica. La app puede andar igual, pero macOS
         podría pedir permisos de nuevo o negarse a abrirla. Revisá: codesign -dv --verbose=2 \"$APP\""
fi

# Que el Finder y LaunchServices noten el cambio.
touch "$APP"

step "Listo: $APP"
info "Para instalarla en Aplicaciones y abrirla: ./scripts/install.sh"
info "Para probarla sin instalar:                open \"$APP\""
