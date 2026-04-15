#!/usr/bin/env bash
# Run in Linux Docker (e.g. ghcr.io/neugates/build:x86_64-main): build open62541 + Neuron, start neuron, run OPC UA E2E pytest.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git ca-certificates python3-pip

python3 -m pip install -q pytest asyncua requests

O62541_TAG="${O62541_TAG:-v1.4.6}"

if ! ldconfig -p 2>/dev/null | grep -q 'libopen62541.so'; then
  rm -rf /tmp/open62541
  git clone --depth 1 --branch "${O62541_TAG}" https://github.com/open62541/open62541.git /tmp/open62541
  mkdir -p /tmp/open62541/build
  cd /tmp/open62541/build
  # Same compiler as Neuron cross toolchain when present
  CC_BIN="${CC:-cc}"
  command -v x86_64-linux-gnu-gcc >/dev/null && CC_BIN=x86_64-linux-gnu-gcc
  cmake .. \
    -DCMAKE_C_COMPILER="${CC_BIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
  cmake --build . -j1
  cmake --install .
  ldconfig
fi

cd /workspace
git config --global --add safe.directory /workspace

rm -rf build-docker-opcua-e2e
mkdir -p build-docker-opcua-e2e
cd build-docker-opcua-e2e

cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=../cmake/x86_64-linux-gnu.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DDISABLE_UT=ON \
  -DCMAKE_PREFIX_PATH=/usr/local

# Parallel link with LTO can hit "jobserver: Bad file descriptor" in some Docker/shell setups.
cmake --build . -j1

export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
# Ensure open62541 is on the link map before plugins resolve internal client symbols (e.g. __UA_Client_connect).
export LD_PRELOAD="/usr/local/lib/libopen62541.so${LD_PRELOAD:+:${LD_PRELOAD}}"

cd /workspace/build-docker-opcua-e2e
./neuron --log &
NPID=$!
sleep 15

cd /workspace/tests/ft
set +e
OPCUA_E2E=1 python3 -m pytest driver/test_opcua_plugin.py::TestOpcUaPluginE2e -v --tb=short
EC=$?
set -e

kill "${NPID}" 2>/dev/null || true
wait "${NPID}" 2>/dev/null || true
exit "${EC}"
