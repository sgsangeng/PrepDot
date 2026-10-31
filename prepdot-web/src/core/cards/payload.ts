import type { CardPayload, Flashcard } from '@/core/api/types'

export type CardMode = 'qa' | 'choice' | 'blank'

export interface CardPayloadInput {
  mode: CardMode
  question: string
  /** 问答/填空题的答案；选择题不使用该字段。 */
  answer: string
  /** 选择题的四个选项输入值。 */
  optionValues: readonly string[]
  /** 选择题当前选中的正确答案。 */
  selectedOption: string
  /** 编辑时传入原卡片；更新必须回传原分类，否则后端默认值会把它覆盖成「综合」。 */
  card?: Pick<Flashcard, 'category'> | null
  /** 新建时所在卡组的分类。 */
  deckCategory?: string | null
}

/**
 * 构造 `POST/PUT /cards` 的请求体。
 *
 * 后端 `CardRequest.category` 有默认值「综合」，更新接口只在 null 时跳过覆盖，
 * 因此编辑卡片时必须显式带上传入卡片的原分类；新建时继承所在卡组的分类。
 */
export function buildCardPayload(input: CardPayloadInput): CardPayload {
  const category = input.card
    ? input.card.category
    : input.deckCategory?.trim() || undefined
  const categoryField = category === undefined ? {} : { category }

  if (input.mode === 'choice') {
    const filled = input.optionValues
      .map(item => item.trim())
      .filter(item => item.length > 0)
    return {
      question: input.question.trim(),
      answer: input.selectedOption.trim(),
      cardType: 'choice',
      options: JSON.stringify(filled),
      ...categoryField
    }
  }

  return {
    question: input.question.trim(),
    answer: input.answer,
    cardType: input.mode,
    options: null,
    ...categoryField
  }
}
