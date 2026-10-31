<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, BellRing, TriangleAlert } from 'lucide-vue-next'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useAuthStore } from '@/ui/stores/auth'
import { useToastStore } from '@/ui/stores/toast'

const REMINDER_KEY = 'prepdot.reminder'
const DEFAULT_TIME = '09:00'
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/

interface ReminderSettings {
  enabled: boolean
  time: string
}

const router = useRouter()
const auth = useAuthStore()
const toast = useToastStore()

const enabled = ref(false)
const time = ref(DEFAULT_TIME)
const loading = ref(true)
const busy = ref(false)
const permissionDenied = ref(false)
const saveError = ref('')

let operationSeq = 0

/** 与 iOS 一致：目标缺失时按 20 张兜底。 */
const target = computed(() => {
  const value = auth.user?.studyTarget
  return typeof value === 'number' && value > 0 ? value : 20
})

/** 存储损坏、字段缺失或格式非法时回退到默认值，避免页面崩溃。 */
function parseSettings(raw: string | null): ReminderSettings {
  if (!raw) return { enabled: false, time: DEFAULT_TIME }
  try {
    const parsed: unknown = JSON.parse(raw)
    if (typeof parsed !== 'object' || parsed === null) return { enabled: false, time: DEFAULT_TIME }
    const record = parsed as Record<string, unknown>
    return {
      enabled: typeof record.enabled === 'boolean' ? record.enabled : false,
      time: typeof record.time === 'string' && TIME_PATTERN.test(record.time)
        ? record.time
        : DEFAULT_TIME
    }
  } catch {
    return { enabled: false, time: DEFAULT_TIME }
  }
}

async function persist(): Promise<void> {
  await getRuntime().adapters.storage.set(REMINDER_KEY, JSON.stringify({
    enabled: enabled.value,
    time: time.value
  }))
}

async function schedule(): Promise<void> {
  await getRuntime().adapters.notification.scheduleDaily(time.value, target.value)
}

onMounted(async () => {
  const runtime = getRuntime()
  try {
    const [raw, permission] = await Promise.all([
      runtime.adapters.storage.get(REMINDER_KEY),
      runtime.adapters.notification.permission()
    ])
    const settings = parseSettings(raw)
    time.value = settings.time

    if (!settings.enabled) {
      enabled.value = false
      // 不支持的浏览器 permission() 返回 denied，同样给出橙色提示。
      permissionDenied.value = permission === 'denied'
      return
    }

    // 定时器只存在于当前页面生命周期，重新打开应用后需要在权限仍可用时重建，
    // 否则存储显示「已开启」却收不到提醒。
    if (permission === 'granted') {
      enabled.value = true
      permissionDenied.value = false
      try {
        await schedule()
      } catch (e) {
        saveError.value = friendlyError(e)
      }
      return
    }

    // 权限被撤销或从未授予：保持关闭并持久化，避免界面与实际提醒状态不一致。
    enabled.value = false
    permissionDenied.value = permission === 'denied'
    await persist()
  } catch (e) {
    saveError.value = friendlyError(e)
  } finally {
    loading.value = false
  }
})

function onToggleClick(): void {
  void toggle(!enabled.value)
}

async function toggle(next: boolean): Promise<void> {
  if (busy.value || next === enabled.value) return
  saveError.value = ''
  const seq = ++operationSeq
  busy.value = true
  try {
    if (!next) {
      enabled.value = false
      await persist()
      if (seq !== operationSeq) return
      await getRuntime().adapters.notification.cancelDaily()
      if (seq !== operationSeq) return
      toast.show('每日提醒已关闭')
      return
    }

    const permission = await getRuntime().adapters.notification.requestPermission()
    if (seq !== operationSeq) return
    if (permission !== 'granted') {
      enabled.value = false
      permissionDenied.value = true
      await persist()
      return
    }

    permissionDenied.value = false
    enabled.value = true
    await persist()
    if (seq !== operationSeq) return
    await schedule()
    if (seq !== operationSeq) return
    toast.show('每日提醒已开启')
  } catch (e) {
    if (seq === operationSeq) saveError.value = friendlyError(e)
  } finally {
    if (seq === operationSeq) busy.value = false
  }
}

async function onTimeChange(): Promise<void> {
  if (busy.value) return
  saveError.value = ''
  // <input type="time"> 被清空时回退默认值，避免保存非法格式。
  if (!TIME_PATTERN.test(time.value)) time.value = DEFAULT_TIME

  busy.value = true
  try {
    await persist()
    if (!enabled.value) return
    await schedule()
    toast.show(`提醒时间已更新为 ${time.value}`)
  } catch (e) {
    saveError.value = friendlyError(e)
  } finally {
    busy.value = false
  }
}

function goBack(): void {
  const profileHref = router.resolve({ name: 'profile' }).href
  const back = (router.options.history.state as { back?: unknown }).back
  if (
    typeof back === 'string'
    && (back === profileHref || back.startsWith(`${profileHref}?`) || back.startsWith(`${profileHref}#`))
  ) {
    router.back()
    return
  }
  void router.push({ name: 'profile' })
}
</script>

<template>
  <section class="reminder-page">
    <header class="page-head">
      <button
        class="back-btn"
        type="button"
        @click="goBack"
      >
        <ArrowLeft
          :size="18"
          aria-hidden="true"
        />
        我的
      </button>
      <h1 class="head-title">
        每日提醒
      </h1>
    </header>

    <div class="settings-card">
      <div class="switch-row">
        <span class="switch-copy">
          <span
            id="reminder-toggle-label"
            class="switch-title"
          >开启每日复习提醒</span>
          <span class="switch-desc">每天在指定时间收到一条提醒，帮你养成复习习惯</span>
        </span>
        <button
          class="switch"
          type="button"
          role="switch"
          :aria-checked="enabled"
          aria-labelledby="reminder-toggle-label"
          :disabled="busy || loading"
          @click="onToggleClick"
        >
          <span
            class="switch-track"
            aria-hidden="true"
          >
            <span class="switch-thumb" />
          </span>
        </button>
      </div>

      <div
        v-if="enabled"
        class="time-row"
      >
        <label
          class="label"
          for="reminder-time"
        >提醒时间</label>
        <input
          id="reminder-time"
          v-model="time"
          class="input time-input"
          type="time"
          :disabled="busy"
          @change="onTimeChange"
        >
      </div>
    </div>

    <p
      v-if="permissionDenied"
      class="hint hint-warning"
      role="status"
    >
      <TriangleAlert
        :size="16"
        aria-hidden="true"
      />
      通知权限被拒绝。请在浏览器地址栏左侧的网站设置中允许通知，然后重新开启提醒。
    </p>

    <p
      v-if="saveError"
      class="hint hint-error"
      role="alert"
    >
      {{ saveError }}
    </p>

    <div class="note">
      <BellRing
        :size="18"
        aria-hidden="true"
      />
      <div>
        <p class="note-title">
          浏览器提醒限制
        </p>
        <p class="note-text">
          提醒依赖浏览器通知能力：页面需要保持打开（前台标签页）才能按时提醒，关闭浏览器或标签页后可能无法收到。
          更可靠的提醒将在后续版本通过 Service Worker 提供。
        </p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.reminder-page {
  display: flex;
  flex-direction: column;
  gap: 14px;
  width: min(100%, 720px);
  min-width: 0;
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.page-head {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 44px;
}

.back-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-height: 44px;
  padding: 0 8px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
}

.back-btn:hover {
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.head-title {
  display: none;
  font-size: 20px;
  font-weight: 800;
}

.settings-card {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.switch-row {
  display: flex;
  align-items: center;
  gap: 14px;
  min-height: 64px;
  padding: 10px 16px;
}

.switch-copy {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}

.switch-title {
  font-size: 15px;
  font-weight: 600;
}

.switch-desc {
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.5;
}

.switch {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 52px;
  height: 44px;
  padding: 0;
  border: 0;
  border-radius: 999px;
  background: transparent;
}

.switch-track {
  position: relative;
  display: block;
  width: 52px;
  height: 32px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--surface-muted);
  transition: background 0.2s ease, border-color 0.2s ease;
}

.switch-thumb {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: var(--surface);
  box-shadow: var(--shadow-sm);
  transition: transform 0.2s ease, background 0.2s ease;
}

.switch[aria-checked="true"] .switch-track {
  border-color: var(--color-indigo);
  background: var(--color-indigo);
}

.switch[aria-checked="true"] .switch-thumb {
  background: var(--on-primary);
  transform: translateX(20px);
}

.switch:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

.switch:disabled {
  cursor: not-allowed;
  opacity: 0.5;
}

.time-row {
  padding: 4px 16px 16px;
  border-top: 1px solid var(--border);
}

.time-row .label {
  margin-top: 12px;
}

.time-input {
  width: min(100%, 220px);
}

.hint {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 12px 14px;
  border-radius: var(--radius-sm);
  font-size: 13px;
  line-height: 1.6;
}

.hint svg {
  flex: none;
  margin-top: 2px;
}

.hint-warning {
  border: 1px solid color-mix(in srgb, var(--color-orange) 35%, transparent);
  background: color-mix(in srgb, var(--color-orange) 12%, var(--surface));
  color: var(--color-orange);
}

.hint-error {
  border: 1px solid color-mix(in srgb, var(--color-red) 35%, transparent);
  background: color-mix(in srgb, var(--color-red) 10%, var(--surface));
  color: var(--color-red);
}

.note {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface-soft);
  color: var(--text-secondary);
}

.note svg {
  flex: none;
  margin-top: 1px;
  color: var(--color-indigo);
}

.note-title {
  margin-bottom: 4px;
  color: var(--text);
  font-size: 13px;
  font-weight: 700;
}

.note-text {
  font-size: 12px;
  line-height: 1.7;
}

.back-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .reminder-page {
    padding: 24px 16px 48px;
  }

  .back-btn {
    display: none;
  }

  .head-title {
    display: block;
  }
}
</style>
