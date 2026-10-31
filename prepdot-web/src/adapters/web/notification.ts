import type { NotificationPort } from '@/adapters/types'

type Permission = 'granted' | 'denied' | 'default'

let timer: ReturnType<typeof setTimeout> | null = null

function isSupported(): boolean {
  return typeof Notification !== 'undefined'
}

function nextDelay(time: string): number | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(time)
  if (!match) return null
  const hours = Number(match[1])
  const minutes = Number(match[2])
  if (hours > 23 || minutes > 59) return null
  const now = new Date()
  const next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hours, minutes, 0, 0)
  if (next.getTime() <= now.getTime()) {
    next.setDate(next.getDate() + 1)
  }
  return next.getTime() - now.getTime()
}

function showReminder(target: number): void {
  if (!isSupported() || Notification.permission !== 'granted') return
  new Notification('序岛 PrepDot', {
    body: `今天的复习目标是 ${target} 张卡片，来打卡吧！`,
    tag: 'prepdot-daily-reminder'
  })
}

function scheduleNext(time: string, target: number): void {
  const delay = nextDelay(time)
  if (delay === null) return
  timer = setTimeout(() => {
    timer = null
    showReminder(target)
    scheduleNext(time, target)
  }, delay)
}

function clearTimer(): void {
  if (timer !== null) {
    clearTimeout(timer)
    timer = null
  }
}

export function createNotificationPort(): NotificationPort {
  return {
    async permission(): Promise<Permission> {
      return isSupported() ? Notification.permission : 'denied'
    },
    async requestPermission(): Promise<Permission> {
      if (!isSupported()) return 'denied'
      return Notification.requestPermission()
    },
    async scheduleDaily(time: string, target: number): Promise<void> {
      clearTimer()
      scheduleNext(time, target)
    },
    async cancelDaily(): Promise<void> {
      clearTimer()
    }
  }
}
