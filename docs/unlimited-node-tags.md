# Unlimited Node Tags (Custom Build)

This custom build removes the REST-side hard limit on the number of node tags.

## What was changed

- Removed the `tags_length(req->tags) > 5` validation in:
  - `plugins/restful/adapter_handle.c` (`handle_add_adapter`)
  - `plugins/restful/adapter_handle.c` (`handle_put_node_tag`)
- Updated functional test expectation in:
  - `tests/ft/node/test_node_tag.py` (`test_add_many_tags`)

## Behavior after change

- Node tag count is no longer limited to 5 by REST validation.
- Tag count is now effectively limited by runtime resources (CPU, memory, I/O) and downstream workload.

## Build and test notes

The project was successfully built in a Linux Docker environment using the same image/toolchain strategy as upstream CI.

### Docker Linux build (verified)

```bash
docker pull --platform linux/amd64 ghcr.io/neugates/build:x86_64-main

docker run --rm --platform linux/amd64 \
  --mount type=bind,source="$(pwd)",target=/workspace \
  -w /workspace \
  ghcr.io/neugates/build:x86_64-main \
  bash -lc "git config --global --add safe.directory /workspace && \
            mkdir -p build-linux && cd build-linux && \
            cmake .. -DCMAKE_TOOLCHAIN_FILE=../cmake/x86_64-linux-gnu.cmake \
                     -DCMAKE_BUILD_TYPE=Release -DDISABLE_UT=ON && \
            make -j4"
```

Smoke run:

```bash
docker run --rm --platform linux/amd64 \
  --mount type=bind,source="$(pwd)",target=/workspace \
  -w /workspace/build-linux \
  ghcr.io/neugates/build:x86_64-main \
  bash -lc "LD_LIBRARY_PATH=/home/neuron/main/libs/x86_64-linux-gnu/lib:$LD_LIBRARY_PATH \
            ./neuron --version"
```

For regression/load checks, verify these scenarios:

1. Add/update node tags with small set (<= 5) and larger sets (for example 100, 1000).
2. Confirm API responses remain successful for valid tag strings.
3. Observe system resource usage under high tag counts.
