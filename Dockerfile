FROM apache/apisix:3.19.0-ubuntu

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
