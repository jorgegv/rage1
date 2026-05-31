#!/usr/bin/env bash
# install-cpctelera-converters.sh — build cpctelera's Img2CPC host tool and
# install cpct_img2tileset onto PATH.
#
# Called by the CI Dockerfile (docker/Dockerfile) during image construction and
# can also be run manually in a dev environment.
#
# Requires:
#   - g++ (tested with GCC 9+), make
#   - libfreeimage + libfreeimage-devel (Fedora: freeimage freeimage-devel;
#     Debian/Ubuntu: libfreeimage-dev)
#   - The cpctelera submodule already checked out at external/cpctelera
#     (CI uses `submodules: recursive`; manual: `git submodule update --init`)
#
# What this script does:
#   1. Builds external/cpctelera/cpctelera/tools/img2cpc/bin/img2cpc
#   2. Creates a cpct_img2tileset wrapper in a well-known install prefix that
#      sets CPCT_PATH and delegates to the vendored script.
#   3. Adds the prefix to PATH (via /etc/profile.d/ when run as root, or
#      prints a PATH hint when run as a normal user).
#
# Usage (called from the repo root or from the Dockerfile):
#   tools/install-cpctelera-converters.sh [--prefix <dir>]
#   --prefix <dir>   Directory for cpct_img2tileset wrapper. Default: /usr/local/bin
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Locate repo root (the directory containing this script is tools/)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PREFIX="/usr/local/bin"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            PREFIX="$2"; shift 2 ;;
        *)
            echo "Unknown argument: $1"; exit 1 ;;
    esac
done

CPCTELERA_ROOT="$REPO_ROOT/external/cpctelera/cpctelera"
IMG2CPC_DIR="$CPCTELERA_ROOT/tools/img2cpc"
IMG2CPC_BIN="$IMG2CPC_DIR/bin/img2cpc"
CPCT_SCRIPT_SRC="$CPCTELERA_ROOT/tools/scripts/cpct_img2tileset"

echo "[cpctelera-converters] repo root : $REPO_ROOT"
echo "[cpctelera-converters] img2cpc   : $IMG2CPC_BIN"
echo "[cpctelera-converters] install to: $PREFIX"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [ ! -d "$IMG2CPC_DIR" ]; then
    echo "ERROR: $IMG2CPC_DIR not found."
    echo "       Run: git submodule update --init external/cpctelera"
    exit 1
fi

if ! command -v g++ >/dev/null 2>&1; then
    echo "ERROR: g++ not found. Install gcc-c++ (Fedora) or build-essential (Debian)."
    exit 1
fi

# Check for FreeImage headers (required for building Img2CPC)
if ! [ -f /usr/include/FreeImage.h ] && ! [ -f /usr/local/include/FreeImage.h ]; then
    echo "ERROR: FreeImage.h not found."
    echo "       Fedora: sudo dnf install freeimage freeimage-devel"
    echo "       Debian: sudo apt-get install libfreeimage-dev"
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Build Img2CPC
# ---------------------------------------------------------------------------
echo "[cpctelera-converters] Building Img2CPC..."
(cd "$IMG2CPC_DIR" && make -j"$(nproc)" 2>&1)

if [ ! -x "$IMG2CPC_BIN" ]; then
    echo "ERROR: img2cpc binary not produced at $IMG2CPC_BIN"
    exit 1
fi
echo "[cpctelera-converters] img2cpc built OK: $IMG2CPC_BIN"

# ---------------------------------------------------------------------------
# 2. Install cpct_img2tileset wrapper into PREFIX
#    The vendored cpct_img2tileset bash script expects CPCT_PATH to point at
#    the cpctelera root (it sources lib/bash_library.sh and uses $IMG2CPC).
#    We write a small wrapper that sets CPCT_PATH before delegating.
# ---------------------------------------------------------------------------
mkdir -p "$PREFIX"
WRAPPER="$PREFIX/cpct_img2tileset"

cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# cpct_img2tileset — installed wrapper.
# Sets CPCT_PATH to the vendored cpctelera submodule so the underlying script
# can find its bash library and the Img2CPC binary.
export CPCT_PATH="${CPCTELERA_ROOT}"
exec "${CPCT_SCRIPT_SRC}" "\$@"
EOF
chmod +x "$WRAPPER"

echo "[cpctelera-converters] wrapper installed: $WRAPPER"

# ---------------------------------------------------------------------------
# 3. PATH hint / profile.d
# ---------------------------------------------------------------------------
# Colon-delimited exact match so /usr/local/bin doesn't spuriously match e.g.
# /usr/local/bin-other, and a bare $PREFIX isn't matched as a substring.
if [[ ":$PATH:" == *":$PREFIX:"* ]]; then
    echo "[cpctelera-converters] $PREFIX is on PATH — no further action needed."
else
    # If running as root, drop a profile.d fragment
    if [ "$(id -u)" = "0" ] && [ -d /etc/profile.d ]; then
        echo "export PATH=\"$PREFIX:\$PATH\"" > /etc/profile.d/rage1-cpctelera.sh
        echo "[cpctelera-converters] Added /etc/profile.d/rage1-cpctelera.sh"
    else
        echo "[cpctelera-converters] NOTE: add $PREFIX to your PATH:"
        echo "    export PATH=\"$PREFIX:\$PATH\""
    fi
fi

echo "[cpctelera-converters] Done. Verify with: cpct_img2tileset --help"
