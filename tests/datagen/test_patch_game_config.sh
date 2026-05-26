#!/usr/bin/env bash
#
# A2-5: End-to-end regression smoke test for PATCH_GAME_CONFIG.
#
# Drops a transient patches/game_config/override.gdata into games/minimal
# that adds a BEGIN_CPC_COLOR_MAP block (a per-platform tweak that touches
# only a small subset of GAME_CONFIG fields), builds the game, asserts:
#
#   1. The build succeeds.
#   2. The patched value (CPC_COLOR_MAP) is parsed without error.
#   3. The rest of game_config (e.g. LIVES_AREA / GAME_AREA) is inherited
#      verbatim from the shared GAME_CONFIG (no regressions).
#
# This locks in the §5.11 'surgical merge' contract: overlays restate only
# what changes, and the rest stays inherited.
#
# Per assets.md A2-5 — synthetic ZX-side overlay form, since CPC isn't
# standing yet. On ZX the CPC_COLOR_MAP block is parsed and dropped (with
# a 'parsed and dropped' warning); the build succeeds either way.
#
# Usage:
#   bash tests/datagen/test_patch_game_config.sh
#
# Exits 0 on success, 1 on failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

TEST_GAME="games/minimal"
PATCH_DIR="$TEST_GAME/game_data/patches/game_config"
PATCH_FILE="$PATCH_DIR/_a2_5_test_override.gdata"

# Always clean up the transient patch on exit, even on failure.
cleanup() {
    rm -f "$PATCH_FILE" 2>/dev/null
    rmdir "$PATCH_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# 1. Capture pre-patch reference values for non-patched fields.
BASELINE_LIVES_AREA="$(grep -hE '^\s*LIVES_AREA\s+' "$TEST_GAME"/game_data/game_config/*.gdata | head -1)"
if [[ -z "${BASELINE_LIVES_AREA}" ]]; then
    echo "** Error: baseline LIVES_AREA not found in games/minimal — test setup broken" >&2
    exit 1
fi

# 2. Drop the transient PATCH_GAME_CONFIG file.
mkdir -p "$PATCH_DIR"
cat > "$PATCH_FILE" <<'EOF'
// A2-5 regression: PATCH_GAME_CONFIG with a CPC_COLOR_MAP-only override.
// The shared GAME_CONFIG defines all the standard fields (LIVES_AREA,
// GAME_AREA, HERO, etc.); this patch only adds a CPC firmware-colour map.
// On ZX the map is parsed and dropped (a warning is emitted, expected).

PATCH_GAME_CONFIG
	BEGIN_CPC_COLOR_MAP
		BLACK	FW=0
		WHITE	FW=26
		RED	FW=6
	END_CPC_COLOR_MAP
END_GAME_CONFIG
EOF

# 3. Build the game; capture log for inspection.
LOG="/tmp/test_patch_game_config.log"
if ! PERL_HASH_SEED=0 make build-minimal >"$LOG" 2>&1; then
    echo "** Error: build-minimal failed after PATCH_GAME_CONFIG drop — see $LOG" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

# 4. Assert the build produced a tap.
if [[ ! -f game.tap ]]; then
    echo "** Error: build-minimal produced no game.tap" >&2
    exit 1
fi

# 5. Assert non-patched fields are inherited verbatim from shared.
GENERATED_HEADER="build/generated/game_data.h"
if [[ ! -f "$GENERATED_HEADER" ]]; then
    echo "** Error: $GENERATED_HEADER not generated" >&2
    exit 1
fi

# LIVES_AREA values must come from shared (not modified by the patch).
EXPECTED_LIVES_TOP="$(echo "$BASELINE_LIVES_AREA" | grep -oP 'TOP=\K\d+')"
EXPECTED_LIVES_LEFT="$(echo "$BASELINE_LIVES_AREA" | grep -oP 'LEFT=\K\d+')"
ACTUAL_LIVES_TOP="$(grep -E '^\s*#define\s+LIVES_AREA_TOP\b' "$GENERATED_HEADER" | awk '{print $NF}')"
ACTUAL_LIVES_LEFT="$(grep -E '^\s*#define\s+LIVES_AREA_LEFT\b' "$GENERATED_HEADER" | awk '{print $NF}')"

if [[ "$ACTUAL_LIVES_TOP" != "$EXPECTED_LIVES_TOP" ]]; then
    echo "** Error: LIVES_AREA_TOP regression: expected '$EXPECTED_LIVES_TOP' (from shared), got '$ACTUAL_LIVES_TOP'" >&2
    exit 1
fi
if [[ "$ACTUAL_LIVES_LEFT" != "$EXPECTED_LIVES_LEFT" ]]; then
    echo "** Error: LIVES_AREA_LEFT regression: expected '$EXPECTED_LIVES_LEFT' (from shared), got '$ACTUAL_LIVES_LEFT'" >&2
    exit 1
fi

# 6. Confirm CPC_COLOR_MAP was parsed without dying (the build succeeded;
#    on ZX the block is dropped with a warning, which is the expected
#    behaviour per A1-7 / assets.md §5.10).
if grep -q "CPC_COLOR_MAP:.*not.*recognized" "$LOG"; then
    echo "** Error: CPC_COLOR_MAP parser failure detected in $LOG" >&2
    grep "CPC_COLOR_MAP" "$LOG" >&2
    exit 1
fi

echo "PASS: PATCH_GAME_CONFIG end-to-end smoke test"
echo "      - build-minimal succeeded with transient PATCH_GAME_CONFIG patch"
echo "      - non-patched fields (LIVES_AREA: TOP=$ACTUAL_LIVES_TOP LEFT=$ACTUAL_LIVES_LEFT) inherited verbatim from shared"
echo "      - CPC_COLOR_MAP block parsed cleanly (dropped on ZX as expected)"
exit 0
