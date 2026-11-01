import { describe, expect, it } from 'vitest'
import { buildQuiz, scoreQuiz } from '../quiz'
import type { Flashcard } from '@/core/api/types'

const card = (id: number, answer: string): Flashcard => ({
  id, deckId: 1, question: `Q${id}`, answer, cardType: 'qa', options: null, category: '综合',
  memoryScore: 50, difficulty: 5, stability: 2, note: null, reviewCount: 1,
  lastReviewedAt: null, nextReviewAt: null, createdAt: ''
})

describe('quiz', () => {
  it('builds at most 10 questions with 4 unique options', () => {
    const cards = [1, 2, 3, 4, 5].map(i => card(i, `A${i}`))
    const quiz = buildQuiz(cards, 10, () => 0.5)
    expect(quiz).toHaveLength(5)
    for (const q of quiz) {
      expect(q.options).toHaveLength(4)
      expect(new Set(q.options).size).toBe(q.options.length)
      expect(q.options[q.correctIndex]).toBe(q.answer)
    }
  })
  it('caps the quiz at 10 questions', () => {
    const cards = Array.from({ length: 15 }, (_, i) => card(i + 1, `A${i + 1}`))
    const quiz = buildQuiz(cards, 10, () => 0.5)
    expect(quiz).toHaveLength(10)
    expect(new Set(quiz.map(q => q.cardId)).size).toBe(10)
    // 同一随机源下截断结果可复现，题量稳定为 10。
    expect(buildQuiz(cards, 10, () => 0.5).map(q => q.cardId)).toEqual(quiz.map(q => q.cardId))
  })
  it('scores answers', () => {
    const quiz = buildQuiz([card(1, 'x'), card(2, 'y')], 10, () => 0.5)
    expect(scoreQuiz(quiz, quiz.map(q => q.correctIndex))).toBe(quiz.length)
    expect(scoreQuiz(quiz, quiz.map(() => 0))).toBeLessThanOrEqual(quiz.length)
  })
  it('deduplicates distractors when different cards share an answer', () => {
    const cards = [card(1, 'A'), card(2, 'A'), card(3, 'B'), card(4, 'C'), card(5, 'D')]
    for (const q of buildQuiz(cards, 10, () => 0.5)) {
      expect(new Set(q.options).size).toBe(q.options.length)
      expect(q.options[q.correctIndex]).toBe(q.answer)
      expect(q.options.length).toBeLessThanOrEqual(4)
    }
  })
})
