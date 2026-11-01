import type { AgentRun } from '@/core/api/types'
import { toolLabel } from './progress'

export { COACH_TOOL_LABELS, localizeProgress, toolLabel } from './progress'
export { sessionTitle } from './sessions'

/**
 * 汇总一次 AgentRun 调用过的工具，去重并保留首次调用顺序。
 * 没有工具步骤时返回 undefined（与 iOS 一致，不展示工具行）。
 */
export function toolSummary(run: AgentRun): string | undefined {
  const labels: string[] = []
  for (const step of run.steps) {
    if (step.stepType !== 'TOOL' || !step.toolName) continue
    const label = toolLabel(step.toolName)
    if (!labels.includes(label)) labels.push(label)
  }
  return labels.length > 0 ? `本次调用：${labels.join('、')}` : undefined
}

/**
 * 取最后一个同名 TOOL 步骤的结果并解析为数组。
 * 缺失、非 JSON 或不是数组时返回 []，与 iOS `decodeTool` 的容错一致。
 */
export function extractToolResult<T>(run: AgentRun, toolName: string): T[] {
  let result: string | null = null
  for (let index = run.steps.length - 1; index >= 0; index -= 1) {
    const step = run.steps[index]
    if (step.stepType === 'TOOL' && step.toolName === toolName) {
      result = step.toolResult
      break
    }
  }
  if (!result) return []
  try {
    const parsed: unknown = JSON.parse(result)
    return Array.isArray(parsed) ? parsed as T[] : []
  } catch {
    return []
  }
}
