# Edge Gateway Remote Minimal API - Examples

This document provides ready-to-use request/response samples for:

- `POST /v1/edge-gateways`
- `POST /v1/edge-gateways/{edgeGatewayId}/commands`
- `GET /v1/edge-gateways/{edgeGatewayId}/commands/{commandId}`

Base URL example:

`https://remote-control.example.com`

---

## 1) Create edge gateway and bootstrap params

### Request

```http
POST /v1/edge-gateways
Content-Type: application/json
```

```json
{
  "edgeGatewayId": "gw_quangninh_001",
  "siteCode": "QN-WTP-01",
  "displayName": "Quang Ninh Water Plant 01",
  "authMode": "mtls"
}
```

### Response (201)

```json
{
  "edgeGatewayId": "gw_quangninh_001",
  "bootstrap": {
    "controlServerUrl": "wss://remote-control.example.com/reverse-channel",
    "authMode": "mtls",
    "heartbeatSec": 20,
    "reconnectSec": 3
  },
  "createdAt": "2026-04-23T16:45:00Z"
}
```

### What Neuron maps locally

Map `bootstrap` values into local Remote Control form/API:

- `gatewayId` -> `gw_quangninh_001`
- `controlServerUrl` -> `wss://remote-control.example.com/reverse-channel`
- `authMode` -> `mtls`
- `heartbeatSec`, `reconnectSec` -> same values

---

## 2) Dispatch command to edgeGatewayId (no direct IP)

### 2.1 get_nodes

```http
POST /v1/edge-gateways/gw_quangninh_001/commands
Content-Type: application/json
```

```json
{
  "commandId": "cmd_get_nodes_20260423_001",
  "operation": "get_nodes",
  "neuronRequest": {
    "method": "GET",
    "path": "/api/v2/node",
    "query": {
      "type": 1
    }
  },
  "timeoutMs": 10000,
  "idempotencyKey": "gw_quangninh_001:get_nodes:20260423:001",
  "dryRun": false
}
```

Accepted response (202):

```json
{
  "edgeGatewayId": "gw_quangninh_001",
  "commandId": "cmd_get_nodes_20260423_001",
  "status": "queued",
  "queuedAt": "2026-04-23T16:46:05Z"
}
```

### 2.2 get_groups

```json
{
  "commandId": "cmd_get_groups_20260423_001",
  "operation": "get_groups",
  "neuronRequest": {
    "method": "GET",
    "path": "/api/v2/group"
  },
  "timeoutMs": 10000,
  "idempotencyKey": "gw_quangninh_001:get_groups:20260423:001",
  "dryRun": false
}
```

### 2.3 get_tags (example node/group)

```json
{
  "commandId": "cmd_get_tags_20260423_001",
  "operation": "get_tags",
  "neuronRequest": {
    "method": "GET",
    "path": "/api/v2/tags",
    "query": {
      "node": "BL1_1",
      "group": "TSC"
    }
  },
  "timeoutMs": 10000,
  "idempotencyKey": "gw_quangninh_001:get_tags:20260423:001",
  "dryRun": false
}
```

---

## 3) Poll command result

### Request

```http
GET /v1/edge-gateways/gw_quangninh_001/commands/cmd_get_tags_20260423_001
```

### Response (200, success)

```json
{
  "edgeGatewayId": "gw_quangninh_001",
  "commandId": "cmd_get_tags_20260423_001",
  "status": "success",
  "httpStatus": 200,
  "result": {
    "tags": [
      {
        "name": "MucNuocBeLoc11",
        "address": "1!451019#BL",
        "type": 9
      },
      {
        "name": "GocMoVanThu11",
        "address": "1!451021#BL",
        "type": 9
      }
    ]
  },
  "startedAt": "2026-04-23T16:46:30Z",
  "completedAt": "2026-04-23T16:46:30.120Z"
}
```

### Response (200, still running)

```json
{
  "edgeGatewayId": "gw_quangninh_001",
  "commandId": "cmd_get_tags_20260423_001",
  "status": "running"
}
```

### Response (404, no command)

```json
{
  "errorCode": "NOT_FOUND",
  "message": "command not found",
  "traceId": "trace_123"
}
```

