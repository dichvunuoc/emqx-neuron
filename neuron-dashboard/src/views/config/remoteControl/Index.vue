<template>
  <emqx-card class="remote-control" v-emqx-loading="loading">
    <ViewHeaderBar>
      <template #left>
        <span class="header-title">{{ $t('config.remoteControl') }}</span>
      </template>
    </ViewHeaderBar>

    <el-alert v-if="lastError" :title="lastError" type="error" :closable="false" show-icon class="mb12" />

    <emqx-form label-position="left" label-width="220px" class="remote-form">
      <emqx-form-item :label="$t('config.runtimeStatus')">
        <emqx-tag :type="statusTagType">{{ status.state || 'unknown' }}</emqx-tag>
        <span class="status-meta" v-if="status.lastHeartbeatAt">
          {{ $t('config.lastHeartbeatAt') }}: {{ status.lastHeartbeatAt }}
        </span>
      </emqx-form-item>

      <emqx-form-item :label="$t('config.gatewayId')">
        <emqx-input v-model="form.gatewayId" />
      </emqx-form-item>

      <emqx-form-item :label="$t('config.controlServerUrl')">
        <emqx-input v-model="form.controlServerUrl" placeholder="wss://control.example.com/reverse-channel" />
      </emqx-form-item>

      <emqx-form-item :label="$t('config.authMode')">
        <emqx-select v-model="form.authMode" style="width: 100%">
          <emqx-option label="mTLS" value="mtls" />
          <emqx-option label="mTLS + HMAC" value="mtls_hmac" />
        </emqx-select>
      </emqx-form-item>

      <emqx-form-item v-if="form.authMode === 'mtls_hmac'" :label="$t('config.hmacSecret')">
        <emqx-input v-model="form.hmacSecret" show-password />
      </emqx-form-item>

      <emqx-form-item :label="$t('config.heartbeatSec')">
        <emqx-input-number v-model="form.heartbeatSec" :min="5" :max="120" />
      </emqx-form-item>

      <emqx-form-item :label="$t('config.reconnectSec')">
        <emqx-input-number v-model="form.reconnectSec" :min="1" :max="60" />
      </emqx-form-item>

      <emqx-form-item :label="$t('config.dryRunDefault')">
        <emqx-switch v-model="form.dryRunDefault" />
      </emqx-form-item>

      <emqx-form-item>
        <emqx-button type="primary" size="small" @click="onSave">{{ $t('common.save') }}</emqx-button>
        <emqx-button size="small" @click="onTest">{{ $t('config.testConnection') }}</emqx-button>
        <emqx-button type="success" size="small" @click="onConnect">{{ $t('config.connectAction') }}</emqx-button>
        <emqx-button type="warning" size="small" @click="onDisconnect">{{ $t('config.disconnectAction') }}</emqx-button>
      </emqx-form-item>
    </emqx-form>

    <emqx-descriptions v-if="testResult.checkedAt" :title="$t('config.lastTestResult')" :column="1" border>
      <emqx-descriptions-item label="ok">{{ testResult.ok }}</emqx-descriptions-item>
      <emqx-descriptions-item label="code">{{ testResult.code }}</emqx-descriptions-item>
      <emqx-descriptions-item :label="$t('common.message')">{{ testResult.message }}</emqx-descriptions-item>
      <emqx-descriptions-item label="latencyMs">{{ testResult.latencyMs }}</emqx-descriptions-item>
      <emqx-descriptions-item label="checkedAt">{{ testResult.checkedAt }}</emqx-descriptions-item>
    </emqx-descriptions>
  </emqx-card>
</template>

<script lang="ts" setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { EmqxMessage } from '@emqx/emqx-ui'
import ViewHeaderBar from '@/components/ViewHeaderBar.vue'
import {
  connectRemoteConnection,
  disconnectRemoteConnection,
  getRemoteConnection,
  getRemoteConnectionStatus,
  saveRemoteConnection,
  testRemoteConnection,
} from '@/api/remoteControl'
import type { ConnectionProfileSaveRequest, ConnectionRuntimeStatus, ConnectionTestResult } from '@/api/remoteControl'

const POLL_INTERVAL_MS = 5000

const loading = ref(false)
const lastError = ref('')
let timer: number | undefined

const form = reactive<ConnectionProfileSaveRequest>({
  gatewayId: '',
  controlServerUrl: '',
  authMode: 'mtls',
  hmacSecret: '',
  heartbeatSec: 20,
  reconnectSec: 3,
  dryRunDefault: true,
})

const status = reactive<ConnectionRuntimeStatus>({
  state: 'disabled',
  lastError: '',
  lastHeartbeatAt: '',
  lastChangeAt: '',
})

const testResult = reactive<ConnectionTestResult>({
  ok: false,
  code: 'INVALID_CONFIG',
  message: '',
  latencyMs: 0,
  checkedAt: '',
})

const statusTagType = computed(() => {
  switch (status.state) {
    case 'connected':
      return 'success'
    case 'connecting':
      return 'primary'
    case 'degraded':
      return 'warning'
    case 'disconnected':
    case 'disabled':
    default:
      return 'info'
  }
})

const validateForm = () => {
  if (!form.gatewayId || form.gatewayId.length < 3) {
    throw new Error('gatewayId must be at least 3 chars')
  }
  if (!form.controlServerUrl || !form.controlServerUrl.startsWith('wss://')) {
    throw new Error('controlServerUrl must start with wss://')
  }
  if (form.authMode === 'mtls_hmac' && !form.hmacSecret) {
    throw new Error('hmacSecret is required for mtls_hmac')
  }
}

const withLoading = async (handler: () => Promise<void>) => {
  loading.value = true
  lastError.value = ''
  try {
    await handler()
  } catch (error: any) {
    lastError.value = error?.message || String(error)
  } finally {
    loading.value = false
  }
}

const syncStatus = async () => {
  const data = await getRemoteConnectionStatus()
  status.state = data.state
  status.lastError = data.lastError || ''
  status.lastHeartbeatAt = data.lastHeartbeatAt || ''
  status.lastChangeAt = data.lastChangeAt
}

const loadInitial = async () => {
  await withLoading(async () => {
    const [profile] = await Promise.all([getRemoteConnection(), syncStatus()])
    form.gatewayId = profile.gatewayId
    form.controlServerUrl = profile.controlServerUrl
    form.authMode = profile.authMode
    form.heartbeatSec = profile.heartbeatSec
    form.reconnectSec = profile.reconnectSec
    form.dryRunDefault = profile.dryRunDefault
  })
}

const onSave = async () => {
  await withLoading(async () => {
    validateForm()
    await saveRemoteConnection(form)
    EmqxMessage.success('Saved')
  })
}

const onTest = async () => {
  await withLoading(async () => {
    validateForm()
    const result = await testRemoteConnection(form)
    testResult.ok = result.ok
    testResult.code = result.code
    testResult.message = result.message
    testResult.latencyMs = result.latencyMs || 0
    testResult.checkedAt = result.checkedAt
    if (result.ok) {
      EmqxMessage.success('Connection OK')
    } else {
      EmqxMessage.warning(result.message)
    }
  })
}

const onConnect = async () => {
  await withLoading(async () => {
    const result = await connectRemoteConnection()
    EmqxMessage.success(result?.message || 'Connected')
    await syncStatus()
  })
}

const onDisconnect = async () => {
  await withLoading(async () => {
    const result = await disconnectRemoteConnection()
    EmqxMessage.success(result?.message || 'Disconnected')
    await syncStatus()
  })
}

onMounted(async () => {
  await loadInitial()
  timer = window.setInterval(() => {
    syncStatus().catch(() => undefined)
  }, POLL_INTERVAL_MS)
})

onBeforeUnmount(() => {
  if (timer) {
    window.clearInterval(timer)
    timer = undefined
  }
})
</script>

<style lang="scss" scoped>
.remote-control {
  .header-title {
    font-weight: 600;
  }

  .mb12 {
    margin-bottom: 12px;
  }

  .status-meta {
    margin-left: 10px;
    color: var(--color-text-secondary);
  }

  .remote-form {
    max-width: 720px;
  }
}
</style>
