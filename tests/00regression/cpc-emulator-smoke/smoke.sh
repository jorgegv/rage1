#!/usr/bin/env bash
# TS2-5 CPC emulator infrastructure smoke test.
#
# Feeds tools/cpc-poc/poc.dsk to Caprice32 headless (Xvfb + SDL x11), takes
# a screenshot via CAP32_SCRNSHOT autocmd, and exits.  Verifies the whole
# Xvfb + cap32 + autocmd chain works on this host.
#
# This directory is NOT a RAGE1 regression test — it is an emulator-infra
# smoke test committed to prove the headless screenshot chain works end-to-end.
# It will be removed at TS3 phase exit (after the real CPC regression lands).
#
# Usage:
#   bash tests/00regression/cpc-emulator-smoke/smoke.sh
#   # Output PNG: tests/00regression/cpc-emulator-smoke/actual.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DSK="$REPO_ROOT/tools/cpc-poc/poc.dsk"
OUT_PNG="$SCRIPT_DIR/actual.png"

CAP32DIR="${CAP32DIR:-$HOME/src/cpc/caprice32}"
CAP32_BIN="$CAP32DIR/cap32"
CAP32_CFG="$CAP32DIR/cap32.cfg"

# Xvfb display for headless rendering
DISP=:99
RES=640x480x24

# ---- dependency checks ----
for f in "$CAP32_BIN" "$CAP32_CFG" "$DSK"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 1; }
done
for bin in Xvfb xdpyinfo; do
  command -v "$bin" >/dev/null || { echo "MISSING tool: $bin"; exit 1; }
done

SCRNDIR=$(mktemp -d)
LOG="$SCRNDIR/cap32.log"

cleanup() {
  kill "${CAP_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
  rm -rf "$SCRNDIR"
}
trap cleanup EXIT

# ---- clear stale Xvfb lock ----
if [ -e "/tmp/.X${DISP#:}-lock" ]; then
  pkill -f "Xvfb $DISP" 2>/dev/null || true
  sleep 0.3
  rm -f "/tmp/.X${DISP#:}-lock"
fi

# ---- start Xvfb ----
Xvfb "$DISP" -screen 0 "$RES" >/dev/null 2>&1 &
XVFB_PID=$!
# wait up to 5s for it to be ready
up=
for _ in $(seq 1 50); do
  if DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1; then up=1; break; fi
  sleep 0.1
done
[ -n "$up" ] || { echo "Xvfb never came up"; exit 1; }

# ---- run cap32 with autocmd ----
# boot_time=300 (300 frames after boot before first autocmd fires)
# sdump_dir set to SCRNDIR (screenshot lands there with date-stamped name)
# Autocmd sequence:
#   run"poc.\r   — type the AMSDOS RUN command + Enter to launch the binary
#   CAP32_DELAY  — wait another boot_time frames for the program to start
#   CAP32_SCRNSHOT — save screenshot to sdump_dir/screenshot_<date>.png
#   CAP32_EXIT   — exit cap32 cleanly (returns 0)
DISPLAY="$DISP" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
  "$CAP32_BIN" -c "$CAP32_CFG" \
  -O "system.boot_time=300" \
  -O "file.sdump_dir=$SCRNDIR" \
  -a $'run"poc.\r' \
  -a "CAP32_DELAY" \
  -a "CAP32_SCRNSHOT" \
  -a "CAP32_EXIT" \
  "$DSK" >"$LOG" 2>&1 &
CAP_PID=$!

# wait up to 60s for cap32 to exit
for i in $(seq 1 120); do
  if ! kill -0 "$CAP_PID" 2>/dev/null; then break; fi
  sleep 0.5
done

if kill -0 "$CAP_PID" 2>/dev/null; then
  echo "cap32 did not exit within 60s — timeout"
  cat "$LOG"
  exit 1
fi
wait "$CAP_PID" || { echo "cap32 exited non-zero"; cat "$LOG"; exit 1; }

# ---- collect screenshot ----
SCRNFILE="$(ls "$SCRNDIR"/screenshot_*.png 2>/dev/null | head -1)"
if [ -z "$SCRNFILE" ]; then
  echo "No screenshot produced"
  cat "$LOG"
  exit 1
fi

cp "$SCRNFILE" "$OUT_PNG"
echo "OK: headless CPC screenshot at $OUT_PNG"
