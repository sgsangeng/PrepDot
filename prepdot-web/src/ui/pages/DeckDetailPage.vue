<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  CheckCheck,
  ChevronRight,
  ListChecks,
  Plus,
  Trash2,
  X
} from 'lucide-vue-next'
import CardRow from '@/ui/components/CardRow.vue'
import ConfirmDialog from '@/ui/components/ConfirmDialog.vue'
import DeckRow from '@/ui/components/DeckRow.vue'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import CardFormSheet from '@/ui/sheets/CardFormSheet.vue'
import type { Deck, Flashcard } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useToastStore } from '@/ui/stores/toast'

const props = defineProps<{ deckId?: number | null }>()

const router = useRouter()
const toast = useToastStore()

const decks = ref<Deck[]>([])
const cards = ref<Flashcard[]>([])
const loading = ref(false)
const loadError = ref('')
const missing = ref(false)

const isManaging = ref(false)
const selectedIds = ref<Set<number>>(new Set())

const showForm = ref(false)
const editingCard = ref<Flashcard | null>(null)

const pendingDelete = ref<{ ids: number[] } | null>(null)
const deleting = ref(false)
const deleteError = ref('')

let loadSeq = 0

const deck = computed<Deck | null>(() => {
  if (props.deckId == null) return null
  return decks.value.find(item => item.id === props.deckId) ?? null
})
const childDecks = computed(() =>
  props.deckId == null ? [] : decks.value.filter(item => item.parentId === props.deckId)
)
const isLeaf = computed(() => childDecks.value.length === 0)

const selectedCount = computed(() => selectedIds.value.size)
const allSelected = computed(() => cards.value.length > 0 && selectedIds.value.size === cards.value.length)
const quizEligible = computed(() => isLeaf.value && cards.value.length >= 2 && !isManaging.value)
const canManage = computed(() => isLeaf.value && (cards.value.length > 0 || isManaging.value))

const pendingIds = computed(() => pendingDelete.value?.ids ?? [])
const deleteTitle = computed(() =>
  pendingIds.value.length > 1 ? `删除所选的 ${pendingIds.value.length} 张卡片？` : '删除这张卡片？'
)
const deleteMessage = computed(() =>
  pendingIds.value.length > 1
    ? '删除后这些卡片将无法恢复。'
    : '删除后该卡片将无法恢复。'
)

/** 只接受最新一次请求，避免快速切换卡组时旧响应覆盖新数据。 */
async function load(showLoading = true): Promise<void> {
  const id = props.deckId
  const seq = ++loadSeq
  if (id == null) {
    decks.value = []
    cards.value = []
    loadError.value = ''
    missing.value = false
    loading.value = false
    return
  }
  if (showLoading) loading.value = true
  loadError.value = ''
  missing.value = false
  try {
    const [deckList, cardList] = await Promise.all([
      getRuntime().endpoints.decks(),
      getRuntime().endpoints.cards(id, false)
    ])
    if (seq !== loadSeq) return
    decks.value = deckList
    cards.value = cardList
    missing.value = !deckList.some(item => item.id === id)
    const valid = new Set(cardList.map(card => card.id))
    selectedIds.value = new Set([...selectedIds.value].filter(cardId => valid.has(cardId)))
  } catch (e) {
    if (seq !== loadSeq) return
    loadError.value = friendlyError(e)
  } finally {
    if (seq === loadSeq) loading.value = false
  }
}

function resetInteractions(): void {
  isManaging.value = false
  selectedIds.value = new Set()
  showForm.value = false
  editingCard.value = null
  pendingDelete.value = null
  deleteError.value = ''
}

watch(
  () => props.deckId,
  () => {
    resetInteractions()
    cards.value = []
    void load()
  },
  { immediate: true }
)

function openChild(child: Deck): void {
  void router.push({ name: 'decks', params: { id: String(child.id) } })
}

function goQuiz(): void {
  if (props.deckId == null) return
  void router.push({ name: 'quiz', params: { id: String(props.deckId) } })
}

function openCreate(): void {
  editingCard.value = null
  showForm.value = true
}

function onCardActivate(card: Flashcard): void {
  if (isManaging.value) {
    toggleSelected(card.id)
    return
  }
  editingCard.value = card
  showForm.value = true
}

function toggleSelected(id: number): void {
  const next = new Set(selectedIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  selectedIds.value = next
}

function toggleManage(): void {
  isManaging.value = !isManaging.value
  if (!isManaging.value) selectedIds.value = new Set()
}

function toggleSelectAll(): void {
  selectedIds.value = allSelected.value
    ? new Set()
    : new Set(cards.value.map(card => card.id))
}

function askDelete(card: Flashcard): void {
  deleteError.value = ''
  pendingDelete.value = { ids: [card.id] }
}

function askBatchDelete(): void {
  if (selectedIds.value.size === 0) return
  deleteError.value = ''
  pendingDelete.value = { ids: [...selectedIds.value] }
}

function cancelDelete(): void {
  if (deleting.value) return
  pendingDelete.value = null
  deleteError.value = ''
}

async function confirmDelete(): Promise<void> {
  const pending = pendingDelete.value
  if (!pending || deleting.value) return
  deleting.value = true
  deleteError.value = ''
  try {
    const endpoints = getRuntime().endpoints
    if (pending.ids.length === 1) await endpoints.deleteCard(pending.ids[0])
    else await endpoints.deleteCards(pending.ids)
    const removed = new Set(pending.ids)
    cards.value = cards.value.filter(card => !removed.has(card.id))
    selectedIds.value = new Set([...selectedIds.value].filter(cardId => !removed.has(cardId)))
    pendingDelete.value = null
    if (pending.ids.length > 1) {
      isManaging.value = false
      toast.show(`已删除 ${pending.ids.length} 张卡片`)
    } else {
      toast.show('已删除卡片')
    }
  } catch (e) {
    deleteError.value = friendlyError(e)
  } finally {
    deleting.value = false
  }
}

function onSaved(): void {
  showForm.value = false
  editingCard.value = null
  // 后台刷新，保留现有列表避免闪烁，同时同步后端生成的字段与排序。
  void load(false)
}

function closeForm(): void {
  showForm.value = false
  editingCard.value = null
}
</script>

<template>
  <section class="deck-detail">
    <div
      v-if="deckId == null"
      class="state-card"
    >
      <EmptyState
        title="选择节点"
        text="从知识树中选择节点查看卡片"
      />
    </div>

    <div
      v-else-if="loading"
      class="state-card"
    >
      <LoadingState text="正在加载卡片…" />
    </div>

    <div
      v-else-if="loadError"
      class="state-card"
    >
      <ErrorState
        title="卡片加载失败"
        :message="loadError"
        retry-text="重新加载"
        show-retry
        @retry="load()"
      />
    </div>

    <div
      v-else-if="missing || !deck"
      class="state-card"
    >
      <ErrorState
        title="卡组不存在"
        message="该卡组可能已被删除，请刷新后重试。"
        retry-text="刷新"
        show-retry
        @retry="load()"
      />
    </div>

    <template v-else>
      <header class="detail-head">
        <div class="title-block">
          <div class="title-line">
            <h2 class="deck-title">
              {{ deck.title }}
            </h2>
            <span class="category-pill">{{ deck.category }}</span>
          </div>
          <p
            v-if="isLeaf"
            class="deck-sub"
          >
            {{ cards.length }} 张卡片 · 记忆度 {{ deck.avgMemoryScore }}%
          </p>
        </div>

        <div class="head-actions">
          <button
            v-if="quizEligible"
            class="btn btn-ghost head-btn quiz-btn"
            type="button"
            @click="goQuiz"
          >
            <ListChecks
              :size="17"
              aria-hidden="true"
            />
            <span>测验</span>
          </button>
          <button
            v-if="canManage"
            class="btn btn-ghost head-btn"
            :class="{ 'manage-active': isManaging }"
            type="button"
            @click="toggleManage"
          >
            {{ isManaging ? '完成' : '管理' }}
          </button>
        </div>
      </header>

      <div class="detail-body">
        <ul
          v-if="!isLeaf"
          class="child-list"
          aria-label="子卡组"
        >
          <li
            v-for="child in childDecks"
            :key="child.id"
          >
            <button
              class="child-btn"
              type="button"
              @click="openChild(child)"
            >
              <DeckRow
                class="child-deck"
                :deck="child"
              />
              <ChevronRight
                :size="18"
                class="chevron"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>

        <template v-else>
          <div
            v-if="isManaging"
            class="select-bar"
          >
            <button
              class="btn btn-ghost btn-sm"
              type="button"
              :disabled="cards.length === 0"
              @click="toggleSelectAll"
            >
              <X
                v-if="allSelected"
                :size="16"
                aria-hidden="true"
              />
              <CheckCheck
                v-else
                :size="16"
                aria-hidden="true"
              />
              {{ allSelected ? '取消全选' : `全选（${cards.length}）` }}
            </button>
            <span
              class="select-count"
              aria-live="polite"
            >已选 {{ selectedCount }} 张</span>
          </div>

          <EmptyState
            v-if="cards.length === 0"
            title="还没有卡片"
            text="点击下方按钮添加第一张卡片"
          />

          <ul
            v-else
            class="card-list"
            aria-label="卡片列表"
          >
            <li
              v-for="card in cards"
              :key="card.id"
              class="card-item"
            >
              <CardRow
                :card="card"
                :managing="isManaging"
                :selected="selectedIds.has(card.id)"
                @activate="onCardActivate(card)"
              />
              <button
                v-if="!isManaging"
                class="card-delete"
                type="button"
                :aria-label="`删除卡片：${card.question}`"
                @click="askDelete(card)"
              >
                <Trash2
                  :size="16"
                  aria-hidden="true"
                />
              </button>
            </li>
          </ul>
        </template>
      </div>

      <footer class="detail-actions">
        <button
          v-if="isManaging"
          class="btn btn-danger action-btn batch-btn"
          type="button"
          :disabled="selectedCount === 0 || deleting"
          @click="askBatchDelete"
        >
          <Trash2
            :size="18"
            aria-hidden="true"
          />
          删除所选（{{ selectedCount }}）
        </button>
        <button
          v-else
          class="btn btn-primary action-btn add-card-btn"
          type="button"
          @click="openCreate"
        >
          <Plus
            :size="18"
            aria-hidden="true"
          />
          添加卡片
        </button>
      </footer>
    </template>

    <CardFormSheet
      v-if="showForm && deck"
      :key="editingCard?.id ?? 'new'"
      :deck-id="deck.id"
      :card="editingCard ?? undefined"
      @saved="onSaved"
      @close="closeForm"
    />

    <ConfirmDialog
      v-if="pendingDelete"
      :title="deleteTitle"
      :message="deleteMessage"
      confirm-text="删除"
      :busy="deleting"
      :error="deleteError"
      @confirm="confirmDelete"
      @cancel="cancelDelete"
    />
  </section>
</template>

<style scoped>
.deck-detail {
  display: flex;
  flex-direction: column;
  gap: 14px;
  min-width: 0;
  padding-bottom: 68px;
}

.state-card {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 320px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.state-card > * {
  width: 100%;
}

.detail-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 2px 2px 0;
}

.title-block {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.title-line {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.deck-title {
  overflow: hidden;
  font-size: 20px;
  font-weight: 800;
  line-height: 1.3;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.category-pill {
  flex: none;
  padding: 2px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  color: var(--color-indigo);
  font-size: 11px;
  font-weight: 600;
}

.deck-sub {
  color: var(--text-secondary);
  font-size: 12px;
}

.head-actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 8px;
}

.head-btn {
  min-height: 44px;
  padding: 0 12px;
  font-size: 14px;
}

.quiz-btn {
  border-color: color-mix(in srgb, var(--color-indigo) 35%, transparent);
  color: var(--color-indigo);
}

.manage-active {
  background: color-mix(in srgb, var(--color-indigo) 10%, transparent);
  border-color: color-mix(in srgb, var(--color-indigo) 35%, transparent);
  color: var(--color-indigo);
}

.detail-body {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.child-list {
  display: flex;
  flex-direction: column;
  margin: 0;
  padding: 0;
  list-style: none;
}

.child-list li + li .child-btn {
  border-top: 1px solid var(--border);
}

.child-btn {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-height: 44px;
  padding: 12px 14px;
  border: 0;
  background: transparent;
  color: var(--text);
  text-align: left;
  transition: background 0.15s ease;
}

.child-btn:hover {
  background: var(--surface-muted);
}

.child-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: -2px;
}

.child-deck {
  flex: 1;
  min-width: 0;
}

.chevron {
  flex: none;
  color: var(--text-tertiary);
}

.select-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 10px;
  border-bottom: 1px solid var(--border);
  background: var(--surface-muted);
}

.select-count {
  color: var(--text-secondary);
  font-size: 13px;
  white-space: nowrap;
}

.card-list {
  display: flex;
  flex-direction: column;
  margin: 0;
  padding: 0;
  list-style: none;
}

.card-item {
  display: flex;
  align-items: stretch;
  border-bottom: 1px solid var(--border);
}

.card-item:last-child {
  border-bottom: 0;
}

.card-item:hover {
  background: var(--surface-muted);
}

.card-item :deep(.card-row) {
  flex: 1;
  border-bottom: 0;
}

.card-delete {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  align-self: center;
  width: 44px;
  min-height: 44px;
  margin-right: 4px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-tertiary);
  transition: background 0.15s ease, color 0.15s ease;
}

.card-delete:hover {
  background: color-mix(in srgb, var(--color-red) 12%, transparent);
  color: var(--color-red);
}

.card-delete:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

.detail-actions {
  position: fixed;
  right: 0;
  bottom: calc(var(--tab-height) + env(safe-area-inset-bottom) + 12px);
  left: 0;
  z-index: 15;
  display: flex;
  justify-content: center;
  padding: 0 16px;
  pointer-events: none;
}

.action-btn {
  pointer-events: auto;
  min-height: 48px;
  border-radius: 999px;
  font-size: 15px;
}

.add-card-btn {
  padding: 0 30px;
  box-shadow: var(--shadow-primary);
}

.batch-btn {
  width: 100%;
}

.action-btn:focus-visible,
.head-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .deck-detail {
    padding-bottom: 0;
  }

  .deck-title {
    font-size: 22px;
  }

  .detail-actions {
    position: sticky;
    right: auto;
    bottom: 16px;
    left: auto;
    padding: 4px 0 2px;
  }
}
</style>
