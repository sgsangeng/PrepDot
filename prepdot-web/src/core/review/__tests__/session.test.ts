import { describe, expect, it } from 'vitest'
import { advanceReview, isReviewComplete, parseCardOptions, ratingOptions } from '../session'

describe('review session', () => {
  it('advances until the last card', () => {
    expect(advanceReview(0, 3)).toEqual({ index: 1, done: false })
    expect(advanceReview(2, 3)).toEqual({ index: 2, done: true })
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

  it('returns no options when the column is empty or invalid', () => {
    expect(parseCardOptions(null)).toEqual([])
    expect(parseCardOptions('')).toEqual([])
    expect(parseCardOptions('{"not":"an array"}')).toEqual(['{"not":"an array"}'])
  })
})
