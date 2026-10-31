<script setup lang="ts">
/* global HTMLElement, KeyboardEvent, MouseEvent */
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import {
  ArrowUp,
  ChevronRight,
  Clock3,
  Hourglass,
  ShieldCheck,
  Sparkles,
  SquarePen,
  Trash2,
  Wrench,
  X
} from 'lucide-vue-next'
import type { AgentRun, AgentStep } from '@/core/api/types'
import { createSseParser } from '@/core/api/sse'
import type { CoachMessage, CoachTrendPoint, CoachWeakCardPoint } from '@/core/coach/sessions'
import { relativeTimeLabel } from '@/core/coach/sessions'
import { extractToolResult, localizeProgress, toolSummary } from '@/core/coach/tools'
import { friendlyError } from '@/core/errors'
import { renderInlineMarkdown, renderMarkdown } from '@/core/format/markdown'
import { getRuntime } from '@/runtime'
import BarChart from '@/ui/components/charts/BarChart.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import { useCoachStore } from '@/ui/stores/coach'

interface BarChartPoint {
  label: string
  value: number
}

const quickQuestions = [
  '分析我最近掌握得最差的知识点',
  '看看我最近两周的复习趋势',
  '哪些卡组很久没有复习了？',
  '根据我的薄弱点生成 5 张补强卡片'
]

const store = useCoachStore()
const loading = ref(true)
// 进行中状态存放在 store：页面被路由切走再挂载回来时仍能立即看到进度并保持禁用。
const thinking = computed(() => store.thinking)
const progress = computed(() => store.progress)
const input = ref('')
const listEl = ref<HTMLElement | null>(null)

const historyOpen = ref(false)
const historyPanel = ref<HTMLElement | null>(null)
const historyNow = ref(0)
let historyTrigger: HTMLElement | null = null

async function scrollToBottom(): Promise<void> {
  await nextTick()
  const el = listEl.value
  if (el) el.scrollTop = el.scrollHeight
}

async function initialize(): Promise<void> {
  try {
    await store.load()
  } finally {
    loading.value = false
  }
  await scrollToBottom()
}

/** 校验并收窄 SSE `result` 事件里的 AgentRun，避免脏数据让渲染崩溃。 */
function parseAgentRun(data: string): AgentRun {
  const parsed: unknown = JSON.parse(data)
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error('学习教练返回了无法解析的结果')
  }
  const candidate = parsed as Partial<AgentRun>
  if (typeof candidate.status !== 'string' || !Array.isArray(candidate.steps)) {
    throw new Error('学习教练返回了无法解析的结果')
  }
  const steps = candidate.steps.filter(
    (step): step is AgentStep => typeof step === 'object' && step !== null
  )
  return {
    runId: typeof candidate.runId === 'number' ? candidate.runId : 0,
    status: candidate.status,
    output: typeof candidate.output === 'string' ? candidate.output : null,
    stepCount: typeof candidate.stepCount === 'number' ? candidate.stepCount : steps.length,
    steps
  }
}

/**
 * 优先走 SSE；`error` 事件、连接失败或没有收到 result 时回退到 JSON 接口。
 * 回退也失败时把异常抛给调用方，由页面渲染友好错误气泡。
 */
async function requestRun(text: string): Promise<AgentRun> {
  let run: AgentRun | null = null
  const parser = createSseParser((event) => {
    if (event.event === 'progress') {
      store.setProgress(localizeProgress(event.data))
      return
    }
    if (event.event === 'result') {
      run = parseAgentRun(event.data)
      return
    }
    if (event.event === 'error') {
      throw new Error(event.data || '学习教练运行失败')
    }
  })

  try {
    for await (const chunk of getRuntime().endpoints.coachStream(text)) {
      parser(chunk)
    }
    if (run) return run
  } catch {
    // SSE 未发布或运行失败：自动回退到原有 JSON 接口（与 iOS 一致）。
  }
  return getRuntime().endpoints.coach(text)
}

async function appendReply(sessionId: string, run: AgentRun): Promise<void> {
  const output = run.output?.trim() ?? ''
  const trend = extractToolResult<CoachTrendPoint>(run, 'get_review_trend')
  const weakCards = extractToolResult<CoachWeakCardPoint>(run, 'get_weak_cards')
  const message: CoachMessage = {
    id: store.nextMessageId(),
    role: 'assistant',
    text: output.length > 0 ? output : `教练没有返回有效建议（状态：${run.status}）。`,
    toolNote: toolSummary(run)
  }
  if (trend.length > 0) message.trend = trend
  if (weakCards.length > 0) message.weakCards = weakCards
  await store.addMessage(sessionId, message)
}

async function send(raw: string): Promise<void> {
  if (loading.value) return
  const text = raw.trim()
  if (!text || thinking.value) return
  // 捕获发送时的会话：即使之后可见会话变化，回复也归档到发起提问的会话。
  const sessionId = store.currentId
  if (!sessionId) return

  input.value = ''
  store.beginRun(sessionId)
  try {
    await store.addMessage(sessionId, {
      id: store.nextMessageId(),
      role: 'user',
      text
    })
    try {
      const run = await requestRun(text)
      await appendReply(sessionId, run)
    } catch (error) {
      await store.addMessage(sessionId, {
        id: store.nextMessageId(),
        role: 'assistant',
        text: `分析失败：${friendlyError(error)}`
      })
    }
  } finally {
    store.finishRun()
  }
}

function onInputKeydown(event: KeyboardEvent): void {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return
  event.preventDefault()
  void send(input.value)
}

function trendPoints(message: CoachMessage): BarChartPoint[] {
  return (message.trend ?? [])
    // 工具结果来自远端 JSON，运行时再校验一次，避免脏数据让渲染崩溃。
    .filter(point => typeof point.date === 'string' && Number.isFinite(point.total))
    .map(point => ({
      label: point.date.slice(5),
      value: point.total
    }))
}

function weakCardPoints(message: CoachMessage): BarChartPoint[] {
  return (message.weakCards ?? [])
    .filter(point => typeof point.question === 'string' && Number.isFinite(point.memoryScore))
    .slice(0, 8)
    .map(point => ({
      label: point.question.slice(0, 10),
      value: point.memoryScore
    }))
}

async function openHistory(event: MouseEvent): Promise<void> {
  if (thinking.value) return
  historyTrigger = event.currentTarget instanceof HTMLElement ? event.currentTarget : null
  historyNow.value = getRuntime().adapters.clock.now()
  historyOpen.value = true
  await nextTick()
  historyPanel.value?.focus()
}

async function closeHistory(): Promise<void> {
  if (!historyOpen.value) return
  historyOpen.value = false
  const trigger = historyTrigger
  historyTrigger = null
  if (trigger) {
    await nextTick()
    trigger.focus()
  }
}

async function startNewSession(): Promise<void> {
  if (thinking.value) return
  await store.newSession()
  if (historyOpen.value) await closeHistory()
  await scrollToBottom()
}

async function switchTo(id: string): Promise<void> {
  if (thinking.value) return
  await store.switchSession(id)
  await closeHistory()
  await scrollToBottom()
}

async function removeSession(id: string): Promise<void> {
  if (thinking.value) return
  await store.deleteSession(id)
  historyNow.value = getRuntime().adapters.clock.now()
  await nextTick()
  historyPanel.value?.focus()
}

watch(
  () => [store.messages.length, thinking.value, store.currentId],
  () => {
    void scrollToBottom()
  }
)

onMounted(() => {
  void initialize()
})
</script>

<template>
  <!-- eslint-disable vue/no-v-html -- markdown 由 renderMarkdown/renderInlineMarkdown 生成（html: false） -->
  <section class="coach-page">
    <header class="coach-head">
      <h1 class="coach-title">
        AI 学习教练
      </h1>
      <div class="head-actions">
        <button
          class="icon-btn"
          type="button"
          aria-label="历史会话"
          :disabled="thinking"
          @click="openHistory"
        >
          <Clock3
            :size="20"
            aria-hidden="true"
          />
        </button>
        <button
          class="icon-btn"
          type="button"
          aria-label="新建会话"
          :disabled="thinking"
          @click="startNewSession"
        >
          <SquarePen
            :size="20"
            aria-hidden="true"
          />
        </button>
      </div>
    </header>

    <div
      class="safety-banner"
      role="note"
    >
      <ShieldCheck
        :size="16"
        class="safety-icon"
        aria-hidden="true"
      />
      <p>
        教练会读取你的学习数据进行诊断；生成的补强卡片仅供预览，不会自动新增、修改或删除卡片。
      </p>
    </div>

    <div
      v-if="loading"
      class="coach-loading"
    >
      <LoadingState text="正在加载会话…" />
    </div>

    <div
      v-else-if="store.messages.length === 0 && !thinking"
      class="coach-intro"
    >
      <div class="intro-head">
        <h2 class="intro-title">
          基于真实复习数据给建议
        </h2>
        <p class="intro-desc">
          你可以让教练查找薄弱卡片、分析复习趋势、检查长期未复习的卡组，或生成经过质检的补强卡片预览。
        </p>
      </div>

      <button
        v-for="question in quickQuestions"
        :key="question"
        class="quick-btn"
        type="button"
        :disabled="thinking"
        @click="send(question)"
      >
        <Sparkles
          :size="17"
          class="quick-icon"
          aria-hidden="true"
        />
        <span class="quick-text">{{ question }}</span>
        <ChevronRight
          :size="18"
          class="quick-arrow"
          aria-hidden="true"
        />
      </button>
    </div>

    <div
      v-else
      ref="listEl"
      class="message-list"
      role="log"
      aria-live="polite"
    >
      <div
        v-for="message in store.messages"
        :key="message.id"
        class="message-row"
        :class="message.role"
      >
        <div
          class="bubble"
          :class="message.role"
        >
          <div
            v-if="message.role === 'assistant'"
            class="bubble-text"
            v-html="renderMarkdown(message.text)"
          />
          <div
            v-else
            class="bubble-text"
            v-html="renderInlineMarkdown(message.text)"
          />

          <div
            v-if="trendPoints(message).length > 0"
            class="chart-block"
          >
            <p class="chart-title">
              近期复习量
            </p>
            <BarChart
              :data="trendPoints(message)"
              label="近期复习量柱状图"
            />
          </div>

          <div
            v-if="weakCardPoints(message).length > 0"
            class="chart-block"
          >
            <p class="chart-title">
              薄弱卡片记忆度
            </p>
            <BarChart
              :data="weakCardPoints(message)"
              label="薄弱卡片记忆度横条图"
              horizontal
            />
          </div>

          <p
            v-if="message.toolNote"
            class="tool-note"
          >
            <Wrench
              :size="12"
              aria-hidden="true"
            />
            <span>{{ message.toolNote }}</span>
          </p>
        </div>
      </div>

      <div
        v-if="thinking"
        class="thinking"
        role="status"
        aria-live="polite"
      >
        <span
          class="spinner"
          aria-hidden="true"
        />
        <span>{{ progress || '正在读取学习数据并分析…' }}</span>
      </div>
    </div>

    <div class="composer">
      <textarea
        v-model="input"
        class="composer-input"
        rows="1"
        placeholder="问问最近学得怎么样…"
        aria-label="输入你的问题"
        @keydown="onInputKeydown"
      />
      <button
        class="send-btn"
        type="button"
        aria-label="发送"
        :disabled="thinking || input.trim().length === 0"
        @click="send(input)"
      >
        <Hourglass
          v-if="thinking"
          :size="22"
          aria-hidden="true"
        />
        <ArrowUp
          v-else
          :size="22"
          aria-hidden="true"
        />
      </button>
    </div>
  </section>

  <Teleport to="body">
    <div
      v-if="historyOpen"
      class="sheet-backdrop"
      @click.self="closeHistory"
    >
      <div
        ref="historyPanel"
        class="sheet-panel history-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="coach-history-title"
        tabindex="-1"
        @keydown.esc="closeHistory"
      >
        <header class="sheet-bar">
          <h2
            id="coach-history-title"
            class="sheet-title"
          >
            历史会话
          </h2>
          <button
            class="text-btn"
            type="button"
            @click="startNewSession"
          >
            新建
          </button>
          <button
            class="icon-btn"
            type="button"
            aria-label="关闭"
            @click="closeHistory"
          >
            <X
              :size="18"
              aria-hidden="true"
            />
          </button>
        </header>

        <ul class="history-list">
          <li
            v-for="session in store.orderedSessions"
            :key="session.id"
            class="history-row"
          >
            <button
              class="history-item"
              type="button"
              @click="switchTo(session.id)"
            >
              <span class="history-title">{{ session.title }}</span>
              <span class="history-time">{{ relativeTimeLabel(session.updatedAt, historyNow) }}</span>
            </button>
            <button
              class="history-delete"
              type="button"
              :aria-label="`删除会话：${session.title}`"
              @click="removeSession(session.id)"
            >
              <Trash2
                :size="17"
                aria-hidden="true"
              />
            </button>
          </li>
        </ul>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.coach-page {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: calc(100vh - 56px - var(--tab-height) - env(safe-area-inset-bottom));
  height: calc(100dvh - 56px - var(--tab-height) - env(safe-area-inset-bottom));
  padding: 0 16px;
  overflow: hidden;
}

.coach-head {
  display: flex;
  flex: none;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 52px;
}

.coach-title {
  display: none;
  font-size: 20px;
  font-weight: 800;
}

.head-actions {
  display: flex;
  gap: 4px;
  margin-left: auto;
}

.icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
}

.icon-btn:hover:not(:disabled) {
  background: var(--surface-muted);
}

.icon-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.safety-banner {
  display: flex;
  flex: none;
  align-items: flex-start;
  gap: 8px;
  margin-bottom: 8px;
  padding: 10px 14px;
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-indigo) 6%, transparent);
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.55;
}

.safety-icon {
  flex: none;
  margin-top: 2px;
  color: var(--color-indigo);
}

.coach-loading {
  display: grid;
  flex: 1;
  place-items: center;
}

.coach-intro {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  padding: 8px 0 16px;
  overflow-y: auto;
}

.intro-head {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 4px;
}

.intro-title {
  font-size: 18px;
  font-weight: 700;
}

.intro-desc {
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.6;
}

.quick-btn {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-height: 44px;
  padding: 14px;
  border: 0;
  border-radius: var(--radius-md);
  background: var(--surface-muted);
  color: var(--text);
  font-size: 14px;
  text-align: left;
}

.quick-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--color-indigo) 10%, var(--surface-muted));
}

.quick-btn:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.quick-icon {
  flex: none;
  color: var(--color-indigo);
}

.quick-text {
  flex: 1;
  min-width: 0;
  line-height: 1.45;
}

.quick-arrow {
  flex: none;
  color: var(--color-indigo);
}

.message-list {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  padding: 12px 0 16px;
  overflow-y: auto;
  overscroll-behavior: contain;
}

.message-row {
  display: flex;
  width: 100%;
}

.message-row.user {
  justify-content: flex-end;
}

.message-row.assistant {
  justify-content: flex-start;
}

.bubble {
  max-width: 88%;
  padding: 10px 14px;
  border-radius: var(--radius-md);
  font-size: 14px;
  line-height: 1.6;
  overflow-wrap: anywhere;
}

.bubble.user {
  max-width: 82%;
  border-bottom-right-radius: 4px;
  background: var(--color-indigo);
  color: var(--on-primary);
}

.bubble.assistant {
  max-width: 92%;
  border-bottom-left-radius: 4px;
  background: var(--surface-muted);
  color: var(--text);
}

.bubble-text :deep(p) {
  margin: 0 0 6px;
}

.bubble-text :deep(p:last-child) {
  margin-bottom: 0;
}

.bubble-text :deep(ul),
.bubble-text :deep(ol) {
  margin: 4px 0;
}

.bubble-text :deep(li) {
  margin: 2px 0;
}

.bubble-text :deep(code) {
  padding: 1px 5px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--text) 10%, transparent);
  font-size: 0.9em;
}

.bubble-text :deep(pre) {
  padding: 10px 12px;
  overflow-x: auto;
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--text) 8%, transparent);
}

.bubble-text :deep(pre code) {
  padding: 0;
  background: transparent;
}

.bubble-text :deep(strong) {
  font-weight: 700;
}

.bubble-text :deep(a) {
  color: var(--color-indigo);
  text-decoration: underline;
}

.bubble.user .bubble-text :deep(a) {
  color: var(--on-primary);
}

.chart-block {
  margin-top: 10px;
}

.chart-title {
  margin-bottom: 6px;
  color: var(--text-secondary);
  font-size: 12px;
  font-weight: 700;
}

.tool-note {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-top: 8px;
  color: var(--text-tertiary);
  font-size: 12px;
}

.thinking {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 4px;
  color: var(--text-secondary);
  font-size: 12px;
}

.spinner {
  flex: none;
  width: 16px;
  height: 16px;
  border: 2px solid var(--surface-muted);
  border-top-color: var(--color-indigo);
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.composer {
  display: flex;
  flex: none;
  align-items: flex-end;
  gap: 10px;
  padding: 10px 0 12px;
  border-top: 1px solid var(--border);
}

.composer-input {
  flex: 1;
  max-height: 120px;
  min-height: 44px;
  padding: 11px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
  color: var(--text);
  font-size: 14px;
  line-height: 1.5;
  outline: none;
  resize: none;
}

.composer-input:focus {
  border-color: var(--color-indigo);
  box-shadow: 0 0 0 3px var(--focus-ring);
}

.send-btn {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--color-indigo);
}

.send-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--color-indigo) 10%, transparent);
}

.send-btn:disabled {
  color: var(--text-tertiary);
  cursor: not-allowed;
}

.history-panel {
  display: flex;
  flex-direction: column;
  max-height: min(560px, 80vh);
  padding: 0;
  overflow: hidden;
}

.history-panel:focus {
  outline: none;
}

.sheet-bar {
  display: flex;
  flex: none;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--border);
}

.sheet-title {
  flex: 1;
  font-size: 17px;
  font-weight: 700;
}

.text-btn {
  min-height: 44px;
  padding: 0 12px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
}

.text-btn:hover {
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.history-list {
  flex: 1;
  margin: 0;
  padding: 4px 8px calc(8px + env(safe-area-inset-bottom));
  overflow-y: auto;
  list-style: none;
}

.history-row {
  display: flex;
  align-items: center;
  gap: 4px;
}

.history-row + .history-row {
  border-top: 1px solid var(--border);
}

.history-item {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  min-height: 56px;
  padding: 10px 12px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text);
  text-align: left;
}

.history-item:hover {
  background: var(--surface-muted);
}

.history-title {
  overflow: hidden;
  font-size: 14px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.history-time {
  color: var(--text-tertiary);
  font-size: 12px;
}

.history-delete {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-tertiary);
}

.history-delete:hover {
  background: color-mix(in srgb, var(--color-red) 10%, transparent);
  color: var(--color-red);
}

.icon-btn:focus-visible,
.text-btn:focus-visible,
.quick-btn:focus-visible,
.send-btn:focus-visible,
.history-item:focus-visible,
.history-delete:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .coach-page {
    width: min(100%, 860px);
    height: 100vh;
    height: 100dvh;
    margin: 0 auto;
    padding: 0 24px;
  }

  .coach-title {
    display: block;
  }

  .coach-head {
    min-height: 64px;
  }
}
</style>
