# First stage: build
FROM alpine AS build

# Build arguments
ARG NETPBM_VERSION=10.86.47
ARG APP_DIR=/app

# Set environment variables
ENV NETPBM_VERSION=${NETPBM_VERSION} \
    APP_DIR=${APP_DIR}

# Install build dependencies and tools including ccache
RUN apk add --no-cache \
    git make bash gcc vim patch \
    musl-dev zlib-dev gnu-libiconv-dev \
    musl-utils avahi-dev openssl-dev \
    libpng-dev perl libjpeg-turbo-dev \
    wget tar xz pkgconfig libxml2-dev \
    linux-headers ccache \
    && rm -rf /var/cache/apk/* \
    && mkdir -p /root/.ccache

# Configure ccache
ENV CCACHE_DIR=/root/.ccache \
    CCACHE_COMPRESS=1 \
    CCACHE_COMPRESSLEVEL=6 \
    CCACHE_MAXSIZE=2G \
    CCACHE_SLOPPINESS=file_macro,include_file_mtime,time_macros \
    CCACHE_UMASK=002 \
    CCACHE_NOHASHDIR=1 \
    PATH="/usr/lib/ccache/bin:$PATH"

# Download, build and install Netpbm with ccache
RUN set -eux; \
    NETPBM_TAR="netpbm-${NETPBM_VERSION}.tgz"; \
    wget -q "https://sourceforge.net/projects/netpbm/files/super_stable/${NETPBM_VERSION}/netpbm-${NETPBM_VERSION}.tgz" -O "${NETPBM_TAR}" && \
    tar -xzf "${NETPBM_TAR}" && \
    cd "netpbm-${NETPBM_VERSION}" && \
    # Build and install only the required components
    # auto-confirm all input prompts and enable ccache
    while true ; do echo ; sleep 0.1; done | \
    CC="ccache gcc" \
    CXX="ccache g++" \
    ./configure && \
    cd lib && \
	make BINARIES=pbmtog3 && \
    cp libnetpbm.so* /usr/local/lib/ && \
    ldconfig /usr/local/lib && \
    cd ../converter/pbm/ && \
	make BINARIES=pbmtog3 && \
    cp pbmtog3 /usr/local/bin/ && \
    # Clean up
    cd ../../../ && \
    rm -rf "netpbm-${NETPBM_VERSION}" "${NETPBM_TAR}" \
    # Show ccache statistics
    && ccache -s

# Copy application code and set up build environment
WORKDIR /app
COPY . .

# Configure git (required for some build processes)
RUN git config --global user.email "docker@example.com" && \
    git config --global user.name "Docker Build"

# Build and package the application
RUN set -eux; \
	CC="ccache gcc" \
	CXX="ccache g++" \
	make install && \
    mkdir -p faxserver/lib spool crt && \
    apk add --no-cache tar && \
    tar chf pkg.tar faxserver bin spool crt lib install/lib/*.so*


# Final stage
FROM alpine

# Re-declare ARG for this build stage
ARG APP_DIR=/app

# Set environment variables
ENV APP_DIR=/app \
    LD_LIBRARY_PATH=/app/install/lib \
    PATH=/app/bin:/app/faxserver/bin:$PATH

# Install runtime dependencies
RUN set -eux; \
    apk add --no-cache \
    avahi augeas dbus \
    bash \
    perl perl-json perl-http-message \
    perl-file-slurp perl-libwww \
    perl-lwp-protocol-https html2text \
    # Required for D-Bus and Avahi
    dbus-x11 \
    # Optional dependencies
    # imagemagick poppler-utils \
    && rm -rf /var/cache/apk/*

# Create necessary directories with correct permissions
RUN mkdir -p /var/run/dbus \
    && mkdir -p /var/spool/avahi \
    && chown -R avahi:avahi /var/spool/avahi \
    && chmod 755 /var/run/dbus /var/spool/avahi

# Copy entrypoint and set permissions
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Set working directory
WORKDIR /app

# Copy required files from build stage
COPY --from=build ${APP_DIR}/pkg.tar .
RUN tar xf pkg.tar && \
    rm pkg.tar && \
    chmod a+x bin/*.pl faxserver/bin/*

# Copy Netpbm libraries from build stage
COPY --from=build /usr/local/lib/libnetpbm.so* /usr/local/lib/
COPY --from=build /usr/local/bin/pbmtog3 /usr/local/bin/

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep ippserver >/dev/null || exit 1

# Set the entrypoint
ENTRYPOINT ["/opt/entrypoint.sh"]
