<script setup lang="ts">
/* global HTMLElement */
import { nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { Layers3, Send, X } from 'lucide-vue-next'
import type { Flashcard } from '@/core/api/types'
import { toolSummary } from '@/core/coach/tools'
import { friendlyError } from '@/core/errors'
import { renderInlineMarkdown } from '@/core/format/markdown'
import { getRuntime } from '@/runtime'

interface ChatMessage {
  id: number
  role: 'user' | 'assistant'
  text: string
  toolNote?: string
}

const props = defineProps<{ card: Flashcard }>()
const emit = defineEmits<{ close: [] }>()

const messages = ref<ChatMessage[]>([])
const input = ref('')
const thinking = ref(false)
const listEl = ref<HTMLElement | null>(null)
const panelEl = ref<HTMLElement | null>(null)
let nextId = 1
let cancelled = false

const quickQuestions = [
  '帮我讲透这道题',
  '面试官可能会怎么追问？',
  '出一道同考点的题目考考我'
]

function close(): void {
  emit('close')
}

function buildPrompt(question: string): string {
  return `我正在复习这张卡片：
【问题】${props.card.question}
【答案】${props.card.answer}

我的疑问：${question}`
}

async function send(raw: string): Promise<void> {
  const text = raw.trim()
  if (!text || thinking.value) return
  input.value = ''
  messages.value.push({ id: nextId++, role: 'user', text })
  thinking.value = true
  try {
    const run = await getRuntime().endpoints.coach(buildPrompt(text), 'CARD_QA')
    if (cancelled) return
    const output = run.output?.trim()
    const reply = output && output.length > 0
      ? output
      : `教练暂时没有给出有效回复（状态：${run.status}）。`
    messages.value.push({ id: nextId++, role: 'assistant', text: reply, toolNote: toolSummary(run) })
  } catch (e) {
    if (cancelled) return
    messages.value.push({
      id: nextId++,
      role: 'assistant',
      text: `😥 提问失败：${friendlyError(e)}\n\n请确认后端已配置 AI API Key 后重试。`
    })
  } finally {
    if (!cancelled) thinking.value = false
  }
}

watch([() => messages.value.length, thinking], async () => {
  await nextTick()
  const el = listEl.value
  if (el) el.scrollTop = el.scrollHeight
})

onMounted(() => panelEl.value?.focus())
onUnmounted(() => {
  cancelled = true
})
</script>

<template>
  <!-- eslint-disable vue/no-v-html -- markdown 由 renderInlineMarkdown 生成（html: false） -->
  <Teleport to="body">
    <div
      class="sheet-backdrop"
      @click.self="close"
    >
      <div
        ref="panelEl"
        class="sheet-panel chat-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="coach-title"
        tabindex="-1"
        @keydown.esc="close"
      >
        <header class="chat-head">
          <h2
            id="coach-title"
            class="sheet-title"
          >
            AI 学习教练
          </h2>
          <button
            class="close-btn"
            type="button"
            @click="close"
          >
            <X :size="16" />
            <span>关闭</span>
          </button>
        </header>

        <div class="context-banner">
          <Layers3
            :size="14"
            class="context-icon"
          />
          <span class="context-text">{{ card.question }}</span>
        </div>

        <div
          v-if="messages.length === 0 && !thinking"
          class="intro"
        >
          <p class="muted intro-text">
            对当前题目有疑问？直接提问，教练会给出简短、针对性的解释。
          </p>
          <p class="tiny">
            试试这样问：
          </p>
          <button
            v-for="question in quickQuestions"
            :key="question"
            class="quick"
            type="button"
            @click="send(question)"
          >
            <span>{{ question }}</span>
            <span class="quick-arrow">→</span>
          </button>
        </div>

        <div
          v-else
          ref="listEl"
          class="message-list"
        >
          <div
            v-for="message in messages"
            :key="message.id"
            class="message-row"
            :class="message.role"
          >
            <div class="message-body">
              <div
                v-if="message.role === 'assistant'"
                class="bubble assistant"
                v-html="renderInlineMarkdown(message.text)"
              />
              <div
                v-else
                class="bubble user"
              >
                {{ message.text }}
              </div>
              <span
                v-if="message.toolNote"
                class="tiny tool-note"
              >{{ message.toolNote }}</span>
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
            <span class="muted tiny">教练正在回答…</span>
          </div>
        </div>

        <div class="composer">
          <input
            v-model="input"
            class="input composer-input"
            type="text"
            placeholder="输入你的疑问…"
            aria-label="你的问题"
            @keydown.enter.prevent="send(input)"
          >
          <button
            class="send-btn"
            type="button"
            aria-label="发送"
            :disabled="thinking || input.trim().length === 0"
            @click="send(input)"
          >
            <Send :size="20" />
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.chat-panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  height: min(90vh, 720px);
  overflow: hidden;
}

.chat-panel:focus {
  outline: none;
}

.chat-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.sheet-title {
  font-size: 18px;
  font-weight: 700;
}

.close-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-height: 44px;
  padding: 0 12px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
}

.close-btn:hover {
  background: var(--surface-muted);
}

.context-banner {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 8px 14px;
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-indigo) 7%, transparent);
}

.context-icon {
  flex: none;
  margin-top: 3px;
  color: var(--color-indigo);
}

.context-text {
  display: -webkit-box;
  overflow: hidden;
  font-size: 13px;
  color: var(--text-secondary);
  line-height: 1.5;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.intro {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow-y: auto;
  padding: 4px 2px;
}

.intro-text {
  font-size: 13px;
  line-height: 1.6;
}

.quick {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: 44px;
  padding: 10px 14px;
  border: 0;
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
  color: var(--text);
  font-size: 14px;
  text-align: left;
}

.quick:hover {
  background: color-mix(in srgb, var(--color-indigo) 12%, var(--surface-muted));
}

.quick-arrow {
  color: var(--color-indigo);
  font-weight: 700;
}

.message-list {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 12px;
  overflow-y: auto;
  padding: 4px 2px;
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

.message-body {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-width: 85%;
}

.message-row.user .message-body {
  align-items: flex-end;
}

.bubble {
  padding: 9px 13px;
  border-radius: var(--radius-md);
  font-size: 14px;
  line-height: 1.55;
  overflow-wrap: anywhere;
}

.bubble.user {
  border-bottom-right-radius: 4px;
  background: var(--color-indigo);
  color: var(--on-primary);
  white-space: pre-wrap;
}

.bubble.assistant {
  border-bottom-left-radius: 4px;
  background: var(--surface-muted);
  color: var(--text);
}

.bubble.assistant :deep(p) {
  margin: 0 0 6px;
}

.bubble.assistant :deep(p:last-child) {
  margin-bottom: 0;
}

.bubble.assistant :deep(code) {
  padding: 1px 5px;
  border-radius: 6px;
  background: color-mix(in srgb, var(--text) 10%, transparent);
  font-size: 0.9em;
}

.bubble.assistant :deep(strong) {
  font-weight: 700;
}

.tool-note {
  padding: 0 4px;
}

.thinking {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px;
}

.spinner {
  width: 18px;
  height: 18px;
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
  align-items: center;
  gap: 10px;
  padding-top: 10px;
  border-top: 1px solid var(--border);
}

.composer-input {
  flex: 1;
}

.send-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--color-indigo);
}

.send-btn:disabled {
  color: var(--text-tertiary);
  cursor: not-allowed;
}
</style>
