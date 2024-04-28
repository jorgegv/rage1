# To create the image:
#   $ docker build -t rage1-z88dk -f rage1-z88dk.Dockerfile .
# To run the container:
#   $ docker run -v ${PWD}:/src/ -it rage1-z88dk <command>

FROM fedora:latest

ENV Z88DK_PATH="/opt/z88dk"
ENV Z88DK_TAG="v2.3"

ENV BAS2TAP_PATH="/opt/bas2tap"

RUN \
	dnf install -y git perl perl-Data-Compare perl-List-MoreUtils perl-File-Copy perl-GD perl-YAML m4 make \
	bison flex libxml2-devel boost-devel texinfo perl-Template-Toolkit perl-App-cpanminus gmp-devel ragel re2c ccache \
	dos2unix curl diffutils perl-Algorithm-FastPermute perl-local-lib perl-Digest-SHA1 \
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

ENV PATH="${Z88DK_PATH}/bin:$HOME/perl5/bin:${PATH}" \
    ZCCCFG="${Z88DK_PATH}/lib/config/" \
    PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}" \
    PERL_LOCAL_LIB_ROOT="$HOME/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}" \
    PERL_MB_OPT="--install_base \"$HOME/perl5\"" \
    PERL_MM_OPT="INSTALL_BASE=$HOME/perl5"

WORKDIR /src/
