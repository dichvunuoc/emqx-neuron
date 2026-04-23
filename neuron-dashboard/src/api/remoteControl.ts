import http from '@/utils/http'

export type AuthMode = 'mtls' | 'mtls_hmac'

export interface ConnectionProfile {
  enabled: boolean
  gatewayId: string
  controlServerUrl: string
  authMode: AuthMode
  hmacEnabled?: boolean
  heartbeatSec: number
  reconnectSec: number
  dryRunDefault: boolean
  updatedAt: string
}

export interface ConnectionProfileSaveRequest {
  gatewayId: string
  controlServerUrl: string
  authMode: AuthMode
  hmacSecret?: string
  heartbeatSec: number
  reconnectSec: number
  dryRunDefault: boolean
}

export interface ConnectionTestRequest {
  gatewayId: string
  controlServerUrl: string
  authMode: AuthMode
  hmacSecret?: string
}

export interface ConnectionTestResult {
  ok: boolean
  code: 'CONNECTED' | 'TLS_FAILED' | 'AUTH_FAILED' | 'TIMEOUT' | 'ROUTER_NO_ACK' | 'INVALID_CONFIG'
  message: string
  latencyMs?: number
  checkedAt: string
}

export interface ConnectionRuntimeStatus {
  state: 'disabled' | 'connecting' | 'connected' | 'degraded' | 'disconnected'
  lastError?: string
  lastHeartbeatAt?: string
  lastChangeAt: string
}

export const getRemoteConnection = async (): Promise<ConnectionProfile> => {
  const { data } = await http.get('/remote/connection')
  return data
}

export const saveRemoteConnection = async (payload: ConnectionProfileSaveRequest) => {
  const { data } = await http.put('/remote/connection', payload)
  return data
}

export const testRemoteConnection = async (payload: ConnectionTestRequest): Promise<ConnectionTestResult> => {
  const { data } = await http.post('/remote/connection/test', payload)
  return data
}

export const connectRemoteConnection = async () => {
  const { data } = await http.post('/remote/connection/connect')
  return data
}

export const disconnectRemoteConnection = async () => {
  const { data } = await http.post('/remote/connection/disconnect')
  return data
}

export const getRemoteConnectionStatus = async (): Promise<ConnectionRuntimeStatus> => {
  const { data } = await http.get('/remote/connection/status')
  return data
}
