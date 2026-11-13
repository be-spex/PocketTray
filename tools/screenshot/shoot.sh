#!/bin/bash
# Takes the PocketTray screenshot (pocket open + context menu) in English, in a
# light and a dark theme, without touching the running desktop.
#
#   tools/screenshot/shoot.sh [--site <be-spex.github.io checkout>]
#
# Writes docs/images/pockettray-{light,dark}.png and PocketTray@spex/screenshot.png
# (the dark one, used by Cinnamon Spices); with --site also the WebP files for
# the website.
#
# How: a second Cinnamon runs on an invisible X server (Xvfb) with its own
# D-Bus session, its own HOME and LANG=en_US, at UI scale 2. A few well-known
# tray programs are started in it, the applet is driven through Cinnamon's
# Eval D-Bus method, the screen is captured with ImageMagick.
#
# Needs: Xvfb, cinnamon, dbus-run-session, gdbus, xdotool, ImageMagick (import,
# convert), cwebp for --site, and the tray programs listed in APPS.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APPLET="$ROOT/PocketTray@spex/files/PocketTray@spex"
SITE=""
[ "${1:-}" = "--site" ] && SITE=$(cd "$2" && pwd)

DISPLAY_NO=${DISPLAY_NO:-99}
# Tray programs shown, and the ids of those that go into the pocket.
APPS=(blueman-applet guake sticky mintreport-tray mintupdate-launcher warpinator "transmission-gtk -m")
HIDDEN="'sticky','process-monitor','transmission','warpinator'"
# Background behind the cut-outs, per theme.
declare -A THEME=([dark]=Mint-Y-Dark [light]=Mint-Y) BG=([dark]='#20242c' [light]='#e4e8ee') FUZZ=([dark]=3 [light]=60)

S=$(mktemp -d)
mkdir -p "$S/home/.local/share/cinnamon/applets" "$S/run" && chmod 700 "$S/run"
cp -r "$APPLET" "$S/home/.local/share/cinnamon/applets/"

# Everything started below carries HOME=$S/home; that is how cleanup finds it.
cleanup() {
  for p in $(pgrep -u "$USER" . || true); do
    grep -qz "^HOME=$S/home" "/proc/$p/environ" 2>/dev/null && kill "$p" 2>/dev/null || true
  done
  [ -n "${XVFB:-}" ] && kill "$XVFB" 2>/dev/null || true
  sleep 1; rm -rf "$S"
}
trap cleanup EXIT

Xvfb ":$DISPLAY_NO" -screen 0 2560x1440x24 -nolisten tcp >"$S/xvfb.log" 2>&1 &
XVFB=$!
sleep 2

ENV=(env -i "PATH=$PATH" "HOME=$S/home" "XDG_RUNTIME_DIR=$S/run" "DISPLAY=:$DISPLAY_NO" LANG=en_US.UTF-8 LANGUAGE=en_US:en
     XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11)

cat >"$S/session.sh" <<SESSION
#!/bin/bash
echo "\$DBUS_SESSION_BUS_ADDRESS" > "$S/bus"
gsettings set org.cinnamon enabled-applets "['panel1:center:0:PocketTray@spex:1']"
gsettings set org.cinnamon panels-enabled "['1:0:bottom']"
gsettings set org.cinnamon panels-height "['1:40']"
gsettings set org.cinnamon.theme name Mint-Y-Dark
gsettings set org.cinnamon.desktop.interface gtk-theme Mint-Y-Dark
gsettings set org.cinnamon.desktop.interface icon-theme Mint-Y
gsettings set org.cinnamon.desktop.interface scaling-factor 2
CINNAMON_SOFTWARE_RENDERING=1 cinnamon --replace > "$S/cinnamon.log" 2>&1 &
sleep infinity
SESSION
chmod +x "$S/session.sh"
"${ENV[@]}" dbus-run-session -- "$S/session.sh" >"$S/session.log" 2>&1 &
for _ in $(seq 60); do [ -s "$S/bus" ] && break; sleep 0.5; done
[ -s "$S/bus" ] || { echo "session did not start" >&2; exit 1; }

inside() { "${ENV[@]}" "DBUS_SESSION_BUS_ADDRESS=$(cat "$S/bus")" "$@"; }
js() { inside gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1"; }

echo "starting Cinnamon and the tray programs …"
for _ in $(seq 60); do js "1" >/dev/null 2>&1 && break; sleep 1; done
inside /usr/lib/x86_64-linux-gnu/cinnamon-settings-daemon/csd-xsettings >/dev/null 2>&1 &
for app in "${APPS[@]}"; do inside $app >/dev/null 2>&1 & sleep 1; done
sleep 15

# The applet object; windows of the tray programs out of the way.
PT="Main.panelManager.panels.filter(p => p)[0]._centerBox.get_children()[0]._delegate"
js "global._pt = $PT; [$HIDDEN].forEach(id => global._pt.hiddenList.setHidden(id, true)); global.window_group.hide(); 1" >/dev/null
echo "tray icons: $(js "global._pt._iconMenu._collectEntries().map(e => e.label).join(', ')")"

capture() { DISPLAY=":$DISPLAY_NO" import -window root "$1"; }
OUT="$ROOT/docs/images"; mkdir -p "$OUT"
for t in dark light; do
  inside gsettings set org.cinnamon.theme name "${THEME[$t]}"
  inside gsettings set org.cinnamon.desktop.interface gtk-theme "${THEME[$t]}"
  sleep 5
  inside xdotool mousemove 20 20
  js "global._pt._applet_context_menu.close(); global._pt.pocket.toggle(); 1" >/dev/null; sleep 2; capture "$S/pocket.png"
  js "global._pt.pocket.close(); global._pt._applet_context_menu.toggle(); 1" >/dev/null; sleep 2; capture "$S/menu.png"
  js "global._pt._applet_context_menu.close(); 1" >/dev/null

  # Where the popups are: bounding box of everything above the panel (its top edge is at about y = 1358).
  box() { convert "$1" -crop 2560x1350+0+0 +repage -fuzz 3% -trim -format '%w %h %X %Y\n' info: | tr -d '+'; }
  read -r mw mh mx my < <(box "$S/menu.png")
  read -r pw ph px py < <(box "$S/pocket.png")
  pad=185   # panel to the left and right of the pocket, so its icons are in the picture
  fill=(-fuzz "${FUZZ[$t]}%" -fill "${BG[$t]}")
  convert "$S/menu.png" -crop "${mw}x$((1440-my))+${mx}+${my}" +repage "${fill[@]}" \
          -draw 'color 0,0 floodfill' -draw "color $((mw-1)),0 floodfill" "$S/m.png"
  convert "$S/pocket.png" -crop "$((pw+2*pad))x$((1440-py))+$((px-pad))+${py}" +repage "${fill[@]}" \
          -draw 'color 0,0 floodfill' -draw "color $((pw+2*pad-1)),0 floodfill" "$S/p.png"
  M=70; G=110; PW=$((pw+2*pad)); PH=$((1440-py)); MH=$((1440-my))
  W=$((M+PW+G+mw+M)); H=$((M+MH+M))
  convert -size "${W}x${H}" "xc:${BG[$t]}" "$S/p.png" -geometry "+$M+$((H-M-PH))" -composite \
          "$S/m.png" -geometry "+$((M+PW+G))+$M" -composite "$OUT/pockettray-$t.png"
  echo "docs/images/pockettray-$t.png  ${W}x${H}"
  [ -n "$SITE" ] && cwebp -quiet -q 90 "$OUT/pockettray-$t.png" -o "$SITE/public/shots/pockettray-$t.webp"
done
cp "$OUT/pockettray-dark.png" "$ROOT/PocketTray@spex/screenshot.png"
echo "PocketTray@spex/screenshot.png (dark)"
