import type { AppAdapters } from '@/adapters/types'

/**
 * 每日提醒的本地设置与应用启动时的恢复逻辑。
 *
 * 提醒是浏览器级设置（对应 iOS 的全局 UserDefaults），因此被放在独立模块里，
 * 由 `App.vue` 在启动时调用一次；不能只依赖提醒设置页挂载时注册定时器——
 * 刷新页面或重启浏览器后，用户停留在其他页面时提醒也应继续工作。
 */

export const REMINDER_STORAGE_KEY = 'prepdot.reminder'
export const DEFAULT_REMINDER_TIME = '09:00'
export const DEFAULT_REMINDER_TARGET = 20

const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/

export interface ReminderSettings {
  enabled: boolean
  time: string
}

/** `HH:MM`（24 小时制）是否合法。 */
export function isValidReminderTime(value: string): boolean {
  return TIME_PATTERN.test(value)
}

/** 存储损坏、字段缺失或格式非法时回退到默认值，避免调用方崩溃。 */
export function parseReminderSettings(raw: string | null): ReminderSettings {
  if (!raw) return { enabled: false, time: DEFAULT_REMINDER_TIME }
  try {
    const parsed: unknown = JSON.parse(raw)
    if (typeof parsed !== 'object' || parsed === null) {
      return { enabled: false, time: DEFAULT_REMINDER_TIME }
    }
    const record = parsed as Record<string, unknown>
    return {
      enabled: typeof record.enabled === 'boolean' ? record.enabled : false,
      time: typeof record.time === 'string' && isValidReminderTime(record.time)
        ? record.time
        : DEFAULT_REMINDER_TIME
    }
  } catch {
    return { enabled: false, time: DEFAULT_REMINDER_TIME }
  }
}

/**
 * 应用启动时根据本地设置重建每日提醒定时器。
 *
 * 浏览器定时器不会跨页面生命周期存活，因此每次完整加载应用都需要重新注册；
 * 存储或通知能力不可用时静默跳过（提醒是增强功能，不能让启动失败）。
 */
export async function resumeDailyReminder(
  adapters: AppAdapters,
  target: number = DEFAULT_REMINDER_TARGET
): Promise<void> {
  try {
    const [raw, permission] = await Promise.all([
      adapters.storage.get(REMINDER_STORAGE_KEY),
      adapters.notification.permission()
    ])
    if (permission !== 'granted') return
    const settings = parseReminderSettings(raw)
    if (!settings.enabled) return
    await adapters.notification.scheduleDaily(settings.time, target)
  } catch {
    // 存储被禁用、浏览器不支持通知等场景：保持安静，不影响应用启动。
  }
}
