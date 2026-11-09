# The production image: the truedrive program and FFmpeg, without the compiler.
# Needs the core library in the build context, so run "git submodule update --init" first.

ARG ALPINE_VERSION=3.24

FROM alpine:${ALPINE_VERSION} AS build

RUN apk add --no-cache build-base cmake
WORKDIR /src
COPY . .
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release \
  && cmake --build build --parallel \
  && strip build/truedrive

FROM alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="True Drive CLI" \
      org.opencontainers.image.description="Encodes files to noise videos and decodes them back" \
      org.opencontainers.image.source="https://github.com/true-drive/cli" \
      org.opencontainers.image.licenses="Apache-2.0"

# The core library runs FFmpeg through /bin/sh, which Alpine already provides.
RUN apk add --no-cache ffmpeg \
  && adduser -D -u 1000 truedrive

COPY --from=build /src/build/truedrive /usr/local/bin/truedrive

USER truedrive

# Mount the files to work on here, so that relative -i and -o paths resolve to them.
WORKDIR /data

# Arguments given to "docker run" after the image name are passed to truedrive.
ENTRYPOINT ["truedrive"]
