#!/bin/bash
#
# tools/check-input-hal-clean.sh
#
# Phase IN3-5 of the cross-platform input HAL refactor
# (doc/multiplatform-plan/input.md §5 Phase IN3).
#
# Purpose: enforce that the engine source under engine/src/,
# engine/banked_code/, engine/lowmem/, and engine/include/ talks to
# input strictly through the HAL surface (rage1/input.h) and never
# pulls z88dk's <input.h> or names z88dk-specific input symbols
# directly. The two HAL implementation files — rage1/input_zx.h and
# engine/src/input.c — are the only files where the legacy symbols
# may legitimately appear; they are excluded from the scan.
#
# This is a hard CI guard: any match outside the excluded files is a
# failure. It is the IN3-exit invariant for input.md §5.
#
# Usage:
#   tools/check-input-hal-clean.sh          # check, prints diagnostics
#   tools/check-input-hal-clean.sh --quiet  # check, silent on success
#
# Exit codes:
#   0 = engine input surface is HAL-clean
#   1 = at least one legacy z88dk input symbol leaked outside the HAL
#   2 = invocation / environment error

set -u

QUIET=0
if [ "${1:-}" = "--quiet" ]; then
    QUIET=1
fi

# Resolve repo root from the script location (tools/ is at repo root).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCAN_ROOTS=(
    "$REPO_ROOT/engine/src"
    "$REPO_ROOT/engine/banked_code"
    "$REPO_ROOT/engine/lowmem"
    "$REPO_ROOT/engine/include"
)

# Existence check (engine/lowmem/ may be absent in some checkouts).
for d in "${SCAN_ROOTS[@]}"; do
    if [ ! -d "$d" ]; then
        # Quietly drop missing directories from the scan list.
        :
    fi
done

# Files where the legacy symbols are allowed (relative to REPO_ROOT).
# Per the IN3 spec the two HAL implementation files are exempt:
#   - engine/include/rage1/input_zx.h  : the ZX backend wrapper, which
#                                        includes <input.h> and defines
#                                        the input_* -> in_* macros.
#   - engine/include/rage1/input_cpc.h : the CPC backend wrapper (Phase
#                                        IN5), analogue of input_zx.h;
#                                        its prose comments reference the
#                                        ZX symbols (in_pause/in_inkey)
#                                        to document the cross-platform
#                                        mapping, and IN6 names cpctelera
#                                        symbols here.
#   - engine/src/input.c               : the dispatch body for
#                                        input_state_read; calls the
#                                        z88dk `in_stick_*` primitives.
# We also exempt engine/include/rage1/input.h itself: that header is
# the HAL umbrella and its prose comments necessarily reference the
# backend symbols (e.g. "ZX: macro that calls in_key_pressed") to
# document each prototype's mapping.
ALLOWED_REL=(
    "engine/include/rage1/input.h"
    "engine/include/rage1/input_zx.h"
    "engine/include/rage1/input_cpc.h"
    "engine/src/input.c"
)

is_allowed() {
    local f="$1"
    local a
    for a in "${ALLOWED_REL[@]}"; do
        if [ "$f" = "$a" ]; then return 0; fi
    done
    return 1
}

# Symbol matchers. Each entry is "label|regex". The regex is fed to
# `grep -nE`; word boundaries (\b) keep us from matching substrings
# (e.g. plain English text like "input.h" in a comment, or a
# `INPUT_STATE_FIRE` HAL constant getting caught by a loose `IN_STICK`
# match). We deliberately keep `<input.h>` as a literal include-line
# match (the comments in input.h / input_zx.h that mention "<input.h>"
# in prose are NOT preceded by `#include` so they survive).
PATTERNS=(
    'z88dk <input.h> include|#[[:space:]]*include[[:space:]]*<input\.h>'
    'in_inkey|\<in_inkey\>'
    'in_pause|\<in_pause(_fastcall)?\>'
    'in_wait_*|\<in_wait_(key|nokey)\>'
    'in_test_key|\<in_test_key\>'
    'in_key_pressed|\<in_key_pressed(_fastcall)?\>'
    'in_stick_*|\<in_stick_(keyboard|kempston|sinclair[12]|cursor|fuller)(_fastcall)?\>'
    'in_key_scancode|\<in_key_scancode(_fastcall)?\>'
    'IN_STICK_*|\<IN_STICK_(UP|DOWN|LEFT|RIGHT|FIRE(_[123])?)\>'
    'IN_KEY_SCANCODE_*|\<IN_KEY_SCANCODE_[A-Za-z0-9_]+\>'
    'udk_s|\<udk_s\>'
)

# Build the actual grep target list. Only scan source-y files; skip
# the build artefacts (.lis, .map, .o, .bin, ...) that the compiler
# scatters under engine/src and that legitimately quote every z88dk
# library symbol.
TARGETS_REL=()
for root in "${SCAN_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' f; do
        rel="${f#"$REPO_ROOT"/}"
        # Skip HAL-allowlisted files.
        if is_allowed "$rel"; then continue; fi
        TARGETS_REL+=("$rel")
    done < <(find "$root" -type f \( -name '*.c' -o -name '*.h' -o -name '*.asm' -o -name '*.s' -o -name '*.inc' \) -print0)
done

if [ "${#TARGETS_REL[@]}" -eq 0 ]; then
    echo "check-input-hal-clean: no source files found under scan roots" >&2
    exit 2
fi

# Run each pattern; collect violations.
VIOLATIONS=()
for pat in "${PATTERNS[@]}"; do
    label="${pat%%|*}"
    regex="${pat#*|}"
    # Use `grep -nE -H` for "file:line:text" output.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        VIOLATIONS+=("[$label] $line")
    done < <(
        # cd to REPO_ROOT so grep prints repo-relative paths.
        cd "$REPO_ROOT" && grep -nHE "$regex" "${TARGETS_REL[@]}" 2>/dev/null
    )
done

if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
    echo "check-input-hal-clean: FAIL" >&2
    echo "  Engine source outside the HAL allowlist references legacy z88dk" >&2
    echo "  input symbols. Allowed files (per Phase IN3 spec):" >&2
    for a in "${ALLOWED_REL[@]}"; do echo "    - $a" >&2; done
    echo "" >&2
    echo "  Violations:" >&2
    for v in "${VIOLATIONS[@]}"; do
        echo "    $v" >&2
    done
    echo "" >&2
    echo "  Fix: replace direct z88dk-input usage with the HAL surface" >&2
    echo "  declared in rage1/input.h (input_state_read, input_key_pressed," >&2
    echo "  input_wait_key, input_wait_nokey, input_lookup_key, input_scan)." >&2
    exit 1
fi

if [ "$QUIET" -eq 0 ]; then
    echo "check-input-hal-clean: OK"
    echo "  scanned ${#TARGETS_REL[@]} files under:"
    for root in "${SCAN_ROOTS[@]}"; do
        [ -d "$root" ] && echo "    - ${root#"$REPO_ROOT"/}"
    done
    echo "  HAL allowlist (legacy symbols permitted here):"
    for a in "${ALLOWED_REL[@]}"; do echo "    - $a"; done
fi

exit 0
