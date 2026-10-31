export interface AiPreviewCard {
  question: string
  answer: string
}

export interface AiPreviewChild {
  title: string
  cards: AiPreviewCard[]
}

export interface AiPreviewDeck {
  title: string
  category: string
  description: string
  children: AiPreviewChild[]
}

/** 与 iOS AIGenerateView 完全一致的详细程度文案。 */
export const detailLabels = ['极简', '简洁', '标准', '详细', '极详'] as const

/** 每个档位在生成 Prompt 中使用的详细程度提示。 */
export const detailHints = [
  '答案极简，不超过20字',
  '答案简洁，不超过50字',
  '答案详细，100字以内',
  '答案详细，可分要点列举，150字以内',
  '答案尽可能详尽，含原理和示例，200字以内'
] as const

const INVALID_JSON = 'AI 返回的内容不是有效 JSON'

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function trimmed(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function parseCard(value: unknown): AiPreviewCard | null {
  if (!isRecord(value)) return null
  const question = trimmed(value.question)
  const answer = trimmed(value.answer)
  return question !== '' && answer !== '' ? { question, answer } : null
}

function parseChild(value: unknown): AiPreviewChild | null {
  if (!isRecord(value)) return null
  const title = trimmed(value.title)
  if (title === '') return null
  const cards = Array.isArray(value.cards)
    ? value.cards.map(parseCard).filter((card): card is AiPreviewCard => card !== null)
    : []
  return { title, cards }
}

/**
 * 解析 `/ai/generate` 返回的原始 JSON：
 * 标题必填；分类/描述缺失时回退默认值；子卡组必须带标题；
 * 问题或答案 trim 后为空白的卡片会被丢弃。
 */
export function parseAiPreview(raw: string): AiPreviewDeck {
  let parsed: unknown
  try {
    parsed = JSON.parse(raw)
  } catch {
    throw new Error(INVALID_JSON)
  }
  if (!isRecord(parsed)) throw new Error(INVALID_JSON)

  const title = trimmed(parsed.title)
  if (title === '') throw new Error('AI 返回的内容缺少卡组标题')

  return {
    title,
    category: trimmed(parsed.category) || '综合',
    description: trimmed(parsed.description),
    children: Array.isArray(parsed.children)
      ? parsed.children.map(parseChild).filter((child): child is AiPreviewChild => child !== null)
      : []
  }
}

/**
 * 合并多次生成结果：根节点使用用户输入的名称，分类/描述取第一份，
 * 子卡组按生成顺序拼接。结构可直接 POST 给 `/ai/import`。
 */
export function mergePreviews(title: string, previews: AiPreviewDeck[]): AiPreviewDeck {
  const first = previews[0]
  return {
    title,
    category: first?.category ?? '综合',
    description: first?.description ?? '',
    children: previews.flatMap(preview => preview.children)
  }
}
