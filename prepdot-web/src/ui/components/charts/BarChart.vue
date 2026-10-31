<script setup lang="ts">
import { computed, useId } from 'vue'

/**
 * 极简柱状图，供学习教练的复习趋势与薄弱卡片图共用。
 *
 * - 默认（竖向）：indigo→purple 渐变柱，高度由 `height` 控制（默认 150，与 iOS 一致）。
 * - `horizontal`：横向条形图，数值按 0..100 定义域换算，行高 30px，
 *   总高度 `min(count, 8) * 30 + 30`，与 iOS 的薄弱卡片图一致；最多展示 8 行。
 *
 * 数据为空时不渲染任何内容（与 iOS 一致）。
 */
interface BarChartPoint {
  label: string
  value: number
}

const props = withDefaults(defineProps<{
  data: BarChartPoint[]
  /** 无障碍名称，同时作为图表标题。 */
  label: string
  horizontal?: boolean
  height?: number
}>(), {
  horizontal: false,
  height: 150
})

const instanceId = useId()
const gradientId = `bar-gradient-${instanceId}`

const visibleData = computed(() => props.horizontal ? props.data.slice(0, 8) : props.data)

const maxValue = computed(() => Math.max(1, ...visibleData.value.map(point => point.value)))

const verticalBars = computed(() => {
  const count = visibleData.value.length
  if (count === 0) return []
  const slot = 100 / count
  const width = Math.min(slot * 0.6, 24)
  return visibleData.value.map((point, index) => {
    const ratio = Math.min(1, Math.max(0, point.value / maxValue.value))
    return {
      x: index * slot + (slot - width) / 2,
      width,
      y: 100 - ratio * 100,
      height: ratio * 100
    }
  })
})

const horizontalRows = computed(() =>
  visibleData.value.map(point => ({
    ...point,
    percent: Math.min(100, Math.max(0, point.value))
  }))
)

const chartHeight = computed(() =>
  props.horizontal ? Math.min(props.data.length, 8) * 30 + 30 : props.height
)
</script>

<template>
  <div
    v-if="data.length > 0"
    class="chart-wrap"
  >
    <div
      class="chart"
      :class="{ horizontal }"
      :style="{ height: `${chartHeight}px` }"
      role="img"
      :aria-label="label"
    >
      <svg
        class="chart-defs"
        aria-hidden="true"
        focusable="false"
      >
        <defs>
          <linearGradient
            :id="gradientId"
            x1="0"
            y1="0"
            :x2="horizontal ? 1 : 0"
            :y2="horizontal ? 0 : 1"
          >
            <stop
              offset="0"
              class="stop-start"
            />
            <stop
              offset="1"
              class="stop-end"
            />
          </linearGradient>
        </defs>
      </svg>

      <template v-if="!horizontal">
        <svg
          class="v-chart"
          viewBox="0 0 100 100"
          preserveAspectRatio="none"
          aria-hidden="true"
          focusable="false"
        >
          <rect
            v-for="(bar, index) in verticalBars"
            :key="index"
            :x="bar.x"
            :y="bar.y"
            :width="bar.width"
            :height="bar.height"
            :fill="`url(#${gradientId})`"
          />
        </svg>
        <div
          class="v-labels"
          :style="{ gridTemplateColumns: `repeat(${visibleData.length}, minmax(0, 1fr))` }"
          aria-hidden="true"
        >
          <span
            v-for="(point, index) in visibleData"
            :key="index"
            class="axis-label"
          >{{ point.label }}</span>
        </div>
      </template>

      <div
        v-else
        class="h-rows"
      >
        <div
          v-for="(row, index) in horizontalRows"
          :key="index"
          class="h-row"
        >
          <span class="h-label">{{ row.label }}</span>
          <svg
            class="h-track"
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            aria-hidden="true"
            focusable="false"
          >
            <rect
              class="h-bg"
              x="0"
              y="0"
              width="100"
              height="100"
            />
            <rect
              y="0"
              :width="row.percent"
              height="100"
              :fill="`url(#${gradientId})`"
            />
          </svg>
          <span class="h-value">{{ row.value }}</span>
        </div>
      </div>
    </div>

    <table class="sr-only">
      <caption>{{ label }}</caption>
      <thead>
        <tr>
          <th scope="col">
            项目
          </th>
          <th scope="col">
            数值
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(point, index) in visibleData"
          :key="index"
        >
          <th scope="row">
            {{ point.label }}
          </th>
          <td>{{ point.value }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.chart-wrap {
  width: 100%;
}

.chart {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 6px;
  width: 100%;
}

.chart-defs {
  position: absolute;
  width: 0;
  height: 0;
  overflow: hidden;
}

.stop-start {
  stop-color: var(--color-indigo);
}

.stop-end {
  stop-color: var(--color-purple);
}

.v-chart {
  display: block;
  flex: 1;
  width: 100%;
  min-height: 0;
}

.v-labels {
  display: grid;
  flex: none;
  gap: 2px;
  height: 16px;
}

.axis-label {
  overflow: hidden;
  color: var(--text-tertiary);
  font-size: 9px;
  line-height: 16px;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.h-rows {
  display: flex;
  flex: 1;
  flex-direction: column;
  justify-content: center;
  min-height: 0;
}

.h-row {
  display: grid;
  grid-template-columns: 104px minmax(0, 1fr) 34px;
  align-items: center;
  gap: 8px;
  height: 30px;
}

.h-label {
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 10px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.h-track {
  display: block;
  width: 100%;
  height: 16px;
  overflow: hidden;
  border-radius: 4px;
}

.h-bg {
  fill: var(--surface-muted);
}

.h-value {
  color: var(--text-tertiary);
  font-size: 10px;
  font-variant-numeric: tabular-nums;
  text-align: right;
}
</style>
