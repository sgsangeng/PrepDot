import { describe, expect, it } from 'vitest'
import {
  advanceAfterRating,
  advanceReview,
  isReviewComplete,
  parseCardOptions,
  ratingOptions
} from '../session'

describe('review session', () => {
  it('advances until the last card', () => {
    expect(advanceReview(0, 3)).toEqual({ index: 1, done: false })
    expect(advanceReview(2, 3)).toEqual({ index: 2, done: true })
    expect(advanceReview(0, 1)).toEqual({ index: 0, done: true })
  })

  it('reloads the plan instead of finishing when again empties the local queue', () => {
    expect(advanceAfterRating(2, 3, 'again')).toEqual({ index: 2, done: true, reload: true })
    expect(advanceAfterRating(0, 1, 'again')).toEqual({ index: 0, done: true, reload: true })
    // 中间卡片保持 iOS 流程：直接切到下一张，不触发刷新。
    expect(advanceAfterRating(0, 3, 'again')).toEqual({ index: 1, done: false, reload: false })
    // 其它评分清空队列时仍直接进入完成页。
    expect(advanceAfterRating(2, 3, 'good')).toEqual({ index: 2, done: true, reload: false })
  })

  it('exposes four ratings in iOS order', () => {
    expect(ratingOptions.map(r => r.rating)).toEqual(['again', 'hard', 'good', 'easy'])
  })

  it('reports completion only when today had cards and all were reviewed', () => {
    expect(isReviewComplete({ totalCount: 4, cards: [] })).toBe(true)
    expect(isReviewComplete({ totalCount: 4, cards: [{}] })).toBe(false)
    // 今日没有到期卡片属于空状态，而不是“复习完成”。
    expect(isReviewComplete({ totalCount: 0, cards: [] })).toBe(false)
  })

  it('parses JSON encoded choice options', () => {
    expect(parseCardOptions('["选项 A","选项 B"]')).toEqual(['选项 A', '选项 B'])
  })

  it('drops non-string and blank entries from option arrays', () => {
    expect(parseCardOptions('["A", 1, "", "  ", "B"]')).toEqual(['A', 'B'])
  })

  it('falls back to the raw text when options are not valid JSON', () => {
    expect(parseCardOptions('A. 旧格式\nB. 仍然是选项')).toEqual(['A. 旧格式\nB. 仍然是选项'])
  })

  it('returns no options for empty input and raw text for non-array JSON', () => {
    expect(parseCardOptions(null)).toEqual([])
    expect(parseCardOptions('')).toEqual([])
    expect(parseCardOptions('{"not":"an array"}')).toEqual(['{"not":"an array"}'])
  })
})
