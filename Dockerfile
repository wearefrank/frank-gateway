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
COPY certs/haal-centraal/Staat-der-Nederlanden-Private-Root-CA-G1.pem /usr/local/share/ca-certificates/Staat-der-Nederlanden-Private-Root-CA-G1.crt
COPY certs/haal-centraal/DomPrivateServicesCA-G1.pem /usr/local/share/ca-certificates/DomPrivateServicesCA-G1.crt
COPY certs/haal-centraal/QuoVadis-PKIoverheid-Private-Services-CA-G1-PEM.pem /usr/local/share/ca-certificates/QuoVadis-PKIoverheid-Private-Services-CA-G1-PEM.crt

#Copy test certificates into image
COPY certs/test/apisix.pem /usr/local/apisix/ssl/apisix.pem
COPY certs/test/apisix.pem /usr/local/apisix/ssl/apisix-key.pem
COPY certs/test/ca-bundle.pem /usr/local/apisix/ssl/ca-bundle.pem


#set permissions as root
USER root
RUN chmod 644 /usr/local/share/ca-certificates/Staat-der-Nederlanden-Private-Root-CA-G1.crt
RUN chmod 644 /usr/local/share/ca-certificates/DomPrivateServicesCA-G1.crt
RUN chmod 644 /usr/local/share/ca-certificates/QuoVadis-PKIoverheid-Private-Services-CA-G1-PEM.crt

#update the local cert store
RUN update-ca-certificates

#copy the local cert store and convert it to PEM for use in Lua
RUN cp /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.pem
