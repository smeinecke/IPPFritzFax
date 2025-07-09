# Build arguments
ARG NETPBM_VERSION=10.86.33
ARG APP_DIR=/app

# Build stage
FROM alpine AS build

# Set environment variables
ENV NETPBM_VERSION=${NETPBM_VERSION} \
    APP_DIR=${APP_DIR}

# Install build dependencies and tools
RUN apk add --no-cache \
    git make bash gcc vim patch \
    musl-dev zlib-dev gnu-libiconv-dev \
    musl-utils avahi-dev openssl-dev \
    libpng perl libjpeg-turbo-dev \
    wget tar xz \
    && rm -rf /var/cache/apk/*

# Download, build and install Netpbm
RUN set -eux; \
    NETPBM_TAR="netpbm-${NETPBM_VERSION}.tgz"; \
    wget -q "https://sourceforge.net/projects/netpbm/files/super_stable/${NETPBM_VERSION}/netpbm-${NETPBM_VERSION}.tgz/download" -O "${NETPBM_TAR}" && \
    tar -xzf "${NETPBM_TAR}" && \
    cd "netpbm-${NETPBM_VERSION}" && \
    # Build and install only the required components
    (cd lib && make -j$(nproc) BINARIES=pbmtog3) && \
    cp lib/libnetpbm.so* /usr/local/lib/ && \
    (cd converter/pbm/ && make -j$(nproc) BINARIES=pbmtog3) && \
    cp converter/pbm/pbmtog3 /usr/local/bin/ && \
    # Clean up
    cd .. && \
    rm -rf "netpbm-${NETPBM_VERSION}" "${NETPBM_TAR}"

# Copy application code and set up build environment
WORKDIR ${APP_DIR}
COPY . .

# Configure git (required for some build processes)
RUN git config --global user.email "docker@example.com" && \
    git config --global user.name "Docker Build"

# Build and package the application
RUN set -eux; \
    make install && \
    mkdir -p faxserver/lib spool crt && \
    apk add --no-cache tar && \
    tar chf pkg.tar faxserver bin spool crt lib install/lib/*.so*


# Final stage
FROM alpine

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
    # Optional dependencies
    # imagemagick poppler-utils \
    && rm -rf /var/cache/apk/*

# Copy entrypoint and set permissions
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Set working directory
WORKDIR ${APP_DIR}

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
