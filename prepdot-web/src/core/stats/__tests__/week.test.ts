import { describe, expect, it } from 'vitest'
import { last7Days } from '../week'

// 2026-10-31 12:00 Asia/Shanghai
const now = Date.UTC(2026, 9, 31, 4, 0)

describe('last7Days', () => {
  it('fills missing days and labels them', () => {
    const rows = last7Days([{ day: '10-31', count: 5 }, { day: '10-29', count: 2 }], now)
    expect(rows).toHaveLength(7)
    expect(rows.at(-1)).toEqual({ day: '2026-10-31', label: '10/31', count: 5 })
    expect(rows.find(r => r.day === '2026-10-30')?.count).toBe(0)
    expect(rows[0]).toEqual({ day: '2026-10-25', label: '10/25', count: 0 })
  })

  it('sorts unsorted input into ascending day order', () => {
    const rows = last7Days([
      { day: '10-26', count: 1 },
      { day: '10-31', count: 9 },
      { day: '10-28', count: 3 }
    ], now)
    expect(rows.map(r => r.day)).toEqual([
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
      '2026-10-31'
    ])
    expect(rows[1].count).toBe(1)
    expect(rows[3].count).toBe(3)
  })

  it('sums duplicate MM-DD keys', () => {
    const rows = last7Days([
      { day: '10-30', count: 1 },
      { day: '2026-10-30', count: 2 }
    ], now)
    expect(rows.find(r => r.day === '2026-10-30')?.count).toBe(3)
  })

  it('keeps the MM-DD lookup key across a year boundary', () => {
    // 2026-01-02 12:00 Asia/Shanghai → 2025-12-27 .. 2026-01-02
    const newYear = Date.UTC(2026, 0, 2, 4, 0)
    const rows = last7Days([{ day: '12-27', count: 4 }, { day: '01-02', count: 2 }], newYear)
    expect(rows).toHaveLength(7)
    expect(rows[0]).toEqual({ day: '2025-12-27', label: '12/27', count: 4 })
    expect(rows.at(-1)).toEqual({ day: '2026-01-02', label: '01/02', count: 2 })
    expect(rows.map(r => r.day)).toContain('2025-12-31')
  })

  it('respects an explicit time zone', () => {
    // 2026-10-31 23:30 UTC = 2026-11-01 07:30 in Shanghai, but still 10-31 in UTC.
    const lateUtc = Date.UTC(2026, 9, 31, 23, 30)
    expect(last7Days([], lateUtc, 'UTC').at(-1)?.day).toBe('2026-10-31')
    expect(last7Days([], lateUtc).at(-1)?.day).toBe('2026-11-01')
  })
})
