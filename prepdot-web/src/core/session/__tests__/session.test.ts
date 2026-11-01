import { describe, expect, it } from 'vitest'
import type { Clock, HttpTransport, RawResponse, StoragePort } from '@/adapters/types'
import type { AuthUser } from '@/core/api/types'
import { AuthSession } from '../session'

const NOW = 1_700_000_000_000
const DAY_SECONDS = 86400

function jwt(expSeconds: number): string {
  const enc = (v: object) => btoa(JSON.stringify(v)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  return `${enc({ alg: 'HS256' })}.${enc({ exp: expSeconds })}.sig`
}

function expiringIn(days: number): string {
  return jwt(Math.floor(NOW / 1000) + days * DAY_SECONDS)
}

function user(token: string, nickname = '小明'): AuthUser {
  return { token, userId: 1, username: 'u', nickname, avatarColor: '#fff', studyTarget: 20 }
}

function memoryStorage(initial: Record<string, string> = {}): StoragePort & { data: Record<string, string> } {
  const data: Record<string, string> = { ...initial }
  return {
    data,
    get: async key => data[key] ?? null,
    set: async (key, value) => { data[key] = value },
    remove: async key => { delete data[key] }
  }
}

function clockAt(now: number): Clock {
  return { now: () => now }
}

function httpUnavailable(): HttpTransport {
  return {
    json: async () => { throw new TypeError('Failed to fetch') },
    multipart: async () => { throw new TypeError('Failed to fetch') },
    streamText: async function* () {
      yield* [] as string[]
      throw new TypeError('Failed to fetch')
    }
  }
}

function httpResponding(response: RawResponse<AuthUser>): HttpTransport {
  return {
    json: async <T,>() => response as unknown as RawResponse<T>,
    multipart: async <T,>() => response as unknown as RawResponse<T>,
    streamText: async function* () {
      yield* [] as string[]
    }
  }
}

/** 返回一个挂起的 refresh 请求，允许测试控制响应时机。 */
function deferredHttp() {
  let resolveResponse: (value: RawResponse<AuthUser>) => void = () => {}
  let calls = 0
  const http: HttpTransport = {
    json: <T,>() => {
      calls += 1
      return new Promise<RawResponse<T>>(resolve => {
        resolveResponse = value => resolve(value as unknown as RawResponse<T>)
      })
    },
    multipart: <T,>() => Promise.reject(new Error('unexpected multipart')) as Promise<RawResponse<T>>,
    streamText: async function* () {
      yield* [] as string[]
    }
  }
  return { http, resolve: (value: RawResponse<AuthUser>) => resolveResponse(value), calls: () => calls }
}

function storedSession(token: string, nickname?: string) {
  return {
    'prepdot.token': token,
    'prepdot.user': JSON.stringify(user(token, nickname))
  }
}

describe('AuthSession.restore', () => {
  it('keeps the session when refresh fails with a network error while the token is still valid', async () => {
    const token = expiringIn(1)
    const cached = user(token)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))

    await expect(session.restore()).resolves.toEqual(cached)
    expect(session.isAuthenticated).toBe(true)
    expect(storage.data['prepdot.token']).toBe(token)
  })

  it('logs out when the refresh is rejected with 401', async () => {
    const token = expiringIn(1)
    const storage = memoryStorage(storedSession(token))
    const http = httpResponding({ status: 401, body: { code: 401, message: 'expired', data: null } })
    const session = new AuthSession(storage, http, clockAt(NOW))

    await expect(session.restore()).resolves.toBeNull()
    expect(session.isAuthenticated).toBe(false)
    expect(storage.data['prepdot.token']).toBeUndefined()
  })

  it('logs out when the token is already expired even if the network fails', async () => {
    const token = expiringIn(-1)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))

    await expect(session.restore()).resolves.toBeNull()
    expect(session.isAuthenticated).toBe(false)
    expect(storage.data['prepdot.token']).toBeUndefined()
  })

  it('keeps the token but reports no session when the user cache is missing', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage({ 'prepdot.token': token })
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))

    await expect(session.restore()).resolves.toBeNull()
    expect(session.currentUser).toBeNull()
    expect(session.isAuthenticated).toBe(false)
    expect(storage.data['prepdot.token']).toBe(token)
  })

  it('keeps the token but reports no session when the user cache is corrupt', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage({ 'prepdot.token': token, 'prepdot.user': '{not json' })
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))

    await expect(session.restore()).resolves.toBeNull()
    expect(session.currentUser).toBeNull()
    expect(session.isAuthenticated).toBe(false)
    expect(storage.data['prepdot.token']).toBe(token)
  })

  it('does not keep a stale cached user when no token is stored', async () => {
    const storage = memoryStorage({ 'prepdot.user': JSON.stringify(user('stale')) })
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))

    await expect(session.restore()).resolves.toBeNull()
    expect(session.currentUser).toBeNull()
    expect(session.isAuthenticated).toBe(false)
  })
})

describe('AuthSession.refresh', () => {
  it('dedupes concurrent refreshes into a single request', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const deferred = deferredHttp()
    const session = new AuthSession(storage, deferred.http, clockAt(NOW))
    await session.restore() // 10 天有效期，不触发续期

    const first = session.refresh()
    const second = session.refresh()
    expect(deferred.calls()).toBe(1)

    const refreshed = user(expiringIn(20), '新昵称')
    deferred.resolve({ status: 200, body: { code: 200, message: 'ok', data: refreshed } })
    await Promise.all([first, second])
    expect(session.currentUser).toEqual(refreshed)
    expect(deferred.calls()).toBe(1)
  })

  it('discards a refresh response that arrives after logout', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const deferred = deferredHttp()
    const session = new AuthSession(storage, deferred.http, clockAt(NOW))
    await session.restore()

    const pending = session.refresh()
    await session.logout()
    deferred.resolve({ status: 200, body: { code: 200, message: 'ok', data: user(token, '旧昵称') } })
    await pending

    expect(session.isAuthenticated).toBe(false)
    expect(session.currentUser).toBeNull()
    expect(storage.data['prepdot.token']).toBeUndefined()
  })
})

describe('AuthSession.onUnauthorized', () => {
  it('clears the session and stored credentials', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))
    await session.restore()
    expect(session.isAuthenticated).toBe(true)

    await session.onUnauthorized()

    expect(session.isAuthenticated).toBe(false)
    expect(session.currentUser).toBeNull()
    expect(storage.data['prepdot.token']).toBeUndefined()
    expect(storage.data['prepdot.user']).toBeUndefined()
  })

  it('invokes unauthorized listeners after the session is cleared', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))
    await session.restore()

    const observed: boolean[] = []
    session.onUnauthorizedChange(() => {
      observed.push(session.isAuthenticated)
    })

    await session.onUnauthorized()

    expect(observed).toEqual([false])
  })

  it('stops invoking a listener after it unsubscribes', async () => {
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))
    await session.restore()

    let calls = 0
    const unsubscribe = session.onUnauthorizedChange(() => {
      calls += 1
    })
    unsubscribe()

    await session.onUnauthorized()

    expect(calls).toBe(0)
  })

  it('does not invoke listeners on manual logout', async () => {
    // 手动登出由 auth store 自己清空用户；监听器只服务于 401 这类被动登出。
    const token = expiringIn(10)
    const storage = memoryStorage(storedSession(token))
    const session = new AuthSession(storage, httpUnavailable(), clockAt(NOW))
    await session.restore()

    let calls = 0
    session.onUnauthorizedChange(() => {
      calls += 1
    })

    await session.logout()

    expect(calls).toBe(0)
  })
})
