# Remote Server (Complete Control Plane Skeleton)

This service implements a minimal but complete REMOTE control plane:

- Create edge gateway IDs and bootstrap mapping params.
- Accept outbound reverse-channel websocket from GatewayAgent.
- Dispatch commands by `edgeGatewayId` (no direct edge IP).
- Track command status/result by `commandId`.

## API

- `POST /v1/edge-gateways`
- `POST /v1/edge-gateways/{edgeGatewayId}/commands`
- `GET /v1/edge-gateways/{edgeGatewayId}/commands/{commandId}`
- WebSocket reverse channel: `wss://<host>:9010/reverse-channel`

## Local run

```bash
python3 -m pip install -r scripts/neuron-remote-control/remote-server/requirements.txt
uvicorn app.main:app --app-dir scripts/neuron-remote-control/remote-server --host 0.0.0.0 --port 9010
```
