FROM alpine:3.20

RUN apk add --no-cache \
    lua5.1 \
    lua5.1-dev\
    luarocks \
      gcc \
    musl-dev \
    yaml-dev

RUN  luarocks-5.1 install luafilesystem

WORKDIR /usr/local/apisix/conf


# COPY script
COPY scripts/ ./scripts/

CMD ["lua5.1", "scripts/merge.lua"]