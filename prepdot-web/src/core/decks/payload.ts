import type { DeckPayload } from '@/core/api/types'

export interface DeckPayloadInput {
  title: string
  category: string
  description: string
  /** true 表示更新已有卡组；后端更新接口会忽略 null 描述，需用空字符串清空。 */
  updating?: boolean
}

/** 构造 `POST/PUT /decks` 的请求体。 */
export function buildDeckPayload(input: DeckPayloadInput): DeckPayload {
  const description = input.description.trim()
  return {
    title: input.title.trim(),
    category: input.category.trim() || '综合',
    // 更新时传空字符串才能真正清空描述；创建时保持原有的 null 表示「没有描述」。
    description: description === '' ? (input.updating ? '' : null) : description
  }
}
