# Security Policy for Remote Neuron Management

## Trust Boundaries

- Cloud control plane and reverse router run in trusted central environment.
- Gateway site network is semi-trusted; only outbound connections are allowed.
- Local Neuron API is treated as privileged and reachable only by GatewayAgent.

## Authentication and Transport

- Use **mTLS** between GatewayAgent and ReverseChannelRouter.
- Certificate identity maps to one `gatewayId`; CN/SAN must match registry entry.
- TLS minimum version: 1.2 (1.3 preferred), modern cipher suites only.
- Reject plaintext transport; only `wss` is allowed for command channel.

## Authorization (RBAC)

Define three roles at control plane level:

- `remote_read`: read-only operations (`get_*`, `read_tags`).
- `remote_write`: controlled writes (`create/update/delete` subscribe/group/tags).
- `remote_runtime`: runtime control (`node_ctl`) and emergency actions.

Policy engine checks role + gateway scope before command dispatch.

## Agent Allowlist Enforcement

- Agent executes only operations listed in `contracts/operation-allowlist.md`.
- Agent blocks unknown `method/path` combinations.
- Agent strips command-supplied `Authorization` and injects local Neuron token.
- Maximum request body size and tag batch count are enforced to prevent abuse.

## Command Integrity and Replay Protection

- Each command includes a detached signature (or JWS) from control plane key.
- Agent verifies signature and timestamp skew (`<=120s`).
- `idempotencyKey` plus `commandId` prevents replay and duplicate execution.

## Secrets and Credential Handling

- Store gateway private keys in OS keychain or TPM when available.
- Never store raw Neuron admin credentials in central control database.
- Agent obtains local Neuron token with dedicated local account and rotates periodically.

## Certificate Rotation

- Support overlapping validity windows for zero-downtime rotation.
- Standard lifecycle:
  1. Issue new cert and publish to gateway registry.
  2. Agent downloads and hot-reloads cert.
  3. Reconnect using new cert.
  4. Revoke old cert after confirmation.
- Rotation interval recommendation: 60-90 days.

## Auditing and Compliance

Every remote action must generate immutable audit records with:

- actor identity and RBAC role
- gatewayId, commandId, operation
- payload hash (not always full payload)
- before/after summary for write operations
- outcome, duration, and Neuron error code

## Incident Response Controls

- Kill switch per gateway (disable remote writes, keep read-only).
- Global policy mode `read-only` for emergency freeze.
- Automatic lockout after repeated signature/auth failures.
