<script setup lang="ts">
/* global Event, HTMLInputElement, HTMLElement */
import { computed, ref } from 'vue'
import { Bold, CheckCircle2, Circle, Code, List, ListOrdered, X } from 'lucide-vue-next'
import type { CardPayload, Flashcard } from '@/core/api/types'
import { buildCardPayload, type CardMode } from '@/core/cards/payload'
import { friendlyError } from '@/core/errors'
import { parseCardOptions } from '@/core/review/session'
import { normalizeCardType } from '@/core/format/text'
import { getRuntime } from '@/runtime'
import { useDialogFocus } from '@/ui/composables/useDialogFocus'

type EditorField = 'question' | 'answer'

const props = defineProps<{ deckId: number; card?: Flashcard; deckCategory?: string }>()
const emit = defineEmits<{ saved: [card: Flashcard]; close: [] }>()

const modeTabs: readonly { value: CardMode; label: string }[] = [
  { value: 'qa', label: '问答' },
  { value: 'choice', label: '选择题' },
  { value: 'blank', label: '填空' }
]

const mode = ref<CardMode>(props.card ? normalizeCardType(props.card.cardType) : 'qa')
const question = ref(props.card?.question ?? '')
const answer = ref(props.card?.answer ?? '')
const optionA = ref('')
const optionB = ref('')
const optionC = ref('')
const optionD = ref('')
const correctIndex = ref(0)
const saving = ref(false)
const saveError = ref('')
const panelEl = ref<HTMLElement | null>(null)

const optionValues = computed(() => [optionA.value, optionB.value, optionC.value, optionD.value])
const selectedOption = computed(() => optionValues.value[correctIndex.value] ?? '')
const isEdit = computed(() => props.card !== undefined)

const modeHint = computed(() => {
  if (mode.value === 'choice') return '设置 2-4 个选项，选择正确答案，复习时作为单选题'
  if (mode.value === 'blank') return '用 ____ 表示填空位，复习时输入答案填空'
  return '正面写问题，背面写答案，复习时翻转查看'
})

const canSave = computed(() => {
  if (question.value.trim().length === 0) return false
  if (mode.value === 'qa' || mode.value === 'blank') return answer.value.trim().length > 0
  return optionA.value.trim().length > 0
    && optionB.value.trim().length > 0
    && selectedOption.value.trim().length > 0
})

// 编辑选择题时回填选项与正确项
if (props.card && mode.value === 'choice') {
  const parsed = parseCardOptions(props.card.options)
  optionA.value = parsed[0] ?? ''
  optionB.value = parsed[1] ?? ''
  optionC.value = parsed[2] ?? ''
  optionD.value = parsed[3] ?? ''
  const found = parsed.indexOf(props.card.answer)
  correctIndex.value = found >= 0 ? found : 0
}

function appendMarkdown(field: EditorField, snippet: string, newline = false): void {
  const target = field === 'question' ? question : answer
  let value = target.value
  if (newline && value.length > 0 && !value.endsWith('\n')) value += '\n'
  target.value = value + snippet
}

function insertBlank(): void {
  question.value += '____'
}

function setOption(i: number, value: string): void {
  const refs = [optionA, optionB, optionC, optionD]
  refs[i].value = value
}

function onOptionInput(i: number, event: Event): void {
  setOption(i, (event.target as HTMLInputElement).value)
}

function buildBody(): CardPayload {
  return buildCardPayload({
    mode: mode.value,
    question: question.value,
    answer: answer.value,
    optionValues: optionValues.value,
    selectedOption: selectedOption.value,
    card: props.card,
    deckCategory: props.deckCategory
  })
}

async function save(): Promise<void> {
  if (!canSave.value || saving.value) return
  saving.value = true
  saveError.value = ''
  try {
    const endpoints = getRuntime().endpoints
    const body = buildBody()
    const result = props.card
      ? await endpoints.updateCard(props.card.id, body)
      : await endpoints.createCard({ ...body, deckId: props.deckId })
    emit('saved', result)
    emit('close')
  } catch (e) {
    saveError.value = friendlyError(e)
  } finally {
    saving.value = false
  }
}

function close(): void {
  if (saving.value) return
  emit('close')
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
        aria-labelledby="form-title"
        tabindex="-1"
      >
        <header class="sheet-head">
          <h2
            id="form-title"
            class="sheet-title"
          >
            {{ isEdit ? '编辑卡片' : '新建卡片' }}
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

        <div
          class="segmented"
          role="group"
          aria-label="卡片类型"
        >
          <button
            v-for="tab in modeTabs"
            :key="tab.value"
            class="segment"
            :class="{ active: mode === tab.value }"
            type="button"
            :aria-pressed="mode === tab.value"
            @click="mode = tab.value"
          >
            {{ tab.label }}
          </button>
        </div>
        <p class="muted sheet-hint">
          {{ modeHint }}
        </p>

        <label
          class="label"
          for="card-question"
        >问题</label>
        <textarea
          id="card-question"
          v-model="question"
          class="textarea"
          :placeholder="mode === 'blank' ? '输入带有 ____ 的问题' : '输入问题'"
        />
        <div class="toolbar">
          <button
            v-if="mode === 'blank'"
            class="tool-btn blank-btn"
            type="button"
            @click="insertBlank"
          >
            插入填空符 ____
          </button>
          <button
            class="tool-btn"
            type="button"
            title="加粗"
            @click="appendMarkdown('question', '**重点**')"
          >
            <Bold
              :size="14"
              aria-hidden="true"
            />
            <span>加粗</span>
          </button>
          <button
            class="tool-btn"
            type="button"
            title="列表"
            @click="appendMarkdown('question', '- ', true)"
          >
            <List
              :size="14"
              aria-hidden="true"
            />
            <span>列表</span>
          </button>
          <button
            class="tool-btn"
            type="button"
            title="编号"
            @click="appendMarkdown('question', '1. ', true)"
          >
            <ListOrdered
              :size="14"
              aria-hidden="true"
            />
            <span>编号</span>
          </button>
          <button
            class="tool-btn"
            type="button"
            title="代码"
            @click="appendMarkdown('question', '`代码`')"
          >
            <Code
              :size="14"
              aria-hidden="true"
            />
            <span>代码</span>
          </button>
        </div>

        <template v-if="mode === 'qa'">
          <label
            class="label"
            for="card-answer"
          >答案</label>
          <textarea
            id="card-answer"
            v-model="answer"
            class="textarea answer-area"
            placeholder="输入答案，可回车换行"
          />
          <div class="toolbar">
            <button
              class="tool-btn"
              type="button"
              title="加粗"
              @click="appendMarkdown('answer', '**重点**')"
            >
              <Bold
                :size="14"
                aria-hidden="true"
              />
              <span>加粗</span>
            </button>
            <button
              class="tool-btn"
              type="button"
              title="列表"
              @click="appendMarkdown('answer', '- ', true)"
            >
              <List
                :size="14"
                aria-hidden="true"
              />
              <span>列表</span>
            </button>
            <button
              class="tool-btn"
              type="button"
              title="编号"
              @click="appendMarkdown('answer', '1. ', true)"
            >
              <ListOrdered
                :size="14"
                aria-hidden="true"
              />
              <span>编号</span>
            </button>
            <button
              class="tool-btn"
              type="button"
              title="代码"
              @click="appendMarkdown('answer', '`代码`')"
            >
              <Code
                :size="14"
                aria-hidden="true"
              />
              <span>代码</span>
            </button>
          </div>
        </template>

        <template v-else-if="mode === 'choice'">
          <span class="label">选项（至少填 A、B）</span>
          <div
            v-for="(value, i) in optionValues"
            :key="i"
            class="option-row"
          >
            <button
              class="option-pick"
              type="button"
              :aria-pressed="correctIndex === i"
              :aria-label="`设选项 ${['A', 'B', 'C', 'D'][i]} 为正确答案`"
              @click="correctIndex = i"
            >
              <CheckCircle2
                v-if="correctIndex === i"
                :size="20"
                class="pick-checked"
                aria-hidden="true"
              />
              <Circle
                v-else
                :size="20"
                class="pick-idle"
                aria-hidden="true"
              />
            </button>
            <input
              :value="value"
              class="input option-input"
              type="text"
              :aria-label="`选项 ${['A', 'B', 'C', 'D'][i]}`"
              :placeholder="`选项 ${['A', 'B', 'C（选填）', 'D（选填）'][i]}`"
              @input="onOptionInput(i, $event)"
            >
          </div>
        </template>

        <template v-else>
          <label
            class="label"
            for="blank-answer"
          >填空答案</label>
          <textarea
            id="blank-answer"
            v-model="answer"
            class="textarea"
            placeholder="按顺序填写答案，多个答案用分号分隔"
          />
        </template>

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
            :disabled="!canSave || saving"
            @click="save"
          >
            {{ saving ? '保存中…' : isEdit ? '保存' : '添加' }}
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

.sheet-hint {
  margin-bottom: 2px;
  font-size: 13px;
  line-height: 1.5;
}

.segmented {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 4px;
  padding: 4px;
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
}

.segment {
  min-height: 44px;
  border: 0;
  border-radius: calc(var(--radius-sm) - 4px);
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
  font-weight: 600;
}

.segment.active {
  background: var(--surface);
  color: var(--color-indigo-text);
  box-shadow: var(--shadow-sm);
}

.answer-area {
  min-height: 150px;
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.tool-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-height: 44px;
  padding: 4px 10px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: transparent;
  color: var(--text-secondary);
  font-size: 12px;
}

.tool-btn:hover {
  background: var(--surface-muted);
}

.blank-btn {
  color: var(--color-indigo-text);
  border-color: color-mix(in srgb, var(--color-indigo) 35%, transparent);
}

.option-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.option-pick {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  border: 0;
  border-radius: 50%;
  background: transparent;
}

.pick-checked {
  color: var(--color-green);
}

.pick-idle {
  color: var(--text-tertiary);
}

.option-input {
  flex: 1;
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
</style>
