import { describe, expect, it } from 'vitest'
import { buildPlot, scoreColor } from '../plot'
import type { Flashcard } from '@/core/api/types'

const card = (id: number, difficulty: number | null, stability: number | null, score = 50): Flashcard => ({
  id, deckId: 1, question: `Q${id}`, answer: 'A', cardType: 'qa', options: null, category: '综合',
  memoryScore: score, difficulty, stability, note: null, reviewCount: 1,
  lastReviewedAt: null, nextReviewAt: null, createdAt: ''
})

describe('plot', () => {
  it('drops unreviewed cards', () => {
    expect(buildPlot([card(1, null, null), card(2, 5, 10)], 400, 300, 40)).toHaveLength(1)
  })

  it('keeps points inside the plot area', () => {
    const points = buildPlot([card(1, 1, 0.1), card(2, 10, 1000)], 400, 300, 40)
    for (const p of points) {
      expect(p.x).toBeGreaterThanOrEqual(40)
      expect(p.x).toBeLessThanOrEqual(360)
      expect(p.y).toBeGreaterThanOrEqual(40)
      expect(p.y).toBeLessThanOrEqual(260)
    }
  })

  it('is deterministic and changes color with score', () => {
    const a = buildPlot([card(7, 5, 10, 0)], 400, 300, 40)[0]
    const b = buildPlot([card(7, 5, 10, 0)], 400, 300, 40)[0]
    expect([a.x, a.y]).toEqual([b.x, b.y])
    expect(scoreColor(0)).not.toBe(scoreColor(100))
  })

  it('keeps jittered points inside the plot area', () => {
    const cards = [
      card(1, 1, 0.01),
      card(2, 10, 100000),
      card(3, 1, 0.01),
      card(4, 10, 100000),
      card(5, 1, 100000),
      card(6, 10, 0.01)
    ]
    const points = buildPlot(cards, 400, 320, 40)
    expect(points).toHaveLength(cards.length)
    for (const p of points) {
      expect(p.x).toBeGreaterThanOrEqual(40)
      expect(p.x).toBeLessThanOrEqual(360)
      expect(p.y).toBeGreaterThanOrEqual(40)
      expect(p.y).toBeLessThanOrEqual(280)
    }
  })

  it('places higher stability higher on the chart (smaller y)', () => {
    const [low, high] = buildPlot([card(1, 5, 1), card(2, 5, 1000)], 400, 320, 40)
    expect(high.y).toBeLessThan(low.y)
    // x is driven by difficulty alone; equal difficulty keeps x close.
    expect(Math.abs(high.x - low.x)).toBeLessThanOrEqual(12)
  })

  it('handles an equal stability range without dividing by zero', () => {
    const points = buildPlot([card(1, 5, 10), card(2, 5, 10)], 400, 300, 40)
    for (const p of points) {
      expect(Number.isFinite(p.x)).toBe(true)
      expect(Number.isFinite(p.y)).toBe(true)
      expect(p.x).toBeGreaterThanOrEqual(40)
      expect(p.x).toBeLessThanOrEqual(360)
      // Equal min/max means both points sit on the vertical middle line.
      expect(p.y).toBeGreaterThanOrEqual(40)
      expect(p.y).toBeLessThanOrEqual(260)
    }
  })

  it('clamps out-of-range difficulty to the plot edges', () => {
    const [tooEasy, tooHard] = buildPlot([card(1, -5, 10), card(2, 20, 10)], 400, 300, 40)
    // 归一化值夹紧到 0/1，抖动最多 ±6 后仍留在边带内。
    expect(tooEasy.x).toBeGreaterThanOrEqual(40)
    expect(tooEasy.x).toBeLessThanOrEqual(46)
    expect(tooHard.x).toBeGreaterThanOrEqual(354)
    expect(tooHard.x).toBeLessThanOrEqual(360)
  })

  it('returns the source card with each point', () => {
    const source = card(42, 5, 10)
    expect(buildPlot([source], 400, 300, 40)[0].card).toBe(source)
  })
})

describe('scoreColor', () => {
  it('builds color exclusively from design tokens', () => {
    expect(scoreColor(50)).toContain('var(--color-')
    expect(scoreColor(50)).not.toMatch(/#[0-9a-f]{3,8}|rgba?\(|hsla?\(/i)
  })

  it('is deterministic for the same input', () => {
    expect(scoreColor(37)).toBe(scoreColor(37))
  })

  it('clamps scores below 0 and above 100', () => {
    expect(scoreColor(-10)).toBe(scoreColor(0))
    expect(scoreColor(200)).toBe(scoreColor(100))
  })

  it('interpolates from pink to indigo', () => {
    expect(scoreColor(0)).toContain('0%')
    expect(scoreColor(100)).toContain('100%')
  })
})
