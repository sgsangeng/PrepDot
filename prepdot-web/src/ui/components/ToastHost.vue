<script setup lang="ts">
import { useToastStore } from '@/ui/stores/toast'

const toast = useToastStore()
</script>

<template>
  <Teleport to="body">
    <Transition name="toast">
      <div
        v-if="toast.visible"
        class="toast-host"
        role="status"
        aria-live="polite"
      >
        <div class="toast">
          {{ toast.message }}
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: opacity 0.2s ease, transform 0.2s ease;
}

.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, 8px);
}
</style>
