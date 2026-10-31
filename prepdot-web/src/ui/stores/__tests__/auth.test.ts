import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import type { AppAdapters, HttpTransport, RawResponse, StoragePort } from '@/adapters/types'
import type { AuthUser } from '@/core/api/types'
import { createRuntime, setRuntime } from '@/runtime'
import { useAuthStore } from '../auth'

const NOW = 1_700_000_000_000

const demoUser: AuthUser = {
  token: 'token',
  userId: 1,
  username: 'demo',
  nickname: '演示用户',
  avatarColor: '#4f46e5',
  studyTarget: 20
}

function memoryStorage(): StoragePort {
  const data: Record<string, string> = {}
  return {
    get: async key => data[key] ?? null,
    set: async (key, value) => { data[key] = value },
    remove: async key => { delete data[key] }
  }
}

function loginHttp(): HttpTransport {
  return {
    json: async <T,>(): Promise<RawResponse<T>> => ({
      status: 200,
      body: { code: 200, message: 'ok', data: demoUser as unknown as T }
    }),
    multipart: async () => {
      throw new Error('unexpected multipart')
    },
    streamText: async function* () {
      yield* [] as string[]
    }
  }
}

function adapters(): AppAdapters {
  return {
    storage: memoryStorage(),
    http: loginHttp(),
    clock: { now: () => NOW },
    file: { pick: async () => [] },
    notification: {
      permission: async () => 'granted',
      requestPermission: async () => 'granted',
      scheduleDaily: async () => {},
      cancelDaily: async () => {}
    },
    clipboard: { readText: async () => '' }
  }
}

describe('auth store unauthorized sync', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('clears the user when the session is logged out by a 401', async () => {
    const runtime = createRuntime(adapters())
    setRuntime(runtime)
    const auth = useAuthStore()

    await auth.login('demo', 'PrepDot2026')
    expect(auth.isAuthenticated).toBe(true)

    await runtime.session.onUnauthorized()

    expect(auth.user).toBeNull()
    expect(auth.isAuthenticated).toBe(false)
    expect(auth.ready).toBe(true)
  })
})
