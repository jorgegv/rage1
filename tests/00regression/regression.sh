#!/usr/bin/env bash
# RAGE1 screenshot-based regression test suite, driven by the JNEXT emulator.
#
# Usage:
#   bash tests/00regression/regression.sh [--update] [test_name...]
#
#   --update      Capture a fresh reference.png for each selected test
#                 (use after intended visual changes; review the diffs before committing)
#   test_name     Run only specified tests (default: all subdirs of tests/00regression/)
#
# Env overrides:
#   JNEXT             Path to jnext binary
#   JNEXT_SD_CARD     Path to NextZXOS SD-card image
#   JNEXT_TEST_TOLERANCE  Pixel-diff tolerance (default 0 = pixel-perfect)
#
# Each test lives in tests/00regression/<name>/ with:
#   test.conf       — required, sourced by this script
#   reference.png   — checked-in baseline (created by --update)
#   actual.png      — gitignored, last run's screenshot
#   diff.png        — gitignored, only present on FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Locate jnext binary
if [[ -z "${JNEXT:-}" ]]; then
    for candidate in "$HOME/src/spectrum/jnext/build/gui-release/jnext" \
                     "$HOME/src/spectrum/jnext/build/gui-debug/jnext" \
                     "$HOME/src/spectrum/jnext/build/jnext"; do
        if [[ -x "$candidate" ]]; then
            JNEXT="$candidate"
            break
        fi
    done
fi
JNEXT="${JNEXT:-}"

# Default SD-card image (overridable)
JNEXT_SD_CARD="${JNEXT_SD_CARD:-$HOME/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img}"

TOLERANCE="${JNEXT_TEST_TOLERANCE:-0}"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'

# Args
UPDATE_MODE=false
FILTER_TESTS=()
for arg in "$@"; do
    if [[ "$arg" == "--update" ]]; then
        UPDATE_MODE=true
    else
        FILTER_TESTS+=("$arg")
    fi
done

# Prereqs
if [[ -z "$JNEXT" || ! -x "$JNEXT" ]]; then
    echo -e "${RED}ERROR: jnext binary not found. Set JNEXT=... or build at ~/src/spectrum/jnext/build/gui-release/jnext${RESET}" >&2
    exit 1
fi
if [[ ! -f "$JNEXT_SD_CARD" ]]; then
    echo -e "${RED}ERROR: SD-card image not found at $JNEXT_SD_CARD. Set JNEXT_SD_CARD=...${RESET}" >&2
    exit 1
fi
if ! command -v compare &>/dev/null; then
    echo -e "${RED}ERROR: ImageMagick 'compare' not found${RESET}" >&2
    exit 1
fi

# Source RAGE1 env so z88dk is in PATH for make
if [[ -f "$PROJECT_DIR/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/env.sh" >/dev/null 2>&1
fi

# Discover tests (subdirs of SCRIPT_DIR with test.conf)
ALL_TESTS=()
for d in "$SCRIPT_DIR"/*/; do
    [[ -d "$d" && -f "$d/test.conf" ]] || continue
    ALL_TESTS+=("$(basename "$d")")
done

# Apply filter
if [[ ${#FILTER_TESTS[@]} -gt 0 ]]; then
    SELECTED=()
    for t in "${FILTER_TESTS[@]}"; do
        if [[ -f "$SCRIPT_DIR/$t/test.conf" ]]; then
            SELECTED+=("$t")
        else
            echo -e "${YELLOW}WARN: no test '$t' under $SCRIPT_DIR${RESET}" >&2
        fi
    done
    ALL_TESTS=("${SELECTED[@]}")
fi

if [[ ${#ALL_TESTS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No tests to run${RESET}"
    exit 0
fi

pass=0; fail=0; updated=0

echo -e "${BOLD}=== RAGE1 Regression (jnext) ===${RESET}"
echo "  jnext:   $JNEXT"
echo "  sd:      $JNEXT_SD_CARD"
$UPDATE_MODE && echo -e "  mode:    ${YELLOW}UPDATE (capturing baselines)${RESET}"
echo ""

for test_name in "${ALL_TESTS[@]}"; do
    test_dir="$SCRIPT_DIR/$test_name"
    conf="$test_dir/test.conf"
    ref_img="$test_dir/reference.png"
    out_img="$test_dir/actual.png"
    diff_img="$test_dir/diff.png"

    # Reset and source per-test config
    TARGET_GAME=""; MACHINE=""; DELAY_FRAMES=""; EXTRA_ARGS=""
    # shellcheck disable=SC1090
    source "$conf"

    printf "  %-25s " "[$test_name]"

    if [[ -z "$TARGET_GAME" || -z "$MACHINE" || -z "$DELAY_FRAMES" ]]; then
        echo -e "${RED}FAIL${RESET} (test.conf missing TARGET_GAME/MACHINE/DELAY_FRAMES)"
        fail=$((fail + 1))
        continue
    fi

    # Build the game (sequential so ./game.tap is not clobbered)
    if ! (cd "$PROJECT_DIR" && make clean >/dev/null 2>&1 && make build target_game="$TARGET_GAME" >/dev/null 2>&1); then
        echo -e "${RED}FAIL${RESET} (build failed for $TARGET_GAME)"
        fail=$((fail + 1))
        continue
    fi

    if [[ ! -f "$PROJECT_DIR/game.tap" ]]; then
        echo -e "${RED}FAIL${RESET} (game.tap not produced)"
        fail=$((fail + 1))
        continue
    fi

    # Wall-clock safety: assume >= 25 emulated fps headless
    exit_delay=$(( DELAY_FRAMES / 25 + 5 ))
    [[ $exit_delay -lt 10 ]] && exit_delay=10
    wall_timeout=$(( (exit_delay + 5) * 4 ))

    # Stash the produced TAP into the test dir for debug; emulator loads from there
    cp "$PROJECT_DIR/game.tap" "$test_dir/game.tap"

    rm -f "$out_img" "$diff_img"

    # shellcheck disable=SC2206
    extra_array=($EXTRA_ARGS)
    if ! timeout --kill-after=5s "${wall_timeout}s" \
        "$JNEXT" --headless \
        --sd-card "$JNEXT_SD_CARD" \
        --machine "$MACHINE" \
        --load "$test_dir/game.tap" \
        --delayed-screenshot "$out_img" \
        --delayed-screenshot-frames "$DELAY_FRAMES" \
        --delayed-automatic-exit "$exit_delay" \
        "${extra_array[@]}" \
        >/dev/null 2>&1; then
        : # non-zero exit is OK if the screenshot was still produced
    fi

    if [[ ! -f "$out_img" ]]; then
        echo -e "${RED}FAIL${RESET} (jnext produced no screenshot)"
        fail=$((fail + 1))
        continue
    fi

    if $UPDATE_MODE; then
        cp "$out_img" "$ref_img"
        echo -e "${YELLOW}UPDATED${RESET}"
        updated=$((updated + 1))
        continue
    fi

    if [[ ! -f "$ref_img" ]]; then
        echo -e "${YELLOW}SKIP${RESET} (no reference.png — run with --update first)"
        continue
    fi

    diff_raw=$(compare -metric AE "$out_img" "$ref_img" /dev/null 2>&1) || true
    diff_pixels=$(echo "$diff_raw" | awk '{printf "%d", $1+0}' 2>/dev/null || echo 999999)
    if [[ "$diff_pixels" -le "$TOLERANCE" ]]; then
        echo -e "${GREEN}PASS${RESET} (${diff_pixels} px diff)"
        pass=$((pass + 1))
    else
        compare "$out_img" "$ref_img" "$diff_img" 2>/dev/null || true
        echo -e "${RED}FAIL${RESET} (${diff_pixels} px differ — see $diff_img)"
        fail=$((fail + 1))
    fi
done

echo ""
echo -e "${BOLD}=== Results ===${RESET}"
if $UPDATE_MODE; then
    echo -e "  ${YELLOW}Updated: $updated${RESET}  ${RED}Fail: $fail${RESET}"
else
    echo -e "  ${GREEN}Pass: $pass${RESET}  ${RED}Fail: $fail${RESET}"
fi

[[ $fail -gt 0 ]] && exit 1
exit 0
