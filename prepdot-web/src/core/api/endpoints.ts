import type { PickedFile } from '@/adapters/types'
import type { ApiClient } from './client'
import type {
  AgentRun,
  CardPayload,
  CommunityPack,
  CommunityPackDetail,
  Deck,
  DeckPayload,
  Flashcard,
  ReviewSummary,
  TodayPlan,
  UserStats
} from './types'

export interface GenerateRequest {
  file: PickedFile
  deckTitle: string
  customKey?: string
  cardCount: number
  detailHint: string
  signal?: AbortSignal
}

export function createApi(client: ApiClient) {
  return {
    decks: () => client.request<Deck[]>({ method: 'GET', path: '/decks' }),
    createDeck: (body: DeckPayload) => client.request<Deck>({ method: 'POST', path: '/decks', body }),
    updateDeck: (id: number, body: DeckPayload) => client.request<Deck>({ method: 'PUT', path: `/decks/${id}`, body }),
    moveDeck: (id: number, parentId: number | null) => client.request<Deck>({ method: 'PUT', path: `/decks/${id}/parent`, body: { parentId } }),
    deleteDeck: (id: number) => client.request<void>({ method: 'DELETE', path: `/decks/${id}` }),
    cards: (deckId: number, deep = false) => client.request<Flashcard[]>({ method: 'GET', path: `/decks/${deckId}/cards${deep ? '?deep=true' : ''}` }),
    createCard: (body: CardPayload) => client.request<Flashcard>({ method: 'POST', path: '/cards', body }),
    updateCard: (id: number, body: CardPayload) => client.request<Flashcard>({ method: 'PUT', path: `/cards/${id}`, body }),
    deleteCard: (id: number) => client.request<void>({ method: 'DELETE', path: `/cards/${id}` }),
    deleteCards: (ids: number[]) => client.request<void>({ method: 'DELETE', path: `/cards/batch?${ids.map(id => `ids=${id}`).join('&')}` }),
    updateCardNote: (id: number, note: string) => client.request<Flashcard>({ method: 'PUT', path: `/cards/${id}/note`, body: { note } }),
    todayPlan: () => client.request<TodayPlan>({ method: 'GET', path: '/plan/today' }),
    submitReview: (cardId: number, rating: string) => client.request<Flashcard>({ method: 'POST', path: '/plan/review', body: { cardId, rating } }),
    todaySummary: () => client.request<ReviewSummary>({ method: 'GET', path: '/plan/summary' }),
    stats: () => client.request<UserStats>({ method: 'GET', path: '/auth/stats' }),
    deleteAccount: (password: string) => client.request<void>({ method: 'DELETE', path: '/auth/account', body: { password } }),
    coach: (message: string, mode = 'LEARNING_COACH') => client.request<AgentRun>({ method: 'POST', path: '/agent/coach', body: { message, mode } }),
    coachStream: (message: string, mode = 'LEARNING_COACH') => client.stream({ method: 'POST', path: '/agent/coach/stream', body: { message, mode } }),
    generate: async (req: GenerateRequest) =>
      client.upload<string>({
        path: '/ai/generate',
        fields: [
          { name: 'deckTitle', value: req.deckTitle },
          { name: 'customKey', value: req.customKey ?? '' },
          { name: 'cardCount', value: String(req.cardCount) },
          { name: 'detailHint', value: req.detailHint }
        ],
        file: { field: 'file', name: req.file.name, mime: req.file.mime, bytes: await req.file.bytes() },
        signal: req.signal
      }),
    importAiDeck: (rawJson: string) => client.request<Deck>({ method: 'POST', path: '/ai/import', body: rawJson, headers: { 'Content-Type': 'application/json' } }),
    communityPacks: () => client.request<CommunityPack[]>({ method: 'GET', path: '/community/packs' }),
    communityPack: (id: number) => client.request<CommunityPackDetail>({ method: 'GET', path: `/community/packs/${id}` }),
    importCommunityPack: (id: number) => client.request<Deck>({ method: 'POST', path: `/community/packs/${id}/import` })
  }
}
