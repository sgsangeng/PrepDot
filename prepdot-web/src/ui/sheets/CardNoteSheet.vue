<script setup lang="ts">
/* global HTMLElement */
import { computed, ref } from 'vue'
import { X } from 'lucide-vue-next'
import type { Flashcard } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useDialogFocus } from '@/ui/composables/useDialogFocus'

const props = defineProps<{ card: Flashcard }>()
const emit = defineEmits<{ saved: [card: Flashcard]; close: [] }>()

const text = ref(props.card.note ?? '')
const saving = ref(false)
const saveError = ref('')
const panelEl = ref<HTMLElement | null>(null)

const hasText = computed(() => text.value.trim().length > 0)

function close(): void {
  if (saving.value) return
  emit('close')
}

async function save(): Promise<void> {
  if (saving.value) return
  saving.value = true
  saveError.value = ''
  try {
    const updated = await getRuntime().endpoints.updateCardNote(props.card.id, text.value)
    emit('saved', updated)
    emit('close')
  } catch (e) {
    saveError.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

useDialogFocus(panelEl, { onClose: close })</script>

<template>
  <Teleport to="body">
    <div
      class="sheet-backdrop"
      @click.self="close"
    >
      <div
        ref="panelEl"
        class="sheet-panel note-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="note-title"
        tabindex="-1"
      >
        <header class="sheet-head">
          <h2
            id="note-title"
            class="sheet-title"
          >
            卡片笔记
          </h2>
          <button
            class="icon-btn"
            type="button"
            aria-label="关闭"
            @click="close"
          >
            <X
              :size="20"
              aria-hidden="true"
            />
          </button>
        </header>

        <p class="muted sheet-hint">
          写给自己看的复习笔记，不会改动卡片的原始问题/答案。
        </p>

        <textarea
          v-model="text"
          class="textarea note-input"
          placeholder="记录你的理解、易错点或联想…"
          aria-label="卡片笔记"
        />

        <div class="note-meta">
          <button
            v-if="hasText"
            class="link-btn"
            type="button"
            @click="text = ''"
          >
            清空
          </button>
          <span class="tiny num">{{ text.length }} 字</span>
        </div>

        <p
          v-if="saveError"
          class="form-error"
          role="alert"
        >
          {{ saveError }}
        </p>

        <footer class="sheet-actions">
          <button
            class="btn btn-ghost"
            type="button"
            :disabled="saving"
            @click="close"
          >
            取消
          </button>
          <button
            class="btn btn-primary"
            type="button"
            :disabled="saving"
            @click="save"
          >
            {{ saving ? '保存中…' : '保存' }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.note-panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.note-panel:focus {
  outline: none;
}

.sheet-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.sheet-title {
  font-size: 18px;
  font-weight: 700;
}

.sheet-hint {
  font-size: 13px;
  line-height: 1.5;
}

.note-input {
  min-height: 220px;
  line-height: 1.6;
}

.note-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 24px;
}

.link-btn {
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
}

.icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
}

.icon-btn:hover {
  background: var(--surface-muted);
}

.form-error {
  padding: 10px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red-text);
  font-size: 14px;
}

.sheet-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-top: 4px;
}
</style>
