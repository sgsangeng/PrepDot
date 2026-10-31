import type { Flashcard } from '@/core/api/types'

/** A plotted card plus its fixed position in the SVG viewBox coordinate space. */
export interface PlotPoint {
  card: Flashcard
  x: number
  y: number
}

type ReviewedCard = Flashcard & { difficulty: number; stability: number }

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value))
}

/**
 * 由 id 派生的确定性抖动（±6），把完全重合的点摊开。
 * 与 iOS KnowledgeGraphView.jitter 使用同一公式。
 */
function jitter(id: number): { x: number; y: number } {
  function hash(seed: number): number {
    const s = Math.sin(seed) * 43758.5453
    return s - Math.floor(s)
  }
  const jx = (hash(id * 12.9898) - 0.5) * 2
  const jy = (hash(id * 78.233) - 0.5) * 2
  return { x: jx * 6, y: jy * 6 }
}

/**
 * 掌握度颜色：浅粉（0）→ 深紫（100）。
 *
 * 项目约束要求颜色只来自设计 token，因此用 color-mix + var(--color-*)
 * 代替 iOS 的 rgb 公式；输出仍是纯字符串，可直接用作 SVG fill。
 */
export function scoreColor(score: number): string {
  const t = clamp01(score / 100)
  // 保留两位小数后再归一，避免 0.1 + 0.2 之类的浮点尾数让输出不稳定。
  const percent = Number((t * 100).toFixed(2))
  return `color-mix(in srgb, var(--color-pink), var(--color-indigo) ${percent}%)`
}

/**
 * 把卡片映射到固定 viewBox 坐标。
 *
 * - 只保留已有 FSRS 难度/稳定性的卡片（未复习过的不画）。
 * - X：难度 1..10 → padding..width-padding。
 * - Y：log10(稳定性) 按本批点的 min/max 归一化，高稳定性在上方。
 * - 抖动 ±6px 后再次夹紧，保证节点不出绘图区。
 */
export function buildPlot(
  cards: Flashcard[],
  width: number,
  height: number,
  padding: number
): PlotPoint[] {
  const reviewed = cards.filter(
    (card): card is ReviewedCard => card.difficulty !== null && card.stability !== null
  )
  if (reviewed.length === 0) return []

  const logs = reviewed.map(card => Math.log10(Math.max(card.stability, 0.01)))
  let minLog = Math.min(...logs)
  let maxLog = Math.max(...logs)
  // 所有点稳定性相同：给 ±0.5 的跨度，避免除以 0，并让它们落在中线附近。
  if (minLog === maxLog) {
    minLog -= 0.5
    maxLog += 0.5
  }
  const span = Math.max(maxLog - minLog, 0.001)

  const innerWidth = Math.max(width - padding * 2, 0)
  const innerHeight = Math.max(height - padding * 2, 0)
  const minX = padding
  const maxX = width - padding
  const minY = padding
  const maxY = height - padding

  return reviewed.map((card, index) => {
    const nx = clamp01((card.difficulty - 1) / 9)
    const ny = clamp01((logs[index] - minLog) / span)
    const offset = jitter(card.id)
    const x = padding + nx * innerWidth + offset.x
    const y = height - padding - ny * innerHeight + offset.y
    return {
      card,
      x: Math.min(maxX, Math.max(minX, x)),
      y: Math.min(maxY, Math.max(minY, y))
    }
  })
}
