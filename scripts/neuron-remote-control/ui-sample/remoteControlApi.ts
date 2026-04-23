export type AuthMode = "mtls" | "mtls_hmac";

export type ConnectionProfile = {
  enabled: boolean;
  gatewayId: string;
  controlServerUrl: string;
  authMode: AuthMode;
  hmacEnabled?: boolean;
  heartbeatSec: number;
  reconnectSec: number;
  dryRunDefault: boolean;
  updatedAt: string;
};

export type ConnectionProfileSaveRequest = {
  gatewayId: string;
  controlServerUrl: string;
  authMode: AuthMode;
  hmacSecret?: string;
  heartbeatSec: number;
  reconnectSec: number;
  dryRunDefault: boolean;
};

export type ConnectionTestRequest = {
  gatewayId: string;
  controlServerUrl: string;
  authMode: AuthMode;
  hmacSecret?: string;
};

export type ConnectionTestResult = {
  ok: boolean;
  code:
    | "CONNECTED"
    | "TLS_FAILED"
    | "AUTH_FAILED"
    | "TIMEOUT"
    | "ROUTER_NO_ACK"
    | "INVALID_CONFIG";
  message: string;
  latencyMs?: number;
  checkedAt: string;
};

export type ConnectionRuntimeStatus = {
  state: "disabled" | "connecting" | "connected" | "degraded" | "disconnected";
  lastError?: string;
  lastHeartbeatAt?: string;
  lastChangeAt: string;
};

export type ErrorResponse = {
  errorCode: string;
  message: string;
};

async function parseJson<T>(res: Response): Promise<T> {
  const data = (await res.json()) as T | ErrorResponse;
  if (!res.ok) {
    const err = data as ErrorResponse;
    throw new Error(`${err.errorCode}: ${err.message}`);
  }
  return data as T;
}

export class RemoteControlApi {
  constructor(private readonly baseUrl: string) {}

  getConnection(): Promise<ConnectionProfile> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection`).then(parseJson);
  }

  saveConnection(payload: ConnectionProfileSaveRequest): Promise<{ error: number; updatedAt: string }> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).then(parseJson);
  }

  testConnection(payload: ConnectionTestRequest): Promise<ConnectionTestResult> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection/test`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).then(parseJson);
  }

  connect(): Promise<{ error: number; status: "connecting" | "connected" | "failed"; message: string }> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection/connect`, {
      method: "POST",
    }).then(parseJson);
  }

  disconnect(): Promise<{ error: number; status: "disconnected"; message: string }> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection/disconnect`, {
      method: "POST",
    }).then(parseJson);
  }

  getStatus(): Promise<ConnectionRuntimeStatus> {
    return fetch(`${this.baseUrl}/api/v2/remote/connection/status`).then(parseJson);
  }
}
