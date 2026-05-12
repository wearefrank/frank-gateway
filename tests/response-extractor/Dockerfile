FROM alpine:3.20

RUN apk add --no-cache \
    lua5.1 \
    lua5.1-dev \
    luarocks \
    gcc \
    musl-dev \
    make

# Install busted
RUN luarocks-5.1 install busted

WORKDIR /frank-gateway

CMD ["busted", "spec"]