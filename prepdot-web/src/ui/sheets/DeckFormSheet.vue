<script setup lang="ts">
/* global HTMLElement */
import { computed, ref } from 'vue'
import { X } from 'lucide-vue-next'
import type { Deck, DeckPayload } from '@/core/api/types'
import { buildDeckTree, descendantIds, type DeckNode } from '@/core/decks/tree'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useDialogFocus } from '@/ui/composables/useDialogFocus'

const props = defineProps<{ deck?: Deck; decks: Deck[] }>()
const emit = defineEmits<{ saved: [deck: Deck]; close: [] }>()

const isEdit = computed(() => props.deck !== undefined)
const title = ref(props.deck?.title ?? '')
const category = ref(props.deck?.category || '综合')
const description = ref(props.deck?.description ?? '')
const parentId = ref<number | null>(props.deck?.parentId ?? null)
const saving = ref(false)
const saveError = ref('')
const panelEl = ref<HTMLElement | null>(null)

function flatten(nodes: DeckNode[]): Deck[] {
  const result: Deck[] = []
  const walk = (items: DeckNode[]): void => {
    for (const item of items) {
      result.push(item.deck)
      walk(item.children)
    }
  }
  walk(nodes)
  return result
}

/** 根节点 + 深度 < 2 的卡组；编辑时排除自身与后代，并保证移动后仍不超过三级。 */
const parentCandidates = computed(() => {
  const ordered = flatten(buildDeckTree(props.decks))
  const current = props.deck
  if (!current) return ordered.filter(item => item.depth < 2)

  const descendants = descendantIds(current.id, props.decks)
  const maxRelativeDepth = props.decks
    .filter(item => descendants.has(item.id))
    .reduce((max, item) => Math.max(max, item.depth - current.depth), 0)

  return ordered.filter(item =>
    item.id !== current.id
    && !descendants.has(item.id)
    && item.depth + 1 + maxRelativeDepth <= 2
  )
})

const canSave = computed(() => title.value.trim().length > 0 && !saving.value)

function optionLabel(deck: Deck): string {
  return `${'　'.repeat(Math.max(0, deck.depth))}${deck.title}`
}

function close(): void {
  if (saving.value) return
  emit('close')
}

async function save(): Promise<void> {
  if (!canSave.value) return
  saving.value = true
  saveError.value = ''
  const trimmedCategory = category.value.trim() || '综合'
  const trimmedTitle = title.value.trim()
  const trimmedDescription = description.value.trim()

  try {
    const endpoints = getRuntime().endpoints
    const body: DeckPayload = {
      title: trimmedTitle,
      category: trimmedCategory,
      description: trimmedDescription === '' ? null : trimmedDescription
    }

    if (props.deck) {
      let result = await endpoints.updateDeck(props.deck.id, body)
      if (parentId.value !== (props.deck.parentId ?? null)) {
        result = await endpoints.moveDeck(props.deck.id, parentId.value)
      }
      emit('saved', result)
    } else {
      const created = await endpoints.createDeck({ ...body, parentId: parentId.value })
      emit('saved', created)
    }
    emit('close')
  } catch (e) {
    saveError.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

useDialogFocus(panelEl, { onClose: close })
</script>

<template>
  <Teleport to="body">
    <div
      class="sheet-backdrop"
      @click.self="close"
    >
      <div
        ref="panelEl"
        class="sheet-panel form-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="deck-form-title"
        tabindex="-1"
      >
        <header class="sheet-head">
          <h2
            id="deck-form-title"
            class="sheet-title"
          >
            {{ isEdit ? '编辑卡组' : '新建卡组' }}
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

        <label
          class="label"
          for="deck-title"
        >卡组名称（必填）</label>
        <input
          id="deck-title"
          v-model="title"
          class="input"
          type="text"
          placeholder="例如：Java 基础"
          maxlength="80"
        >

        <label
          class="label"
          for="deck-category"
        >分类</label>
        <input
          id="deck-category"
          v-model="category"
          class="input"
          type="text"
          placeholder="综合"
          maxlength="40"
        >

        <label
          class="label"
          for="deck-description"
        >描述（可选）</label>
        <textarea
          id="deck-description"
          v-model="description"
          class="textarea"
          placeholder="简单描述这个卡组"
          maxlength="500"
        />

        <label
          class="label"
          for="deck-parent"
        >父节点</label>
        <select
          id="deck-parent"
          v-model="parentId"
          class="select"
        >
          <option :value="null">
            根节点
          </option>
          <option
            v-for="candidate in parentCandidates"
            :key="candidate.id"
            :value="candidate.id"
          >
            {{ optionLabel(candidate) }}
          </option>
        </select>
        <p class="tiny">
          知识树最多三级：可选择根节点或前两级卡组作为父节点。
        </p>

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
            :disabled="!canSave"
            @click="save"
          >
            {{ saving ? '保存中…' : isEdit ? '保存' : '创建' }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.form-panel {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.form-panel:focus {
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

.form-panel .label {
  margin-bottom: 0;
}

.form-panel .textarea {
  min-height: 96px;
}

.form-error {
  padding: 10px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red);
  font-size: 14px;
  overflow-wrap: anywhere;
}

.sheet-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-top: 6px;
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

.form-panel :focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}
</style>
