<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{ value: number; max: number; tone?: 'indigo' | 'green' | 'orange' | 'red' }>(),
  { tone: 'indigo' }
)

const percent = computed(() => {
  if (props.max <= 0) return 0
  return Math.min(100, Math.max(0, (props.value / props.max) * 100))
})
</script>

<template>
  <div
    class="bar"
    role="progressbar"
    :aria-valuenow="value"
    aria-valuemin="0"
    :aria-valuemax="max"
  >
    <span
      class="fill"
      :class="`tone-${tone}`"
      :style="{ width: `${percent}%` }"
    />
  </div>
</template>

<style scoped>
.bar {
  width: 100%;
  height: 6px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--surface-muted);
}

.fill {
  display: block;
  height: 100%;
  border-radius: inherit;
  transition: width 0.4s ease-out;
}

.tone-indigo {
  background: linear-gradient(90deg, var(--color-indigo), var(--color-purple));
}

.tone-green {
  background: var(--color-green);
}

.tone-orange {
  background: var(--color-orange);
}

.tone-red {
  background: var(--color-red);
}
</style>
