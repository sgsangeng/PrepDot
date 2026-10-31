export interface CoachTrendPoint {
  date: string
  total: number
  again?: number
  hard?: number
  good?: number
  easy?: number
}

export interface CoachWeakCardPoint {
  cardId?: number
  deckId?: number
  deckTitle?: string
  question: string
  memoryScore: number
}

export interface CoachMessage {
  id: string
  role: 'user' | 'assistant'
  text: string
  /** 本次回答调用的工具摘要，如「本次调用：薄弱卡片诊断」。 */
  toolNote?: string
  /** `get_review_trend` 工具结果，用于渲染复习趋势图。 */
  trend?: CoachTrendPoint[]
  /** `get_weak_cards` 工具结果，用于渲染薄弱卡片图。 */
  weakCards?: CoachWeakCardPoint[]
}

export interface CoachSession {
  id: string
  title: string
  /** 毫秒时间戳，来自注入的 Clock，便于历史会话排序。 */
  updatedAt: number
  messages: CoachMessage[]
}

const MINUTE_MS = 60_000
const HOUR_MS = 3_600_000
const DAY_MS = 86_400_000

/** 会话标题取首条用户消息的前 24 个字符（与 iOS `prefix(24)` 一致）。 */
export function sessionTitle(text: string): string {
  return text.trim().slice(0, 24)
}

/**
 * 纯函数生成会话 id，不依赖 `crypto` / `Date.now` 等浏览器全局；
 * 时间与序号都来自调用方，测试可完全确定。
 */
export function makeSessionId(nowMs: number, seq: number): string {
  return `coach-session-${nowMs}-${seq}`
}

/** 消息 id，规则与会话 id 相同；只需要在当前会话内唯一。 */
export function makeMessageId(nowMs: number, seq: number): string {
  return `coach-message-${nowMs}-${seq}`
}

/** 历史会话列表中的相对时间，与 iOS `Text(date, style: .relative)` 的中文表达对齐。 */
export function relativeTimeLabel(timestampMs: number, nowMs: number): string {
  const diff = Math.max(0, nowMs - timestampMs)
  if (diff < MINUTE_MS) return '刚刚'
  if (diff < HOUR_MS) return `${Math.floor(diff / MINUTE_MS)} 分钟前`
  if (diff < DAY_MS) return `${Math.floor(diff / HOUR_MS)} 小时前`
  return `${Math.floor(diff / DAY_MS)} 天前`
}

/** 按 id 更新已有会话，否则追加；返回新数组，便于 Pinia 触发更新。 */
export function upsertSession(sessions: readonly CoachSession[], session: CoachSession): CoachSession[] {
  const index = sessions.findIndex(item => item.id === session.id)
  if (index < 0) return [...sessions, session]
  const next = sessions.slice()
  next[index] = session
  return next
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function parseTrend(value: unknown): CoachTrendPoint[] | undefined {
  if (!Array.isArray(value)) return undefined
  const points = value
    .filter(isRecord)
    .filter(item => typeof item.date === 'string' && Number.isFinite(item.total))
    .map(item => ({ date: item.date as string, total: item.total as number }))
  return points.length > 0 ? points : undefined
}

function parseWeakCards(value: unknown): CoachWeakCardPoint[] | undefined {
  if (!Array.isArray(value)) return undefined
  const points = value
    .filter(isRecord)
    .filter(item => typeof item.question === 'string' && Number.isFinite(item.memoryScore))
    .map((item) => {
      const point: CoachWeakCardPoint = {
        question: item.question as string,
        memoryScore: item.memoryScore as number
      }
      if (Number.isFinite(item.cardId)) point.cardId = item.cardId as number
      if (Number.isFinite(item.deckId)) point.deckId = item.deckId as number
      if (typeof item.deckTitle === 'string') point.deckTitle = item.deckTitle
      return point
    })
  return points.length > 0 ? points : undefined
}

function parseMessage(value: unknown): CoachMessage | null {
  if (!isRecord(value)) return null
  const role = value.role
  if (typeof value.id !== 'string' || value.id.length === 0) return null
  if (role !== 'user' && role !== 'assistant') return null
  if (typeof value.text !== 'string') return null

  const message: CoachMessage = { id: value.id, role, text: value.text }
  if (typeof value.toolNote === 'string' && value.toolNote.length > 0) message.toolNote = value.toolNote
  const trend = parseTrend(value.trend)
  if (trend) message.trend = trend
  const weakCards = parseWeakCards(value.weakCards)
  if (weakCards) message.weakCards = weakCards
  return message
}

function parseSession(value: unknown): CoachSession | null {
  if (!isRecord(value)) return null
  if (typeof value.id !== 'string' || value.id.length === 0) return null
  if (typeof value.title !== 'string') return null
  if (typeof value.updatedAt !== 'number' || !Number.isFinite(value.updatedAt)) return null
  if (!Array.isArray(value.messages)) return null

  const title = value.title.trim() ? value.title : '新会话'
  const messages = value.messages
    .map(parseMessage)
    .filter((message): message is CoachMessage => message !== null)
  return { id: value.id, title, updatedAt: value.updatedAt, messages }
}

/**
 * 防御式读取本地会话：损坏的 JSON、错误的顶层结构、字段不完整的会话都会被丢弃。
 * 返回值可能为空数组，由 store 决定回退到全新的「新会话」并覆盖存储。
 */
export function parseStoredSessions(raw: string | null): CoachSession[] {
  if (!raw) return []
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    return []
  }
  if (!Array.isArray(parsed)) return []
  return parsed
    .map(parseSession)
    .filter((session): session is CoachSession => session !== null)
}
