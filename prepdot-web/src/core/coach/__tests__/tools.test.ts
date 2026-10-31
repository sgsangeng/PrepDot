import { describe, expect, it } from 'vitest'
import type { AgentRun, AgentStep } from '@/core/api/types'
import { extractToolResult, localizeProgress, sessionTitle, toolSummary } from '../tools'

const run: AgentRun = {
  runId: 1, status: 'SUCCEEDED', output: 'ok', stepCount: 2,
  steps: [
    { stepNo: 1, stepType: 'TOOL', modelContent: null, toolName: 'get_weak_cards', toolArguments: null, toolResult: '[{"question":"Q"}]', durationMs: 1 },
    { stepNo: 2, stepType: 'MODEL', modelContent: 'done', toolName: null, toolArguments: null, toolResult: null, durationMs: 1 }
  ]
}

function step(overrides: Partial<AgentStep>): AgentStep {
  return {
    stepNo: 1,
    stepType: 'TOOL',
    modelContent: null,
    toolName: null,
    toolArguments: null,
    toolResult: null,
    durationMs: 1,
    ...overrides
  }
}

function runWith(steps: AgentStep[]): AgentRun {
  return { runId: 1, status: 'SUCCEEDED', output: 'ok', stepCount: steps.length, steps }
}

describe('coach tools', () => {
  it('extracts tool result arrays', () => {
    expect(extractToolResult(run, 'get_weak_cards')).toEqual([{ question: 'Q' }])
  })

  it('summarizes tools in Chinese', () => {
    expect(toolSummary(run)).toBe('本次调用：薄弱卡片诊断')
  })

  it('localizes progress', () => {
    expect(localizeProgress('calling get_review_trend')).toBe('calling 复习趋势统计')
  })

  it('derives a short session title', () => {
    expect(sessionTitle('分析我最近掌握得最差的知识点，并给出建议')).toBe('分析我最近掌握得最差的知识点，并给出建议'.slice(0, 24))
  })

  it('deduplicates tool labels while keeping call order', () => {
    const summary = toolSummary(runWith([
      step({ toolName: 'get_review_trend' }),
      step({ toolName: 'get_weak_cards' }),
      step({ toolName: 'get_review_trend' })
    ]))
    expect(summary).toBe('本次调用：复习趋势统计、薄弱卡片诊断')
  })

  it('returns undefined when no tool ran', () => {
    expect(toolSummary(runWith([
      step({ stepType: 'MODEL', modelContent: 'hello' })
    ]))).toBeUndefined()
  })

  it('uses the last matching tool result', () => {
    const result = extractToolResult(runWith([
      step({ toolName: 'get_weak_cards', toolResult: '[{"question":"old"}]' }),
      step({ toolName: 'get_weak_cards', toolResult: '[{"question":"new"}]' })
    ]), 'get_weak_cards')
    expect(result).toEqual([{ question: 'new' }])
  })

  it('returns [] when the tool result is missing or not JSON', () => {
    expect(extractToolResult(run, 'get_review_trend')).toEqual([])
    expect(extractToolResult(runWith([
      step({ toolName: 'get_weak_cards', toolResult: 'not json' })
    ]), 'get_weak_cards')).toEqual([])
    expect(extractToolResult(runWith([
      step({ toolName: 'get_weak_cards', toolResult: '{"question":"Q"}' })
    ]), 'get_weak_cards')).toEqual([])
  })

  it('localizes the real backend progress sentences', () => {
    expect(localizeProgress('正在执行工具：get_weak_cards')).toBe('正在执行工具：薄弱卡片诊断')
    expect(localizeProgress('工具完成：get_weak_cards')).toBe('工具完成：薄弱卡片诊断')
    expect(localizeProgress('正在执行工具：get_review_trend')).toBe('正在执行工具：复习趋势统计')
    expect(localizeProgress('正在执行工具：get_neglected_decks')).toBe('正在执行工具：冷落卡组检查')
    expect(localizeProgress('工具完成：generate_supplement_cards')).toBe('工具完成：补强卡片生成与质检')
  })

  it('leaves unknown tool names untouched', () => {
    expect(localizeProgress('正在执行工具：unknown_tool')).toBe('正在执行工具：unknown_tool')
    expect(toolSummary(runWith([step({ toolName: 'unknown_tool' })]))).toBe('本次调用：unknown_tool')
  })
})
