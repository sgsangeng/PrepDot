<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowRight,
  Check,
  CheckCircle2,
  RotateCcw,
  X,
  XCircle
} from 'lucide-vue-next'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import ProgressBar from '@/ui/components/ProgressBar.vue'
import type { Flashcard } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { buildQuiz, scoreQuiz, type QuizQuestion } from '@/core/quiz/quiz'
import { getRuntime } from '@/runtime'

type OptionState = 'normal' | 'selected' | 'correct' | 'wrong'
type ScoreTone = 'green' | 'orange' | 'red'

const route = useRoute()
const router = useRouter()

const cards = ref<Flashcard[]>([])
const questions = ref<QuizQuestion[]>([])
const loading = ref(true)
const error = ref('')

const current = ref(0)
const selected = ref<number | null>(null)
const answered = ref(false)
const answers = ref<number[]>([])
const finished = ref(false)

let loadSeq = 0

const deckId = computed<number | null>(() => {
  const raw = route.params.id
  const value = Array.isArray(raw) ? raw[0] : raw
  const parsed = Number(value)
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null
})

const question = computed<QuizQuestion | null>(() => questions.value[current.value] ?? null)
const correctCount = computed(() => scoreQuiz(questions.value, answers.value))
const accuracy = computed(() =>
  questions.value.length === 0
    ? 0
    : Math.round((correctCount.value / questions.value.length) * 100)
)
const isCorrect = computed(
  () => question.value != null && selected.value === question.value.correctIndex
)
const scoreTone = computed<ScoreTone>(() => {
  if (accuracy.value >= 80) return 'green'
  if (accuracy.value >= 60) return 'orange'
  return 'red'
})
const resultTitle = computed(() => {
  if (questions.value.length === 0) return ''
  const ratio = correctCount.value / questions.value.length
  if (ratio === 1) return '完美！全部正确 🎉'
  if (ratio >= 0.8) return '非常棒！继续保持 💪'
  if (ratio >= 0.6) return '不错，还需加强 📚'
  return '需要多复习哦 😅'
})

const ringRadius = 58
const circumference = 2 * Math.PI * ringRadius
const ringDash = computed(() => {
  if (questions.value.length === 0) return 0
  return (correctCount.value / questions.value.length) * circumference
})

function optionLabel(index: number): string {
  return ['A', 'B', 'C', 'D'][index] ?? String(index + 1)
}

function optionState(index: number): OptionState {
  const q = question.value
  if (!q) return 'normal'
  if (!answered.value) return selected.value === index ? 'selected' : 'normal'
  if (index === q.correctIndex) return 'correct'
  if (index === selected.value) return 'wrong'
  return 'normal'
}

function resetRun(): void {
  current.value = 0
  selected.value = null
  answered.value = false
  answers.value = []
  finished.value = false
}

function start(): void {
  if (cards.value.length < 2) {
    questions.value = []
    return
  }
  questions.value = buildQuiz(cards.value, 10)
  resetRun()
}

async function load(): Promise<void> {
  const id = deckId.value
  const seq = ++loadSeq
  loading.value = true
  error.value = ''
  questions.value = []
  resetRun()
  try {
    if (id == null) {
      cards.value = []
      return
    }
    const loaded = await getRuntime().endpoints.cards(id, false)
    if (seq !== loadSeq) return
    cards.value = loaded
    start()
  } catch (e) {
    if (seq !== loadSeq) return
    error.value = friendlyError(e)
  } finally {
    if (seq === loadSeq) loading.value = false
  }
}

function choose(index: number): void {
  if (answered.value || !question.value) return
  selected.value = index
  answered.value = true
  const next = [...answers.value]
  next[current.value] = index
  answers.value = next
}

function nextQuestion(): void {
  if (current.value < questions.value.length - 1) {
    current.value += 1
    selected.value = null
    answered.value = false
  } else {
    finished.value = true
  }
}

function restart(): void {
  start()
}

function exitQuiz(): void {
  const id = deckId.value
  if (id == null) {
    void router.replace({ name: 'decks' })
    return
  }
  void router.replace({ name: 'decks', params: { id: String(id) } })
}

watch(
  () => deckId.value,
  () => {
    cards.value = []
    void load()
  },
  { immediate: true }
)
</script>

<template>
  <section class="quiz-page">
    <header class="quiz-head">
      <button
        class="exit-btn"
        type="button"
        @click="exitQuiz"
      >
        <X
          :size="18"
          aria-hidden="true"
        />
        <span>退出</span>
      </button>
      <h1 class="page-heading">
        选择题模式
      </h1>
      <span
        class="head-spacer"
        aria-hidden="true"
      />
    </header>

    <div
      v-if="loading"
      class="state-card"
    >
      <LoadingState text="正在加载卡片…" />
    </div>

    <div
      v-else-if="error"
      class="state-card"
    >
      <ErrorState
        title="测验加载失败"
        :message="error"
        retry-text="重新加载"
        show-retry
        @retry="load"
      />
    </div>

    <div
      v-else-if="deckId == null"
      class="state-card"
    >
      <EmptyState
        title="无法开始测验"
        text="请从卡组详情进入选择题模式"
      >
        <button
          class="btn btn-primary"
          type="button"
          @click="exitQuiz"
        >
          返回知识树
        </button>
      </EmptyState>
    </div>

    <div
      v-else-if="cards.length < 2"
      class="state-card"
    >
      <EmptyState
        title="卡片不足"
        text="选择题至少需要 2 张卡片"
      >
        <button
          class="btn btn-primary"
          type="button"
          @click="exitQuiz"
        >
          返回卡组
        </button>
      </EmptyState>
    </div>

    <div
      v-else-if="finished"
      class="result"
    >
      <div
        class="score-wrap"
        role="img"
        :aria-label="`得分 ${correctCount} / ${questions.length}`"
      >
        <svg
          class="score-ring"
          viewBox="0 0 140 140"
          aria-hidden="true"
        >
          <circle
            class="ring-track"
            cx="70"
            cy="70"
            :r="ringRadius"
            fill="none"
            stroke-width="12"
          />
          <circle
            class="ring-value"
            :class="scoreTone"
            cx="70"
            cy="70"
            :r="ringRadius"
            fill="none"
            stroke-width="12"
            stroke-linecap="round"
            :stroke-dasharray="`${ringDash} ${circumference}`"
            transform="rotate(-90 70 70)"
          />
        </svg>
        <div class="score-center">
          <span class="score-number">{{ correctCount }}/{{ questions.length }}</span>
          <span class="score-label">正确</span>
        </div>
      </div>

      <div class="result-text">
        <h2 class="result-title">
          {{ resultTitle }}
        </h2>
        <p class="result-accuracy">
          正确率 {{ accuracy }}%
        </p>
      </div>

      <div class="result-actions">
        <button
          class="btn btn-ghost"
          type="button"
          @click="restart"
        >
          <RotateCcw
            :size="18"
            aria-hidden="true"
          />
          再来一次
        </button>
        <button
          class="btn btn-primary"
          type="button"
          @click="exitQuiz"
        >
          退出
        </button>
      </div>
    </div>

    <div
      v-else-if="question"
      class="quiz"
    >
      <ProgressBar
        :value="current + 1"
        :max="questions.length"
      />

      <div class="question-card">
        <p class="question-count">
          第 {{ current + 1 }} 题 / 共 {{ questions.length }} 题
        </p>
        <p class="question-text">
          {{ question.question }}
        </p>
      </div>

      <div
        class="options"
        role="group"
        aria-label="选项"
      >
        <button
          v-for="(option, index) in question.options"
          :key="index"
          class="option-btn"
          :class="optionState(index)"
          type="button"
          :aria-pressed="selected === index"
          :disabled="answered"
          @click="choose(index)"
        >
          <span class="option-letter">{{ optionLabel(index) }}</span>
          <span class="option-text">{{ option }}</span>
          <Check
            v-if="answered && index === question.correctIndex"
            :size="18"
            class="option-mark correct-mark"
            aria-hidden="true"
          />
          <X
            v-else-if="answered && index === selected"
            :size="18"
            class="option-mark wrong-mark"
            aria-hidden="true"
          />
        </button>
      </div>

      <div
        v-if="answered"
        class="feedback"
        :class="isCorrect ? 'correct' : 'wrong'"
        aria-live="polite"
      >
        <div class="feedback-head">
          <CheckCircle2
            v-if="isCorrect"
            :size="20"
            aria-hidden="true"
          />
          <XCircle
            v-else
            :size="20"
            aria-hidden="true"
          />
          <span>{{ isCorrect ? '回答正确' : '回答错误' }}</span>
        </div>
        <p class="feedback-answer">
          正确答案：{{ question.options[question.correctIndex] }}
        </p>
        <button
          class="btn btn-primary next-btn"
          type="button"
          @click="nextQuestion"
        >
          {{ current < questions.length - 1 ? '下一题' : '查看结果' }}
          <ArrowRight
            :size="18"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
  </section>
</template>

<style scoped>
.quiz-page {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: min(100%, 720px);
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.quiz-head {
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

.page-heading {
  display: none;
  font-size: 20px;
  font-weight: 800;
}

.head-spacer {
  display: none;
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

.quiz {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.question-card {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 18px;
  border-radius: var(--radius-md);
  background: var(--surface-muted);
}

.question-count {
  color: var(--text-secondary);
  font-size: 12px;
}

.question-text {
  font-size: 18px;
  font-weight: 600;
  line-height: 1.5;
  white-space: pre-line;
  overflow-wrap: anywhere;
}

.options {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.option-btn {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  width: 100%;
  min-height: 56px;
  padding: 14px;
  border: 1.5px solid transparent;
  border-radius: 14px;
  background: var(--surface-muted);
  color: var(--text);
  text-align: left;
  transition: background 0.15s ease, border-color 0.15s ease;
}

.option-btn.normal:hover:not(:disabled) {
  background: color-mix(in srgb, var(--text) 8%, var(--surface-muted));
}

.option-btn.selected {
  border-color: var(--color-indigo);
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
}

.option-btn.correct {
  border-color: var(--color-green);
  background: color-mix(in srgb, var(--color-green) 14%, transparent);
}

.option-btn.wrong {
  border-color: var(--color-red);
  background: color-mix(in srgb, var(--color-red) 14%, transparent);
}

.option-btn:disabled {
  cursor: default;
}

.option-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

.option-letter {
  display: grid;
  flex: none;
  place-items: center;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: var(--text-tertiary);
  color: var(--on-primary);
  font-size: 13px;
  font-weight: 700;
}

.selected .option-letter {
  background: var(--color-indigo);
}

.correct .option-letter {
  background: var(--color-green);
}

.wrong .option-letter {
  background: var(--color-red);
}

.option-text {
  flex: 1;
  min-width: 0;
  padding-top: 3px;
  font-size: 14px;
  line-height: 1.5;
  overflow-wrap: anywhere;
}

.option-mark {
  flex: none;
  margin-top: 5px;
}

.correct-mark {
  color: var(--color-green);
}

.wrong-mark {
  color: var(--color-red);
}

.feedback {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 14px;
  border-radius: var(--radius-sm);
}

.feedback.correct {
  background: color-mix(in srgb, var(--color-green) 8%, transparent);
}

.feedback.wrong {
  background: color-mix(in srgb, var(--color-red) 8%, transparent);
}

.feedback-head {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 600;
}

.feedback.correct .feedback-head {
  color: var(--color-green);
}

.feedback.wrong .feedback-head {
  color: var(--color-red);
}

.feedback-answer {
  color: var(--text-secondary);
  font-size: 14px;
  overflow-wrap: anywhere;
}

.next-btn {
  width: 100%;
  min-height: 48px;
  margin-top: 4px;
}

.result {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 28px;
  padding: 36px 0;
  text-align: center;
}

.score-wrap {
  position: relative;
  width: 140px;
  height: 140px;
}

.score-ring {
  display: block;
  width: 100%;
  height: 100%;
}

.ring-track {
  stroke: color-mix(in srgb, var(--text) 10%, transparent);
}

.ring-value {
  transition: stroke-dasharray 0.8s ease-out;
}

.ring-value.green {
  stroke: var(--color-green);
}

.ring-value.orange {
  stroke: var(--color-orange);
}

.ring-value.red {
  stroke: var(--color-red);
}

.score-center {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
}

.score-number {
  font-family: var(--font-rounded);
  font-size: 34px;
  font-weight: 800;
  line-height: 1;
}

.score-label {
  color: var(--text-secondary);
  font-size: 12px;
}

.result-text {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.result-title {
  font-size: 22px;
  font-weight: 800;
}

.result-accuracy {
  color: var(--text-secondary);
  font-size: 14px;
}

.result-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 12px;
}

.exit-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .quiz-page {
    padding: 24px 32px 48px;
  }

  .page-heading {
    display: block;
  }

  .head-spacer {
    display: block;
    width: 76px;
  }
}
</style>
