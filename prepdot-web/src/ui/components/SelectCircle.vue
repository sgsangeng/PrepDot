<script setup lang="ts">
import { CheckCircle2, Circle } from 'lucide-vue-next'

withDefaults(defineProps<{ selected: boolean; size?: number }>(), { size: 22 })
</script>

<template>
  <span
    class="select-circle"
    :class="{ selected }"
    aria-hidden="true"
  >
    <CheckCircle2
      v-if="selected"
      :size="size"
      class="check"
    />
    <Circle
      v-else
      :size="size"
      class="idle"
    />
  </span>
</template>

<style scoped>
.select-circle {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  color: var(--text-tertiary);
  transition: color 0.15s ease;
}

.select-circle.selected {
  color: var(--color-indigo);
}
</style>
