<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, CheckCircle2, X } from 'lucide-vue-next'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import ScatterChart from '@/ui/components/charts/ScatterChart.vue'
import type { Deck, Flashcard } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { typeLabel } from '@/core/format/text'
import { scoreColor } from '@/core/graph/plot'
import { getRuntime } from '@/runtime'

/**
 * 掌握度地图（对应 iOS KnowledgeGraphView）。
 *
 * 每个点是一张已复习卡片：X = FSRS 难度，Y = log10 稳定性为底的归一化位置，
 * 颜色 = 实时掌握度。点击节点展开详情面板。
 */

const router = useRouter()

const rootDecks = ref<Deck[]>([])
const selectedRootIndex = ref(0)
const cards = ref<Flashcard[]>([])
const loading = ref(true)
const cardsLoading = ref(false)
const errorMsg = ref('')
const selectedCard = ref<Flashcard | null>(null)

let deckSeq = 0
let cardSeq = 0

const selectedRoot = computed<Deck | null>(() => rootDecks.value[selectedRootIndex.value] ?? null)

/** 只绘制已经复习过（有难度/稳定性）的卡片，与 iOS plotCards 一致。 */
const plotCards = computed(() =>
  cards.value.filter(card => card.difficulty !== null && card.stability !== null)
)

const unreviewedCount = computed(() => Math.max(cards.value.length - plotCards.value.length, 0))

/** 卡组选择器与统计条只在卡组列表加载完成且存在根卡组时显示。 */
const showBars = computed(() => !loading.value && rootDecks.value.length > 0)

function formatOne(value: number | null): string {
  return (value ?? 0).toFixed(1)
}

async function loadDecks(): Promise<void> {
  const seq = ++deckSeq
  loading.value = true
  errorMsg.value = ''
  try {
    const all = await getRuntime().endpoints.decks()
    if (seq !== deckSeq) return
    const roots = all.filter(deck => deck.parentId === null)
    rootDecks.value = roots
    selectedRootIndex.value = 0
    selectedCard.value = null
    if (roots.length > 0) {
      void loadCards(roots[0])
    } else {
      cards.value = []
    }
  } catch (e) {
    if (seq !== deckSeq) return
    errorMsg.value = friendlyError(e)
  } finally {
    if (seq === deckSeq) loading.value = false
  }
}

async function loadCards(deck: Deck): Promise<void> {
  const seq = ++cardSeq
  cardsLoading.value = true
  errorMsg.value = ''
  try {
    const loaded = await getRuntime().endpoints.cards(deck.id, true)
    // 只接受最新一次请求，避免快速切换卡组时旧响应覆盖新卡组。
    if (seq !== cardSeq) return
    cards.value = loaded
    selectedCard.value = null
  } catch (e) {
    if (seq !== cardSeq) return
    errorMsg.value = friendlyError(e)
  } finally {
    if (seq === cardSeq) cardsLoading.value = false
  }
}

function selectDeck(index: number): void {
  if (index === selectedRootIndex.value) return
  selectedRootIndex.value = index
  selectedCard.value = null
  const deck = rootDecks.value[index]
  if (deck) void loadCards(deck)
}

function retry(): void {
  if (rootDecks.value.length === 0) {
    void loadDecks()
    return
  }
  const deck = selectedRoot.value
  if (deck) void loadCards(deck)
}

/** 点击/键盘激活节点：再次激活同一点即取消选中。 */
function toggleCard(id: number): void {
  if (selectedCard.value?.id === id) {
    selectedCard.value = null
    return
  }
  selectedCard.value = cards.value.find(card => card.id === id) ?? null
}

function closeDetail(): void {
  selectedCard.value = null
}

function goBack(): void {
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

onMounted(() => {
  void loadDecks()
})
</script>

<template>
  <section class="map-page">
    <header class="map-head">
      <button
        class="back-btn"
        type="button"
        @click="goBack"
      >
        <ArrowLeft
          :size="18"
          aria-hidden="true"
        />
        知识树
      </button>
      <h1 class="head-title">
        掌握度地图
      </h1>
    </header>

    <div
      v-if="showBars"
      class="deck-picker"
      aria-label="根卡组"
    >
      <button
        v-for="(deck, index) in rootDecks"
        :key="deck.id"
        class="deck-pill"
        :class="{ selected: index === selectedRootIndex }"
        type="button"
        :aria-pressed="index === selectedRootIndex"
        @click="selectDeck(index)"
      >
        {{ deck.title }}
      </button>
    </div>

    <div
      v-if="showBars"
      class="stats-bar"
    >
      <span class="stats-reviewed">
        <CheckCircle2
          :size="14"
          aria-hidden="true"
        />
        已复习 {{ plotCards.length }} / {{ cards.length }} 张
      </span>
      <span
        v-if="unreviewedCount > 0"
        class="stats-due"
      >{{ unreviewedCount }} 张待复习</span>
    </div>

    <div class="plot-card">
      <LoadingState
        v-if="loading || cardsLoading"
        text="生成掌握度地图…"
      />
      <ErrorState
        v-else-if="errorMsg"
        title="加载失败"
        :message="errorMsg"
        retry-text="重新加载"
        show-retry
        @retry="retry"
      />
      <EmptyState
        v-else-if="rootDecks.length === 0"
        title="暂无卡组"
        text="先创建卡组，再回来查看掌握度地图"
      />
      <EmptyState
        v-else-if="cards.length === 0"
        title="该卡组暂无卡片"
        text="添加卡片并完成首次复习后，这里会出现掌握度分布"
      />
      <EmptyState
        v-else-if="plotCards.length === 0"
        title="还没有复习记录"
        text="完成第一次复习后，卡片会按难度/稳定性出现在图上"
      />
      <div
        v-else
        class="chart-area"
      >
        <ScatterChart
          :cards="plotCards"
          :selected-id="selectedCard?.id ?? null"
          @select="toggleCard"
        />
        <div
          class="legend"
          aria-label="掌握度图例"
        >
          <span class="legend-row">
            <span
              class="legend-dot low"
              aria-hidden="true"
            />待加强
          </span>
          <span class="legend-row">
            <span
              class="legend-dot mid"
              aria-hidden="true"
            />进行中
          </span>
          <span class="legend-row">
            <span
              class="legend-dot high"
              aria-hidden="true"
            />已掌握
          </span>
        </div>
      </div>
    </div>

    <Transition name="detail">
      <div
        v-if="selectedCard"
        class="detail-panel"
      >
        <div class="detail-head">
          <span
            class="detail-dot"
            :style="{ background: scoreColor(selectedCard.memoryScore) }"
            aria-hidden="true"
          />
          <span class="detail-score">掌握度 {{ selectedCard.memoryScore }}%</span>
          <button
            class="detail-close"
            type="button"
            aria-label="关闭详情"
            @click="closeDetail"
          >
            <X
              :size="20"
              aria-hidden="true"
            />
          </button>
        </div>

        <p class="detail-question">
          {{ selectedCard.question }}
        </p>

        <dl class="detail-stats">
          <div class="stat">
            <dt>难度</dt>
            <dd>{{ formatOne(selectedCard.difficulty) }}</dd>
          </div>
          <div class="stat">
            <dt>稳定性</dt>
            <dd>{{ formatOne(selectedCard.stability) }} 天</dd>
          </div>
          <div class="stat">
            <dt>复习次数</dt>
            <dd>{{ selectedCard.reviewCount }} 次</dd>
          </div>
          <div class="stat">
            <dt>类型</dt>
            <dd>{{ typeLabel(selectedCard.cardType) }}</dd>
          </div>
        </dl>
      </div>
    </Transition>
  </section>
</template>

<style scoped>
.map-page {
  width: min(100%, var(--content-max));
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.map-head {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  margin-bottom: 10px;
}

.back-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-height: 44px;
  padding: 0 8px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
}

.back-btn:hover {
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.head-title {
  display: none;
  font-size: 20px;
  font-weight: 800;
}

.deck-picker {
  display: flex;
  gap: 8px;
  padding: 10px 0;
  overflow-x: auto;
  scrollbar-width: none;
}

.deck-picker::-webkit-scrollbar {
  display: none;
}

.deck-pill {
  flex: none;
  min-height: 44px;
  padding: 8px 14px;
  border: 1px solid transparent;
  border-radius: 999px;
  background: var(--surface-muted);
  color: var(--text);
  font-size: 14px;
  white-space: nowrap;
}

.deck-pill.selected {
  background: linear-gradient(135deg, var(--color-indigo), var(--color-purple));
  color: var(--on-primary);
  font-weight: 600;
  border-color: transparent;
}

.stats-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 0 0 8px;
  color: var(--text-secondary);
  font-size: 12px;
}

.stats-reviewed {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.stats-due {
  color: var(--text-tertiary);
}

.plot-card {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.chart-area {
  position: relative;
  padding: 8px 4px 4px;
}

.legend {
  position: absolute;
  right: 12px;
  bottom: 12px;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 4px;
  padding: 6px 8px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-soft);
  -webkit-backdrop-filter: blur(12px);
  backdrop-filter: blur(12px);
  color: var(--text-secondary);
  font-size: 10px;
  pointer-events: none;
}

.legend-row {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.legend-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
}

.legend-dot.low {
  background: var(--color-pink);
}

.legend-dot.mid {
  background: var(--color-purple);
}

.legend-dot.high {
  background: var(--color-indigo);
}

.detail-panel {
  position: fixed;
  right: 12px;
  bottom: calc(var(--tab-height) + env(safe-area-inset-bottom) + 8px);
  left: 12px;
  z-index: 25;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: color-mix(in srgb, var(--surface) 94%, transparent);
  box-shadow: var(--shadow-lg);
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
}

.detail-head {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
}

.detail-dot {
  flex: none;
  width: 9px;
  height: 9px;
  border-radius: 50%;
}

.detail-score {
  flex: 1;
  color: var(--text-secondary);
  font-size: 12px;
}

.detail-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  margin: -8px -8px -8px 0;
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--text-secondary);
}

.detail-close:hover {
  background: var(--surface-muted);
}

.detail-question {
  display: -webkit-box;
  overflow: hidden;
  color: var(--text);
  font-size: 14px;
  font-weight: 700;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 4;
}

.detail-stats {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 20px;
  margin: 0;
}

.stat {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.stat dt {
  color: var(--text-tertiary);
  font-size: 11px;
}

.stat dd {
  margin: 0;
  color: var(--text);
  font-size: 12px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.detail-enter-active,
.detail-leave-active {
  transition: transform 0.25s ease, opacity 0.25s ease;
}

.detail-enter-from,
.detail-leave-to {
  opacity: 0;
  transform: translateY(16px);
}

.back-btn:focus-visible,
.deck-pill:focus-visible,
.detail-close:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .map-page {
    padding: 24px 32px 48px;
  }

  .back-btn {
    display: none;
  }

  .head-title {
    display: block;
  }

  .detail-panel {
    position: static;
    width: min(100%, 520px);
    margin: 10px auto 0;
  }
}
</style>
