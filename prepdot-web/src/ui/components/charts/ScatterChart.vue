<script setup lang="ts">
import { computed } from 'vue'
import type { Flashcard } from '@/core/api/types'
import { buildPlot, scoreColor, type PlotPoint } from '@/core/graph/plot'

/**
 * 掌握度散点图（对应 iOS KnowledgeGraphView.scatter）。
 *
 * 坐标在固定的 400×320 viewBox 内一次算好，再由 CSS 缩放；
 * 因此不依赖任何测量 API（ResizeObserver / getBoundingClientRect）。
 */
const WIDTH = 400
const HEIGHT = 320
const PADDING = 40
const INNER_WIDTH = WIDTH - PADDING * 2
const INNER_HEIGHT = HEIGHT - PADDING * 2

const props = defineProps<{
  cards: Flashcard[]
  selectedId: number | null
}>()

const emit = defineEmits<{ select: [id: number] }>()

const points = computed<PlotPoint[]>(() => buildPlot(props.cards, WIDTH, HEIGHT, PADDING))

/** 4×4 网格线（0..4），与 iOS 的 Canvas 网格一致。 */
const grid = [0, 1, 2, 3, 4].map(i => ({
  x: PADDING + (INNER_WIDTH * i) / 4,
  y: PADDING + (INNER_HEIGHT * i) / 4
}))

function isSelected(card: Flashcard): boolean {
  return props.selectedId === card.id
}

function toggle(id: number): void {
  emit('select', id)
}
</script>

<template>
  <svg
    class="scatter"
    :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
    role="group"
    :aria-label="`掌握度散点图，共 ${points.length} 张已复习卡片`"
  >
    <!-- 网格 -->
    <g
      class="grid"
      aria-hidden="true"
    >
      <line
        v-for="line in grid"
        :key="`v-${line.x}`"
        :x1="line.x"
        :y1="PADDING"
        :x2="line.x"
        :y2="HEIGHT - PADDING"
      />
      <line
        v-for="line in grid"
        :key="`h-${line.y}`"
        :x1="PADDING"
        :y1="line.y"
        :x2="WIDTH - PADDING"
        :y2="line.y"
      />
    </g>

    <!-- 坐标轴 -->
    <g
      class="axes"
      aria-hidden="true"
    >
      <line
        :x1="PADDING"
        :y1="HEIGHT - PADDING"
        :x2="WIDTH - PADDING"
        :y2="HEIGHT - PADDING"
      />
      <line
        :x1="PADDING"
        :y1="PADDING"
        :x2="PADDING"
        :y2="HEIGHT - PADDING"
      />
      <text
        class="axis-label"
        :x="WIDTH - PADDING - 20"
        :y="HEIGHT - PADDING + 14"
        text-anchor="middle"
      >难度 →</text>
      <text
        class="axis-label"
        :x="PADDING - 16"
        :y="HEIGHT / 2"
        text-anchor="middle"
        :transform="`rotate(-90 ${PADDING - 16} ${HEIGHT / 2})`"
      >稳定性 ↑</text>
    </g>

    <!-- 节点：可见圆保持 14/22px，透明命中圆保证 ≥44px 触控目标 -->
    <g
      v-for="point in points"
      :key="point.card.id"
      class="node"
      :class="{ selected: isSelected(point.card) }"
      tabindex="0"
      role="button"
      :aria-label="`${point.card.question}，掌握度 ${point.card.memoryScore}%`"
      :aria-pressed="isSelected(point.card)"
      @click="toggle(point.card.id)"
      @keydown.enter.prevent="toggle(point.card.id)"
      @keydown.space.prevent="toggle(point.card.id)"
    >
      <circle
        class="hit"
        :cx="point.x"
        :cy="point.y"
        r="22"
        fill="transparent"
      />
      <circle
        class="dot"
        :cx="point.x"
        :cy="point.y"
        :r="isSelected(point.card) ? 11 : 7"
        :fill="scoreColor(point.card.memoryScore)"
        :fill-opacity="isSelected(point.card) ? 1 : 0.72"
        :stroke="isSelected(point.card) ? 'var(--on-primary)' : 'none'"
        stroke-width="2"
      />
    </g>
  </svg>
</template>

<style scoped>
.scatter {
  display: block;
  width: 100%;
  height: min(60vh, 520px);
  overflow: visible;
}

.grid line {
  stroke: var(--border);
  stroke-width: 0.5;
}

.axes line {
  stroke: var(--text-tertiary);
  stroke-width: 1;
}

.axis-label {
  fill: var(--text-secondary);
  font-size: 11px;
}

.node {
  cursor: pointer;
  outline: none;
}

.node .hit {
  stroke: transparent;
}

.node:focus-visible .hit {
  stroke: var(--color-indigo);
  stroke-width: 2;
  stroke-dasharray: 4 3;
}

.node .dot {
  filter: drop-shadow(0 1px 3px color-mix(in srgb, var(--color-indigo) 22%, transparent));
  transition: r 0.15s ease, fill-opacity 0.15s ease;
}

.node.selected .dot {
  filter: drop-shadow(0 2px 8px color-mix(in srgb, var(--color-indigo) 45%, transparent));
}

@media (prefers-reduced-motion: reduce) {
  .node .dot {
    transition: none;
  }
}
</style>
