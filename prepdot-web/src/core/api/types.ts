export interface AuthUser {
  token: string
  userId: number
  username: string
  nickname: string
  avatarColor: string
  studyTarget: number
}

export interface Deck {
  id: number
  parentId: number | null
  depth: number
  title: string
  type: string
  category: string
  description: string | null
  cardCount: number
  reviewedCount: number
  dueCount: number
  avgMemoryScore: number
  createdAt: string
}

export interface Flashcard {
  id: number
  deckId: number
  question: string
  answer: string
  cardType: 'qa' | 'choice' | 'blank' | string
  options: string | null
  category: string
  memoryScore: number
  difficulty: number | null
  stability: number | null
  note: string | null
  reviewCount: number
  lastReviewedAt: string | null
  nextReviewAt: string | null
  createdAt: string
}

export interface TodayPlan {
  planId: number
  planDate: string
  totalCount: number
  completedCount: number
  estimatedMinutes: number
  cards: Flashcard[]
  deckProgress: { deckId: number; deckTitle: string; totalCount: number; completedCount: number }[]
}

export interface ReviewSummary {
  totalCount: number
  decks: { deckId: number; deckTitle: string; count: number }[]
}

export interface AgentStep {
  stepNo: number
  stepType: 'MODEL' | 'TOOL' | string
  modelContent: string | null
  toolName: string | null
  toolArguments: string | null
  toolResult: string | null
  durationMs: number | null
}

export interface AgentRun {
  runId: number
  status: string
  output: string | null
  stepCount: number
  steps: AgentStep[]
}

export interface UserStats {
  streakDays: number
  todayReviewed: number
  totalReviewed: number
  totalDecks: number
  totalCards: number
  avgMemoryScore: number
  weeklyData: { day: string; count: number }[]
  memoryDistribution: { low: number; mid: number; high: number }
}

export interface CommunityPack {
  id: number
  title: string
  category: string
  description: string
  cardCount: number
  tags: string[]
}

export interface CommunityPackDetail extends CommunityPack {
  cards: { question: string; answer: string }[]
}

export interface AiPreviewCard { question: string; answer: string }
export interface AiPreviewChild { title: string; cards: AiPreviewCard[] }
export interface AiPreviewDeck {
  title: string
  category: string
  description: string
  children: AiPreviewChild[]
}

/** 新建/编辑卡组请求体，对应后端 DeckRequest。 */
export interface DeckPayload {
  title: string
  type?: string
  category?: string
  description?: string | null
  parentId?: number | null
  cards?: { question: string; answer: string; category?: string; cardType?: string; options?: string | null }[]
}

/** 新建/编辑卡片请求体，对应后端 CardRequest。 */
export interface CardPayload {
  deckId?: number
  question: string
  answer: string
  category?: string
  cardType?: string
  options?: string | null
}
