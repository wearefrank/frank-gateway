FROM apache/apisix:3.6.0-debian

LABEL org.opencontainers.image.title="Frank API Gateway"
LABEL org.opencontainers.image.description="Open Source API Gateway by We Are Frank! based on Apache APISIX"
LABEL org.opencontainers.image.vendor="We Are Frank!"
LABEL org.opencontainers.image.version="0.1-beta"

ARG BUILD_DATE
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.authors="https://github.com/pimg, https://github.com/jjansenvr"
LABEL based-on="Apache APISIX 3.6"

COPY src /usr/local/apisix/custom-plugins
COPY conf/config-default.yaml /usr/local/apisix/conf/config-default.yaml
