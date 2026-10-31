<script setup lang="ts">
withDefaults(
  defineProps<{ label: string; tone?: 'indigo' | 'orange' | 'teal' }>(),
  { tone: 'indigo' }
)
</script>

<template>
  <span
    class="type-badge"
    :class="`tone-${tone}`"
  >{{ label }}</span>
</template>

<style scoped>
.type-badge {
  display: inline-flex;
  flex: none;
  align-items: center;
  padding: 2px 7px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  line-height: 1.4;
  white-space: nowrap;
}

.tone-indigo {
  background: color-mix(in srgb, var(--color-indigo) 14%, transparent);
  color: var(--color-indigo);
}

.tone-orange {
  background: color-mix(in srgb, var(--color-orange) 16%, transparent);
  color: var(--color-orange);
}

.tone-teal {
  background: color-mix(in srgb, var(--color-teal) 16%, transparent);
  color: var(--color-teal);
}
</style>
