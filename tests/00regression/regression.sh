#!/usr/bin/env bash
# RAGE1 multi-platform screenshot-based regression test suite.
#
# Drives the JNEXT emulator for ZX (zx48/zx128) baselines and Caprice32
# for CPC (cpc464) baselines. Each test declares the platforms it covers
# via the PLATFORMS key in test.conf; the runner builds, runs and compares
# one baseline per platform.
#
# Usage:
#   bash tests/00regression/regression.sh [--update] [--platform <name>] [test_name...]
#
#   --update            Capture a fresh reference.png for each selected test/platform
#                       (use after intended visual changes; review diffs before commit)
#   --platform <name>   Run/update only the named platform (zx48|zx128|cpc464|...)
#   test_name           Run only specified tests (default: all subdirs with test.conf)
#
# Env overrides:
#   JNEXT                 Path to jnext binary
#   JNEXT_SD_CARD         Path to NextZXOS SD-card image
#   JNEXT_TEST_TOLERANCE  ZX pixel-diff tolerance (default 0 = pixel-perfect)
#   CAPRICE32             Path to cap32 binary
#   CAPRICE32_CFG         Path to cap32.cfg
#
# Each test lives in tests/00regression/<name>/ with:
#   test.conf                — required, sourced by this script
#   <platform>/reference.png — checked-in baseline (created by --update)
#   <platform>/actual.png    — gitignored, last run's screenshot
#   <platform>/diff.png      — gitignored, only present on FAIL
#
# Back-compat (README §5.6, indefinite): if a test has a top-level
# reference.png but no <platform>/reference.png, the top-level file is used
# as the implicit baseline for the test's single declared platform.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---- emulator binary discovery ----------------------------------------

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
JNEXT_SD_CARD="${JNEXT_SD_CARD:-$HOME/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img}"

# Locate cap32 (Caprice32) binary + config
if [[ -z "${CAPRICE32:-}" ]]; then
    for candidate in "$HOME/src/cpc/caprice32/cap32" \
                     "/usr/local/bin/cap32" \
                     "/usr/bin/cap32"; do
        if [[ -x "$candidate" ]]; then
            CAPRICE32="$candidate"
            break
        fi
    done
fi
CAPRICE32="${CAPRICE32:-}"
CAPRICE32_CFG="${CAPRICE32_CFG:-$HOME/src/cpc/caprice32/cap32.cfg}"

TOLERANCE_DEFAULT="${JNEXT_TEST_TOLERANCE:-0}"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'

# ---- args -------------------------------------------------------------
UPDATE_MODE=false
PLATFORM_FILTER=""
FILTER_TESTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --update)   UPDATE_MODE=true; shift ;;
        --platform) PLATFORM_FILTER="${2:-}"; shift 2 ;;
        *)          FILTER_TESTS+=("$1"); shift ;;
    esac
done

# ---- common prereq: ImageMagick compare -------------------------------
if ! command -v compare &>/dev/null; then
    echo -e "${RED}ERROR: ImageMagick 'compare' not found${RESET}" >&2
    exit 1
fi

# Source RAGE1 env so z88dk is in PATH for make
if [[ -f "$PROJECT_DIR/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/env.sh" >/dev/null 2>&1
fi

# ---- platform helpers -------------------------------------------------

# Map a platform id to the JNEXT --machine value (ZX only).
zx_machine_for() {
    case "$1" in
        zx48)  echo "48k" ;;
        zx128) echo "128k" ;;
        *)     echo "" ;;
    esac
}

# True if the platform is a ZX (JNEXT) platform.
is_zx_platform()  { [[ "$1" == zx48 || "$1" == zx128 ]]; }
# True if the platform is a CPC (Caprice32) platform.
is_cpc_platform() { [[ "$1" == cpc* ]]; }

# Build the game for a given platform. Echoes the absolute path of the
# produced artefact on stdout; returns non-zero on build failure.
#   $1 = platform   $2 = TARGET_GAME (e.g. games/minimal_cpc)
build_for_platform() {
    local platform="$1" target_game="$2" game_base
    game_base="$(basename "$target_game")"
    if is_cpc_platform "$platform"; then
        # CPC engine-full games link via a dedicated make target
        # (CPC_LINK_ENGINE_FULL=1); there is no generic
        # `make build target_game=... PLATFORM=cpc464` path yet (G8 scope:
        # cpc-flat / cpc464; the unified PLATFORM= knob arrives with T3).
        ( cd "$PROJECT_DIR" && make "build-${game_base}" >/dev/null 2>&1 ) || return 1
        echo "$PROJECT_DIR/game.dsk"
    else
        ( cd "$PROJECT_DIR" \
            && make clean >/dev/null 2>&1 \
            && make build target_game="$target_game" >/dev/null 2>&1 ) || return 1
        echo "$PROJECT_DIR/game.tap"
    fi
}

# Run JNEXT for a ZX platform and capture a screenshot.
#   $1 platform  $2 artefact(tap)  $3 frames  $4 out_png  $5 extra_args
run_emulator_zx() {
    local platform="$1" artefact="$2" frames="$3" out_png="$4" extra="$5"
    local machine exit_delay wall_timeout
    machine="$(zx_machine_for "$platform")"
    exit_delay=$(( frames / 25 + 5 ))
    [[ $exit_delay -lt 10 ]] && exit_delay=10
    wall_timeout=$(( (exit_delay + 5) * 4 ))
    # shellcheck disable=SC2206
    local extra_array=($extra)
    timeout --kill-after=5s "${wall_timeout}s" \
        "$JNEXT" --headless \
        --sd-card "$JNEXT_SD_CARD" \
        --machine "$machine" \
        --load "$artefact" \
        --delayed-screenshot "$out_png" \
        --delayed-screenshot-frames "$frames" \
        --delayed-automatic-exit "$exit_delay" \
        "${extra_array[@]}" \
        >/dev/null 2>&1 || true
}

# Run Caprice32 for a CPC platform and capture a screenshot.
# The screenshot fires at ~2*boot_time emulated frames (boot wait +
# CAP32_DELAY), which is fully deterministic frame-counted timing — the
# "frames" arg is consumed as system.boot_time. RUN name is the AMSDOS
# binary name inside game.dsk (always "game" for cpc-flat builds).
#   $1 platform  $2 artefact(dsk)  $3 boot_frames  $4 out_png
run_emulator_cpc() {
    local platform="$1" artefact="$2" boot_frames="$3" out_png="$4"
    local disp=":99" res="640x480x24" scrndir model_opt=""
    [[ "$platform" == "cpc6128" ]] && model_opt="-O system.model=2"  # 0=464, 2=6128
    scrndir="$(mktemp -d)"

    if [[ -e "/tmp/.X${disp#:}-lock" ]]; then
        pkill -f "Xvfb $disp" 2>/dev/null || true
        sleep 0.3
        rm -f "/tmp/.X${disp#:}-lock"
    fi
    Xvfb "$disp" -screen 0 "$res" >/dev/null 2>&1 &
    local xvfb_pid=$!
    local up=""
    for _ in $(seq 1 50); do
        if DISPLAY="$disp" xdpyinfo >/dev/null 2>&1; then up=1; break; fi
        sleep 0.1
    done
    if [[ -z "$up" ]]; then
        kill "$xvfb_pid" 2>/dev/null || true
        rm -rf "$scrndir"
        return 1
    fi

    # WAYLAND_DISPLAY= deliberately clears the var for the cap32 subprocess so
    # SDL2 uses the Xvfb X11 server, not the host Wayland compositor.
    # shellcheck disable=SC1007,SC2086
    DISPLAY="$disp" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
        "$CAPRICE32" -c "$CAPRICE32_CFG" \
        $model_opt \
        -O "system.boot_time=$boot_frames" \
        -O "file.sdump_dir=$scrndir" \
        -a $'run"game.\r' \
        -a "CAP32_DELAY" \
        -a "CAP32_SCRNSHOT" \
        -a "CAP32_EXIT" \
        "$artefact" >"$scrndir/cap32.log" 2>&1 &
    local cap_pid=$!
    for _ in $(seq 1 240); do
        kill -0 "$cap_pid" 2>/dev/null || break
        sleep 0.5
    done
    kill "$cap_pid" 2>/dev/null || true
    kill "$xvfb_pid" 2>/dev/null || true

    local shot
    shot="$(ls "$scrndir"/screenshot_*.png 2>/dev/null | sort | head -1)"
    if [[ -n "$shot" ]]; then
        cp "$shot" "$out_png"
    fi
    rm -rf "$scrndir"
}

# Per-platform emulator prereq guard. Returns non-zero (and prints) if the
# emulator for the platform is unavailable.
check_emulator_for() {
    local platform="$1"
    if is_zx_platform "$platform"; then
        if [[ -z "$JNEXT" || ! -x "$JNEXT" ]]; then
            echo -e "${RED}ERROR: jnext binary not found (set JNEXT=...)${RESET}" >&2
            return 1
        fi
        if [[ ! -f "$JNEXT_SD_CARD" ]]; then
            echo -e "${RED}ERROR: SD-card image not found at $JNEXT_SD_CARD (set JNEXT_SD_CARD=...)${RESET}" >&2
            return 1
        fi
    elif is_cpc_platform "$platform"; then
        if [[ -z "$CAPRICE32" || ! -x "$CAPRICE32" ]]; then
            echo -e "${RED}ERROR: cap32 binary not found (set CAPRICE32=...)${RESET}" >&2
            return 1
        fi
        if [[ ! -f "$CAPRICE32_CFG" ]]; then
            echo -e "${RED}ERROR: cap32 config not found at $CAPRICE32_CFG (set CAPRICE32_CFG=...)${RESET}" >&2
            return 1
        fi
        for bin in Xvfb xdpyinfo; do
            command -v "$bin" >/dev/null || {
                echo -e "${RED}ERROR: '$bin' not found (needed for headless CPC)${RESET}" >&2
                return 1
            }
        done
    else
        echo -e "${RED}ERROR: unknown platform '$platform'${RESET}" >&2
        return 1
    fi
}

# ---- test discovery ---------------------------------------------------
ALL_TESTS=()
for d in "$SCRIPT_DIR"/*/; do
    [[ -d "$d" && -f "$d/test.conf" ]] || continue
    ALL_TESTS+=("$(basename "$d")")
done

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

pass=0; fail=0; updated=0; skipped=0
declare -A platform_pass platform_fail

echo -e "${BOLD}=== RAGE1 Multi-platform Regression ===${RESET}"
[[ -n "$JNEXT"     ]] && echo "  jnext:    $JNEXT"
[[ -n "$CAPRICE32" ]] && echo "  cap32:    $CAPRICE32"
[[ -n "$PLATFORM_FILTER" ]] && echo -e "  filter:   ${YELLOW}platform=$PLATFORM_FILTER${RESET}"
$UPDATE_MODE && echo -e "  mode:     ${YELLOW}UPDATE (capturing baselines)${RESET}"
echo ""

for test_name in "${ALL_TESTS[@]}"; do
    test_dir="$SCRIPT_DIR/$test_name"
    conf="$test_dir/test.conf"

    # Reset and source per-test config
    TARGET_GAME=""; MACHINE=""; PLATFORMS=""; DELAY_FRAMES=""
    EXTRA_ARGS=""; SKIP_REGRESSION=""
    # shellcheck disable=SC1090
    source "$conf"

    if [[ "$SKIP_REGRESSION" == "true" ]]; then
        printf "  %-25s " "[$test_name]"
        echo -e "${YELLOW}SKIP${RESET} (SKIP_REGRESSION=true in test.conf)"
        skipped=$((skipped + 1))
        continue
    fi

    # Derive the platform list. Back-compat: if PLATFORMS is absent, derive
    # from the legacy MACHINE field (48k -> zx48, 128k -> zx128); default zx48.
    if [[ -z "$PLATFORMS" ]]; then
        case "$MACHINE" in
            128k) PLATFORMS="zx128" ;;
            48k)  PLATFORMS="zx48" ;;
            *)    PLATFORMS="zx48" ;;
        esac
    fi

    for platform in $PLATFORMS; do
        # Honour --platform filter
        if [[ -n "$PLATFORM_FILTER" && "$platform" != "$PLATFORM_FILTER" ]]; then
            continue
        fi

        printf "  %-18s %-8s " "[$test_name]" "$platform"

        # Per-platform reference baseline, with indefinite top-level
        # back-compat fallback (README §5.6).
        plat_dir="$test_dir/$platform"
        ref_img="$plat_dir/reference.png"
        if [[ ! -f "$ref_img" && -f "$test_dir/reference.png" ]]; then
            ref_img="$test_dir/reference.png"   # implicit single-platform baseline
        fi
        out_img="$plat_dir/actual.png"
        diff_img="$plat_dir/diff.png"

        # Per-platform tolerance: TOLERANCE_<PLATFORM> overrides default.
        tol_var="TOLERANCE_$(echo "$platform" | tr '[:lower:]' '[:upper:]')"
        tol="${!tol_var:-$TOLERANCE_DEFAULT}"

        # Per-platform delay: DELAY_FRAMES_<PLATFORM> overrides DELAY_FRAMES.
        delay_var="DELAY_FRAMES_$(echo "$platform" | tr '[:lower:]' '[:upper:]')"
        frames="${!delay_var:-$DELAY_FRAMES}"

        if [[ -z "$TARGET_GAME" || -z "$frames" ]]; then
            echo -e "${RED}FAIL${RESET} (test.conf missing TARGET_GAME / DELAY_FRAMES[_$platform])"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
            continue
        fi

        if ! check_emulator_for "$platform"; then
            echo -e "${RED}FAIL${RESET} (emulator for $platform unavailable)"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
            continue
        fi

        # Build for this platform; capture artefact path.
        if ! artefact="$(build_for_platform "$platform" "$TARGET_GAME")"; then
            echo -e "${RED}FAIL${RESET} (build failed for $TARGET_GAME @ $platform)"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
            continue
        fi
        if [[ ! -f "$artefact" ]]; then
            echo -e "${RED}FAIL${RESET} (artefact $(basename "$artefact") not produced)"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
            continue
        fi

        mkdir -p "$plat_dir"
        cp "$artefact" "$plat_dir/$(basename "$artefact")"   # stash for debug
        rm -f "$out_img" "$diff_img"

        # Dispatch to the right emulator.
        if is_zx_platform "$platform"; then
            run_emulator_zx "$platform" "$artefact" "$frames" "$out_img" "$EXTRA_ARGS"
        else
            run_emulator_cpc "$platform" "$artefact" "$frames" "$out_img"
        fi

        if [[ ! -f "$out_img" ]]; then
            echo -e "${RED}FAIL${RESET} (emulator produced no screenshot)"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
            continue
        fi

        if $UPDATE_MODE; then
            cp "$out_img" "$plat_dir/reference.png"
            echo -e "${YELLOW}UPDATED${RESET} ($plat_dir/reference.png)"
            updated=$((updated + 1))
            continue
        fi

        if [[ ! -f "$ref_img" ]]; then
            echo -e "${YELLOW}SKIP${RESET} (no reference.png — run with --update first)"
            skipped=$((skipped + 1))
            continue
        fi

        diff_raw=$(compare -metric AE "$out_img" "$ref_img" /dev/null 2>&1) || true
        diff_pixels=$(echo "$diff_raw" | awk '{printf "%d", $1+0}' 2>/dev/null || echo 999999)
        if [[ "$diff_pixels" -le "$tol" ]]; then
            echo -e "${GREEN}PASS${RESET} (${diff_pixels} px diff, tol $tol)"
            pass=$((pass + 1)); platform_pass[$platform]=$(( ${platform_pass[$platform]:-0} + 1 ))
        else
            compare "$out_img" "$ref_img" "$diff_img" 2>/dev/null || true
            echo -e "${RED}FAIL${RESET} (${diff_pixels} px differ, tol $tol — see $diff_img)"
            fail=$((fail + 1)); platform_fail[$platform]=$(( ${platform_fail[$platform]:-0} + 1 ))
        fi
    done
done

echo ""
echo -e "${BOLD}=== Results ===${RESET}"
if $UPDATE_MODE; then
    echo -e "  ${YELLOW}Updated: $updated${RESET}  ${RED}Fail: $fail${RESET}  ${YELLOW}Skip: $skipped${RESET}"
else
    echo -e "  ${GREEN}Pass: $pass${RESET}  ${RED}Fail: $fail${RESET}  ${YELLOW}Skip: $skipped${RESET}"
    # Per-platform breakdown (union of platforms seen in pass / fail maps)
    seen_platforms=("${!platform_pass[@]}" "${!platform_fail[@]}")
    if [[ ${#seen_platforms[@]} -gt 0 ]]; then
        for p in $(printf '%s\n' "${seen_platforms[@]}" | sort -u); do
            [[ -z "$p" ]] && continue
            echo -e "    ${p}: ${GREEN}${platform_pass[$p]:-0} pass${RESET}, ${RED}${platform_fail[$p]:-0} fail${RESET}"
        done
    fi
fi

[[ $fail -gt 0 ]] && exit 1
exit 0
