#!/usr/bin/env bash
# Headless cap32 screenshot driver.
#
# Runs cap32 inside a dedicated Xvfb (a rootful X server) — NOT the live
# Wayland/:0 session, where root-window grabs come back black. Inside Xvfb,
# `import -window root` reliably captures the emulator, and xdotool can drive
# cap32's own F3 screen dump.
#
# Usage:  cd tools/cpc-poc && ../cap32-shot.sh [DISKFILE] [CPC_RUN_NAME]
#   DISKFILE     defaults to poc.dsk
#   CPC_RUN_NAME defaults to POC  (the AMSDOS binary on the disk)
set -euo pipefail

DISP=:99
RES=1024x768x24
DISK="${1:-poc.dsk}"
RUNNAME="${2:-POC}"
SHOT_DIR="$PWD/screenshots"
ROOT_SHOT="$PWD/shot.png"
LOG=/tmp/cap32-run.log

# --- cap32 lives outside PATH and the interactive `cap32` is a shell function
#     ("$CAP32DIR/cap32" -c "$CAP32DIR/cap32.cfg" "$@"). Replicate that here so
#     the emulator finds its ROMs via the cfg.
CAP32DIR="${CAP32DIR:-$HOME/src/cpc/caprice32}"
CAP32_BIN="$CAP32DIR/cap32"
CAP32_CFG="$CAP32DIR/cap32.cfg"

for f in "$CAP32_BIN" "$CAP32_CFG" "$DISK"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 1; }
done
for bin in Xvfb xdotool import; do
  command -v "$bin" >/dev/null || { echo "MISSING tool: $bin"; exit 1; }
done

cleanup() { kill "${CAP_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

# --- 1. Clear any stale server/lock on this display from a previous run.
if [ -e "/tmp/.X${DISP#:}-lock" ]; then
  echo "Display $DISP busy; clearing stale server."
  pkill -f "Xvfb $DISP" 2>/dev/null || true
  sleep 0.5
  rm -f "/tmp/.X${DISP#:}-lock"
fi

# --- 2. Start Xvfb and WAIT until it accepts connections (probe with xdotool,
#        since xdpyinfo isn't installed here).
Xvfb "$DISP" -screen 0 "$RES" >/dev/null 2>&1 &
XVFB_PID=$!
up=
for _ in $(seq 1 50); do
  if DISPLAY="$DISP" xdotool getdisplaygeometry >/dev/null 2>&1; then up=1; break; fi
  sleep 0.1
done
[ -n "$up" ] || { echo "Xvfb never came up"; exit 1; }

# --- 3. cap32's F3 dump fails silently if the target dir is missing.
mkdir -p "$SHOT_DIR"

# --- 4. Launch the emulator (with its cfg, so ROMs resolve). Keep stderr.
#        Force SDL's X11 backend onto our Xvfb: SDL2 would otherwise follow
#        WAYLAND_DISPLAY to the live compositor (leaving the Xvfb root black).
# NOTE the trailing '.' after the name: z88dk writes the AMSDOS file with an
# EMPTY extension, so `RUN"POC` (which AMSDOS expands to POC.BAS/POC.BIN) finds
# nothing — `RUN"POC.` selects the empty-extension file explicitly.
DISPLAY="$DISP" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
  "$CAP32_BIN" -c "$CAP32_CFG" -a "run\"$RUNNAME." "$DISK" >"$LOG" 2>&1 &
CAP_PID=$!

# --- 5. Give it time to boot + load (CPC6128 boot is a few seconds).
sleep 8
if ! kill -0 "$CAP_PID" 2>/dev/null; then
  echo "cap32 exited early. Log:"; cat "$LOG"; exit 1
fi

# --- 6a. PRIMARY: grab the virtual root window directly.
DISPLAY="$DISP" import -window root "$ROOT_SHOT"
echo "Wrote $ROOT_SHOT"

# --- 6b. SECONDARY: trigger cap32's own F3 clean-framebuffer dump (to the cfg's
#         sdump_dir). XSendEvent is ignored by SDL, so focus then send via XTEST.
WID=$(DISPLAY="$DISP" xdotool search --name Caprice 2>/dev/null | head -n1 || true)
if [ -n "${WID:-}" ]; then
  DISPLAY="$DISP" xdotool windowactivate --sync "$WID" 2>/dev/null || \
    DISPLAY="$DISP" xdotool windowfocus "$WID" 2>/dev/null || true
  DISPLAY="$DISP" xdotool key --clearmodifiers F3
  sleep 1
  echo "F3 sent; clean dump should be in cap32 sdump_dir (see cap32.cfg)."
else
  echo "No 'Caprice' window found (root grab above is still valid)."
fi
