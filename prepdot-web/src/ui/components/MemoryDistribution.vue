<script setup lang="ts">
import { computed } from 'vue'

/**
 * 记忆度分布：单条胶囊按比例分三段（粉 / 紫 / indigo），
 * 下方图例展示 待加强 / 进行中 / 已掌握 的数量。
 * 计数为 0 的分段不渲染（避免出现 2px 的空隙段）。
 */
const props = defineProps<{ low: number; mid: number; high: number }>()

interface Segment {
  key: 'low' | 'mid' | 'high'
  label: string
  count: number
}

const segments = computed<Segment[]>(() => [
  { key: 'low', label: '待加强', count: props.low },
  { key: 'mid', label: '进行中', count: props.mid },
  { key: 'high', label: '已掌握', count: props.high }
])

const visibleSegments = computed(() => segments.value.filter(segment => segment.count > 0))

const summary = computed(() =>
  segments.value.map(segment => `${segment.label} ${segment.count} 张`).join('，')
)
</script>

<template>
  <section class="memory-card">
    <h2 class="card-title">
      记忆度分布
    </h2>

    <div
      class="bar"
      role="img"
      :aria-label="`记忆度分布：${summary}`"
    >
      <span
        v-for="segment in visibleSegments"
        :key="segment.key"
        class="segment"
        :class="`seg-${segment.key}`"
        :style="{ flexGrow: segment.count }"
      />
    </div>

    <ul class="legend">
      <li
        v-for="segment in segments"
        :key="segment.key"
        class="legend-item"
      >
        <span
          class="dot"
          :class="`seg-${segment.key}`"
          aria-hidden="true"
        />
        <span>{{ segment.label }} {{ segment.count }}</span>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.memory-card {
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.card-title {
  margin-bottom: 14px;
  font-size: 16px;
  font-weight: 700;
}

.bar {
  display: flex;
  gap: 2px;
  height: 14px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--surface-muted);
}

.segment {
  flex-basis: 0;
  min-width: 0;
}

.seg-low {
  background: color-mix(in srgb, var(--color-pink) 32%, var(--on-primary));
}

.seg-mid {
  background: color-mix(in srgb, var(--color-purple) 55%, var(--on-primary));
}

.seg-high {
  background: var(--color-indigo);
}

.legend {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 20px;
  margin: 14px 0 0;
  padding: 0;
  list-style: none;
}

.legend-item {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: var(--text-secondary);
  font-size: 12px;
}

.dot {
  display: block;
  width: 12px;
  height: 12px;
  border-radius: 3px;
}
</style>
