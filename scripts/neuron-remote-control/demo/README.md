# Demo Stack (Backend Stub + Remote Server)

This demo starts:

- `backend-stub` on `http://127.0.0.1:18080`
- `remote-server` on `https://127.0.0.1:9010` (self-signed certificate)
  - REST API: `/v1/edge-gateways`, `/v1/edge-gateways/{edgeGatewayId}/commands`
  - WebSocket: `wss://127.0.0.1:9010/reverse-channel`

## Start

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml up -d --build
```

## Stop

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml down
```

## Notes

- Backend sets `REMOTE_TLS_INSECURE=1` in demo mode to allow self-signed TLS for remote server.
- For production, remove insecure mode and use trusted CA/mTLS cert chain.
