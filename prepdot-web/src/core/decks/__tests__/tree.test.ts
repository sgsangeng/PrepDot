import { describe, expect, it } from 'vitest'
import { buildDeckTree, descendantIds, filterDeckTree } from '../tree'
import type { Deck } from '@/core/api/types'

const deck = (id: number, parentId: number | null, title = `D${id}`): Deck => ({
  id, parentId, depth: parentId ? 1 : 0, title, type: '自建', category: '综合',
  description: null, cardCount: 0, reviewedCount: 0, dueCount: 0, avgMemoryScore: 0, createdAt: ''
})

describe('deck tree', () => {
  it('builds and sorts roots and children', () => {
    const roots = buildDeckTree([deck(2, null, 'B'), deck(1, null, 'A'), deck(3, 1, 'C')])
    expect(roots.map(n => n.deck.id)).toEqual([1, 2])
    expect(roots[0].children[0].deck.id).toBe(3)
  })
  it('does not loop on cyclic parents', () => {
    const roots = buildDeckTree([deck(1, 2), deck(2, 1)])
    expect(roots).toHaveLength(0)
  })
  it('filters while keeping matched ancestors', () => {
    const roots = buildDeckTree([deck(1, null, 'Java'), deck(2, 1, 'JVM')])
    expect(filterDeckTree(roots, 'jvm')[0].children[0].deck.title).toBe('JVM')
  })
  it('collects descendants', () => {
    expect([...descendantIds(1, [deck(1, null), deck(2, 1), deck(3, 2)])]).toEqual([2, 3])
  })
})

describe('deck tree edge cases', () => {
  it('treats decks with unknown parents as roots', () => {
    const roots = buildDeckTree([deck(1, 99, '孤儿'), deck(2, null, '根')])
    expect(roots.map(n => n.deck.id)).toEqual([2, 1])
  })

  it('drops a cycle made only of internal nodes', () => {
    // 1→2→3→1：没有任何节点可以当根，整组不可达，应返回空树而不是死循环。
    const roots = buildDeckTree([deck(1, 3), deck(2, 1), deck(3, 2), deck(4, null, '根')])
    expect(roots.map(n => n.deck.id)).toEqual([4])
  })

  it('sorts with zh-CN numeric collation', () => {
    const roots = buildDeckTree([deck(1, null, '第10章'), deck(2, null, '第2章')])
    expect(roots.map(n => n.deck.title)).toEqual(['第2章', '第10章'])
  })

  it('matches category and description case-insensitively', () => {
    const roots = buildDeckTree([
      { ...deck(1, null, 'Java'), category: '后端' },
      { ...deck(2, null, '其他'), description: '关于 JVM 的笔记' }
    ])
    expect(filterDeckTree(roots, '后端').map(n => n.deck.id)).toEqual([1])
    expect(filterDeckTree(roots, 'jvm').map(n => n.deck.id)).toEqual([2])
  })

  it('returns the same tree for a blank query', () => {
    const roots = buildDeckTree([deck(1, null, 'A')])
    expect(filterDeckTree(roots, '   ')).toBe(roots)
  })

  it('dedupes descendants in a cycle', () => {
    expect([...descendantIds(1, [deck(1, null), deck(2, 1), deck(3, 2), { ...deck(1, 3), id: 4 }])]).toEqual([2, 3, 4])
  })
})
