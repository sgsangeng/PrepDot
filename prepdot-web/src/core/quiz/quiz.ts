import type { Flashcard } from '@/core/api/types'

export interface QuizQuestion {
  cardId: number
  question: string
  options: string[]
  correctIndex: number
  answer: string
}

/** 用注入的随机源洗牌，便于测试时得到可复现的顺序。 */
function shuffle<T>(items: readonly T[], rng: () => number): T[] {
  const result = [...items]
  for (let i = result.length - 1; i > 0; i -= 1) {
    const j = Math.floor(rng() * (i + 1))
    const temp = result[i]
    result[i] = result[j]
    result[j] = temp
  }
  return result
}

/**
 * 从卡片生成选择题：最多 `max` 道，每题正确答案 + 至多 3 个干扰项。
 * 选项去重后随机排序，`correctIndex` 指向正确答案。
 */
export function buildQuiz(cards: Flashcard[], max = 10, rng: () => number = Math.random): QuizQuestion[] {
  return shuffle(cards, rng)
    .slice(0, Math.max(0, max))
    .map(card => {
      // 干扰项按答案文本去重（不同卡片可能共用同一答案），避免出现重复选项。
      const seen = new Set<string>([card.answer])
      const distractors: string[] = []
      for (const item of shuffle(cards, rng)) {
        if (item.id === card.id || seen.has(item.answer)) continue
        seen.add(item.answer)
        distractors.push(item.answer)
        if (distractors.length === 3) break
      }
      const options = shuffle([card.answer, ...distractors], rng)
      return {
        cardId: card.id,
        question: card.question,
        answer: card.answer,
        options,
        correctIndex: options.indexOf(card.answer)
      }
    })
}

/** 统计答对的数量；答案数组与题目一一对应。 */
export function scoreQuiz(questions: QuizQuestion[], answers: number[]): number {
  return questions.reduce(
    (score, question, index) => score + (answers[index] === question.correctIndex ? 1 : 0),
    0
  )
}
