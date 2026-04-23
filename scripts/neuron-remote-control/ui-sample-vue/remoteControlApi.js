export function createRemoteControlApi(baseUrl) {
  async function parseJson(res) {
    const data = await res.json();
    if (!res.ok) {
      const errorCode = data && data.errorCode ? data.errorCode : "HTTP_ERROR";
      const message = data && data.message ? data.message : `HTTP ${res.status}`;
      throw new Error(`${errorCode}: ${message}`);
    }
    return data;
  }

  return {
    getConnection() {
      return fetch(`${baseUrl}/api/v2/remote/connection`).then(parseJson);
    },
    saveConnection(payload) {
      return fetch(`${baseUrl}/api/v2/remote/connection`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      }).then(parseJson);
    },
    testConnection(payload) {
      return fetch(`${baseUrl}/api/v2/remote/connection/test`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      }).then(parseJson);
    },
    connect() {
      return fetch(`${baseUrl}/api/v2/remote/connection/connect`, {
        method: "POST",
      }).then(parseJson);
    },
    disconnect() {
      return fetch(`${baseUrl}/api/v2/remote/connection/disconnect`, {
        method: "POST",
      }).then(parseJson);
    },
    getStatus() {
      return fetch(`${baseUrl}/api/v2/remote/connection/status`).then(parseJson);
    },
  };
}
