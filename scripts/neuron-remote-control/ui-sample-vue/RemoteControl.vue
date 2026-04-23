<template>
  <div class="remote-control-page">
    <el-card>
      <div slot="header" class="clearfix">
        <span>Remote Control</span>
      </div>

      <el-alert
        v-if="error"
        :title="error"
        type="error"
        show-icon
        style="margin-bottom: 12px"
      />

      <el-form :model="form" label-width="180px" size="small">
        <el-form-item label="Runtime Status">
          <el-tag :type="statusTagType">{{ status.state || 'unknown' }}</el-tag>
          <span v-if="status.lastHeartbeatAt" style="margin-left: 8px">
            Last heartbeat: {{ status.lastHeartbeatAt }}
          </span>
        </el-form-item>

        <el-form-item label="Gateway ID">
          <el-input v-model="form.gatewayId" />
        </el-form-item>

        <el-form-item label="Control Server URL">
          <el-input v-model="form.controlServerUrl" placeholder="wss://control.example.com/reverse-channel" />
        </el-form-item>

        <el-form-item label="Auth Mode">
          <el-select v-model="form.authMode" style="width: 100%">
            <el-option label="mTLS" value="mtls" />
            <el-option label="mTLS + HMAC" value="mtls_hmac" />
          </el-select>
        </el-form-item>

        <el-form-item v-if="form.authMode === 'mtls_hmac'" label="HMAC Secret">
          <el-input v-model="form.hmacSecret" show-password />
        </el-form-item>

        <el-form-item label="Heartbeat (sec)">
          <el-input-number v-model="form.heartbeatSec" :min="5" :max="120" />
        </el-form-item>

        <el-form-item label="Reconnect (sec)">
          <el-input-number v-model="form.reconnectSec" :min="1" :max="60" />
        </el-form-item>

        <el-form-item label="Dry Run Default">
          <el-switch v-model="form.dryRunDefault" />
        </el-form-item>

        <el-form-item>
          <el-button type="primary" :loading="loading" @click="onSave">Save</el-button>
          <el-button :loading="loading" @click="onTest">Test Connection</el-button>
          <el-button type="success" :loading="loading" @click="onConnect">Connect</el-button>
          <el-button type="warning" :loading="loading" @click="onDisconnect">Disconnect</el-button>
        </el-form-item>
      </el-form>

      <el-divider />

      <el-descriptions title="Last Test Result" :column="1" size="small" border>
        <el-descriptions-item label="ok">{{ testResult.ok }}</el-descriptions-item>
        <el-descriptions-item label="code">{{ testResult.code }}</el-descriptions-item>
        <el-descriptions-item label="message">{{ testResult.message }}</el-descriptions-item>
        <el-descriptions-item label="latencyMs">{{ testResult.latencyMs }}</el-descriptions-item>
        <el-descriptions-item label="checkedAt">{{ testResult.checkedAt }}</el-descriptions-item>
      </el-descriptions>
    </el-card>
  </div>
</template>

<script>
import { createRemoteControlApi } from "./remoteControlApi";

const POLL_INTERVAL_MS = 5000;

export default {
  name: "RemoteControl",
  data() {
    return {
      api: createRemoteControlApi(window.location.origin),
      loading: false,
      error: "",
      statusTimer: null,
      form: {
        gatewayId: "",
        controlServerUrl: "",
        authMode: "mtls",
        hmacSecret: "",
        heartbeatSec: 20,
        reconnectSec: 3,
        dryRunDefault: true,
      },
      status: {
        state: "disabled",
        lastError: "",
        lastHeartbeatAt: "",
        lastChangeAt: "",
      },
      testResult: {
        ok: false,
        code: "",
        message: "",
        latencyMs: 0,
        checkedAt: "",
      },
    };
  },
  computed: {
    statusTagType() {
      switch (this.status.state) {
        case "connected":
          return "success";
        case "connecting":
          return "primary";
        case "degraded":
          return "warning";
        case "disconnected":
        case "disabled":
        default:
          return "info";
      }
    },
  },
  async created() {
    await this.loadInitial();
    this.statusTimer = setInterval(this.refreshStatus, POLL_INTERVAL_MS);
  },
  beforeDestroy() {
    if (this.statusTimer) {
      clearInterval(this.statusTimer);
      this.statusTimer = null;
    }
  },
  methods: {
    validateForm() {
      if (!this.form.gatewayId || this.form.gatewayId.length < 3) {
        throw new Error("INVALID_REQUEST: gatewayId must be at least 3 chars");
      }
      if (!this.form.controlServerUrl.startsWith("wss://")) {
        throw new Error("INVALID_REQUEST: controlServerUrl must start with wss://");
      }
      if (this.form.authMode === "mtls_hmac" && !this.form.hmacSecret) {
        throw new Error("INVALID_REQUEST: hmacSecret is required for mtls_hmac");
      }
    },
    async runAction(action) {
      this.loading = true;
      this.error = "";
      try {
        await action();
      } catch (e) {
        this.error = e.message || String(e);
      } finally {
        this.loading = false;
      }
    },
    async loadInitial() {
      await this.runAction(async () => {
        const [profile, status] = await Promise.all([
          this.api.getConnection(),
          this.api.getStatus(),
        ]);
        this.form.gatewayId = profile.gatewayId;
        this.form.controlServerUrl = profile.controlServerUrl;
        this.form.authMode = profile.authMode;
        this.form.heartbeatSec = profile.heartbeatSec;
        this.form.reconnectSec = profile.reconnectSec;
        this.form.dryRunDefault = profile.dryRunDefault;
        this.status = status;
      });
    },
    async refreshStatus() {
      try {
        this.status = await this.api.getStatus();
      } catch (e) {
        this.error = e.message || String(e);
      }
    },
    async onSave() {
      await this.runAction(async () => {
        this.validateForm();
        await this.api.saveConnection(this.form);
        this.$message.success("Saved");
      });
    },
    async onTest() {
      await this.runAction(async () => {
        this.validateForm();
        this.testResult = await this.api.testConnection(this.form);
        if (this.testResult.ok) {
          this.$message.success("Connection OK");
        } else {
          this.$message.warning(this.testResult.message);
        }
      });
    },
    async onConnect() {
      await this.runAction(async () => {
        const result = await this.api.connect();
        await this.refreshStatus();
        this.$message.success(result.message || "Connected");
      });
    },
    async onDisconnect() {
      await this.runAction(async () => {
        const result = await this.api.disconnect();
        await this.refreshStatus();
        this.$message.success(result.message || "Disconnected");
      });
    },
  },
};
</script>

<style scoped>
.remote-control-page {
  padding: 12px;
}
</style>
