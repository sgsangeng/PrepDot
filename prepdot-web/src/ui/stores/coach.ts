import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { CoachMessage, CoachSession } from '@/core/coach/sessions'
import {
  makeMessageId,
  makeSessionId,
  parseStoredSessions,
  sessionTitle,
  upsertSession
} from '@/core/coach/sessions'
import { getRuntime } from '@/runtime'

/** iOS 使用 `learning_coach_sessions_v1`；Web 端沿用带应用前缀的键名。 */
export const COACH_STORAGE_KEY = 'prepdot.coach.sessions.v1'

/**
 * 会话按用户隔离。旧的全局键 `prepdot.coach.sessions.v1` 不再读取：
 * 它没有归属信息，若迁移给「第一个登录的用户」会把 A 的历史泄露给 B。
 */
export function coachStorageKey(userId: number | null): string {
  return userId == null ? `${COACH_STORAGE_KEY}.anonymous` : `${COACH_STORAGE_KEY}.${userId}`
}

const FRESH_TITLE = '新会话'

export const useCoachStore = defineStore('coach', () => {
  const sessions = ref<CoachSession[]>([])
  const currentId = ref('')
  const loaded = ref(false)
  /**
   * 进行中的请求状态放在 store 而不是页面里：页面切换（无 KeepAlive）会卸载
   * CoachPage，但 store 是单例，重新挂载后仍能立即看到进行中的请求并维持禁用态。
   * 仅存活于当前应用会话，刷新页面后重置（无需持久化）。
   */
  const thinking = ref(false)
  const progress = ref('')
  const pendingSessionId = ref('')

  const orderedSessions = computed(() =>
    [...sessions.value].sort((a, b) => b.updatedAt - a.updatedAt)
  )
  const messages = computed(
    () => sessions.value.find(session => session.id === currentId.value)?.messages ?? []
  )

  let loadPromise: Promise<void> | null = null
  let activeUserId: number | null = null
  /** 账号切换计数：切换前发起的异步读写看到旧代数后自行放弃。 */
  let generation = 0
  let activeRunToken = 0
  let nextRunToken = 0
  let sessionSeq = 0
  let messageSeq = 0

  function now(): number {
    return getRuntime().adapters.clock.now()
  }

  /**
   * 账号变化时清空内存态并重新读取该用户的本地历史。
   * 进行中的教练请求也可能正在写回，`generation` 会让它们的落盘/状态更新失效。
   */
  function setActiveUser(userId: number | null): void {
    activeUserId = userId
    generation += 1
    loadPromise = null
    sessions.value = []
    currentId.value = ''
    loaded.value = false
    thinking.value = false
    progress.value = ''
    pendingSessionId.value = ''
    activeRunToken = 0
  }

  /** 本地存储不可用（隐私模式、配额不足）时保持内存会话可用，不阻塞对话。 */
  async function persist(): Promise<void> {
    try {
      await getRuntime().adapters.storage.set(
        coachStorageKey(activeUserId),
        JSON.stringify(sessions.value)
      )
    } catch {
      // 忽略写入失败：会话仍在内存中，用户可继续使用。
    }
  }

  function nextMessageId(): string {
    return makeMessageId(now(), messageSeq++)
  }

  /**
   * 标记一次请求开始；`sessionId` 记录回复应归档到的会话。
   * 返回本次请求的 token：页面应把它传给 setProgress/finishRun，
   * 这样账号切换后迟到的旧请求不会清掉新账号的进行中状态。
   */
  function beginRun(sessionId: string): number {
    const token = ++nextRunToken
    activeRunToken = token
    pendingSessionId.value = sessionId
    thinking.value = true
    progress.value = '正在连接学习教练…'
    return token
  }

  /** 更新流式进度；请求已结束或不属于当前请求时忽略迟到的进度事件。 */
  function setProgress(text: string, token?: number): void {
    if (!thinking.value) return
    if (token !== undefined && token !== activeRunToken) return
    progress.value = text
  }

  /** 请求结束（无论成功、失败还是页面已卸载），解除全局禁用态。 */
  function finishRun(token?: number): void {
    // 账号切换后旧请求的收尾不能影响新账号正在进行的请求。
    if (token !== undefined && token !== activeRunToken) return
    thinking.value = false
    progress.value = ''
    pendingSessionId.value = ''
    activeRunToken = 0
  }

  function mostRecentId(items: readonly CoachSession[]): string {
    return [...items].sort((a, b) => b.updatedAt - a.updatedAt)[0]?.id ?? ''
  }

  /** 读取当前用户已保存的会话；损坏数据回退到全新的「新会话」并覆盖存储。 */
  async function load(): Promise<void> {
    if (loaded.value) return
    if (loadPromise) return loadPromise
    const gen = generation
    const promise = (async () => {
      let stored: CoachSession[] = []
      try {
        stored = parseStoredSessions(
          await getRuntime().adapters.storage.get(coachStorageKey(activeUserId))
        )
      } catch {
        stored = []
      }
      // 读取期间账号已切换：结果属于上一个用户，直接丢弃。
      if (gen !== generation) return
      if (stored.length === 0) {
        sessions.value = []
        await newSession()
      } else {
        sessions.value = stored
        currentId.value = mostRecentId(stored)
        // 回写一次，顺带清掉被容错逻辑丢弃的脏数据。
        await persist()
      }
      if (gen !== generation) return
      loaded.value = true
    })()
    loadPromise = promise
    void promise.finally(() => {
      if (loadPromise === promise) loadPromise = null
    })
    return promise
  }

  async function newSession(): Promise<string> {
    const time = now()
    const session: CoachSession = {
      id: makeSessionId(time, sessionSeq++),
      title: FRESH_TITLE,
      updatedAt: time,
      messages: []
    }
    sessions.value = [...sessions.value, session]
    currentId.value = session.id
    await persist()
    return session.id
  }

  async function switchSession(id: string): Promise<void> {
    if (!sessions.value.some(session => session.id === id)) return
    currentId.value = id
    await persist()
  }

  async function deleteSession(id: string): Promise<void> {
    sessions.value = sessions.value.filter(session => session.id !== id)
    if (sessions.value.length === 0) {
      await newSession()
      return
    }
    if (currentId.value === id) currentId.value = mostRecentId(sessions.value)
    await persist()
  }

  /**
   * 追加消息到指定会话（而不是当前可见会话）。
   * 发送期间用户无法切换会话，但回复仍按发送时捕获的 id 归档，避免错位。
   */
  async function addMessage(sessionId: string, message: CoachMessage): Promise<void> {
    const session = sessions.value.find(item => item.id === sessionId)
    if (!session) return
    const updated: CoachSession = {
      ...session,
      title: session.title === FRESH_TITLE && message.role === 'user'
        ? sessionTitle(message.text)
        : session.title,
      updatedAt: now(),
      messages: [...session.messages, message]
    }
    sessions.value = upsertSession(sessions.value, updated)
    await persist()
  }

  return {
    sessions,
    orderedSessions,
    currentId,
    messages,
    loaded,
    thinking,
    progress,
    pendingSessionId,
    setActiveUser,
    load,
    newSession,
    switchSession,
    deleteSession,
    addMessage,
    nextMessageId,
    beginRun,
    setProgress,
    finishRun,
    persist
  }
})
