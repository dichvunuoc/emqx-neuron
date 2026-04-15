# OPC UA Southbound Plugin (OSS)

This repository includes an OSS OPC UA southbound plugin at `plugins/opcua` (open62541).

## Build behavior

- If **open62541** is found at configure time (`find_library` / headers), `plugin-opcua` is built with `NEU_OPCUA_HAS_OPEN62541=1` and linked against the library.
- If it is **not** found, the plugin still builds, but runtime calls return a dependency / library-not-found style error.

On Debian/Ubuntu you can install the development package so CMake discovers the stack, for example:

```bash
sudo apt-get install libopen62541-1.4-dev
```

Then configure and build Neuron as usual (see `Install-dependencies.md` for the full toolchain).

## Plugin schema

Schema file: `plugins/opcua/opcua.json`

Parameters:

| Key | Meaning |
|-----|---------|
| `endpoint` | OPC UA endpoint URL (e.g. `opc.tcp://127.0.0.1:4840/` or a path including `/server/` as required by the server) |
| `timeout` | Connection timeout (ms) |
| `enable_auth` | Use username/password when non-zero |
| `username` / `password` | Optional credentials when auth is enabled |
| `read_mode` | `0` = poll read in `group_timer`; `1` = OPC UA subscription (monitored items + `UA_Client_run_iterate`) |
| `publish_interval` | Publishing / sampling interval (ms); minimum enforced in driver (e.g. 100 ms) |

## Tag address format

Supported styles:

- `ns=2;i=2258`
- `ns=2;s=Demo.Static.Scalar.Int32`
- `2!i=2258`
- `2!s=Demo.Static.Scalar.Int32`

## Behavior (summary)

- **Read (poll):** `group_timer` reads tag values over OPC UA for configured scalar types.
- **Read (subscription):** when `read_mode` is subscription, the driver creates a subscription and monitored items, then runs `UA_Client_run_iterate` on the group interval so data-change notifications update Neuron.
- **Write:** scalar writes map Neuron types to OPC UA variants and call `UA_Client_writeValueAttribute`.
- **Scan:** `scan_tags` performs a Browse from the Objects folder (or from `id` when non-empty) and returns child references for the UI.
- **`test_read_tag`:** uses the driver test-read path when built with open62541.

## Functional tests (optional E2E)

Requirements:

- Neuron running with the API reachable (`tests/ft/neuron/config.py` `BASE_URL`).
- Plugin built **with** open62541 (not the stub-only build).
- Python package **asyncua** for the tiny simulator: `pip install asyncua`.

Run the asyncua-based E2E tests:

```bash
cd tests/ft
OPCUA_E2E=1 python3 -m pytest driver/test_opcua_plugin.py::TestOpcUaPluginE2e -v
```

The simulator script is `tests/ft/simulator/opcua_asyncua_server.py`. By default the basic plugin tests (`TestOpcUaPlugin`) do not need a live OPC UA server; E2E tests are skipped unless `OPCUA_E2E=1`.
