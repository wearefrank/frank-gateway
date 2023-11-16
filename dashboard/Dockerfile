FROM apache/apisix-dashboard:3.0.1-centos

LABEL org.opencontainers.image.title="Frank API Dashboard"
LABEL org.opencontainers.image.description="Open Source API Dashboard by We Are Frank! based on Apache APISIX"
LABEL org.opencontainers.image.vendor="We Are Frank!"
LABEL org.opencontainers.image.version="0.1-beta"

ARG BUILD_DATE
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.authors="https://github.com/pimg, https://github.com/jjansenvr"
LABEL based-on="Apache APISIX Dashboard 3.6"

COPY dashboard/schema.json /usr/local/apisix-dashboard/conf/schema.json
COPY dashboard/conf.yaml /usr/local/apisix-dashboard/conf/conf.yaml
