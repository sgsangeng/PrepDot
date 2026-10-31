export type ReviewRating = 'again' | 'hard' | 'good' | 'easy'

export interface RatingOption {
  rating: ReviewRating
  label: string
  sub: string
  color: 'red' | 'orange' | 'green' | 'indigo'
}

/** 与 iOS `RatingButtons` 保持相同的顺序与文案。 */
export const ratingOptions: readonly RatingOption[] = [
  { rating: 'again', label: 'Again', sub: '重新学', color: 'red' },
  { rating: 'hard', label: 'Hard', sub: '明天', color: 'orange' },
  { rating: 'good', label: 'Good', sub: '2–4 天', color: 'green' },
  { rating: 'easy', label: 'Easy', sub: '5–10 天', color: 'indigo' }
]

export interface AdvanceResult {
  index: number
  done: boolean
}

/** 评分成功后推进到下一张；最后一张保持原下标并标记完成。 */
export function advanceReview(index: number, total: number): AdvanceResult {
  const next = index + 1
  return next >= total ? { index, done: true } : { index: next, done: false }
}

/**
 * 今日计划已完成：今天原本有到期卡片，但队列已经清空。
 * 今日没有卡片（totalCount === 0）属于空状态，不算“完成”。
 */
export function isReviewComplete(plan: { totalCount: number; cards: readonly unknown[] }): boolean {
  return plan.totalCount > 0 && plan.cards.length === 0
}

/**
 * `Flashcard.options` 是 JSON 字符串数组；解析失败时退回原始文本，
 * 保证旧数据不会导致复习页崩溃。
 */
export function parseCardOptions(raw: string | null | undefined): string[] {
  const value = raw?.trim()
  if (!value) return []
  try {
    const parsed: unknown = JSON.parse(value)
    if (Array.isArray(parsed)) {
      return parsed.filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
    }
  } catch {
    // 旧格式或损坏数据，落回原始文本。
  }
  return [value]
}
