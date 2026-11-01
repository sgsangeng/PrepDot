import type { Deck } from '@/core/api/types'

/** 知识树节点：`children` 始终为数组，便于递归渲染与过滤。 */
export interface DeckNode {
  deck: Deck
  children: DeckNode[]
}

const collator = new Intl.Collator('zh-CN', { numeric: true, sensitivity: 'variant' })

/** 按中文拼音/数字自然顺序比较标题。 */
export function compareDeckTitle(a: string, b: string): number {
  return collator.compare(a, b)
}

function sortDecks(decks: Deck[]): Deck[] {
  return [...decks].sort((a, b) => compareDeckTitle(a.title, b.title))
}

/**
 * 把扁平卡组列表组装成知识树。
 *
 * - 根节点：`parentId` 为空，或父节点不在列表中（脏数据）。
 * - 循环保护：沿当前分支记录祖先 id，绝不会重复进入同一节点。
 * - 完全由内部节点组成的环（没有任何可达根）会被整组忽略。
 * - 根与子节点均按 zh-CN locale（数字感知）排序。
 */
export function buildDeckTree(decks: Deck[]): DeckNode[] {
  const knownIds = new Set(decks.map(deck => deck.id))
  const childrenByParent = new Map<number, Deck[]>()

  for (const deck of decks) {
    if (deck.parentId == null) continue
    const siblings = childrenByParent.get(deck.parentId)
    if (siblings) siblings.push(deck)
    else childrenByParent.set(deck.parentId, [deck])
  }

  function build(deck: Deck, ancestors: ReadonlySet<number>): DeckNode {
    const nextAncestors = new Set(ancestors)
    nextAncestors.add(deck.id)
    const children = sortDecks(
      (childrenByParent.get(deck.id) ?? []).filter(child => !nextAncestors.has(child.id))
    ).map(child => build(child, nextAncestors))
    return { deck, children }
  }

  const roots = decks.filter(deck => deck.parentId == null || !knownIds.has(deck.parentId))
  return sortDecks(roots).map(deck => build(deck, new Set()))
}

/** 查询为空时原样返回，便于保持展开状态与引用稳定。 */
export function filterDeckTree(nodes: DeckNode[], query: string): DeckNode[] {
  const keyword = query.trim().toLocaleLowerCase('zh-CN')
  if (keyword === '') return nodes

  function matches(deck: Deck): boolean {
    return deck.title.toLocaleLowerCase('zh-CN').includes(keyword)
      || deck.category.toLocaleLowerCase('zh-CN').includes(keyword)
      || (deck.description?.toLocaleLowerCase('zh-CN').includes(keyword) ?? false)
  }

  function filter(nodes: DeckNode[]): DeckNode[] {
    const result: DeckNode[] = []
    for (const node of nodes) {
      const children = filter(node.children)
      if (matches(node.deck) || children.length > 0) {
        result.push({ deck: node.deck, children })
      }
    }
    return result
  }

  return filter(nodes)
}

/**
 * 收集某个卡组的全部后代 id（BFS，去重，不含自身）。
 * 只依赖 `parentId`，因此即使数据成环也能终止。
 */
export function descendantIds(rootId: number, decks: Deck[]): Set<number> {
  const childrenByParent = new Map<number, number[]>()
  for (const deck of decks) {
    if (deck.parentId == null) continue
    const siblings = childrenByParent.get(deck.parentId)
    if (siblings) siblings.push(deck.id)
    else childrenByParent.set(deck.parentId, [deck.id])
  }

  const result = new Set<number>()
  const queue = [...(childrenByParent.get(rootId) ?? [])]
  for (let index = 0; index < queue.length; index += 1) {
    const id = queue[index]
    if (id === rootId || result.has(id)) continue
    result.add(id)
    queue.push(...(childrenByParent.get(id) ?? []))
  }
  return result
}
