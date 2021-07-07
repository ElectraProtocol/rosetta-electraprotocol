# Copyright 2020 Coinbase, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build xepd
FROM ubuntu:18.04 as xepd-builder

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

# Source: https://github.com/ElectraProtocol/XEP-Core/blob/master/doc/build-unix.md#ubuntu--debian
RUN apt-get update && apt-get install -y git make file autoconf automake build-base libtool db-c++ db-dev boost-system boost-program_options \
  boost-filesystem boost-dev libressl-dev libevent-dev wget curl


# VERSION: ElectraProtocol Core v1.0.3.0
RUN git clone https://github.com/ElectraProtocol/XEP-Core \
  && cd XEP-Core \
  && git checkout 821291659f9741e6c2152725f82d5fc36becd832

RUN cd XEP-Core \
  && ./autogen.sh \
  && ./configure --disable-tests \
                 --disable-bench --disable-static  \
                 --without-gui --disable-zmq \
                 --with-incompatible-bdb \
                 CFLAGS='-w' CXXFLAGS='-w' \
  && make -j 4

RUN mv XEP-Core/src/xepd /app/xepd \
  && rm -rf XEP-Core

# Build Rosetta Server Components
FROM ubuntu:18.04 as rosetta-builder

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app
WORKDIR /app

RUN apt-get update && apt-get install -y curl make gcc g++
ENV GOLANG_VERSION 1.15.5
ENV GOLANG_DOWNLOAD_SHA256 9a58494e8da722c3aef248c9227b0e9c528c7318309827780f16220998180a0d
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz

RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
  && echo "$GOLANG_DOWNLOAD_SHA256  golang.tar.gz" | sha256sum -c - \
  && tar -C /usr/local -xzf golang.tar.gz \
  && rm golang.tar.gz

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

# Use native remote build context to build in any directory
COPY . src
RUN cd src \
  && go build \
  && cd .. \
  && mv src/rosetta-electraprotocol /app/rosetta-electraprotocol \
  && mv src/assets/* /app \
  && rm -rf src

## Build Final Image
FROM ubuntu:18.04

RUN apt-get update && \
  apt-get install --no-install-recommends -y libevent-dev libboost-system-dev libboost-filesystem-dev libboost-test-dev libboost-thread-dev && \
  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /app \
  && chown -R nobody:nogroup /app \
  && mkdir -p /data \
  && chown -R nobody:nogroup /data

WORKDIR /app

# Copy binary from xepd-builder
COPY --from=xepd-builder /app/xepd /app/xepd

# Copy binary from rosetta-builder
COPY --from=rosetta-builder /app/* /app/

# Set permissions for everything added to /app
RUN chmod -R 755 /app/*

CMD ["/app/rosetta-electraprotocol"]
