# syntax=docker/dockerfile:1

# Change this default to custom in a PR to build and use the custom runtime.
# BuildKit skips runtime-builder when base is selected.
ARG RUNTIME=custom
ARG APISIX_BUILD_TOOLS_TAG=apisix-runtime/1.4.3
ARG APISIX_BUILD_TOOLS_COMMIT=a582dc4dd467732119f35a05a5ee40b406897b98
ARG APISIX_RUNTIME_VERSION=1.4.3
ARG OPENRESTY_VERSION=1.31.8.1
ARG OPENSSL_VERSION=3.5.9

FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8 AS runtime-builder

ARG APISIX_BUILD_TOOLS_TAG
ARG APISIX_BUILD_TOOLS_COMMIT
ARG APISIX_RUNTIME_VERSION
ARG OPENRESTY_VERSION
ARG OPENSSL_VERSION

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        sudo git wget curl gnupg ca-certificates lsb-release \
        build-essential make perl cpanminus patch \
        libreadline-dev libssl-dev xz-utils; \
    install -d /etc/apt/keyrings; \
    curl -fsSL https://openresty.org/package/pubkey.gpg -o /tmp/openresty-pubkey.gpg; \
    gpg --dearmor --output /etc/apt/keyrings/openresty.gpg /tmp/openresty-pubkey.gpg; \
    rm /tmp/openresty-pubkey.gpg; \
    arch=$(dpkg --print-architecture); \
    arch_path=""; if [ "$arch" = "arm64" ]; then arch_path="arm64/"; fi; \
    echo "deb [signed-by=/etc/apt/keyrings/openresty.gpg] https://openresty.org/package/${arch_path}ubuntu $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/openresty.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends openresty-pcre-dev openresty-zlib-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /apisix-build-tools
RUN set -eux; \
    git clone --depth 1 -b "${APISIX_BUILD_TOOLS_TAG}" https://github.com/api7/apisix-build-tools.git .; \
    test "$(git rev-parse HEAD)" = "${APISIX_BUILD_TOOLS_COMMIT}"

RUN runtime_version="${APISIX_RUNTIME_VERSION}" \
    OPENRESTY_VERSION="${OPENRESTY_VERSION}" \
    OPENSSL_VERSION="${OPENSSL_VERSION}" \
    ./build-apisix-runtime.sh

FROM apache/apisix:3.19.0-ubuntu@sha256:bb4958b943949b3543353481eff1333e10b3323c6095dd0af4406de2b8cf738e AS runtime-base
LABEL runtime-source=base

FROM runtime-base AS runtime-custom
USER root
RUN rm -rf /usr/local/openresty
COPY --from=runtime-builder /usr/local/openresty /usr/local/openresty

ARG APISIX_RUNTIME_VERSION
ARG OPENRESTY_VERSION
ARG OPENSSL_VERSION
LABEL runtime-source=custom
LABEL apisix-runtime-version=$APISIX_RUNTIME_VERSION
LABEL openresty-version=$OPENRESTY_VERSION
LABEL openssl-version=$OPENSSL_VERSION

FROM runtime-${RUNTIME} AS gateway

ARG BUILD_DATE
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL based-on="Apache APISIX 3.19.0 Ubuntu"

# Overlay patched APISIX plugins from the local patches folder.
# Files with the same path/name in /usr/local/apisix/apisix/plugins are replaced.
COPY patches/ /usr/local/apisix/apisix/plugins/

#Copy Custom plugins into image
COPY src /usr/local/apisix/custom-plugins

#Copy Base APISIX config
COPY conf/config.yaml /usr/local/apisix/conf/config.yaml

# Copy haal centraal Certificates into image
COPY certs/ /usr/local/share/ca-certificates/

USER root

#update the local cert store, copy the local cert store and convert it to PEM for use in Lua
RUN chmod -R 644 /usr/local/share/ca-certificates && \
    update-ca-certificates && \
    cp /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.pem
   
RUN apt-get update && apt-get install -y \
    lua5.1 \
    luarocks \
    build-essential \
    libyaml-dev
    
RUN luarocks install luafilesystem && \
    luarocks install lyaml

    #Monkey Patch, issue Frank-gateway 152 - certificates with newlines in apisix.yml    
    
RUN set -eux; \
    f=/usr/local/apisix/apisix/core/config_yaml.lua; \
    sed -i \
      -e 's|local resolved, err = file.resolve_conf_var_in_text(raw_config)|local resolved = yaml.load(raw_config); local ok, err = file.resolve_conf_var(resolved or {}); if not ok then resolved = nil end|' \
      -e 's|return yaml.load(resolved), nil|return resolved, nil|' \
      "$f"; \
    grep -q 'file.resolve_conf_var(resolved or {})' "$f"; \
    grep -q 'return resolved, nil' "$f"; \
    ! grep -q 'resolve_conf_var_in_text(raw_config)' "$f"

RUN set -eux; \
        f=/usr/local/apisix/apisix/cli/file.lua; \
        sed -i \
            -e 's|local resolved, err = resolve_conf_var_in_text(apisix_conf_yaml)|local resolved = yaml.load(apisix_conf_yaml); local ok, err = resolve_conf_var(resolved or {}); if not ok then resolved = nil end|' \
            -e 's|local apisix_conf = yaml.load(resolved)|local apisix_conf = resolved|' \
            "$f"; \
        grep -q 'resolve_conf_var(resolved or {})' "$f"; \
        grep -q 'local apisix_conf = resolved' "$f"; \
        ! grep -q 'resolve_conf_var_in_text(apisix_conf_yaml)' "$f"

USER apisix

CMD ["docker-start"]
