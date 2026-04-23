# Remote Control FastAPI Stub

Standalone backend stub implementing local Neuron bootstrap endpoints:

- `GET /api/v2/remote/connection`
- `PUT /api/v2/remote/connection`
- `POST /api/v2/remote/connection/test`
- `POST /api/v2/remote/connection/connect`
- `POST /api/v2/remote/connection/disconnect`
- `GET /api/v2/remote/connection/status`

## Run

```bash
python3 -m pip install -r scripts/neuron-remote-control/backend-stub/requirements.txt
uvicorn scripts.neuron-remote-control.backend-stub.app.main:app --host 0.0.0.0 --port 18080
```

If your Python import path does not accept `-` in folder names, run from repo root with:

```bash
PYTHONPATH=. uvicorn app.main:app --app-dir scripts/neuron-remote-control/backend-stub --host 0.0.0.0 --port 18080
```

## Environment Variables

- `REMOTE_PROFILE_PATH` (default: `scripts/neuron-remote-control/backend-stub/data/connection-profile.json`)
- `REMOTE_CONNECTION_SCHEMA` (default: `scripts/neuron-remote-control/contracts/connection-profile.schema.json`)
- `REMOTE_AGENT_SCRIPT` (default: `scripts/neuron-remote-control/agent/gateway_agent.py`)
- `REMOTE_SCHEMA_PATH` (default: `scripts/neuron-remote-control/contracts/command-envelope.schema.json`)
- `REMOTE_NEURON_BASE_URL` (default: `http://127.0.0.1:7000`)
- `REMOTE_NEURON_TOKEN` (required for meaningful test/connect operations)

## Quick Curl Samples

```bash
curl -s http://127.0.0.1:18080/api/v2/remote/connection | jq
```

```bash
curl -s -X PUT http://127.0.0.1:18080/api/v2/remote/connection \
  -H 'content-type: application/json' \
  -d '{
    "gatewayId":"gw_quangninh_001",
    "controlServerUrl":"wss://control.example.com/reverse-channel",
    "authMode":"mtls_hmac",
    "hmacSecret":"demo-secret",
    "heartbeatSec":20,
    "reconnectSec":3,
    "dryRunDefault":true
  }' | jq
```

```bash
curl -s -X POST http://127.0.0.1:18080/api/v2/remote/connection/test \
  -H 'content-type: application/json' \
  -d '{
    "gatewayId":"gw_quangninh_001",
    "controlServerUrl":"wss://control.example.com/reverse-channel",
    "authMode":"mtls_hmac",
    "hmacSecret":"demo-secret"
  }' | jq
```

```bash
curl -s -X POST http://127.0.0.1:18080/api/v2/remote/connection/connect | jq
curl -s http://127.0.0.1:18080/api/v2/remote/connection/status | jq
curl -s -X POST http://127.0.0.1:18080/api/v2/remote/connection/disconnect | jq
```

## Test Checklist

- Save profile valid/invalid payloads.
- Test connection success and failure paths.
- Connect/disconnect idempotency.
- Status reflects runtime state transitions.
- Error response shape always `{errorCode, message}` for 4xx failures.

## Docker Compose Demo

Run mock router + backend stub:

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml up -d
```

Stop demo:

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml down
```
