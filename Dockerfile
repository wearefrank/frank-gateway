FROM apache/apisix:3.12.0-debian

LABEL org.opencontainers.image.title="Frank!Gateway"
LABEL org.opencontainers.image.description="Open Source API Gateway by We Are Frank! based on Apache APISIX"
LABEL org.opencontainers.image.vendor="WeAreFrank!"
LABEL org.opencontainers.image.version="0.2-beta"

ARG BUILD_DATE
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL based-on="Apache APISIX 3.8"

COPY src /usr/local/apisix/custom-plugins
COPY conf/config.yaml /usr/local/apisix/conf/config.yaml
COPY conf/config-default.yaml /usr/local/apisix/conf/config-default.yaml
COPY conf/apisix-standalone-config.yaml /usr/local/apisix/conf/apisix.yaml

# Copy Haal Centraal certificates into image
COPY certs/ /usr/local/share/ca-certificates/

#set permissions as root
USER root
RUN chmod -R 644 /usr/local/share/ca-certificates

#update the local cert store
RUN update-ca-certificates

#copy the local cert store and convert it to PEM for use in Lua
RUN cp /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.pem

#patch a bug in the APISIX code that causes the gateway to crash when loading certificates in environment variables. see https://github.com/apache/apisix/issues/7223#issuecomment-1380123833
RUN sed -i -e '635i sys_conf["envs"]= {}' -e 's~table_insert(sys_conf\["envs"\], name .. "=" .. value)~table_insert(sys_conf["envs"], name)~g' /usr/local/apisix/apisix/cli/ops.lua