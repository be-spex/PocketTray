#!/bin/sh
# Builds the system-wide Debian package of the applet:
#   packaging/build-deb.sh   → dist/pockettray_<version>_all.deb
# The applet goes to /usr/share/cinnamon/applets/, the compiled translations
# to /usr/share/locale/ (lib/i18n.js looks there when installed below /usr).
set -eu
cd "$(dirname "$0")/.."

UUID=PocketTray@spex
SRC="$UUID/files/$UUID"
VERSION=$(jq -r .version "$SRC/metadata.json")
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

APPLET="$ROOT/usr/share/cinnamon/applets/$UUID"
mkdir -p "$APPLET"
cp -r "$SRC/." "$APPLET/"
rm -rf "$APPLET/po"

for po in "$SRC"/po/*.po; do
    lang=$(basename "$po" .po)
    mkdir -p "$ROOT/usr/share/locale/$lang/LC_MESSAGES"
    msgfmt -o "$ROOT/usr/share/locale/$lang/LC_MESSAGES/$UUID.mo" "$po"
done

DOC="$ROOT/usr/share/doc/pockettray"
mkdir -p "$DOC"
cp README.md CHANGELOG.md "$DOC/"
[ -f LICENSE ] && cp LICENSE "$DOC/copyright"

mkdir -p "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: pockettray
Version: $VERSION
Architecture: all
Maintainer: Bert Speckels <skrrytch@speckels.net>
Depends: cinnamon (>= 6.0)
Section: x11
Priority: optional
Homepage: https://github.com/be-spex/PocketTray
Installed-Size: $(du -sk "$ROOT/usr" | cut -f1)
Description: System tray with a pocket for rarely used icons – by be-spex
 PocketTray keeps the tray icons you use every day in the panel and tucks
 the rest into a small pocket. Works with legacy (XEmbed) and modern
 (XApp/StatusNotifier) icons. After installing, add PocketTray to the panel
 in place of the System Tray and XApp Status applets.
CONTROL

find "$ROOT" -type d -exec chmod 755 {} +
find "$ROOT/usr" -type f -exec chmod 644 {} +
mkdir -p dist
dpkg-deb --root-owner-group --build "$ROOT" "dist/pockettray_${VERSION}_all.deb"
