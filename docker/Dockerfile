# first we build Z88DK and tools for bundling
FROM fedora:37 as z88dk

RUN \
	dnf -y upgrade \
	&& dnf -y install gcc make boost-devel perl ragel re2c ccache \
		dos2unix texinfo texi2html curl perl-App-cpanminus git \
		perl-Template-Toolkit libxml2-devel bison flex which joe \
	&& mkdir /opt/z88dk \
	&& git clone --depth 1 --recursive https://github.com/z88dk/z88dk.git /opt/z88dk \
	&& cd /opt/z88dk \
	&& chmod 777 build.sh \
	&& BUILD_SDCC=1 BUILD_SDCC_HTTP=1 ./build.sh

# copy and build bas2tap
COPY bas2tap /opt/bas2tap
RUN make -C /opt/bas2tap

## second stage build, take the output from the first
FROM fedora:37

MAINTAINER zx@jogv.es

COPY --from=z88dk /opt/z88dk /opt/z88dk
COPY --from=z88dk /opt/bas2tap/bas2tap /opt/z88dk/bin/bas2tap

ENV Z88DK_PATH="/opt/z88dk"

ENV PATH="${Z88DK_PATH}/bin:${PATH}" \
    ZCCCFG="${Z88DK_PATH}/lib/config/"

# create user and install RAGE1 dependencies
RUN \
	useradd z88dk \
	&& dnf -y install netpbm-progs perl perl-Data-Compare \
		perl-List-MoreUtils perl-File-Copy perl-GD perl-YAML m4 make unzip git

# install Arkos and fix config file
RUN mkdir /opt/arkos
WORKDIR /opt/arkos
RUN \
	curl http://www.julien-nevo.com/arkostracker/release/linux64/Arkos%20Tracker%202%20Linux64.zip > arkos.zip \
	&& unzip arkos.zip \
	&& rm arkos.zip \
	&& mkdir /src \
	&& chown z88dk /src

USER z88dk

WORKDIR /src/

CMD /bin/bash
