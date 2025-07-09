# syntax=docker/dockerfile:1.4
FROM --platform=$BUILDPLATFORM alpine AS build

# Install build dependencies in a single layer
RUN apk add --no-cache \
	make bash gcc vim \
	patch \
	musl-dev zlib-dev gnu-libiconv-dev musl-utils avahi-dev openssl-dev \
	subversion libpng perl libjpeg-turbo-dev

	# Build netpbm with parallel jobs
RUN svn checkout http://svn.code.sf.net/p/netpbm/code/stable netpbm && \
	cd netpbm/lib/ && \
	yes '' | make -j$(nproc) BINARIES=pbmtog3 && \
	tar cf - libnetpbm.so* | tar xf - -C /usr/local/lib && \
	cd ../converter/pbm/ && \
	yes '' | make -j$(nproc) BINARIES=pbmtog3 && \
	cp pbmtog3 /usr/local/bin/

ADD .  /IPPFritzFax

WORKDIR IPPFritzFax

RUN make install
# Create package in a single layer
RUN mkdir -p faxserver/lib spool crt && \
	apk add --no-cache tar && \
	tar chf pkg.tar faxserver bin spool crt lib install/lib/*.so*

# Final stage
FROM alpine

# Install runtime dependencies in a single layer
RUN apk add --no-cache \
	avahi augeas dbus \
	bash \
	perl perl-json perl-http-message perl-file-slurp \
	perl-libwww perl-lwp-protocol-https html2text \
	# Optional: imagemagick poppler-utils
	&& rm -rf /var/cache/apk/*

COPY entrypoint.sh /opt/entrypoint.sh
WORKDIR /IPPFritzFax
# Copy built artifacts in a single layer
COPY --from=build /IPPFritzFax/pkg.tar .
RUN tar xf pkg.tar && \
	rm pkg.tar && \
	chmod a+x /IPPFritzFax/bin/*.pl /IPPFritzFax/faxserver/bin/*

# Copy additional files
COPY --from=build /usr/local/lib/libnetpbm* /usr/local/lib/
COPY --from=build /usr/local/bin/pbm* /usr/local/bin/

# Set environment variables
ENV LD_LIBRARY_PATH=/IPPFritzFax/install/lib \
	PATH=/IPPFritzFax/bin:/IPPFritzFax/faxserver/bin:$PATH

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
	CMD pgrep ippserver >/dev/null || exit 1

ENTRYPOINT ["/opt/entrypoint.sh"]
