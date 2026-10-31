<script setup lang="ts">
withDefaults(defineProps<{ title: string; text?: string }>(), { text: '' })
</script>

<template>
  <div class="state">
    <h3 class="title">
      {{ title }}
    </h3>
    <p
      v-if="text"
      class="muted"
    >
      {{ text }}
    </p>
    <slot />
  </div>
</template>

<style scoped>
.state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  min-height: 180px;
  padding: 24px;
  text-align: center;
}

.title {
  color: var(--text-secondary);
  font-size: 16px;
}
</style>
