import { describe, expect, it } from 'vitest'
import { buildCardPayload } from '../payload'

describe('card payload', () => {
  it('keeps the original category when updating a card', () => {
    const body = buildCardPayload({
      mode: 'qa',
      question: ' 问题 ',
      answer: '答案',
      optionValues: [],
      selectedOption: '',
      card: { category: '计算机网络' },
      deckCategory: '操作系统'
    })

    expect(body).toEqual({
      question: '问题',
      answer: '答案',
      cardType: 'qa',
      options: null,
      category: '计算机网络'
    })
  })

  it('inherits the deck category when creating a card', () => {
    const body = buildCardPayload({
      mode: 'blank',
      question: 'TCP 的握手次数是 ____',
      answer: '3',
      optionValues: [],
      selectedOption: '',
      deckCategory: ' 计算机网络 '
    })

    expect(body.category).toBe('计算机网络')
    expect(body.cardType).toBe('blank')
  })

  it('omits category when neither the card nor the deck provides one', () => {
    const body = buildCardPayload({
      mode: 'qa',
      question: 'q',
      answer: 'a',
      optionValues: [],
      selectedOption: ''
    })

    expect(body).not.toHaveProperty('category')
  })

  it('serializes trimmed choice options and the selected answer', () => {
    const body = buildCardPayload({
      mode: 'choice',
      question: '选出正确项',
      answer: 'ignored',
      optionValues: [' A ', '', '  ', 'B'],
      selectedOption: 'B',
      card: { category: '综合' }
    })

    expect(body.cardType).toBe('choice')
    expect(body.answer).toBe('B')
    expect(JSON.parse(body.options as string)).toEqual(['A', 'B'])
    expect(body.category).toBe('综合')
  })
})
