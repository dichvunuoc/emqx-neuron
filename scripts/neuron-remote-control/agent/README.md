# GatewayAgent Skeleton

This directory contains a command execution skeleton plus reverse-channel websocket loop.

## What it does

- Validates command envelope against `contracts/command-envelope.schema.json`.
- Verifies HMAC signature for incoming commands (optional signed mode).
- Enforces operation allowlist (`method` + `path`) from the design contract.
- Rejects caller-supplied `Authorization` header.
- Calls local Neuron API and returns a normalized response envelope.
- Supports `dryRun=true` for write operations.
- Supports websocket loop with `HELLO`, `HEARTBEAT`, `COMMAND`, `RESPONSE`.

## Requirements

- Python 3.9+
- `jsonschema`
- `websocket-client`

Install:

```bash
python3 -m pip install jsonschema
python3 -m pip install -r scripts/neuron-remote-control/agent/requirements.txt
```

## Run one command envelope

```bash
python3 scripts/neuron-remote-control/agent/gateway_agent.py \
  --command scripts/neuron-remote-control/agent/sample-command.json \
  --schema scripts/neuron-remote-control/contracts/command-envelope.schema.json \
  --gateway-id gw_quangninh_001 \
  --neuron-base-url http://127.0.0.1:7000 \
  --neuron-token '<NEURON_JWT_TOKEN>'
```

### Signed command mode (HMAC)

```bash
SIG=$(python3 scripts/neuron-remote-control/agent/sign_command.py \
  --command scripts/neuron-remote-control/agent/sample-command.json \
  --secret 'my-shared-secret')

python3 scripts/neuron-remote-control/agent/gateway_agent.py \
  --command scripts/neuron-remote-control/agent/sample-command.json \
  --schema scripts/neuron-remote-control/contracts/command-envelope.schema.json \
  --gateway-id gw_quangninh_001 \
  --neuron-base-url http://127.0.0.1:7000 \
  --neuron-token '<NEURON_JWT_TOKEN>' \
  --hmac-secret 'my-shared-secret' \
  --signature "$SIG"
```

### Run reverse-channel loop

```bash
python3 scripts/neuron-remote-control/agent/gateway_agent.py \
  --run-loop \
  --router-url 'wss://control.example.com/reverse-channel' \
  --schema scripts/neuron-remote-control/contracts/command-envelope.schema.json \
  --gateway-id gw_quangninh_001 \
  --neuron-base-url http://127.0.0.1:7000 \
  --neuron-token '<NEURON_JWT_TOKEN>' \
  --hmac-secret 'my-shared-secret'
```

### Test router connectivity only

```bash
python3 scripts/neuron-remote-control/agent/gateway_agent.py \
  --test-router \
  --router-url 'wss://control.example.com/reverse-channel' \
  --gateway-id gw_quangninh_001 \
  --neuron-token '<NEURON_JWT_TOKEN>'
```

### Build Docker image

```bash
docker build -f scripts/neuron-remote-control/agent/Dockerfile -t neuron-gateway-agent .
```

## Notes

- This is still a skeleton, but now includes websocket transport loop and signed command verification.
- Signature verification uses shared-secret HMAC for bootstrap; production can upgrade to asymmetric signatures.
