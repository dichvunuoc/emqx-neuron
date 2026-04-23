import React, { useMemo, useState } from "react";
import { ConnectionProfileSaveRequest, ConnectionTestRequest } from "./remoteControlApi";
import { useRemoteControl } from "./useRemoteControl";

function statusColor(state?: string): string {
  switch (state) {
    case "connected":
      return "green";
    case "connecting":
      return "blue";
    case "degraded":
      return "orange";
    case "disconnected":
    case "disabled":
    default:
      return "gray";
  }
}

export function RemoteControlPage() {
  const baseUrl = useMemo(() => window.location.origin, []);
  const { profile, status, testResult, loading, error, saveProfile, testConnection, connect, disconnect } =
    useRemoteControl(baseUrl);

  const [form, setForm] = useState<ConnectionProfileSaveRequest>({
    gatewayId: "",
    controlServerUrl: "",
    authMode: "mtls",
    hmacSecret: "",
    heartbeatSec: 20,
    reconnectSec: 3,
    dryRunDefault: true,
  });

  React.useEffect(() => {
    if (!profile) return;
    setForm((prev) => ({
      ...prev,
      gatewayId: profile.gatewayId,
      controlServerUrl: profile.controlServerUrl,
      authMode: profile.authMode,
      heartbeatSec: profile.heartbeatSec,
      reconnectSec: profile.reconnectSec,
      dryRunDefault: profile.dryRunDefault,
    }));
  }, [profile]);

  const onSave = async () => {
    await saveProfile(form);
    alert("Saved");
  };

  const onTest = async () => {
    const payload: ConnectionTestRequest = {
      gatewayId: form.gatewayId,
      controlServerUrl: form.controlServerUrl,
      authMode: form.authMode,
      hmacSecret: form.hmacSecret,
    };
    const result = await testConnection(payload);
    alert(result.ok ? "Connection OK" : `Test failed: ${result.message}`);
  };

  return (
    <div style={{ padding: 16, maxWidth: 760 }}>
      <h2>Remote Control</h2>

      <div style={{ marginBottom: 12 }}>
        <strong>Status: </strong>
        <span style={{ color: statusColor(status?.state) }}>{status?.state ?? "unknown"}</span>
      </div>

      <label>Gateway ID</label>
      <input
        value={form.gatewayId}
        onChange={(e) => setForm({ ...form, gatewayId: e.target.value })}
        style={{ width: "100%", marginBottom: 8 }}
      />

      <label>Control Server URL</label>
      <input
        value={form.controlServerUrl}
        onChange={(e) => setForm({ ...form, controlServerUrl: e.target.value })}
        style={{ width: "100%", marginBottom: 8 }}
      />

      <label>Auth Mode</label>
      <select
        value={form.authMode}
        onChange={(e) => setForm({ ...form, authMode: e.target.value as "mtls" | "mtls_hmac" })}
        style={{ width: "100%", marginBottom: 8 }}
      >
        <option value="mtls">mTLS</option>
        <option value="mtls_hmac">mTLS + HMAC</option>
      </select>

      {form.authMode === "mtls_hmac" && (
        <>
          <label>HMAC Secret</label>
          <input
            type="password"
            value={form.hmacSecret || ""}
            onChange={(e) => setForm({ ...form, hmacSecret: e.target.value })}
            style={{ width: "100%", marginBottom: 8 }}
          />
        </>
      )}

      <label>Heartbeat Seconds</label>
      <input
        type="number"
        value={form.heartbeatSec}
        onChange={(e) => setForm({ ...form, heartbeatSec: Number(e.target.value) })}
        style={{ width: "100%", marginBottom: 8 }}
      />

      <label>Reconnect Seconds</label>
      <input
        type="number"
        value={form.reconnectSec}
        onChange={(e) => setForm({ ...form, reconnectSec: Number(e.target.value) })}
        style={{ width: "100%", marginBottom: 8 }}
      />

      <label>
        <input
          type="checkbox"
          checked={form.dryRunDefault}
          onChange={(e) => setForm({ ...form, dryRunDefault: e.target.checked })}
        />
        Dry-run by default
      </label>

      <div style={{ marginTop: 12, display: "flex", gap: 8 }}>
        <button onClick={onSave} disabled={loading}>
          Save
        </button>
        <button onClick={onTest} disabled={loading}>
          Test Connection
        </button>
        <button onClick={() => void connect()} disabled={loading}>
          Connect
        </button>
        <button onClick={() => void disconnect()} disabled={loading}>
          Disconnect
        </button>
      </div>

      {testResult && (
        <pre style={{ marginTop: 16, background: "#f5f5f5", padding: 12 }}>
          {JSON.stringify(testResult, null, 2)}
        </pre>
      )}

      {status && (
        <pre style={{ marginTop: 8, background: "#f5f5f5", padding: 12 }}>
          {JSON.stringify(status, null, 2)}
        </pre>
      )}

      {error && <div style={{ color: "red", marginTop: 12 }}>{error}</div>}
    </div>
  );
}

export default RemoteControlPage;
