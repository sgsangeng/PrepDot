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

const FRESH_TITLE = '新会话'

export const useCoachStore = defineStore('coach', () => {
  const sessions = ref<CoachSession[]>([])
  const currentId = ref('')
  const loaded = ref(false)

  const orderedSessions = computed(() =>
    [...sessions.value].sort((a, b) => b.updatedAt - a.updatedAt)
  )
  const messages = computed(
    () => sessions.value.find(session => session.id === currentId.value)?.messages ?? []
  )

  let loadPromise: Promise<void> | null = null
  let sessionSeq = 0
  let messageSeq = 0

  function now(): number {
    return getRuntime().adapters.clock.now()
  }

  /** 本地存储不可用（隐私模式、配额不足）时保持内存会话可用，不阻塞对话。 */
  async function persist(): Promise<void> {
    try {
      await getRuntime().adapters.storage.set(COACH_STORAGE_KEY, JSON.stringify(sessions.value))
    } catch {
      // 忽略写入失败：会话仍在内存中，用户可继续使用。
    }
  }

  function nextMessageId(): string {
    return makeMessageId(now(), messageSeq++)
  }

  function mostRecentId(items: readonly CoachSession[]): string {
    return [...items].sort((a, b) => b.updatedAt - a.updatedAt)[0]?.id ?? ''
  }

  /** 读取已保存的会话；损坏数据回退到全新的「新会话」并覆盖存储。 */
  async function load(): Promise<void> {
    if (loaded.value) return
    if (loadPromise) return loadPromise
    loadPromise = (async () => {
      let stored: CoachSession[] = []
      try {
        stored = parseStoredSessions(await getRuntime().adapters.storage.get(COACH_STORAGE_KEY))
      } catch {
        stored = []
      }
      if (stored.length === 0) {
        sessions.value = []
        await newSession()
      } else {
        sessions.value = stored
        currentId.value = mostRecentId(stored)
        // 回写一次，顺带清掉被容错逻辑丢弃的脏数据。
        await persist()
      }
      loaded.value = true
      loadPromise = null
    })()
    return loadPromise
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
    load,
    newSession,
    switchSession,
    deleteSession,
    addMessage,
    nextMessageId,
    persist
  }
})
