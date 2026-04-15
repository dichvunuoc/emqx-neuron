# Custom Neuron image from this source (OPC UA w/ open62541, local patches).
# Build: docker build --platform linux/amd64 -t neuron-custom:local .
# Run:  docker run --rm -p 7000:7000 neuron-custom:local

FROM ghcr.io/neugates/build:x86_64-main AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq git ca-certificates wget unzip

ARG O62541_TAG=v1.4.6
RUN rm -rf /tmp/open62541 && \
    git clone --depth 1 --branch "${O62541_TAG}" https://github.com/open62541/open62541.git /tmp/open62541 && \
    mkdir -p /tmp/open62541/build && cd /tmp/open62541/build && \
    cmake .. \
      -DCMAKE_C_COMPILER=x86_64-linux-gnu-gcc \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF && \
    cmake --build . -j2 && \
    cmake --install . && \
    ldconfig

WORKDIR /workspace
COPY . .
RUN git config --global --add safe.directory /workspace

# Serial build avoids "jobserver: Bad file descriptor" / lto-wrapper failures when linking plugins in Docker.
RUN rm -rf build-docker-neuron && mkdir -p build-docker-neuron && cd build-docker-neuron && \
    cmake .. \
      -DCMAKE_TOOLCHAIN_FILE=../cmake/x86_64-linux-gnu.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DDISABLE_UT=ON \
      -DCMAKE_PREFIX_PATH=/usr/local \
      -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF && \
    cmake --build . -j1

# Open-source dashboard static files (required for / and /web — without it browsers show Not Found)
RUN cd /workspace/build-docker-neuron && \
    wget -q https://github.com/emqx/neuron-dashboard/releases/download/2.6.3/neuron-dashboard.zip -O /tmp/neuron-dashboard.zip && \
    unzip -q -o /tmp/neuron-dashboard.zip -d . && \
    rm /tmp/neuron-dashboard.zip

# Same base as builder so linked sysroot + libs resolve at runtime without repackaging every .so.
FROM ghcr.io/neugates/build:x86_64-main

ENV LD_LIBRARY_PATH=/usr/local/lib:/home/neuron/main/libs/x86_64-linux-gnu/lib
# open62541 internal client symbols when loading libplugin-opcua.so
ENV LD_PRELOAD=/usr/local/lib/libopen62541.so

WORKDIR /opt/neuron
COPY --from=builder /usr/local/lib/libopen62541.so* /usr/local/lib/
COPY --from=builder /workspace/build-docker-neuron/neuron ./
COPY --from=builder /workspace/build-docker-neuron/libneuron-base.so ./
COPY --from=builder /workspace/build-docker-neuron/plugins ./plugins/
COPY --from=builder /workspace/build-docker-neuron/config ./config/
COPY --from=builder /workspace/build-docker-neuron/dist ./dist/
RUN mkdir -p logs persistence && touch logs/.gitkeep persistence/.gitkeep

EXPOSE 7000
CMD ["./neuron", "--log"]
