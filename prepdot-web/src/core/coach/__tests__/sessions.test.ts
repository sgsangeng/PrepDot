import { describe, expect, it } from 'vitest'
import type { CoachMessage, CoachSession } from '../sessions'
import {
  makeMessageId,
  makeSessionId,
  parseStoredSessions,
  relativeTimeLabel,
  sessionTitle,
  upsertSession
} from '../sessions'

const NOW = 1_700_000_000_000

function session(id: string, updatedAt = NOW, messages: CoachMessage[] = []): CoachSession {
  return { id, title: '新会话', updatedAt, messages }
}

describe('upsertSession', () => {
  it('appends a new session', () => {
    const existing = [session('a')]
    const result = upsertSession(existing, session('b', NOW + 1))
    expect(result.map(s => s.id)).toEqual(['a', 'b'])
    expect(existing).toHaveLength(1)
  })

  it('updates the matching session in place', () => {
    const messages: CoachMessage[] = [{ id: 'm1', role: 'user', text: 'hi' }]
    const result = upsertSession([session('a'), session('b')], {
      id: 'a',
      title: 'hi',
      updatedAt: NOW + 100,
      messages
    })
    expect(result).toHaveLength(2)
    expect(result[0]).toEqual({ id: 'a', title: 'hi', updatedAt: NOW + 100, messages })
    expect(result[1].id).toBe('b')
  })
})

describe('parseStoredSessions', () => {
  it('returns [] for missing or corrupt data', () => {
    expect(parseStoredSessions(null)).toEqual([])
    expect(parseStoredSessions('')).toEqual([])
    expect(parseStoredSessions('{oops')).toEqual([])
  })

  it('returns [] when the top-level shape is not an array', () => {
    expect(parseStoredSessions('{"id":1}')).toEqual([])
    expect(parseStoredSessions('null')).toEqual([])
  })

  it('drops malformed sessions and keeps valid ones', () => {
    const valid = session('ok', NOW, [{ id: 'm1', role: 'user', text: '你好' }])
    const parsed = parseStoredSessions(JSON.stringify([
      { id: 1, title: '坏会话', updatedAt: NOW, messages: [] },
      valid,
      { id: 'no-messages', title: '坏会话', updatedAt: NOW },
      { id: 'bad-time', title: '坏会话', updatedAt: 'yesterday', messages: [] }
    ]))
    expect(parsed).toEqual([valid])
  })

  it('sanitizes messages and chart payloads', () => {
    const parsed = parseStoredSessions(JSON.stringify([{
      id: 's1',
      title: '会话',
      updatedAt: NOW,
      messages: [
        { id: 'm1', role: 'user', text: 'hi' },
        { id: 'm2', role: 'system', text: 'drop me' },
        { id: 'm3', role: 'assistant', text: 'reply', trend: [{ date: '2026-10-31', total: 3 }, { nope: true }], weakCards: [{ question: 'Q', memoryScore: 42 }] }
      ]
    }]))
    expect(parsed).toHaveLength(1)
    expect(parsed[0].messages).toHaveLength(2)
    expect(parsed[0].messages[1].trend).toEqual([{ date: '2026-10-31', total: 3 }])
    expect(parsed[0].messages[1].weakCards).toEqual([{ question: 'Q', memoryScore: 42 }])
  })

  it('treats empty chart arrays as absent', () => {
    const parsed = parseStoredSessions(JSON.stringify([{
      id: 's1',
      title: '会话',
      updatedAt: NOW,
      messages: [{ id: 'm1', role: 'assistant', text: 'ok', trend: [], weakCards: [] }]
    }]))
    expect(parsed[0].messages[0].trend).toBeUndefined()
    expect(parsed[0].messages[0].weakCards).toBeUndefined()
  })
})

describe('relativeTimeLabel', () => {
  it('labels just now', () => {
    expect(relativeTimeLabel(NOW - 30_000, NOW)).toBe('刚刚')
    expect(relativeTimeLabel(NOW, NOW)).toBe('刚刚')
  })

  it('labels future timestamps as just now', () => {
    expect(relativeTimeLabel(NOW + 60_000, NOW)).toBe('刚刚')
  })

  it('labels minutes, hours and days', () => {
    expect(relativeTimeLabel(NOW - 5 * 60_000, NOW)).toBe('5 分钟前')
    expect(relativeTimeLabel(NOW - 3 * 3_600_000, NOW)).toBe('3 小时前')
    expect(relativeTimeLabel(NOW - 2 * 86_400_000, NOW)).toBe('2 天前')
  })
})

describe('sessionTitle', () => {
  it('trims and truncates to 24 characters', () => {
    const long = '  一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十  '
    expect(sessionTitle(long)).toBe(long.trim().slice(0, 24))
    expect(sessionTitle(long)).toHaveLength(24)
  })

  it('keeps short titles unchanged', () => {
    expect(sessionTitle(' 看看复习趋势 ')).toBe('看看复习趋势')
  })
})

describe('id helpers', () => {
  it('is deterministic and unique per sequence', () => {
    expect(makeSessionId(NOW, 1)).toBe(makeSessionId(NOW, 1))
    expect(makeSessionId(NOW, 1)).not.toBe(makeSessionId(NOW, 2))
    expect(makeMessageId(NOW, 1)).not.toBe(makeMessageId(NOW, 2))
  })
})
