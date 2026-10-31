<script setup lang="ts">
import { computed, useId } from 'vue'

const props = withDefaults(
  defineProps<{ value: number; max: number; percent?: number; size?: number }>(),
  { percent: undefined, size: 190 }
)

const gradientId = `progress-ring-${useId()}`
const strokeWidth = 12

const percent = computed(() => {
  const raw = props.percent ?? (props.max > 0 ? (props.value / props.max) * 100 : 0)
  // 与 iOS 一致向下取整；圆弧和文字使用同一个百分比，避免 0% 时仍画出圆点。
  return Math.floor(Math.min(100, Math.max(0, raw)))
})
const radius = computed(() => (props.size - strokeWidth) / 2)
const circumference = computed(() => 2 * Math.PI * radius.value)
const dash = computed(() => (percent.value / 100) * circumference.value)
</script>

<template>
  <div
    class="ring"
    :style="{ width: `${size}px`, height: `${size}px` }"
    role="img"
    :aria-label="`今日复习进度 ${percent}%`"
  >
    <svg
      class="ring-svg"
      :viewBox="`0 0 ${size} ${size}`"
      aria-hidden="true"
    >
      <defs>
        <linearGradient
          :id="gradientId"
          x1="0%"
          y1="0%"
          x2="100%"
          y2="100%"
        >
          <stop
            offset="0%"
            style="stop-color: var(--color-indigo)"
          />
          <stop
            offset="55%"
            style="stop-color: var(--color-purple)"
          />
          <stop
            offset="100%"
            style="stop-color: var(--color-pink)"
          />
        </linearGradient>
      </defs>
      <circle
        class="track"
        :cx="size / 2"
        :cy="size / 2"
        :r="radius"
        :stroke-width="strokeWidth"
        fill="none"
      />
      <circle
        v-if="percent > 0"
        class="value"
        :cx="size / 2"
        :cy="size / 2"
        :r="radius"
        :stroke-width="strokeWidth"
        fill="none"
        :stroke="`url(#${gradientId})`"
        :stroke-dasharray="`${dash} ${circumference}`"
        stroke-linecap="round"
        :transform="`rotate(-90 ${size / 2} ${size / 2})`"
      />
    </svg>
    <div class="center">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.ring {
  position: relative;
  flex: none;
}

.ring-svg {
  display: block;
  width: 100%;
  height: 100%;
}

.track {
  stroke: color-mix(in srgb, var(--text) 10%, transparent);
}

.value {
  transition: stroke-dasharray 0.8s ease-out;
}

.center {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  text-align: center;
}
</style>
