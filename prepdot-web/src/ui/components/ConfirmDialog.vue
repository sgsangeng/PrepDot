<script setup lang="ts">
/* global HTMLElement, HTMLButtonElement */
import { computed, ref, useId } from 'vue'
import { TriangleAlert } from 'lucide-vue-next'
import { useDialogFocus } from '@/ui/composables/useDialogFocus'

const props = withDefaults(
  defineProps<{
    title: string
    message: string
    confirmText?: string
    cancelText?: string
    danger?: boolean
    busy?: boolean
    error?: string
  }>(),
  {
    confirmText: '确定',
    cancelText: '取消',
    danger: true,
    busy: false,
    error: ''
  }
)

const emit = defineEmits<{ confirm: []; cancel: [] }>()

const titleId = useId()
const messageId = useId()
const panel = ref<HTMLElement | null>(null)
const cancelButton = ref<HTMLButtonElement | null>(null)

const busy = computed(() => props.busy)

function cancel(): void {
  if (!busy.value) emit('cancel')
}

function confirm(): void {
  if (!busy.value) emit('confirm')
}

/** 打开时优先聚焦取消按钮；按钮不可用时退回面板本身。 */
function initialFocus(): HTMLElement | null {
  const button = cancelButton.value
  return button && !button.disabled ? button : panel.value
}

useDialogFocus(panel, { onClose: cancel, initialFocus })
</script>

<template>
  <Teleport to="body">
    <div
      class="confirm-backdrop"
      @click.self="cancel"
    >
      <div
        ref="panel"
        class="confirm-panel"
        role="alertdialog"
        aria-modal="true"
        :aria-labelledby="titleId"
        :aria-describedby="messageId"
        tabindex="-1"
      >
        <div class="confirm-head">
          <span
            class="confirm-icon"
            :class="{ danger }"
            aria-hidden="true"
          >
            <TriangleAlert :size="20" />
          </span>
          <h2
            :id="titleId"
            class="confirm-title"
          >
            {{ title }}
          </h2>
        </div>

        <p
          :id="messageId"
          class="confirm-message"
        >
          {{ message }}
        </p>

        <p
          v-if="error"
          class="confirm-error"
          role="alert"
        >
          {{ error }}
        </p>

        <div class="confirm-actions">
          <button
            ref="cancelButton"
            class="btn btn-ghost"
            type="button"
            :disabled="busy"
            @click="cancel"
          >
            {{ cancelText }}
          </button>
          <button
            class="btn"
            :class="danger ? 'btn-danger' : 'btn-primary'"
            type="button"
            :disabled="busy"
            @click="confirm"
          >
            {{ busy ? '处理中…' : confirmText }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.confirm-backdrop {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  background: var(--overlay);
}

.confirm-panel {
  width: min(100%, 360px);
  padding: 20px;
  border-radius: var(--radius-lg);
  background: var(--surface);
  box-shadow: var(--shadow-lg);
}

.confirm-panel:focus {
  outline: none;
}

.confirm-head {
  display: flex;
  align-items: center;
  gap: 10px;
}

.confirm-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: var(--surface-muted);
  color: var(--text-secondary);
}

.confirm-icon.danger {
  background: color-mix(in srgb, var(--color-red) 14%, transparent);
  color: var(--color-red);
}

.confirm-title {
  font-size: 17px;
  font-weight: 700;
}

.confirm-message {
  margin-top: 12px;
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.6;
  overflow-wrap: anywhere;
}

.confirm-error {
  margin-top: 12px;
  padding: 10px 12px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red);
  font-size: 13px;
  overflow-wrap: anywhere;
}

.confirm-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 20px;
}

.confirm-panel :focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}
</style>
