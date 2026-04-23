# Full Remote Neuron via Reverse Channel

This package contains implementation-ready design artifacts for managing Neuron gateways behind NAT using an outbound reverse channel.

## Files

- `contracts/command-envelope.schema.json`: schema for remote commands.
- `contracts/response-envelope.schema.json`: schema for command results.
- `contracts/operation-allowlist.md`: operation-to-endpoint mapping and policy.
- `contracts/connection-profile.schema.json`: schema for local Neuron UI connection profile.
- `openapi/control-api.openapi.yaml`: ControlAPI contract for gateway, command, snapshot endpoints.
- `openapi/neuron-local-remote-bootstrap.openapi.yaml`: local Neuron API contract for Save/Test/Connect/Status UI flow.
- `agent/gateway_agent.py`: command execution skeleton (schema validation + allowlist + local Neuron call).
- `agent/sign_command.py`: helper to generate HMAC signatures for command envelopes.
- `agent/Dockerfile`: container packaging for GatewayAgent deployment.
- `agent/requirements.txt`: Python dependencies for GatewayAgent.
- `agent/sample-command.json`: example command envelope for local run.
- `agent/README.md`: setup and run instructions for the agent skeleton.
- `backend-stub/`: FastAPI stub implementing local `/api/v2/remote/*` endpoints for UI onboarding.
- `demo/`: docker-compose demo stack (backend-stub + TLS mock router) for end-to-end API testing.
- `Remote-Control-Bootstrap.postman_collection.json`: Postman collection for testing `/api/v2/remote/*` flow.
- `ui-integration-contract.md`: frontend integration contract (form/state/buttons/polling/errors) for Neuron UI.
- `ui-sample/`: sample React + TypeScript implementation (API client, hook, page skeleton).
- `ui-sample-vue/`: Vue + Element-style page sample and route/menu integration steps for neuron-dashboard source repo.
- `agent-router-design.md`: session lifecycle, routing, timeout and retry logic.
- `security-policy.md`: mTLS, RBAC, allowlist, audit and cert rotation policy.
- `sql/data-model.sql`: control-plane schema for gateway registry, jobs, events, snapshots.
- `rollout-and-test-checklist.md`: phased rollout (P1-P4) and validation checklist.
- `ui-implementation-guide.md`: concrete UI behavior and API interaction contract for Neuron web interface.

## Example Command Envelope

```json
{
  "commandId": "cmd_01J0Q7W6VR8JGF3H2N8M7D9Q4E",
  "gatewayId": "gw_quangninh_001",
  "operation": "get_subscribe",
  "neuronRequest": {
    "method": "GET",
    "path": "/api/v2/subscribe",
    "query": {
      "app": "mqtt"
    }
  },
  "timeoutMs": 10000,
  "idempotencyKey": "gw_quangninh_001:get_subscribe:2026-04-23T12",
  "createdAt": "2026-04-23T04:30:00Z"
}
```

## Example Response Envelope

```json
{
  "commandId": "cmd_01J0Q7W6VR8JGF3H2N8M7D9Q4E",
  "gatewayId": "gw_quangninh_001",
  "status": "success",
  "attempt": 1,
  "httpStatus": 200,
  "result": {
    "groups": [
      {
        "driver": "modbus-tcp",
        "group": "group-1",
        "params": {
          "topic": "neuron/PcznZv/modbus-tcp/group-1"
        }
      }
    ]
  },
  "startedAt": "2026-04-23T04:30:02Z",
  "completedAt": "2026-04-23T04:30:02.410Z",
  "durationMs": 410
}
```

## Integration Notes

- Neuron local API contract reference: `docs/api/english/http.md`.
- Existing API smoke-test collection: `scripts/neuron-excel-import/Neuron-API-v2.postman_collection.json`.
- Apply write operations gradually with `dryRun=true` during pilot.
