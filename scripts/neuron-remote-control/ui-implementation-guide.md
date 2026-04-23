# Neuron Web UI - Remote Connection Implementation Guide

This guide defines the exact UX and backend interaction so an operator can configure reverse-channel remote control directly in Neuron web UI.

## UI location

- Menu: `Configuration -> Remote Control`
- One page with 3 sections:
  1. **Connection Profile**
  2. **Test Connection**
  3. **Runtime Status**

## Section 1 - Connection Profile

Fields:

- `Gateway ID` (text)
- `Control Server URL` (text, `wss://...`)
- `Auth Mode` (`mTLS` or `mTLS + HMAC`)
- `HMAC Secret` (password, optional unless mode requires)
- `Heartbeat (sec)`
- `Reconnect Backoff (sec)`
- `Dry-run by default` (toggle)
- `Enable Remote Control` (toggle)

Buttons:

- `Save`
- `Connect`
- `Disconnect`

## Section 2 - Test Connection

Button: `Test Connection`

Expected behavior:

1. UI sends `POST /api/v2/remote/connection/test` with current form values (without persisting if unsaved).
2. Backend performs HELLO handshake against router (same logic as agent `--test-router`).
3. UI displays badge and details:
   - green: `CONNECTED`
   - yellow: `ROUTER_NO_ACK`
   - red: `TLS_FAILED`, `AUTH_FAILED`, `TIMEOUT`, `INVALID_CONFIG`
4. Show latency in milliseconds if available.

## Section 3 - Runtime Status

Poll `GET /api/v2/remote/connection/status` every 5 seconds:

- states: `disabled`, `connecting`, `connected`, `degraded`, `disconnected`
- show `lastHeartbeatAt` and `lastError`

## API calls from UI

1. `GET /api/v2/remote/connection` on page load
2. `PUT /api/v2/remote/connection` on Save
3. `POST /api/v2/remote/connection/test` on Test
4. `POST /api/v2/remote/connection/connect` on Connect
5. `POST /api/v2/remote/connection/disconnect` on Disconnect
6. `GET /api/v2/remote/connection/status` polling

See full contract in:

- `openapi/neuron-local-remote-bootstrap.openapi.yaml`
- `contracts/connection-profile.schema.json`

## Backend implementation notes

- Persist profile in local config store (do not store plaintext HMAC secret in config file).
- Encrypt secret at rest (OS keychain/keystore preferred).
- Trigger agent process reload after successful profile save when `enabled=true`.
- `connect` should be idempotent: if already connected, return success with current state.

## Security constraints

- Mask `HMAC Secret` in UI and API responses.
- Require authenticated admin session for all `/api/v2/remote/*` endpoints.
- Audit events: save profile, test result, connect, disconnect.
