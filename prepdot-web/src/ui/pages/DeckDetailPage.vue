<script setup lang="ts">
import EmptyState from '@/ui/components/EmptyState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'

defineProps<{ deckId?: number | null }>()
</script>

<template>
  <section class="detail-placeholder">
    <LoadingState
      v-if="deckId != null"
      text="正在加载卡片…"
    />
    <EmptyState
      v-else
      title="选择节点"
      text="从知识树中选择节点查看卡片"
    />
  </section>
</template>

<style scoped>
.detail-placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 320px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}
</style>
