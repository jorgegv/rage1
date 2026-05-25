#!/usr/bin/env bash
#
# RAGE1 — Platform-selection rule (Phase A1, A1-6)
#
# Usage:
#   detect-platform.sh <target_game_dir> [<cli_platform_override>]
#
# Resolves the build's target platform per the rule defined in
# doc/multiplatform-plan/assets.md §2.1 and Phase A1 sub-task A1-6:
#
#   resolved_platform = <CLI override> > <Game.gdata PLATFORM directive>
#
# Validation rule (A1-6):
#   - If the resolved platform matches the game's declared default
#     (i.e. the value of PLATFORM in shared game_data/), build is allowed.
#   - Otherwise, an overlay directory <platform>/game_data/ must exist
#     under the target game tree. If not, the build is REJECTED with a
#     clear error.
#
# Output (success):
#   - For ZX platforms (zx48 / zx128): prints '48' or '128' on stdout
#     (the legacy ZX_TARGET internal token, consumed by the Makefile-N
#     selection downstream). Exit 0.
#   - For non-ZX platforms (Phase A5+ adds CPC handling): rejected
#     in Phase A1 with a not-yet-supported message. Exit 1.
#
# Output (failure):
#   - Multi-line error message on stderr explaining the reason. Exit 1.
#
# This script is intentionally minimal in Phase A1 — toolchain.md task
# T1-1 will refine it (full platform vocabulary, overlay-tree merge
# semantics, etc.) in later phases.

set -uo pipefail

target_game="${1:-}"
cli_override="${2:-}"

if [[ -z "${target_game}" ]]; then
    echo "** Error: detect-platform.sh: missing <target_game> argument" >&2
    exit 1
fi

if [[ ! -d "${target_game}/game_data/game_config" ]]; then
    echo "** Error: detect-platform.sh: '${target_game}/game_data/game_config' not found" >&2
    exit 1
fi

# Extract the game's declared default platform from its shared
# game_data/game_config/*.gdata. Recognise BOTH the new PLATFORM directive
# (preferred) and the legacy ZX_TARGET directive (permanent silent alias
# per README §5.6).
gdata_files=( "${target_game}"/game_data/game_config/*.gdata )

declared_platform=""

# Try PLATFORM first
declared_platform="$(grep -hE '^\s*PLATFORM\s+\w+\s*$' "${gdata_files[@]}" 2>/dev/null \
                    | grep -vP '^\s*//' \
                    | head -1 \
                    | awk '{print tolower($2)}')"

# Fallback to ZX_TARGET (legacy)
if [[ -z "${declared_platform}" ]]; then
    legacy_zx_target="$(grep -hE '^\s*ZX_TARGET\s+(48|128)\s*$' "${gdata_files[@]}" 2>/dev/null \
                        | grep -vP '^\s*//' \
                        | head -1 \
                        | awk '{print $2}')"
    if [[ "${legacy_zx_target}" == "48" ]]; then
        declared_platform="zx48"
    elif [[ "${legacy_zx_target}" == "128" ]]; then
        declared_platform="zx128"
    fi
fi

if [[ -z "${declared_platform}" ]]; then
    echo "** Error: game '${target_game}' does not declare a PLATFORM (or legacy ZX_TARGET) directive in its game_config/*.gdata" >&2
    exit 1
fi

# Resolve effective platform: CLI override beats the game's declared default
if [[ -n "${cli_override}" ]]; then
    resolved="$(echo "${cli_override}" | tr '[:upper:]' '[:lower:]')"
else
    resolved="${declared_platform}"
fi

# A1-6 overlay-required rule: if the resolved platform is NOT the game's
# declared default, an overlay tree at <platform>/game_data/ MUST exist.
if [[ "${resolved}" != "${declared_platform}" ]]; then
    overlay_dir="${target_game}/${resolved}/game_data"
    if [[ ! -d "${overlay_dir}" ]]; then
        echo "** Error: game '${target_game}' does not declare an overlay for platform '${resolved}'" >&2
        echo "          (its declared default platform is '${declared_platform}')." >&2
        echo "          Add '${overlay_dir}/' to opt in to building for '${resolved}'," >&2
        echo "          or build for the declared default with 'make build target_game=${target_game}'." >&2
        exit 1
    fi
fi

# Map resolved platform to the legacy ZX_TARGET internal token consumed by
# the Makefile-N selection downstream. Phase A1 only supports ZX targets.
case "${resolved}" in
    zx48)
        echo "48"
        ;;
    zx128)
        echo "128"
        ;;
    cpc6128|cpc464|cpc)
        echo "** Error: platform '${resolved}' is not yet supported (Phase A5 adds CPC bring-up)." >&2
        exit 1
        ;;
    *)
        echo "** Error: unknown platform '${resolved}' (accepted in Phase A1: zx48, zx128)" >&2
        exit 1
        ;;
esac

exit 0
