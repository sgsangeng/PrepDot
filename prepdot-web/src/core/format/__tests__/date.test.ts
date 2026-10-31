import { describe, expect, it } from 'vitest'
import { formatRelativeDay, formatServerDate } from '../date'

const now = Date.UTC(2026, 9, 31, 4, 0) // 2026-10-31 12:00 Asia/Shanghai

describe('formatServerDate', () => {
  it('formats wall-clock server time without browser timezone conversion', () => {
    expect(formatServerDate('2026-10-31T12:30:00')).toBe('10月31日 12:30')
  })

  it('renders a dash for missing values', () => {
    expect(formatServerDate(null)).toBe('—')
  })
})

describe('formatRelativeDay', () => {
  it('counts days in Asia/Shanghai', () => {
    expect(formatRelativeDay('2026-11-02T12:00:00', now)).toBe('2 天后')
  })

  it('labels today, tomorrow and yesterday', () => {
    expect(formatRelativeDay('2026-10-31T08:00:00', now)).toBe('今天')
    expect(formatRelativeDay('2026-11-01T08:00:00', now)).toBe('明天')
    expect(formatRelativeDay('2026-10-30T08:00:00', now)).toBe('昨天')
  })

  it('labels past days', () => {
    expect(formatRelativeDay('2026-10-28T08:00:00', now)).toBe('3 天前')
  })
})
