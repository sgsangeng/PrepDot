export type ReviewRating = 'again' | 'hard' | 'good' | 'easy'

export interface RatingOption {
  rating: ReviewRating
  label: string
  sub: string
}

/** 与 iOS `RatingButtons` 保持相同的顺序与文案。 */
export const ratingOptions: readonly RatingOption[] = [
  { rating: 'again', label: 'Again', sub: '重新学' },
  { rating: 'hard', label: 'Hard', sub: '明天' },
  { rating: 'good', label: 'Good', sub: '2–4 天' },
  { rating: 'easy', label: 'Easy', sub: '5–10 天' }
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

export interface RatingAdvance extends AdvanceResult {
  /**
   * 本地队列已清空，但服务器仍可能把这张卡留在当日计划里：
   * `again` 会把卡片置为立即到期并回置 pending，必须重新拉取计划后再决定是否完成。
   */
  reload: boolean
}

/** 评分后的页面决策：普通推进，或（again 清空队列时）先重新拉取今日计划。 */
export function advanceAfterRating(
  index: number,
  total: number,
  rating: ReviewRating
): RatingAdvance {
  const next = advanceReview(index, total)
  if (!next.done) return { ...next, reload: false }
  return { ...next, reload: rating === 'again' }
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
