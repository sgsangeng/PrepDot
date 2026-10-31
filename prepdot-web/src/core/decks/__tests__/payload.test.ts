import { describe, expect, it } from 'vitest'
import { buildDeckPayload } from '../payload'

describe('deck payload', () => {
  it('sends an empty description when clearing it on update', () => {
    const body = buildDeckPayload({
      title: ' Java ',
      category: ' ',
      description: '   ',
      updating: true
    })

    expect(body).toEqual({ title: 'Java', category: '综合', description: '' })
  })

  it('keeps null for an empty description on create', () => {
    const body = buildDeckPayload({
      title: 'Java',
      category: '后端',
      description: ''
    })

    expect(body.description).toBeNull()
  })

  it('trims a non-empty description', () => {
    const body = buildDeckPayload({
      title: 'Java',
      category: '后端',
      description: '  集合与并发  ',
      updating: true
    })

    expect(body.description).toBe('集合与并发')
  })
})
