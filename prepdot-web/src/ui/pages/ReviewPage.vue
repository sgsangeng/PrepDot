<script setup lang="ts">
/* global HTMLElement, MouseEvent */
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  ArrowRight,
  CheckCircle2,
  Clock3,
  Layers3,
  MessageCircle,
  Pencil,
  StickyNote,
  X
} from 'lucide-vue-next'
import AuroraBackground from '@/ui/components/AuroraBackground.vue'
import ProgressRing from '@/ui/components/ProgressRing.vue'
import ProgressBar from '@/ui/components/ProgressBar.vue'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import CardFormSheet from '@/ui/sheets/CardFormSheet.vue'
import CardNoteSheet from '@/ui/sheets/CardNoteSheet.vue'
import CoachChatSheet from '@/ui/sheets/CoachChatSheet.vue'
import type { Flashcard, ReviewSummary, TodayPlan } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { renderInlineMarkdown } from '@/core/format/markdown'
import { cardDisplayText, normalizeCardType } from '@/core/format/text'
import {
  advanceAfterRating,
  isReviewComplete,
  parseCardOptions,
  ratingOptions,
  type ReviewRating
} from '@/core/review/session'
import { getRuntime } from '@/runtime'

type ScreenMode = 'overview' | 'session' | 'done'

interface DeckProgressLike {
  deckId: number
  deckTitle: string
  totalCount: number
  completedCount: number
}

const router = useRouter()

const plan = ref<TodayPlan | null>(null)
const loading = ref(true)
const error = ref('')
const mode = ref<ScreenMode>('overview')
const index = ref(0)
const summary = ref<ReviewSummary | null>(null)
const summaryLoading = ref(false)

const flipped = ref(false)
const submitting = ref(false)
const submitError = ref('')
const submitMessage = computed(() =>
  `${submitError.value.replace(/[.。]\s*$/, '')}。本次评分未记录，请重试。`
)
const lastRating = ref<ReviewRating | null>(null)
/** `again` 已记录但计划刷新失败：评分按钮保持禁用，避免重复提交同一张卡。 */
const queueError = ref('')

const showChat = ref(false)
const showEdit = ref(false)
const showNote = ref(false)

const now = new Date()
const todayLabel = `${new Intl.DateTimeFormat('zh-CN', {
  month: 'long',
  day: 'numeric'
}).format(now)} ${new Intl.DateTimeFormat('zh-CN', { weekday: 'long' }).format(now)}`

const cards = computed(() => plan.value?.cards ?? [])
const deckProgress = computed<DeckProgressLike[]>(() => plan.value?.deckProgress ?? [])
const currentCard = computed<Flashcard | null>(() => cards.value[index.value] ?? null)
const pending = computed(() => cards.value.length)
const progressPercent = computed(() => {
  const p = plan.value
  if (!p || p.totalCount === 0) return 0
  return Math.min(100, Math.floor((p.completedCount / p.totalCount) * 100))
})

const cardType = computed(() => (currentCard.value ? normalizeCardType(currentCard.value.cardType) : 'qa'))
const cardTypeLabel = computed(() => (cardType.value === 'choice' ? '选择题' : cardType.value === 'blank' ? '填空题' : '问答'))
const options = computed(() =>
  currentCard.value && cardType.value === 'choice' ? parseCardOptions(currentCard.value.options) : []
)
const questionHtml = computed(() =>
  currentCard.value ? renderInlineMarkdown(cardDisplayText(currentCard.value.question)) : ''
)
const answerHtml = computed(() =>
  currentCard.value ? renderInlineMarkdown(cardDisplayText(currentCard.value.answer)) : ''
)
const noteHtml = computed(() =>
  currentCard.value?.note ? renderInlineMarkdown(cardDisplayText(currentCard.value.note)) : ''
)

function optionPrefix(i: number): string {
  return ['A', 'B', 'C', 'D'][i] ?? String(i + 1)
}

function isDeckDone(item: DeckProgressLike): boolean {
  return item.totalCount > 0 && item.completedCount >= item.totalCount
}

function deckPending(item: DeckProgressLike): number {
  return Math.max(0, item.totalCount - item.completedCount)
}

async function loadPlan(): Promise<void> {
  loading.value = true
  error.value = ''
  try {
    const loaded = await getRuntime().endpoints.todayPlan()
    plan.value = loaded
    queueError.value = ''
    if (isReviewComplete(loaded)) {
      mode.value = 'done'
      void loadSummary()
    } else {
      mode.value = 'overview'
    }
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

async function loadSummary(): Promise<void> {
  summaryLoading.value = true
  try {
    summary.value = await getRuntime().endpoints.todaySummary()
  } catch {
    // 小结加载失败不阻塞完成页。
    summary.value = null
  } finally {
    summaryLoading.value = false
  }
}

function startSession(): void {
  if (cards.value.length === 0) return
  index.value = 0
  flipped.value = false
  submitError.value = ''
  queueError.value = ''
  lastRating.value = null
  mode.value = 'session'
}

function toggleFlip(): void {
  flipped.value = !flipped.value
}

async function submitRating(rating: ReviewRating): Promise<void> {
  const card = currentCard.value
  if (!card || submitting.value || queueError.value) return
  submitting.value = true
  submitError.value = ''
  lastRating.value = rating
  try {
    await getRuntime().endpoints.submitReview(card.id, rating)
    const result = advanceAfterRating(index.value, cards.value.length, rating)
    if (!result.done) {
      index.value = result.index
      flipped.value = false
      showChat.value = false
      showEdit.value = false
      showNote.value = false
    } else if (result.reload) {
      // again 会把服务器计划项回置 pending；先确认服务器队列，避免误报「今日复习完成」。
      await refreshRemainingQueue()
    } else {
      mode.value = 'done'
      void loadSummary()
    }
    lastRating.value = null
  } catch (e) {
    submitError.value = friendlyError(e)
  } finally {
    submitting.value = false
  }
}

/**
 * again 清空本地队列后重新拉取今日计划。
 * 服务器还有卡片就继续复习（从新队列第一张开始），确实为空才进入完成页。
 */
async function refreshRemainingQueue(): Promise<void> {
  try {
    const fresh = await getRuntime().endpoints.todayPlan()
    queueError.value = ''
    plan.value = fresh
    if (fresh.cards.length > 0) {
      index.value = 0
      flipped.value = false
      showChat.value = false
      showEdit.value = false
      showNote.value = false
      mode.value = 'session'
    } else {
      mode.value = 'done'
      void loadSummary()
    }
  } catch (e) {
    queueError.value = `评分已记录，但今日计划刷新失败：${friendlyError(e)}`
  }
}

async function retryRemainingQueue(): Promise<void> {
  if (submitting.value) return
  submitting.value = true
  try {
    await refreshRemainingQueue()
  } finally {
    submitting.value = false
  }
}

function retrySubmit(): void {
  if (lastRating.value) void submitRating(lastRating.value)
}

function exitSession(): void {
  if (submitting.value) return
  mode.value = 'overview'
  index.value = 0
  flipped.value = false
  submitError.value = ''
  queueError.value = ''
  void loadPlan()
}

/** 卡片内的链接只跳转，不再冒泡触发翻转。 */
function stopLinkFlip(event: MouseEvent): void {
  if ((event.target as HTMLElement | null)?.closest('a')) event.stopPropagation()
}

function applyCardUpdate(updated: Flashcard): void {
  const p = plan.value
  if (!p) return
  const i = p.cards.findIndex(card => card.id === updated.id)
  if (i >= 0) p.cards[i] = updated
}

function onCardSaved(updated: Flashcard): void {
  applyCardUpdate(updated)
  showEdit.value = false
  showNote.value = false
}

function goToDecks(): void {
  void router.push({ name: 'decks' })
}

onMounted(loadPlan)
</script>

<template>
  <!-- eslint-disable vue/no-v-html -- markdown 由 renderInlineMarkdown 生成（html: false） -->
  <section
    v-if="loading"
    class="review-page state-page"
  >
    <AuroraBackground />
    <div class="state-content">
      <LoadingState text="正在加载今日复习…" />
    </div>
  </section>

  <section
    v-else-if="error"
    class="review-page state-page"
  >
    <AuroraBackground />
    <div class="state-content">
      <ErrorState
        title="今日复习加载失败"
        :message="error"
        retry-text="重新加载"
        show-retry
        @retry="loadPlan"
      />
    </div>
  </section>

  <div
    v-else-if="mode === 'session' && currentCard"
    class="review-page"
  >
    <AuroraBackground />
    <div class="session">
      <header class="session-head">
        <div class="session-top">
          <button
            class="exit-btn"
            type="button"
            @click="exitSession"
          >
            <X
              :size="18"
              aria-hidden="true"
            />
            <span>退出复习</span>
          </button>
          <div class="session-meta">
            <span class="session-count num">{{ index + 1 }} / {{ cards.length }}</span>
            <span class="session-memory">记忆度 {{ currentCard.memoryScore }}</span>
          </div>
        </div>
        <ProgressBar
          :value="index + 1"
          :max="cards.length"
        />
      </header>

      <div
        class="flashcard"
        :class="{ flipped }"
        role="button"
        tabindex="0"
        :aria-label="flipped ? '查看问题' : '查看答案'"
        @click="toggleFlip"
        @keydown.enter.prevent="toggleFlip"
        @keydown.space.prevent="toggleFlip"
      >
        <div class="flashcard-inner">
          <article
            class="face front"
            :aria-hidden="flipped"
            :inert="flipped"
          >
            <header class="face-head">
              <span
                v-if="cardType !== 'qa'"
                class="type-badge"
                :class="`badge-${cardType}`"
              >{{ cardTypeLabel }}</span>
              <span class="face-hint">点击翻转查看答案</span>
            </header>
            <div class="front-body">
              <div
                class="question markdown"
                @click="stopLinkFlip"
                v-html="questionHtml"
              />
            </div>
          </article>

          <article
            class="face back"
            :aria-hidden="!flipped"
            :inert="!flipped"
          >
            <header class="face-head">
              <span
                v-if="cardType !== 'qa'"
                class="type-badge"
                :class="`badge-${cardType}`"
              >{{ cardTypeLabel }}</span>
              <span class="face-hint">参考答案</span>
            </header>

            <div
              class="back-question"
              @click="stopLinkFlip"
              v-html="questionHtml"
            />
            <hr class="divider">

            <div class="back-body">
              <div
                class="answer markdown"
                @click="stopLinkFlip"
                v-html="answerHtml"
              />

              <ul
                v-if="options.length"
                class="options"
              >
                <li
                  v-for="(option, i) in options"
                  :key="i"
                  class="option"
                  :class="{ correct: option === currentCard.answer }"
                >
                  <span class="option-prefix">{{ optionPrefix(i) }}</span>
                  <span class="option-text">{{ option }}</span>
                </li>
              </ul>

              <div
                v-if="currentCard.note?.trim()"
                class="note-block"
              >
                <StickyNote
                  :size="14"
                  class="note-icon"
                  aria-hidden="true"
                />
                <div
                  class="note-text markdown"
                  @click="stopLinkFlip"
                  v-html="noteHtml"
                />
              </div>
            </div>
          </article>
        </div>
      </div>

      <p
        v-if="!flipped"
        class="flip-hint"
      >
        点击卡片查看答案
      </p>

      <div
        v-else
        class="answer-panel"
      >
        <div class="action-bar">
          <button
            class="action-btn action-chat"
            type="button"
            @click="showChat = true"
          >
            <MessageCircle
              :size="14"
              aria-hidden="true"
            />
            <span>问AI</span>
          </button>
          <button
            class="action-btn action-edit"
            type="button"
            @click="showEdit = true"
          >
            <Pencil
              :size="14"
              aria-hidden="true"
            />
            <span>编辑</span>
          </button>
          <button
            class="action-btn action-note"
            type="button"
            @click="showNote = true"
          >
            <StickyNote
              :size="14"
              aria-hidden="true"
            />
            <span>笔记</span>
          </button>
        </div>

        <div class="rating-bar">
          <button
            v-for="option in ratingOptions"
            :key="option.rating"
            class="rating"
            :class="`rating-${option.rating}`"
            type="button"
            :disabled="submitting || queueError !== ''"
            @click="submitRating(option.rating)"
          >
            <span class="rating-label">{{ option.label }}</span>
            <span class="rating-sub">{{ option.sub }}</span>
          </button>
        </div>

        <div
          v-if="queueError"
          class="submit-error"
          role="alert"
        >
          <span>{{ queueError }}</span>
          <button
            class="btn btn-ghost btn-sm"
            type="button"
            :disabled="submitting"
            @click="retryRemainingQueue"
          >
            重试
          </button>
        </div>

        <div
          v-if="submitError"
          class="submit-error"
          role="alert"
        >
          <span>{{ submitMessage }}</span>
          <button
            class="btn btn-ghost btn-sm"
            type="button"
            :disabled="submitting"
            @click="retrySubmit"
          >
            重试
          </button>
        </div>
      </div>
    </div>

    <CoachChatSheet
      v-if="showChat"
      :card="currentCard"
      @close="showChat = false"
    />
    <CardFormSheet
      v-if="showEdit"
      :deck-id="currentCard.deckId"
      :card="currentCard"
      @saved="onCardSaved"
      @close="showEdit = false"
    />
    <CardNoteSheet
      v-if="showNote"
      :card="currentCard"
      @saved="onCardSaved"
      @close="showNote = false"
    />
  </div>

  <div
    v-else-if="mode === 'done'"
    class="review-page"
  >
    <AuroraBackground />
    <div class="done">
      <div class="done-hero">
        <span
          class="done-emoji"
          aria-hidden="true"
        >🎉</span>
        <h1 class="done-title">
          今日复习完成！
        </h1>
        <p class="done-sub">
          你的记忆力正在不断增强<br>明天继续加油！
        </p>
      </div>

      <div
        v-if="summaryLoading"
        class="summary-loading"
      >
        <LoadingState text="正在加载今日小结…" />
      </div>
      <div
        v-else-if="summary && summary.decks.length"
        class="summary-card"
      >
        <div class="summary-head">
          <h2 class="summary-title">
            今日小结
          </h2>
          <span class="summary-total">共 {{ summary.totalCount }} 张</span>
        </div>
        <hr class="divider">
        <div
          v-for="deck in summary.decks"
          :key="deck.deckId"
          class="summary-row"
        >
          <Layers3
            :size="16"
            class="summary-icon"
            aria-hidden="true"
          />
          <span class="summary-deck">{{ deck.deckTitle }}</span>
          <span class="summary-count">{{ deck.count }} 张</span>
        </div>
      </div>

      <button
        class="done-btn"
        type="button"
        @click="goToDecks"
      >
        查看卡组
      </button>
    </div>
  </div>

  <div
    v-else
    class="review-page"
  >
    <AuroraBackground />
    <div class="overview">
      <header class="overview-head">
        <h1 class="overview-title">
          今日复习
        </h1>
        <p class="overview-date">
          {{ todayLabel }}
        </p>
      </header>

      <EmptyState
        v-if="plan && plan.cards.length === 0"
        class="overview-empty"
        title="今天没有到期卡片"
        text="去知识树补充或复习卡组吧"
      >
        <button
          class="btn btn-primary"
          type="button"
          @click="goToDecks"
        >
          去知识树
          <ArrowRight
            :size="18"
            aria-hidden="true"
          />
        </button>
      </EmptyState>

      <template v-else-if="plan">
        <ProgressRing
          :value="pending"
          :max="plan.totalCount"
          :percent="progressPercent"
        >
          <span class="ring-number num">{{ pending }}</span>
          <span class="ring-label">张待复习</span>
          <span class="ring-percent">{{ progressPercent }}% 完成</span>
        </ProgressRing>

        <div class="stats">
          <div class="stat-pill">
            <CheckCircle2
              :size="20"
              class="stat-icon"
              aria-hidden="true"
            />
            <span class="stat-value num">{{ plan.completedCount }}/{{ plan.totalCount }}</span>
            <span class="stat-label">今日进度</span>
          </div>
          <div class="stat-pill">
            <Clock3
              :size="20"
              class="stat-icon"
              aria-hidden="true"
            />
            <span class="stat-value">≈{{ plan.estimatedMinutes }} 分钟</span>
            <span class="stat-label">预计时间</span>
          </div>
        </div>

        <div
          v-if="deckProgress.length"
          class="deck-progress"
        >
          <h2 class="section-title">
            卡组进度
          </h2>
          <div
            v-for="item in deckProgress"
            :key="item.deckId"
            class="deck-row"
          >
            <div class="deck-row-head">
              <CheckCircle2
                v-if="isDeckDone(item)"
                :size="18"
                class="deck-icon done"
                aria-hidden="true"
              />
              <Layers3
                v-else
                :size="18"
                class="deck-icon"
                aria-hidden="true"
              />
              <span class="deck-title">{{ item.deckTitle }}</span>
              <span
                v-if="isDeckDone(item)"
                class="deck-status done"
              >已完成</span>
              <span
                v-else
                class="deck-status"
              >剩余 {{ deckPending(item) }} 张</span>
              <span class="deck-count num">{{ item.completedCount }}/{{ item.totalCount }}</span>
            </div>
            <ProgressBar
              :value="item.completedCount"
              :max="item.totalCount"
              :tone="isDeckDone(item) ? 'green' : 'indigo'"
            />
          </div>
        </div>

        <button
          class="start-btn"
          type="button"
          @click="startSession"
        >
          <span>{{ plan.completedCount > 0 ? '继续复习' : '开始复习' }}</span>
          <ArrowRight
            :size="18"
            aria-hidden="true"
          />
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.review-page {
  position: relative;
  min-height: calc(100vh - 56px);
  overflow-x: clip;
}

.state-page {
  display: grid;
  place-items: center;
  padding: 24px;
}

.state-content {
  position: relative;
  z-index: 1;
  width: min(100%, 420px);
}

.overview {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 28px;
  width: min(100%, 720px);
  margin: 0 auto;
  padding: 36px 24px calc(var(--tab-height) + env(safe-area-inset-bottom) + 32px);
}

.overview-head {
  text-align: center;
}

.overview-title {
  display: none;
  font-size: 28px;
  font-weight: 800;
}

.overview-date {
  font-size: 15px;
  color: var(--text-secondary);
}

.overview-empty {
  width: 100%;
  border-radius: var(--radius-xl);
  background: var(--surface-soft);
  border: 1px solid var(--glass-border);
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
}

.ring-number {
  font-family: var(--font-rounded);
  font-size: 54px;
  font-weight: 800;
  line-height: 1;
}

.ring-label {
  font-size: 15px;
  color: var(--text-secondary);
}

.ring-percent {
  font-size: 12px;
  color: var(--text-tertiary);
}

.stats {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 16px;
}

.stat-pill {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  min-width: 132px;
  padding: 14px 20px;
  border-radius: var(--radius-md);
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.stat-icon {
  color: color-mix(in srgb, var(--color-indigo) 75%, var(--text));
}

.stat-value {
  font-family: var(--font-rounded);
  font-size: 17px;
  font-weight: 700;
}

.stat-label {
  font-size: 11px;
  color: var(--text-tertiary);
}

.deck-progress {
  display: flex;
  flex-direction: column;
  gap: 14px;
  width: 100%;
  padding: 18px;
  border-radius: var(--radius-lg);
  background: var(--surface-soft);
  border: 1px solid var(--glass-border);
  box-shadow: var(--shadow-sm);
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
}

.section-title {
  font-size: 16px;
  font-weight: 700;
}

.deck-row {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.deck-row-head {
  display: flex;
  align-items: center;
  gap: 10px;
}

.deck-icon {
  flex: none;
  color: var(--color-indigo);
}

.deck-icon.done {
  color: var(--color-green);
}

.deck-title {
  overflow: hidden;
  font-size: 14px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.deck-status {
  margin-left: auto;
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
}

.deck-status.done {
  color: var(--color-green-text);
  font-weight: 600;
}

.deck-count {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
}

.start-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  width: min(100%, 280px);
  min-height: 56px;
  margin-bottom: 40px;
  border: 0;
  border-radius: 999px;
  background: linear-gradient(135deg, var(--color-indigo), var(--color-purple));
  color: var(--on-primary);
  font-size: 17px;
  font-weight: 700;
  box-shadow: var(--shadow-primary);
  transition: transform 0.15s ease;
}

.start-btn:active {
  transform: scale(0.98);
}

/* ---------- 复习会话 ---------- */

.session {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  gap: 20px;
  width: min(100%, 640px);
  margin: 0 auto;
  padding: 20px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.session-head {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.session-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.exit-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 44px;
  padding: 0 10px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
}

.exit-btn:hover {
  background: var(--surface-muted);
}

.session-meta {
  display: flex;
  align-items: center;
  gap: 12px;
}

.session-count {
  font-size: 15px;
  color: var(--text-secondary);
}

.session-memory {
  font-size: 12px;
  color: var(--color-indigo-text);
}

.flashcard {
  position: relative;
  max-height: 560px;
  perspective: 1400px;
  cursor: pointer;
  outline: none;
}

.flashcard:focus-visible {
  border-radius: var(--radius-xl);
  outline: 2px solid var(--color-indigo);
  outline-offset: 4px;
}

.flashcard-inner {
  position: relative;
  display: grid;
  width: 100%;
  min-height: 260px;
  max-height: 560px;
  transform-style: preserve-3d;
  transition: transform 0.45s cubic-bezier(0.2, 0.8, 0.2, 1);
}

.flashcard.flipped .flashcard-inner {
  transform: rotateY(180deg);
}

.face {
  display: flex;
  flex-direction: column;
  gap: 12px;
  grid-area: 1 / 1;
  max-height: 560px;
  min-height: 260px;
  overflow-y: auto;
  padding: 24px;
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  background: var(--surface);
  box-shadow: var(--shadow-md);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}

.face.back {
  transform: rotateY(180deg);
  border: 1.5px solid color-mix(in srgb, var(--color-indigo) 35%, transparent);
  background: color-mix(in srgb, var(--color-indigo) 10%, var(--surface));
}

.face-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.face-hint {
  margin-left: auto;
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--text-secondary);
  text-transform: uppercase;
}

.type-badge {
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
}

.badge-choice {
  background: color-mix(in srgb, var(--color-orange) 15%, transparent);
  color: var(--color-orange-text);
}

.badge-blank {
  background: color-mix(in srgb, var(--color-teal) 15%, transparent);
  color: var(--color-teal-text);
}

.front-body {
  display: flex;
  flex: 1;
  align-items: center;
  justify-content: center;
}

.question {
  font-size: 20px;
  font-weight: 600;
  line-height: 1.5;
  text-align: center;
  overflow-wrap: anywhere;
}

.back-question {
  display: -webkit-box;
  overflow: hidden;
  font-size: 14px;
  font-weight: 500;
  color: var(--text-secondary);
  line-height: 1.45;
  text-align: center;
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
}

.divider {
  width: 100%;
  margin: 0;
  border: 0;
  border-top: 1px solid var(--border);
}

.back-body {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.answer {
  font-size: 16px;
  line-height: 1.6;
  overflow-wrap: anywhere;
}

.markdown :deep(p) {
  margin: 0 0 8px;
}

.markdown :deep(p:last-child) {
  margin-bottom: 0;
}

.markdown :deep(ul),
.markdown :deep(ol) {
  margin: 0 0 8px;
  padding-left: 1.3em;
}

.markdown :deep(code) {
  padding: 1px 5px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--text) 9%, transparent);
  font-size: 0.9em;
}

.markdown :deep(strong) {
  font-weight: 700;
}

.options {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin: 0;
  padding: 4px 0 0;
  list-style: none;
}

.option {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 13px;
  color: var(--text-secondary);
}

.option-prefix {
  display: grid;
  flex: none;
  place-items: center;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  font-size: 11px;
  font-weight: 700;
}

.option.correct .option-prefix {
  background: var(--color-indigo);
  color: var(--on-primary);
}

.option.correct .option-text {
  color: var(--color-indigo-text);
}

.option-text {
  line-height: 1.45;
}

.note-block {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 10px;
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-teal) 8%, transparent);
}

.note-icon {
  flex: none;
  margin-top: 2px;
  color: var(--color-teal);
}

.note-text {
  font-size: 13px;
  color: var(--text-secondary);
  line-height: 1.5;
}

.flip-hint {
  margin-bottom: 8px;
  font-size: 12px;
  color: var(--text-secondary);
  text-align: center;
}

.answer-panel {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.action-bar {
  display: flex;
  justify-content: center;
  gap: 12px;
}

.action-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  min-height: 44px;
  padding: 0 14px;
  border: 1px solid color-mix(in srgb, var(--action-color) 35%, transparent);
  border-radius: 999px;
  background: color-mix(in srgb, var(--action-color) 10%, transparent);
  color: var(--action-text);
  font-size: 12px;
  font-weight: 600;
}

.action-chat {
  --action-color: var(--color-indigo);
  --action-text: var(--color-indigo-text);
}

.action-edit {
  --action-color: var(--color-orange);
  --action-text: var(--color-orange-text);
}

.action-note {
  --action-color: var(--color-teal);
  --action-text: var(--color-teal-text);
}

.rating-bar {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 10px;
}

.rating {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  min-height: 62px;
  padding: 10px 4px;
  border: 1px solid color-mix(in srgb, var(--rating-color) 40%, transparent);
  border-radius: 14px;
  background: color-mix(in srgb, var(--rating-color) 12%, transparent);
  color: var(--rating-text);
  transition: transform 0.12s ease, opacity 0.12s ease;
}

.rating:active {
  transform: scale(0.97);
}

.rating:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.rating-again {
  --rating-color: var(--color-red);
  --rating-text: var(--color-red-text);
}

.rating-hard {
  --rating-color: var(--color-orange);
  --rating-text: var(--color-orange-text);
}

.rating-good {
  --rating-color: var(--color-green);
  --rating-text: var(--color-green-text);
}

.rating-easy {
  --rating-color: var(--color-indigo);
  --rating-text: var(--color-indigo-text);
}

.rating-label {
  font-size: 15px;
  font-weight: 700;
}

.rating-sub {
  font-size: 11px;
}

.submit-error {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 8px 8px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red-text);
  font-size: 13px;
}

/* ---------- 完成页 ---------- */

.done {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  width: min(100%, 560px);
  margin: 0 auto;
  padding: 64px 24px calc(var(--tab-height) + env(safe-area-inset-bottom) + 32px);
  text-align: center;
}

.done-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 20px;
}

.done-emoji {
  font-size: 80px;
  line-height: 1;
}

.done-title {
  font-size: 28px;
  font-weight: 800;
}

.done-sub {
  font-size: 15px;
  color: var(--text-secondary);
  line-height: 1.5;
}

.summary-loading,
.summary-card {
  width: 100%;
  margin-top: 32px;
}

.summary-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px;
  border-radius: var(--radius-lg);
  background: var(--surface-soft);
  border: 1px solid var(--glass-border);
  box-shadow: var(--shadow-sm);
  text-align: left;
  -webkit-backdrop-filter: blur(16px);
  backdrop-filter: blur(16px);
}

.summary-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.summary-title {
  font-size: 16px;
  font-weight: 700;
}

.summary-total {
  font-size: 14px;
  color: var(--text-secondary);
}

.summary-row {
  display: flex;
  align-items: center;
  gap: 10px;
}

.summary-icon {
  flex: none;
  color: var(--color-indigo);
}

.summary-deck {
  overflow: hidden;
  font-size: 14px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.summary-count {
  margin-left: auto;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-secondary);
  white-space: nowrap;
}

.done-btn {
  width: min(100%, 280px);
  min-height: 56px;
  margin-top: 40px;
  border: 1.5px solid color-mix(in srgb, var(--color-indigo) 30%, transparent);
  border-radius: 999px;
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  color: var(--color-indigo-text);
  font-size: 17px;
  font-weight: 700;
}

@media (min-width: 900px) {
  .review-page {
    min-height: 100vh;
  }

  .overview-title {
    display: block;
    margin-bottom: 6px;
  }

  .overview {
    padding-bottom: 48px;
  }

  .session {
    padding-bottom: 40px;
  }

  .done {
    padding-bottom: 48px;
  }
}
</style>
