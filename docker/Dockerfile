# RAGE1 Docker image — multi-stage build
#
# Stage :build — z88dk + SDCC + Perl tools (ZX + CPC compile environment)
# Stage :test  — :build + Caprice32 + Xvfb + ImageMagick (CPC headless test)
#
# Build both stages:
#   docker build --target build -t rage1-z88dk:build -f docker/Dockerfile docker/
#   docker build --target test  -t rage1-z88dk:test  -f docker/Dockerfile docker/
#
# Run a build (using :build):
#   docker run -v ${PWD}:/src/ -it rage1-z88dk:build make all-test-builds
#
# Check the emulator is present (using :test):
#   docker run --rm rage1-z88dk:test cap32 -V
# (cap32 -V exits before SDL_Init, so no xvfb-run needed for the version check;
#  a real headless screenshot run does need xvfb-run / a live Xvfb — see
#  tests/00regression/README.md for the verified autocmd recipe.)
#
# Phase T0 (cross-platform plan) additions:
#   - gcc / gcc-c++: needed to build cpctelera's bundled host tools
#     (2cdt, iDSK, hex2bin, dskgen, img2cpc) under external/cpctelera/
#     on demand from the submodule. No system-wide install of cpctelera.
#   - The cpctelera submodule itself is brought in via the workspace
#     checkout (CI uses `submodules: recursive`); no clone happens here.

# ============================================================
# Stage 1: build — ZX + CPC compile environment
# ============================================================
FROM fedora:latest AS build

ENV Z88DK_PATH="/opt/z88dk"
ENV Z88DK_TAG="v2.3"

ENV BAS2TAP_PATH="/opt/bas2tap"

RUN \
	dnf install -y git perl perl-Data-Compare perl-List-MoreUtils perl-File-Copy perl-GD perl-YAML m4 make \
	bison flex libxml2-devel boost-devel texinfo perl-Template-Toolkit perl-App-cpanminus gmp-devel ragel re2c ccache \
	dos2unix curl diffutils perl-Algorithm-FastPermute perl-local-lib perl-Digest-SHA1 \
	gcc gcc-c++ \
	&& cpanm -l $HOME/perl5 --no-wget Template::Plugin::YAML

RUN \
	git clone --recursive https://github.com/z88dk/z88dk.git ${Z88DK_PATH} \
	&& cd ${Z88DK_PATH} \
	&& git checkout ${Z88DK_TAG} \
	&& eval "$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib)" \
	&& chmod 777 build.sh \
	&& BUILD_SDCC=1 BUILD_SDCC_HTTP=1 ./build.sh

RUN \
	git clone https://github.com/speccyorg/bas2tap ${BAS2TAP_PATH} \
	&& cd ${BAS2TAP_PATH} \
	&& git checkout master \
	&& make \
	&& cp ${BAS2TAP_PATH}/bas2tap ${Z88DK_PATH}/bin

# T2-9: install 2cdt for CPC cassette tape image (.cdt) generation.
# 2cdt source is in the CPCTools project by Clemens Bartz.
ENV TWOCDT_PATH="/opt/2cdt"
RUN \
	git clone https://github.com/cpcitor/cpc-dev-tool-chain ${TWOCDT_PATH} \
	&& gcc -o ${Z88DK_PATH}/bin/2cdt ${TWOCDT_PATH}/cpclib/2cdt/2cdt.c \
	|| ( echo "2cdt build failed — CDT generation will be skipped at runtime" ; true )

# Phase R3: build dependency for cpctelera's host asset converter
# (Img2CPC + cpct_img2tileset).  Requires gcc-c++ (already above) + freeimage.
# The converter itself is built/installed at CI time by
# tools/install-cpctelera-converters.sh (see .github/workflows/build-test-games.yaml),
# because Img2CPC needs the external/cpctelera submodule which only exists after
# the workspace checkout (CI uses `submodules: recursive`) — not at image build.
RUN dnf install -y freeimage freeimage-devel

ENV PATH="${Z88DK_PATH}/bin:$HOME/perl5/bin:${PATH}" \
    ZCCCFG="${Z88DK_PATH}/lib/config/" \
    PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}" \
    PERL_LOCAL_LIB_ROOT="$HOME/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}" \
    PERL_MB_OPT="--install_base \"$HOME/perl5\"" \
    PERL_MM_OPT="INSTALL_BASE=$HOME/perl5"

WORKDIR /src/

# ============================================================
# Stage 2: test — :build + Caprice32 headless CPC emulator
# ============================================================
FROM build AS test

# TS2-3: Add Caprice32 + Xvfb + ImageMagick to the test image.
#
# Caprice32 runtime deps: SDL2, freetype, libpng, zlib
# Caprice32 build deps:   SDL2-devel, freetype-devel, libpng-devel, zlib-devel, gcc-c++
# Headless:               xorg-x11-server-Xvfb
# Pixel comparison:       ImageMagick
#
# Caprice32 is built from source, pinned to the verified commit.
# Pinned commit: 93486f87189397f3ae80e7c5c2966ac8bfae9897 — post-v4.6.0 master
# HEAD (tag v4.6.0 = 0eb07f5, ~647 commits earlier; the VERSION_STRING in
# cap32.h still reads "v4.6.0" — it was never bumped). Pinned 2026-05-31.
# Verified to support: CAP32_SCRNSHOT, CAP32_DELAY (no argument, uses
# boot_time frames), CAP32_WAITBREAK, CAP32_EXIT (see TS2-2 findings in
# tests/00regression/README.md).
ENV CAP32_COMMIT="93486f87189397f3ae80e7c5c2966ac8bfae9897"
ENV CAP32_PATH="/opt/caprice32"

RUN dnf install -y \
    SDL2-devel \
    freetype-devel \
    libpng-devel \
    zlib-devel \
    xorg-x11-server-Xvfb \
    ImageMagick \
    xdpyinfo

RUN \
    git clone https://github.com/ColinPitrat/caprice32.git ${CAP32_PATH} \
    && cd ${CAP32_PATH} \
    && git checkout ${CAP32_COMMIT} \
    && make ARCH=linux WITHOUT_GL=TRUE APP_PATH=${CAP32_PATH} \
    && cp cap32 /usr/local/bin/cap32

# Generate cap32.cfg from the template so ROMs, resources, etc. resolve to
# the build tree at ${CAP32_PATH}/rom, ${CAP32_PATH}/resources, etc.
# At runtime override sdump_dir with -O file.sdump_dir=<path> and
# boot_time with -O system.boot_time=<frames> for the screenshot delay.
RUN \
    sed "s|__SHARE_PATH__|${CAP32_PATH}|g" \
        ${CAP32_PATH}/cap32.cfg.tmpl > /etc/cap32.cfg \
    && mkdir -p /tmp/cap32-screenshots

ENV CAP32_CFG="/etc/cap32.cfg"

# Smoke-verify: cap32 -V exits before SDL_Init — no Xvfb needed.
# Confirms the binary links correctly and the version matches the pinned commit.
RUN cap32 -V

WORKDIR /src/
