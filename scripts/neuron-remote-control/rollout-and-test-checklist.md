# Rollout Plan and Production Checklist

## Phase P1 - Read-only Foundation

- Deploy ReverseChannelRouter and GatewayAgent connectivity only.
- Enable read operations (`get_*`, `read_tags`) and disable writes by policy.
- Build inventory sync pipeline into `config_snapshot`.
- SLO target: `99.5%` command completion for read jobs within 10s.

Exit criteria:

- At least 95% gateways report online heartbeat.
- Inventory snapshot is collected at least every 15 minutes.
- No unresolved critical security findings.

## Phase P2 - Controlled Write

- Enable write operations: subscribe/group/tag management.
- Introduce approval workflow for high-risk changes.
- Enable mandatory `dryRun` for first rollout wave.

Exit criteria:

- Write success rate above 98% in pilot gateways.
- All write jobs have complete audit records.
- Rollback tested for each write operation.

## Phase P3 - Full Remote Management

- Add runtime controls (`node_ctl`) and batch orchestration.
- Introduce site-level rollout windows and freeze periods.
- Add drift detection between desired state and Neuron snapshots.

Exit criteria:

- Batch rollout supports staged deployment by site/group.
- Drift detection noise rate below agreed threshold.
- Operational runbook approved by SRE and OT teams.

## Phase P4 - Production Hardening

- Chaos drills: router restarts, network partitions, cert expiry.
- Scale tests: peak command throughput and reconnect storms.
- Finalize alerting on timeout, retry storm, and auth failures.

Exit criteria:

- Recovery objectives met in chaos tests.
- Alert-to-mitigation workflow proven by on-call drills.
- Capacity headroom >= 30% at peak load.

## Cross-phase Test Matrix

### Connectivity

- Gateway offline/online flapping behavior.
- Heartbeat miss handling and session replacement.
- Reconnect with exponential backoff and jitter.

### Reliability

- Command timeout path and retry caps.
- Idempotency duplicate submission behavior.
- Queue persistence across router restart.

### Security

- mTLS verification failure handling.
- Signature validation and replay rejection.
- Certificate rotation without downtime.

### Functional

- Endpoint allowlist blocks non-approved API calls.
- Dry-run response correctness for write operations.
- Before/after snapshots for config-changing commands.

## Canary Strategy

- Wave 1: 5 gateways (non-critical sites).
- Wave 2: 10-20% of gateways, mixed network quality.
- Wave 3: 50% rollout with weekend freeze window.
- Wave 4: 100% rollout after two stable weeks.
