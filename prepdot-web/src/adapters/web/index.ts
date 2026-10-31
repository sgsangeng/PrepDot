import type { AppAdapters } from '@/adapters/types'
import { createStorage } from './storage'
import { createHttpTransport } from './http'
import { createFilePort } from './file'
import { createNotificationPort } from './notification'
import { createClipboardPort } from './clipboard'
import { createClock } from './clock'

export function createWebAdapters(): AppAdapters {
  return {
    storage: createStorage(),
    http: createHttpTransport(),
    file: createFilePort(),
    notification: createNotificationPort(),
    clipboard: createClipboardPort(),
    clock: createClock()
  }
}
