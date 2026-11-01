import { beforeEach, describe, expect, it } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import type { AppAdapters, Clock, HttpTransport, RawResponse, StoragePort } from '@/adapters/types'
import { createRuntime, setRuntime } from '@/runtime'
import { coachStorageKey, useCoachStore } from '../coach'

const NOW = 1_700_000_000_000
const ANON_KEY = coachStorageKey(null)

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
    const storage = memoryStorage({ [ANON_KEY]: '{corrupt' })
    setup(storage.port)
    const store = useCoachStore()
    await store.load()

    expect(store.sessions).toHaveLength(1)
    expect(store.sessions[0].title).toBe('新会话')
    expect(store.currentId).toBe(store.sessions[0].id)
    expect(store.messages).toEqual([])

    const saved = JSON.parse(storage.data[ANON_KEY] as string) as unknown[]
    expect(saved).toHaveLength(1)
  })

  it('restores the most recently updated session', async () => {
    const storage = memoryStorage({
      [ANON_KEY]: JSON.stringify([
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

    const saved = JSON.parse(storage.data[ANON_KEY] as string) as {
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

    const saved = JSON.parse(storage.data[ANON_KEY] as string) as unknown[]
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

  it('keeps an in-flight run observable across page remounts and clears it when settled', async () => {
    const storage = memoryStorage()
    setup(storage.port)
    const store = useCoachStore()
    await store.load()
    const id = store.currentId

    store.beginRun(id)
    expect(store.thinking).toBe(true)
    expect(store.progress).toBe('正在连接学习教练…')
    expect(store.pendingSessionId).toBe(id)

    store.setProgress('正在执行工具：复习趋势统计')
    expect(store.progress).toBe('正在执行工具：复习趋势统计')

    // 路由切换不会重建 Pinia：重新挂载的页面立即看到同一段进行中状态。
    await store.load()
    const remounted = useCoachStore()
    expect(remounted.thinking).toBe(true)
    expect(remounted.progress).toBe('正在执行工具：复习趋势统计')
    expect(remounted.pendingSessionId).toBe(id)

    // 成功与失败都会在 finally 中调用 finishRun。
    remounted.finishRun()
    expect(remounted.thinking).toBe(false)
    expect(remounted.progress).toBe('')
    expect(remounted.pendingSessionId).toBe('')

    // 结束后迟到的进度事件不会重新点亮进度行。
    remounted.setProgress('迟到的进度')
    expect(remounted.thinking).toBe(false)
    expect(remounted.progress).toBe('')
  })

  it('isolates persisted sessions per user across account switches', async () => {
    const storage = memoryStorage()
    setup(storage.port)
    const store = useCoachStore()

    store.setActiveUser(1)
    await store.load()
    await store.addMessage(store.currentId, {
      id: 'a1',
      role: 'user',
      text: 'A 的私密问题'
    })
    expect(store.messages).toHaveLength(1)
    expect(storage.data[coachStorageKey(1)]).toContain('A 的私密问题')

    store.setActiveUser(2)
    // 切换账号立即清空内存态，B 不会看到 A 的会话。
    expect(store.sessions).toEqual([])
    expect(store.currentId).toBe('')
    expect(store.loaded).toBe(false)
    expect(store.thinking).toBe(false)

    await store.load()
    expect(store.sessions).toHaveLength(1)
    expect(store.sessions[0].messages).toEqual([])
    // B 的存储键下没有任何 A 的内容。
    expect(storage.data[coachStorageKey(2)] ?? '').not.toContain('A 的私密问题')

    // A 的历史仍保留在自己的命名空间下，切回 A 可以继续使用。
    store.setActiveUser(1)
    await store.load()
    expect(store.sessions.some(s => s.messages.some(m => m.text === 'A 的私密问题'))).toBe(true)
  })

  it('ignores an in-flight reply that arrives after the account switched', async () => {
    const storage = memoryStorage()
    setup(storage.port)
    const store = useCoachStore()

    store.setActiveUser(1)
    await store.load()
    const aSession = store.currentId
    await store.addMessage(aSession, { id: 'a1', role: 'user', text: 'A 的问题' })
    const aToken = store.beginRun(aSession)

    store.setActiveUser(2)
    await store.load()
    const bToken = store.beginRun(store.currentId)

    // A 的请求此时才返回；回复不能写进 B 的会话或存储。
    await store.addMessage(aSession, { id: 'late', role: 'assistant', text: '旧账号的迟到回复' })
    store.setProgress('A 的迟到进度', aToken)
    store.finishRun(aToken)

    expect(store.sessions.some(s => s.messages.some(m => m.text === '旧账号的迟到回复'))).toBe(false)
    expect(storage.data[coachStorageKey(2)] ?? '').not.toContain('旧账号的迟到回复')
    // 旧请求的收尾不能清掉 B 的进行中状态。
    expect(store.thinking).toBe(true)
    expect(store.progress).toBe('正在连接学习教练…')

    store.setProgress('B 的进度', bToken)
    expect(store.progress).toBe('B 的进度')
    store.finishRun(bToken)
    expect(store.thinking).toBe(false)
  })
})
