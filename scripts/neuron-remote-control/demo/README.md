# Demo Stack (Backend Stub + Mock Router)

This demo starts:

- `backend-stub` on `http://127.0.0.1:18080`
- `mock-router` on `wss://127.0.0.1:9001` (self-signed certificate)

## Start

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml up -d --build
```

## Stop

```bash
docker compose -f scripts/neuron-remote-control/demo/docker-compose.yml down
```

## Notes

- Backend sets `REMOTE_TLS_INSECURE=1` in demo mode to allow self-signed TLS for mock router.
- For production, remove insecure mode and use trusted CA/mTLS cert chain.
