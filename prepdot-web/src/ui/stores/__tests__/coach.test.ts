import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import type { AppAdapters, Clock, HttpTransport, RawResponse, StoragePort } from '@/adapters/types'
import { createRuntime, setRuntime } from '@/runtime'
import { COACH_STORAGE_KEY, useCoachStore } from '../coach'

const NOW = 1_700_000_000_000

function memoryStorage(initial: Record<string, string> = {}) {
  const data = { ...initial }
  const port: StoragePort = {
    get: async key => data[key] ?? null,
    set: async (key, value) => { data[key] = value },
    remove: async key => { delete data[key] }
  }
  return { data, port }
}

function setup(storage: StoragePort, clock: Clock = { now: () => NOW }): void {
  const http: HttpTransport = {
    json: async <T,>(): Promise<RawResponse<T>> => { throw new Error('unexpected json') },
    multipart: async () => { throw new Error('unexpected multipart') },
    streamText: async function* () { yield* [] as string[] }
  }
  const adapters: AppAdapters = {
    storage,
    http,
    clock,
    file: { pick: async () => [] },
    notification: {
      permission: async () => 'granted',
      requestPermission: async () => 'granted',
      scheduleDaily: async () => {},
      cancelDaily: async () => {}
    },
    clipboard: { readText: async () => '' }
  }
  setRuntime(createRuntime(adapters))
}

describe('coach store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('starts a fresh session when stored data is corrupt and overwrites it', async () => {
    const storage = memoryStorage({ [COACH_STORAGE_KEY]: '{corrupt' })
    setup(storage.port)
    const store = useCoachStore()
    await store.load()

    expect(store.sessions).toHaveLength(1)
    expect(store.sessions[0].title).toBe('新会话')
    expect(store.currentId).toBe(store.sessions[0].id)
    expect(store.messages).toEqual([])

    const saved = JSON.parse(storage.data[COACH_STORAGE_KEY] as string) as unknown[]
    expect(saved).toHaveLength(1)
  })

  it('restores the most recently updated session', async () => {
    const storage = memoryStorage({
      [COACH_STORAGE_KEY]: JSON.stringify([
        { id: 'old', title: '旧会话', updatedAt: NOW - 10_000, messages: [] },
        { id: 'new', title: '新会话', updatedAt: NOW - 1_000, messages: [] }
      ])
    })
    setup(storage.port, { now: () => NOW })
    const store = useCoachStore()
    await store.load()

    expect(store.sessions).toHaveLength(2)
    expect(store.currentId).toBe('new')
    expect(store.orderedSessions.map(s => s.id)).toEqual(['new', 'old'])
  })

  it('persists messages and derives the title from the first user message', async () => {
    const storage = memoryStorage()
    let now = NOW
    setup(storage.port, { now: () => now })
    const store = useCoachStore()
    await store.load()
    const id = store.currentId

    await store.addMessage(id, {
      id: 'm1',
      role: 'user',
      text: '分析我最近掌握得最差的知识点，并给出建议'
    })
    expect(store.messages).toHaveLength(1)
    expect(store.sessions[0].title).toBe('分析我最近掌握得最差的知识点，并给出建议'.slice(0, 24))

    now += 60_000
    await store.addMessage(id, { id: 'm2', role: 'assistant', text: '好的' })

    const saved = JSON.parse(storage.data[COACH_STORAGE_KEY] as string) as {
      title: string
      updatedAt: number
      messages: unknown[]
    }[]
    expect(saved).toHaveLength(1)
    expect(saved[0].messages).toHaveLength(2)
    expect(saved[0].updatedAt).toBe(NOW + 60_000)
    expect(saved[0].title).toBe('分析我最近掌握得最差的知识点，并给出建议'.slice(0, 24))
  })

  it('creates, switches and deletes sessions', async () => {
    const storage = memoryStorage()
    let now = NOW
    setup(storage.port, { now: () => now })
    const store = useCoachStore()
    await store.load()
    const first = store.currentId

    now += 1_000
    const second = await store.newSession()
    expect(store.currentId).toBe(second)
    expect(store.sessions).toHaveLength(2)

    await store.switchSession(first)
    expect(store.currentId).toBe(first)

    await store.deleteSession(first)
    expect(store.sessions.map(s => s.id)).toEqual([second])
    expect(store.currentId).toBe(second)

    await store.deleteSession(second)
    expect(store.sessions).toHaveLength(1)
    expect(store.currentId).toBe(store.sessions[0].id)

    const saved = JSON.parse(storage.data[COACH_STORAGE_KEY] as string) as unknown[]
    expect(saved).toHaveLength(1)
  })

  it('keeps a reply attached to the captured session even if the current session changes', async () => {
    const storage = memoryStorage()
    let now = NOW
    setup(storage.port, { now: () => now })
    const store = useCoachStore()
    await store.load()
    const first = store.currentId

    now += 1_000
    const second = await store.newSession()
    await store.addMessage(first, { id: 'm1', role: 'assistant', text: '旧会话的回复' })

    expect(store.currentId).toBe(second)
    expect(store.messages).toEqual([])
    const firstSession = store.sessions.find(s => s.id === first)
    expect(firstSession?.messages).toHaveLength(1)
  })
})
