<template>
  <div class="status-bar">
    <el-divider content-position="left">{{ $t('common.systemStatus') }}</el-divider>
    <template v-if="status">
      <div :class="[status.comm === 'UP' ? 'green' : 'red', 'status-item']">
        <i class="iconfont iconcomm-down1"></i>
        {{ $t('common.comm') }} {{ status.comm || '' }}
      </div>
      <div class="mach status-item">
        <i class="iconfont iconmanu"></i>
        {{ status.mach || '' }}
      </div>
      <div :class="[status.mode === 'ACTIVE' ? 'green' : status.mach === 'STANDBY' ? 'yellow' : 'red', 'status-item']">
        <i class="iconfont iconstanndby"></i>
        {{ status.mode || '' }}
      </div>
      <div :class="[status.mqcn === 'MQDISCONNECT' ? 'red' : 'green', 'status-item']">
        <i class="iconfont iconmqdisconnect"></i>
        {{ status.mqcn || $t('common.mqDisconnected') }}
      </div>
      <div :class="[galm === $t('common.noAlarm') ? 'green' : 'red', 'status-item']">
        <i class="iconfont iconalarm"></i>
        {{ galm }}
      </div>
    </template>
  </div>
</template>

<script lang="ts">
import { computed, defineComponent } from 'vue'
import { ElDivider } from 'element-plus'
import { useStore } from 'vuex'
import { useI18n } from 'vue-i18n'

export default defineComponent({
  name: 'StatusBar',
  components: {
    ElDivider,
  },
  setup() {
    const store = useStore()
    const { t } = useI18n()
    const status = computed(() => {
      return store.state.status
    })
    const galm = computed(() => {
      let res = ''
      switch (status.value.galm) {
        case 'NON-EXIST':
          res = 'common.noAlarm'
          break
        case 'UNACKNOWLEDGE':
          res = 'common.unackAlarm'
          break
        case 'EXIST':
          res = 'common.alarm'
          break
      }
      return res ? t(res) : ''
    })
    return {
      status,
      galm,
    }
  },
})
</script>

<style lang="scss">
.status-bar {
  font-size: 14px;
  font-weight: 500;
  padding: 0 40px 0 15px;
  .mach {
    color: var(--color-grey-font);
  }
  .red {
    color: var(--main-red-color);
  }
  .green {
    color: var(--main-green-color);
  }
  .yellow {
    color: var(--main-yellow-color);
  }
  .status-item {
    margin-bottom: 20px;
    display: flex;
    align-items: center;
    i {
      margin-right: 12px;
      font-size: 20px;
    }
    &:last-child {
      margin-bottom: 0px;
    }
  }
  .el-divider--horizontal {
    margin: 60px 0 40px 0;
  }
  .el-divider__text.is-left {
    left: -16px;
  }
}
</style>
