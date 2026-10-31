<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft,
  FolderPlus,
  Library,
  Map as MapIcon,
  Plus,
  Search,
  Sparkles,
  X
} from 'lucide-vue-next'
import ConfirmDialog from '@/ui/components/ConfirmDialog.vue'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import TreeItem from '@/ui/components/TreeItem.vue'
import CreateDeckSheet from '@/ui/sheets/CreateDeckSheet.vue'
import EditDeckSheet from '@/ui/sheets/EditDeckSheet.vue'
import DeckDetailPage from './DeckDetailPage.vue'
import type { Deck } from '@/core/api/types'
import { buildDeckTree, descendantIds, filterDeckTree, type DeckNode } from '@/core/decks/tree'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useToastStore } from '@/ui/stores/toast'

const route = useRoute()
const router = useRouter()
const toast = useToastStore()

const decks = ref<Deck[]>([])
const loading = ref(true)
const loadError = ref('')
const query = ref('')
const expandedIds = ref<Set<number>>(new Set())
const menuOpen = ref(false)
const showCreate = ref(false)
const editingDeck = ref<Deck | null>(null)
const pendingDelete = ref<Deck | null>(null)
const deleting = ref(false)
const deleteError = ref('')
let seededExpansion = false
let loadSeq = 0

/** 路由里的 deck id：Number 解析失败（NaN/非正整数）时视为未选择。 */
const selectedDeckId = computed<number | null>(() => {
  const raw = route.params.id
  const value = Array.isArray(raw) ? raw[0] : raw
  if (value == null || value === '') return null
  const parsed = Number(value)
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null
})

const tree = computed(() => filterDeckTree(buildDeckTree(decks.value), query.value))
const searching = computed(() => query.value.trim() !== '')

const deleteDescendantCount = computed(() =>
  pendingDelete.value ? descendantIds(pendingDelete.value.id, decks.value).size : 0
)
const deleteMessage = computed(() =>
  deleteDescendantCount.value > 0
    ? `删除后该卡组、其 ${deleteDescendantCount.value} 个子卡组及所有卡片将无法恢复。`
    : '删除后该卡组及其卡片将无法恢复。'
)

function seedExpansion(nodes: DeckNode[]): void {
  const next = new Set(expandedIds.value)
  const walk = (items: DeckNode[]): void => {
    for (const item of items) {
      if (item.children.length > 0) {
        next.add(item.deck.id)
        walk(item.children)
      }
    }
  }
  walk(nodes)
  expandedIds.value = next
}

/** 展开从 parentId 起的整条父链，保证新建/移动后的节点在树中可见。 */
function expandAncestors(parentId: number | null, list: Deck[]): void {
  if (parentId == null) return
  const byId = new Map<number, Deck>(list.map(item => [item.id, item]))
  const next = new Set(expandedIds.value)
  const seen = new Set<number>()
  let current: Deck | undefined = byId.get(parentId)
  while (current && !seen.has(current.id)) {
    seen.add(current.id)
    next.add(current.id)
    current = current.parentId == null ? undefined : byId.get(current.parentId)
  }
  expandedIds.value = next
}

async function loadDecks(showLoading = true): Promise<void> {
  const seq = ++loadSeq
  if (showLoading) loading.value = true
  loadError.value = ''
  try {
    const loaded = await getRuntime().endpoints.decks()
    // 只接受最新一次请求，避免重试/变更刷新乱序覆盖新列表。
    if (seq !== loadSeq) return
    decks.value = loaded

    // 首次拿到非空列表时展开含子节点的分支；首次为空也不会阻止后续种子化。
    if (!seededExpansion && loaded.length > 0) {
      seedExpansion(buildDeckTree(loaded))
      seededExpansion = true
    }

    const selected = selectedDeckId.value
    if (selected != null) {
      const selectedDeck = loaded.find(item => item.id === selected)
      if (selectedDeck) {
        expandAncestors(selectedDeck.parentId, loaded)
      } else {
        // 选中的卡组已不存在（可能被其他端删除）：回到列表，避免详情停留在陈旧数据。
        void router.replace({ name: 'decks' })
      }
    }
  } catch (e) {
    if (seq !== loadSeq) return
    loadError.value = friendlyError(e)
  } finally {
    // 最新请求结束时统一收尾；后台刷新（showLoading=false）不会让加载态卡住。
    if (seq === loadSeq) loading.value = false
  }
}

function toggleExpanded(id: number): void {
  const next = new Set(expandedIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  expandedIds.value = next
}

function goGraph(): void {
  void router.push({ name: 'graph' })
}

function closeDetail(): void {
  // 若上一页就是知识树，直接后退，避免在历史里堆积重复的列表项。
  const listHref = router.resolve({ name: 'decks' }).href
  const back = (router.options.history.state as { back?: unknown }).back
  if (
    typeof back === 'string'
    && (back === listHref || back.startsWith(`${listHref}?`) || back.startsWith(`${listHref}#`))
  ) {
    router.back()
    return
  }
  void router.replace({ name: 'decks' })
}

function openCreate(): void {
  menuOpen.value = false
  showCreate.value = true
}

function goGenerate(): void {
  menuOpen.value = false
  void router.push({ name: 'generate' })
}

function goCommunity(): void {
  menuOpen.value = false
  void router.push({ name: 'community' })
}

function onCreated(deck: Deck): void {
  showCreate.value = false
  toast.show(`已创建「${deck.title}」`)
  // 展开父链，让新建节点立刻出现在视野内。
  expandAncestors(deck.parentId, decks.value)
  void loadDecks(false)
}

function onEdited(deck: Deck): void {
  editingDeck.value = null
  toast.show(`已保存「${deck.title}」`)
  // 节点可能被移动到折叠的父卡组下，同样展开父链。
  expandAncestors(deck.parentId, decks.value)
  void loadDecks(false)
}

function askDelete(deck: Deck): void {
  menuOpen.value = false
  deleteError.value = ''
  pendingDelete.value = deck
}

function cancelDelete(): void {
  if (deleting.value) return
  pendingDelete.value = null
  deleteError.value = ''
}

async function confirmDelete(): Promise<void> {
  const deck = pendingDelete.value
  if (!deck || deleting.value) return
  deleting.value = true
  deleteError.value = ''
  try {
    // 后端为 ON DELETE CASCADE：选中节点自身或其后代被删时都要立刻离开详情。
    const selection = selectedDeckId.value
    const affectsSelection = selection !== null
      && (selection === deck.id || descendantIds(deck.id, decks.value).has(selection))
    await getRuntime().endpoints.deleteDeck(deck.id)
    pendingDelete.value = null
    toast.show(`已删除「${deck.title}」`)
    if (affectsSelection) {
      await router.replace({ name: 'decks' })
    }
    await loadDecks(false)
  } catch (e) {
    deleteError.value = friendlyError(e)
  } finally {
    deleting.value = false
  }
}

onMounted(() => {
  void loadDecks()
})
</script>

<template>
  <section class="decks-page">
    <header class="decks-head">
      <button
        class="btn btn-ghost graph-btn"
        type="button"
        @click="goGraph"
      >
        <MapIcon
          :size="18"
          aria-hidden="true"
        />
        <span>掌握度地图</span>
      </button>

      <h1 class="head-title">
        知识树
      </h1>

      <div
        class="menu-wrap"
        @keydown.esc="menuOpen = false"
      >
        <button
          class="add-btn"
          type="button"
          aria-label="新建卡组菜单"
          aria-haspopup="menu"
          :aria-expanded="menuOpen"
          @click="menuOpen = !menuOpen"
        >
          <Plus
            :size="22"
            aria-hidden="true"
          />
        </button>

        <div
          v-if="menuOpen"
          class="menu-scrim"
          aria-hidden="true"
          @click="menuOpen = false"
        />
        <div
          v-if="menuOpen"
          class="menu"
          role="menu"
          aria-label="新建"
        >
          <button
            class="menu-item"
            type="button"
            role="menuitem"
            @click="openCreate"
          >
            <FolderPlus
              :size="18"
              aria-hidden="true"
            />
            手动新建卡组
          </button>
          <button
            class="menu-item"
            type="button"
            role="menuitem"
            @click="goGenerate"
          >
            <Sparkles
              :size="18"
              aria-hidden="true"
            />
            AI 上传生成
          </button>
          <div class="menu-divider" />
          <button
            class="menu-item"
            type="button"
            role="menuitem"
            @click="goCommunity"
          >
            <Library
              :size="18"
              aria-hidden="true"
            />
            导入精选卡包
          </button>
        </div>
      </div>
    </header>

    <div
      class="split"
      :class="{ 'has-detail': selectedDeckId !== null }"
    >
      <section
        class="list-pane"
        aria-label="知识树列表"
      >
        <div class="search">
          <Search
            class="search-icon"
            :size="18"
            aria-hidden="true"
          />
          <input
            v-model="query"
            class="input search-input"
            type="search"
            placeholder="搜索知识节点"
            aria-label="搜索知识节点"
          >
          <button
            v-if="query"
            class="search-clear"
            type="button"
            aria-label="清空搜索"
            @click="query = ''"
          >
            <X
              :size="16"
              aria-hidden="true"
            />
          </button>
        </div>

        <div class="list-card">
          <LoadingState
            v-if="loading"
            text="正在加载知识树…"
          />
          <ErrorState
            v-else-if="loadError"
            title="卡组加载失败"
            :message="loadError"
            retry-text="重新加载"
            show-retry
            @retry="loadDecks()"
          />
          <EmptyState
            v-else-if="decks.length === 0"
            title="还没有卡组"
            text="点击右上角 + 新建第一个卡组"
          >
            <button
              class="btn btn-primary"
              type="button"
              @click="openCreate"
            >
              <FolderPlus
                :size="18"
                aria-hidden="true"
              />
              新建卡组
            </button>
          </EmptyState>
          <EmptyState
            v-else-if="tree.length === 0"
            title="没有匹配的知识节点"
            text="换个关键词试试"
          />
          <ul
            v-else
            class="tree"
          >
            <TreeItem
              v-for="node in tree"
              :key="node.deck.id"
              :node="node"
              :expanded-ids="expandedIds"
              :selected-id="selectedDeckId"
              :expand-all="searching"
              @toggle="toggleExpanded"
              @edit="editingDeck = $event"
              @delete="askDelete"
            />
          </ul>
        </div>
      </section>

      <section
        class="detail-pane"
        aria-label="卡组详情"
      >
        <button
          v-if="selectedDeckId !== null"
          class="back-btn"
          type="button"
          @click="closeDetail"
        >
          <ArrowLeft
            :size="18"
            aria-hidden="true"
          />
          返回知识树
        </button>
        <ErrorState
          v-if="loadError"
          class="detail-load-error"
          title="卡组加载失败"
          :message="loadError"
          retry-text="重新加载"
          show-retry
          @retry="loadDecks()"
        />
        <DeckDetailPage
          v-else
          :deck-id="selectedDeckId"
        />
      </section>
    </div>

    <CreateDeckSheet
      v-if="showCreate"
      :decks="decks"
      @saved="onCreated"
      @close="showCreate = false"
    />

    <EditDeckSheet
      v-if="editingDeck"
      :key="editingDeck.id"
      :deck="editingDeck"
      :decks="decks"
      @saved="onEdited"
      @close="editingDeck = null"
    />

    <ConfirmDialog
      v-if="pendingDelete"
      :title="`删除「${pendingDelete.title}」？`"
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
.decks-page {
  width: min(100%, var(--content-max));
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.decks-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
}

.graph-btn {
  padding: 0 12px;
  font-size: 14px;
}

.head-title {
  display: none;
  flex: 1;
  font-size: 20px;
  font-weight: 800;
  text-align: center;
}

.menu-wrap {
  position: relative;
  flex: none;
}

.add-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border: 0;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--color-indigo), var(--color-purple));
  color: var(--on-primary);
  box-shadow: var(--shadow-primary);
}

.add-btn:active {
  transform: scale(0.97);
}

.menu-scrim {
  position: fixed;
  inset: 0;
  z-index: 40;
  background: transparent;
}

.menu {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  z-index: 41;
  width: 200px;
  padding: 6px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-lg);
}

.menu-item {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-height: 44px;
  padding: 0 10px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text);
  font-size: 14px;
  text-align: left;
}

.menu-item:hover {
  background: var(--surface-muted);
}

.menu-divider {
  height: 1px;
  margin: 6px 8px;
  background: var(--border);
}

.search {
  position: relative;
  margin-bottom: 12px;
}

.search-icon {
  position: absolute;
  top: 50%;
  left: 14px;
  color: var(--text-tertiary);
  transform: translateY(-50%);
  pointer-events: none;
}

.search-input {
  padding-right: 44px;
  padding-left: 42px;
  background: var(--surface);
}

.search-input::-webkit-search-cancel-button {
  display: none;
}

.search-clear {
  position: absolute;
  top: 50%;
  right: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--text-tertiary);
  transform: translateY(-50%);
}

.search-clear:hover {
  background: var(--surface-muted);
  color: var(--text-secondary);
}

.list-card {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.tree {
  margin: 0;
  padding: 4px;
  list-style: none;
}

.detail-pane {
  display: none;
  min-width: 0;
}

.split.has-detail .list-pane {
  display: none;
}

.split.has-detail .detail-pane {
  display: block;
}

.back-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 44px;
  margin-bottom: 10px;
  padding: 0 12px;
  border: 1px solid var(--border-strong);
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
}

.back-btn:hover {
  background: var(--surface-muted);
}

.add-btn:focus-visible,
.menu-item:focus-visible,
.search-clear:focus-visible,
.back-btn:focus-visible,
.graph-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .decks-page {
    padding: 24px 32px 48px;
  }

  .head-title {
    display: block;
  }

  .split,
  .split.has-detail {
    display: grid;
    grid-template-columns: 360px minmax(0, 1fr);
    gap: 24px;
    align-items: start;
  }

  .split .list-pane,
  .split.has-detail .list-pane {
    display: block;
  }

  .split .detail-pane,
  .split.has-detail .detail-pane {
    display: block;
  }

  .back-btn {
    display: none;
  }

  /* 桌面端错误已由左侧列表展示，避免双栏重复。 */
  .detail-load-error {
    display: none;
  }
}
</style>
