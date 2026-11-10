ARG UPSTREAM_IMAGE=ghcr.io/borgmatic-collective/borgmatic
ARG UPSTREAM_TAG=latest
FROM ${UPSTREAM_IMAGE}:${UPSTREAM_TAG}

RUN apk add --no-cache openssh-client perl \
    && apk add --no-cache \
      --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
      wakeonlan

COPY borgmatic-wol-hook.sh /usr/local/bin/borgmatic-wol-hook.sh
RUN chmod +x /usr/local/bin/borgmatic-wol-hook.sh
