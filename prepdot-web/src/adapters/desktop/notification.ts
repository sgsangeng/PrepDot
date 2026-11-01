import type { NotificationPort } from '@/adapters/types'

const UNIMPLEMENTED = 'desktop adapter 将在 Phase 2 实现'

export function createNotificationPort(): NotificationPort {
  return {
    async permission() {
      throw new Error(UNIMPLEMENTED)
    },
    async requestPermission() {
      throw new Error(UNIMPLEMENTED)
    },
    async scheduleDaily() {
      throw new Error(UNIMPLEMENTED)
    },
    async cancelDaily(): Promise<void> {
      throw new Error(UNIMPLEMENTED)
    }
  }
}
