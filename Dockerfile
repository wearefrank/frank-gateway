FROM apache/apisix:3.16.0-ubuntu

ARG BUILD_DATE
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL based-on="Apache APISIX 3.16.0 Ubuntu"

# Overlay patched APISIX plugins from the local patches folder.
# Files with the same path/name in /usr/local/apisix/apisix/plugins are replaced.
COPY patches/ /usr/local/apisix/apisix/plugins/

#Copy Custom plugins into image
COPY src /usr/local/apisix/custom-plugins

#Copy Base APISIX config
COPY conf/config.yaml /usr/local/apisix/conf/config.yaml

#Copy custom scripts into image
COPY scripts /usr/local/bin/scripts

# Copy haal centraal Certificates into image
COPY certs/ /usr/local/share/ca-certificates/

USER root


#update the local cert store, copy the local cert store and convert it to PEM for use in Lua
RUN chmod -R 644 /usr/local/share/ca-certificates && \
    update-ca-certificates && \
    cp /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.pem

#patch a bug in the APISIX code that causes the gateway to crash when loading certificates in environment variables. see https://github.com/apache/apisix/issues/7223#issuecomment-1380123833
RUN sed -i \
    -e '635i sys_conf["envs"]= {}' \
    -e 's~table_insert(sys_conf\["envs"\], name .. "=" .. value)~table_insert(sys_conf["envs"], name)~g' \
    /usr/local/apisix/apisix/cli/ops.lua

# Make scripts executable
RUN chmod +x /usr/local/bin/scripts/start.sh && \
    chmod +x /usr/local/bin/scripts/merge.lua
    
RUN apt-get update && apt-get install -y \
    lua5.1 \
    luarocks \
    build-essential \
    libyaml-dev
    
RUN luarocks install luafilesystem && \
    luarocks install lyaml

ENTRYPOINT ["/usr/local/bin/scripts/start.sh"]
CMD ["docker-start"]