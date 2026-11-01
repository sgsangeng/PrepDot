/**
 * Agent 工具名 → 中文标签。
 * 后端以工具实现的蛇形命名下发（见 `AgentOrchestrator`），不是类名。
 */
export const COACH_TOOL_LABELS: Record<string, string> = {
  get_weak_cards: '薄弱卡片诊断',
  get_review_trend: '复习趋势统计',
  get_neglected_decks: '冷落卡组检查',
  generate_supplement_cards: '补强卡片生成与质检'
}

export function toolLabel(name: string): string {
  return COACH_TOOL_LABELS[name] ?? name
}

/**
 * 把后端进度文本中的工具名替换为中文标签。
 * 真实文本形如「正在执行工具：get_review_trend」「工具完成：get_weak_cards」，
 * 工具名可能出现在句子任意位置，因此逐项全局替换。
 */
export function localizeProgress(raw: string): string {
  return Object.entries(COACH_TOOL_LABELS)
    .reduce((text, [name, label]) => text.replaceAll(name, label), raw)
}
