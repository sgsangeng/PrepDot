import { describe, expect, it, vi } from 'vitest'
import type { AppAdapters } from '@/adapters/types'
import { resumeDailyReminder } from '../resume'

type Permission = 'granted' | 'denied' | 'default'

function makeAdapters(options: {
  raw?: string | null
  permission?: Permission | Error
  storageError?: boolean
} = {}) {
  const get = vi.fn(async (): Promise<string | null> => {
    if (options.storageError) throw new Error('storage unavailable')
    return options.raw ?? null
  })
  // 参数由 toHaveBeenCalledWith 断言，实现本身无需读取。
  const scheduleDaily = vi.fn(async () => {})
  const permission = vi.fn(async (): Promise<Permission> => {
    if (options.permission instanceof Error) throw options.permission
    return options.permission ?? 'granted'
  })
  const adapters = {
    storage: { get, set: vi.fn(async () => {}), remove: vi.fn(async () => {}) },
    notification: {
      permission,
      requestPermission: vi.fn(async (): Promise<Permission> => 'granted'),
      scheduleDaily,
      cancelDaily: vi.fn(async () => {})
    },
    http: {},
    file: {},
    clipboard: {},
    clock: { now: () => 0 }
  } as unknown as AppAdapters
  return { adapters, scheduleDaily }
}

describe('resumeDailyReminder', () => {
  it('does nothing when the stored reminder is disabled', async () => {
    const { adapters, scheduleDaily } = makeAdapters({
      raw: JSON.stringify({ enabled: false, time: '08:00' })
    })
    await resumeDailyReminder(adapters, 30)
    expect(scheduleDaily).not.toHaveBeenCalled()
  })

  it('re-arms the daily timer with the stored time and target when permission is granted', async () => {
    const { adapters, scheduleDaily } = makeAdapters({
      raw: JSON.stringify({ enabled: true, time: '07:30' }),
      permission: 'granted'
    })
    await resumeDailyReminder(adapters, 35)
    expect(scheduleDaily).toHaveBeenCalledTimes(1)
    expect(scheduleDaily).toHaveBeenCalledWith('07:30', 35)
  })

  it('falls back to the default target when none is provided', async () => {
    const { adapters, scheduleDaily } = makeAdapters({
      raw: JSON.stringify({ enabled: true, time: '07:30' }),
      permission: 'granted'
    })
    await resumeDailyReminder(adapters)
    expect(scheduleDaily).toHaveBeenCalledWith('07:30', 20)
  })

  it('does not schedule when notification permission is denied', async () => {
    const { adapters, scheduleDaily } = makeAdapters({
      raw: JSON.stringify({ enabled: true, time: '07:30' }),
      permission: 'denied'
    })
    await expect(resumeDailyReminder(adapters, 20)).resolves.toBeUndefined()
    expect(scheduleDaily).not.toHaveBeenCalled()
  })

  it('swallows corrupt storage and storage failures', async () => {
    const corrupt = makeAdapters({ raw: '{not-json', permission: 'granted' })
    await expect(resumeDailyReminder(corrupt.adapters, 20)).resolves.toBeUndefined()
    expect(corrupt.scheduleDaily).not.toHaveBeenCalled()

    const failing = makeAdapters({ storageError: true, permission: 'granted' })
    await expect(resumeDailyReminder(failing.adapters, 20)).resolves.toBeUndefined()
    expect(failing.scheduleDaily).not.toHaveBeenCalled()
  })

  it('swallows notification adapter failures', async () => {
    const { adapters, scheduleDaily } = makeAdapters({ permission: new Error('not supported') })
    await expect(resumeDailyReminder(adapters, 20)).resolves.toBeUndefined()
    expect(scheduleDaily).not.toHaveBeenCalled()
  })
})
