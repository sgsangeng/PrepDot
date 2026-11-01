<script setup lang="ts">
withDefaults(
  defineProps<{ message: string; title?: string; retryText?: string; showRetry?: boolean }>(),
  { title: '出错了', retryText: '重试', showRetry: false }
)

const emit = defineEmits<{ retry: [] }>()
</script>

<template>
  <div
    class="state"
    role="alert"
  >
    <h3 class="title">
      {{ title }}
    </h3>
    <p class="muted">
      {{ message }}
    </p>
    <button
      v-if="showRetry"
      class="btn btn-ghost"
      type="button"
      @click="emit('retry')"
    >
      {{ retryText }}
    </button>
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
  color: var(--color-red-text);
  font-size: 16px;
}
</style>
