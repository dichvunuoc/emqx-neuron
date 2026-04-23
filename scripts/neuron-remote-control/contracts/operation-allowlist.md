# Neuron Remote Operation Allowlist

This allowlist maps remote operations to Neuron REST API endpoints from `docs/api/english/http.md`.

## Read Operations (P1)

| operation | method | path | required query/body |
|---|---|---|---|
| `get_version` | GET | `/api/v2/version` | none |
| `get_nodes` | GET | `/api/v2/node` | query: `type` |
| `get_node_state` | GET | `/api/v2/node/state` | query: `node` |
| `get_node_setting` | GET | `/api/v2/node/setting` | query: `node` |
| `get_groups` | GET | `/api/v2/group` | optional query: `node` |
| `get_tags` | GET | `/api/v2/tags` | query: `node`, `group` |
| `get_subscribe` | GET | `/api/v2/subscribe` | query: `app`, optional `driver`, `group` |
| `get_subscribes` | GET | `/api/v2/subscribes` | query: `app`, optional `name` |
| `read_tags` | POST | `/api/v2/read` | body follows Neuron read schema |

## Controlled Write Operations (P2)

| operation | method | path | notes |
|---|---|---|---|
| `create_subscribe` | POST | `/api/v2/subscribe` | write scope: mqtt subscribe only |
| `update_subscribe` | PUT | `/api/v2/subscribe` | update params/topic/static tags |
| `delete_subscribe` | DELETE | `/api/v2/subscribe` | must include app/driver/group |
| `create_group` | POST | `/api/v2/group` | requires approval in production |
| `update_group` | PUT | `/api/v2/group` | validates interval boundaries |
| `delete_group` | DELETE | `/api/v2/group` | block if active tags unless force approved |
| `create_tags` | POST | `/api/v2/tags` | max batch size policy applies |
| `update_tags` | PUT | `/api/v2/tags` | tag schema validation required |
| `delete_tags` | DELETE | `/api/v2/tags` | include exact tag names |
| `node_ctl` | POST | `/api/v2/node/ctl` | only START/STOP accepted |

## Policy Rules

- Gateway agent rejects all paths outside `/api/v2/*`.
- Gateway agent strips caller-provided `Authorization` header and injects local Neuron token.
- Write operations require `dryRun=false` and elevated RBAC role.
- For retries, operations must include `idempotencyKey`.
