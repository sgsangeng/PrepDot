import { describe, expect, it } from 'vitest'
import { detailHints, detailLabels, mergePreviews, parseAiPreview } from '../preview'

describe('ai preview', () => {
  it('parses and trims cards', () => {
    const preview = parseAiPreview(JSON.stringify({
      title: ' T ', category: ' Java ', description: ' d ',
      children: [{ title: ' C ', cards: [{ question: ' q ', answer: ' a ' }, { question: '', answer: 'x' }] }]
    }))
    expect(preview.title).toBe('T')
    expect(preview.children[0].cards).toEqual([{ question: 'q', answer: 'a' }])
  })

  it('rejects non-json', () => {
    expect(() => parseAiPreview('not json')).toThrow('AI 返回的内容不是有效 JSON')
  })

  it('merges children and keeps user title', () => {
    const merged = mergePreviews('Mine', [
      { title: 'a', category: 'Java', description: 'd1', children: [{ title: 'c1', cards: [] }] },
      { title: 'b', category: 'Java', description: 'd2', children: [{ title: 'c2', cards: [] }] }
    ])
    expect(merged.title).toBe('Mine')
    expect(merged.children.map(c => c.title)).toEqual(['c1', 'c2'])
  })

  it('applies defaults and drops invalid children', () => {
    const preview = parseAiPreview(JSON.stringify({
      title: 'Deck',
      children: [
        { title: '  ', cards: [] },
        { cards: [] },
        { title: 'Valid', cards: [{ question: ' q ', answer: ' ' }, { question: 'q2', answer: 'a2' }] }
      ]
    }))
    expect(preview.category).toBe('综合')
    expect(preview.description).toBe('')
    expect(preview.children).toEqual([
      { title: 'Valid', cards: [{ question: 'q2', answer: 'a2' }] }
    ])
  })

  it('rejects payloads without a title', () => {
    expect(() => parseAiPreview(JSON.stringify({ category: 'Java' })))
      .toThrow('AI 返回的内容缺少卡组标题')
  })

  it('uses defaults when merging no previews', () => {
    expect(mergePreviews('Mine', [])).toEqual({
      title: 'Mine',
      category: '综合',
      description: '',
      children: []
    })
  })

  it('keeps the five detail levels aligned with iOS', () => {
    expect(detailLabels).toEqual(['极简', '简洁', '标准', '详细', '极详'])
    expect(detailHints).toEqual([
      '答案极简，不超过20字',
      '答案简洁，不超过50字',
      '答案详细，100字以内',
      '答案详细，可分要点列举，150字以内',
      '答案尽可能详尽，含原理和示例，200字以内'
    ])
  })
})
