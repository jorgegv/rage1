# first we build Z88DK for bundling
FROM fedora:37 as z88dk

#	dnf -y upgrade \
RUN \
	dnf -y install gcc make boost-devel perl ragel re2c ccache dos2unix texinfo texi2html curl perl-App-cpanminus git \
		perl-Template-Toolkit libxml2-devel bison flex \
	&& mkdir /opt/z88dk \
	&& git clone --depth 1 --recursive https://github.com/z88dk/z88dk.git /opt/z88dk \
	&& cd /opt/z88dk \
	&& chmod 777 build.sh \
	&& BUILD_SDCC=1 BUILD_SDCC_HTTP=1 ./build.sh

## second stage build, take the output from the first

FROM fedora:37

MAINTAINER zx@jogv.es

COPY --from=z88dk /opt/z88dk /opt/z88dk

ENV Z88DK_PATH="/opt/z88dk"

ENV PATH="${Z88DK_PATH}/bin:${PATH}" \
    ZCCCFG="${Z88DK_PATH}/lib/config/"

RUN \
	useradd z88dk && \
	dnf -y upgrade && \
	dnf -y install netpbm-progs perl perl-Data-Compare perl-List-MoreUtils perl-File-Copy perl-GD perl-YAML m4 make

USER z88dk

WORKDIR /src/

CMD /bin/bash
