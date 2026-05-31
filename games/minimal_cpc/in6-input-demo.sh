#!/usr/bin/env bash
# Phase IN6 input demo: prove real CPC keyboard input drives the minimal_cpc
# hero.  Boots game.dsk in cap32 (headless via Xvfb), captures a BEFORE shot
# (hero at rest at its STARTUP_XPOS=160), then HOLDS the LEFT key ('O') down on
# the emulated CPC keyboard matrix for a sustained window and captures an AFTER
# shot — the hero must have moved LEFT in response.
#
# The hero reads the hardware matrix via the translated cpct_scanKeyboard
# (engine/src/cpc/cpct_keyboard.asm); cap32's xdotool key events go through
# applyKeypress() into that same matrix, so a held 'o' is seen by input_scan().
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DISK="${1:-$HERE/../../game.dsk}"
DISP=":99"
RES="800x600x24"
CAP32DIR="${CAP32DIR:-$HOME/src/cpc/caprice32}"
CAP32_BIN="$CAP32DIR/cap32"
CAP32_CFG="$CAP32DIR/cap32.cfg"

[ -e "$DISK" ] || { echo "MISSING disk: $DISK"; exit 1; }
[ -x "$CAP32_BIN" ] || { echo "MISSING cap32: $CAP32_BIN"; exit 1; }

cleanup() { kill "${CAP_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Fresh Xvfb
if [ -e "/tmp/.X${DISP#:}-lock" ]; then
  pkill -f "Xvfb $DISP" 2>/dev/null || true; sleep 0.4; rm -f "/tmp/.X${DISP#:}-lock"
fi
Xvfb "$DISP" -screen 0 "$RES" >/dev/null 2>&1 &
XVFB_PID=$!
for _ in $(seq 1 50); do
  DISPLAY="$DISP" xdotool getdisplaygeometry >/dev/null 2>&1 && break; sleep 0.1
done

# Launch the game (RUN"game." — empty AMSDOS extension needs the trailing dot).
DISPLAY="$DISP" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
  "$CAP32_BIN" -c "$CAP32_CFG" -a $'run"game.\r' "$DISK" >/tmp/in6-demo-cap32.log 2>&1 &
CAP_PID=$!

# Boot + load + reach the game loop (menu auto-selects keyboard, no key needed).
sleep 9
kill -0 "$CAP_PID" 2>/dev/null || { echo "cap32 exited early:"; cat /tmp/in6-demo-cap32.log; exit 1; }

WID="$(DISPLAY="$DISP" xdotool search --name Caprice 2>/dev/null | head -n1 || true)"
[ -n "$WID" ] && DISPLAY="$DISP" xdotool windowactivate --sync "$WID" 2>/dev/null || true

# BEFORE: hero at rest.
DISPLAY="$DISP" import -window root "$HERE/in6-demo-before.png"
echo "Wrote in6-demo-before.png (hero at rest)"

# Hold LEFT ('o' = CPC Key_O, the udk LEFT default) for a sustained window so
# the per-frame input_scan()/input_state_read() see it pressed across many
# frames and the hero walks left.  keydown/keyup bracket a real hold.
# 1.0s hold keeps the hero in its own pixel row (Y=120), clear of the enemy
# band (Y=64) — verified before/after centroid: x 430 -> 175, y unchanged (441).
DISPLAY="$DISP" xdotool keydown --window "$WID" o 2>/dev/null || DISPLAY="$DISP" xdotool keydown o
sleep 1.0
DISPLAY="$DISP" xdotool keyup --window "$WID" o 2>/dev/null || DISPLAY="$DISP" xdotool keyup o
sleep 0.4

# AFTER: hero should have moved left.
DISPLAY="$DISP" import -window root "$HERE/in6-demo-after.png"
echo "Wrote in6-demo-after.png (after holding LEFT)"

echo "DONE"
