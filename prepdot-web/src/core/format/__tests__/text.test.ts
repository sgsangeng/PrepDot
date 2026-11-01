import { describe, expect, it } from 'vitest'
import { cardDisplayText, normalizeCardType, typeLabel } from '../text'

describe('cardDisplayText', () => {
  it('breaks lines before circled numbering', () => {
    expect(cardDisplayText('A；②B；③C')).toBe('A；\n②B；\n③C')
  })

  it('also handles ascii semicolons', () => {
    expect(cardDisplayText('A;②B')).toBe('A;\n②B')
  })
})

describe('normalizeCardType', () => {
  it('maps Chinese labels to canonical types', () => {
    expect(normalizeCardType('选择题')).toBe('choice')
    expect(normalizeCardType('填空题')).toBe('blank')
    expect(normalizeCardType('qa')).toBe('qa')
    expect(normalizeCardType('CHOICE')).toBe('choice')
  })
})

describe('typeLabel', () => {
  it('renders a Chinese label', () => {
    expect(typeLabel('choice')).toBe('选择')
    expect(typeLabel('blank')).toBe('填空')
    expect(typeLabel('qa')).toBe('问答')
  })
})
