#!/bin/bash
#
# tools/check-input-include-guard.sh
#
# Phase IN1-3 of the cross-platform input HAL refactor
# (doc/multiplatform-plan/input.md §5 Phase IN1).
#
# Purpose: prevent new C files under engine/banked_code/ from
# `#include <input.h>` (the z88dk-specific keyboard/joystick header).
# Only the files in the ALLOWED list are permitted to include it; any
# new offender causes a non-zero exit so CI catches the regression.
#
# The migration that removes <input.h> from the allowed file(s) is
# tracked separately in Phase IN3 of the same document.
#
# Usage:
#   tools/check-input-include-guard.sh          # check, prints diagnostics
#   tools/check-input-include-guard.sh --quiet  # check, silent on success
#
# Exit codes:
#   0 = banked-code <input.h> include surface matches the allowed list
#   1 = a NEW file under engine/banked_code/ includes <input.h>
#   2 = invocation / environment error

set -u

QUIET=0
if [ "${1:-}" = "--quiet" ]; then
    QUIET=1
fi

# Resolve repo root from the script location (tools/ is at repo root).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCAN_DIR="$REPO_ROOT/engine/banked_code"

if [ ! -d "$SCAN_DIR" ]; then
    echo "check-input-include-guard: scan directory not found: $SCAN_DIR" >&2
    exit 2
fi

# Allowed files (paths relative to repo root). Frozen at Phase IN1 exit.
# Rationale and re-grep procedure: see
# doc/multiplatform-plan/input-baseline-coverage.md §IN1-3.
ALLOWED=(
    "engine/banked_code/common/hero.c"
)

# Find every file under engine/banked_code/ that #include's <input.h>.
# `grep -rl` returns absolute or relative paths depending on the input;
# we feed it the absolute SCAN_DIR and then strip REPO_ROOT/ to get
# repo-relative paths for the diff against ALLOWED.
mapfile -t FOUND_ABS < <(grep -rl '#include[[:space:]]*<input\.h>' "$SCAN_DIR" 2>/dev/null | LC_ALL=C sort)

FOUND_REL=()
for f in "${FOUND_ABS[@]}"; do
    FOUND_REL+=("${f#"$REPO_ROOT"/}")
done

# Diff: anything in FOUND_REL that is not in ALLOWED is a violation.
VIOLATIONS=()
for f in "${FOUND_REL[@]}"; do
    is_allowed=0
    for a in "${ALLOWED[@]}"; do
        if [ "$f" = "$a" ]; then
            is_allowed=1
            break
        fi
    done
    if [ "$is_allowed" -eq 0 ]; then
        VIOLATIONS+=("$f")
    fi
done

# Reverse check (informational, not fatal): an allowed file that no
# longer includes <input.h> is fine — it means Phase IN3 has migrated
# it. Print a note in non-quiet mode so the operator can prune ALLOWED.
MIGRATED=()
for a in "${ALLOWED[@]}"; do
    is_present=0
    for f in "${FOUND_REL[@]}"; do
        if [ "$f" = "$a" ]; then
            is_present=1
            break
        fi
    done
    if [ "$is_present" -eq 0 ]; then
        MIGRATED+=("$a")
    fi
done

if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
    echo "check-input-include-guard: FAIL" >&2
    echo "  The following file(s) under engine/banked_code/ #include <input.h>" >&2
    echo "  but are not in the allowed list (see tools/check-input-include-guard.sh" >&2
    echo "  and doc/multiplatform-plan/input-baseline-coverage.md §IN1-3):" >&2
    for v in "${VIOLATIONS[@]}"; do
        echo "    - $v" >&2
    done
    echo "" >&2
    echo "  Fix: route the include through rage1/input.h (Phase IN3 HAL surface)" >&2
    echo "  instead of pulling z88dk's <input.h> into banked code directly. If" >&2
    echo "  the new file is intentionally a ZX-only backend, add it to the" >&2
    echo "  ALLOWED list and update the audit doc in the same commit." >&2
    exit 1
fi

if [ "$QUIET" -eq 0 ]; then
    echo "check-input-include-guard: OK"
    echo "  allowed sites still including <input.h>: ${#FOUND_REL[@]} / ${#ALLOWED[@]}"
    for f in "${FOUND_REL[@]}"; do
        echo "    - $f"
    done
    if [ "${#MIGRATED[@]}" -gt 0 ]; then
        echo "  note: allowed file(s) that no longer include <input.h>"
        echo "        (safe to prune from ALLOWED in a follow-up commit):"
        for m in "${MIGRATED[@]}"; do
            echo "    - $m"
        done
    fi
fi

exit 0
