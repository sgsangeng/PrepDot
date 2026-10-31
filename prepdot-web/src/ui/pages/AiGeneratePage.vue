<script setup lang="ts">
/* global AbortController, TextEncoder, DOMException */
import { computed, onBeforeUnmount, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  ArrowLeft,
  CheckCircle2,
  ClipboardPaste,
  FileText,
  Folder,
  KeyRound,
  LoaderCircle,
  Plus,
  Presentation,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  TriangleAlert,
  Upload,
  X
} from 'lucide-vue-next'
import ProgressBar from '@/ui/components/ProgressBar.vue'
import type { PickedFile } from '@/adapters/types'
import { detailHints, detailLabels, mergePreviews, parseAiPreview, type AiPreviewDeck } from '@/core/ai/preview'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'

type InputMode = 'file' | 'paste'
type Phase = 'input' | 'generating' | 'preview' | 'importing' | 'done'

const MAX_FILES = 10
const FILE_ACCEPT = [
  'application/pdf',
  'text/plain',
  'text/markdown',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  '.pdf',
  '.txt',
  '.md',
  '.docx',
  '.pptx'
]

const router = useRouter()

const phase = ref<Phase>('input')
const inputMode = ref<InputMode>('paste')

const deckTitle = ref('')
const aiDecideCount = ref(true)
const cardCount = ref(20)
const detailLevel = ref(2)
const useCustomKey = ref(false)
const customKey = ref('')

const files = ref<PickedFile[]>([])
const pastedText = ref('')

const errorMsg = ref('')
const importError = ref('')
const preview = ref<AiPreviewDeck | null>(null)

const generatingProgress = ref('')
const generateTotal = ref(0)
const generateDone = ref(0)
let abortController: AbortController | null = null

const titleReady = computed(() => deckTitle.value.trim() !== '')
const contentReady = computed(() =>
  inputMode.value === 'file' ? files.value.length > 0 : pastedText.value.trim() !== ''
)
const isReady = computed(() => titleReady.value && contentReady.value)

const currentDetailLabel = computed(() => detailLabels[detailLevel.value])
const currentDetailHint = computed(() => detailHints[detailLevel.value])

const totalCards = computed(() =>
  preview.value?.children.reduce((sum, child) => sum + child.cards.length, 0) ?? 0
)
const totalTopics = computed(() => preview.value?.children.length ?? 0)

function goBack(): void {
  abortController?.abort()
  const listHref = router.resolve({ name: 'decks' }).href
  const back = (router.options.history.state as { back?: unknown }).back
  if (
    typeof back === 'string'
    && (back === listHref || back.startsWith(`${listHref}?`) || back.startsWith(`${listHref}#`))
  ) {
    router.back()
    return
  }
  void router.push({ name: 'decks' })
}

function formatSize(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${Math.max(1, Math.round(bytes / 1024))} KB`
}

function fileIcon(name: string) {
  const ext = name.split('.').pop()?.toLowerCase() ?? ''
  return ext === 'pptx' || ext === 'ppt' ? Presentation : FileText
}

async function pickFiles(): Promise<void> {
  if (files.value.length >= MAX_FILES) {
    errorMsg.value = '最多同时上传 10 个文件'
    return
  }
  try {
    const picked = await getRuntime().adapters.file.pick({ multiple: true, accept: FILE_ACCEPT })
    const next = [...files.value]
    let overflow = false
    for (const file of picked) {
      if (next.length >= MAX_FILES) {
        overflow = true
        break
      }
      if (!next.some(item => item.name === file.name)) next.push(file)
    }
    files.value = next
    if (overflow) errorMsg.value = '最多同时上传 10 个文件'
    else if (errorMsg.value === '最多同时上传 10 个文件') errorMsg.value = ''
  } catch (e) {
    errorMsg.value = friendlyError(e)
  }
}

function removeFile(index: number): void {
  files.value = files.value.filter((_, i) => i !== index)
}

async function pasteFromClipboard(): Promise<void> {
  try {
    const text = await getRuntime().adapters.clipboard.readText()
    if (text.trim() !== '') pastedText.value = text
  } catch (e) {
    errorMsg.value = friendlyError(e)
  }
}

function clearPasted(): void {
  pastedText.value = ''
}

/** 粘贴文字没有真实文件，按 iOS 的约定包装成 input.txt 交给同一上传接口。 */
function pastedFile(): PickedFile {
  const buffer = new TextEncoder().encode(pastedText.value).buffer as ArrayBuffer
  return {
    name: 'input.txt',
    mime: 'text/plain',
    size: buffer.byteLength,
    bytes: async () => buffer
  }
}

function canceled(): Error {
  return new DOMException('生成已取消。', 'AbortError')
}

async function startGenerate(): Promise<void> {
  if (!isReady.value || phase.value !== 'input') return
  errorMsg.value = ''
  importError.value = ''
  preview.value = null
  generatingProgress.value = ''
  generateDone.value = 0
  phase.value = 'generating'

  const controller = new AbortController()
  abortController = controller
  const count = aiDecideCount.value ? 0 : cardCount.value
  const detailHint = detailHints[detailLevel.value]
  const key = useCustomKey.value ? customKey.value.trim() : ''

  try {
    const previews: AiPreviewDeck[] = []

    if (inputMode.value === 'file') {
      const snapshot = [...files.value]
      generateTotal.value = snapshot.length
      for (const [index, file] of snapshot.entries()) {
        if (controller.signal.aborted) throw canceled()
        if (snapshot.length > 1) {
          generatingProgress.value = `正在处理第 ${index + 1} / ${snapshot.length} 个文件：${file.name}`
        }
        const raw = await getRuntime().endpoints.generate({
          file,
          deckTitle: snapshot.length === 1 ? deckTitle.value.trim() : file.name,
          customKey: key || undefined,
          cardCount: count,
          detailHint,
          signal: controller.signal
        })
        if (controller.signal.aborted) throw canceled()
        previews.push(parseAiPreview(raw))
        generateDone.value = index + 1
      }
    } else {
      generateTotal.value = 1
      if (controller.signal.aborted) throw canceled()
      const raw = await getRuntime().endpoints.generate({
        file: pastedFile(),
        deckTitle: deckTitle.value.trim(),
        customKey: key || undefined,
        cardCount: count,
        detailHint,
        signal: controller.signal
      })
      if (controller.signal.aborted) throw canceled()
      previews.push(parseAiPreview(raw))
      generateDone.value = 1
    }

    preview.value = mergePreviews(deckTitle.value.trim(), previews)
    generatingProgress.value = ''
    phase.value = 'preview'
  } catch (e) {
    if (controller.signal.aborted) errorMsg.value = '生成已取消。'
    else errorMsg.value = friendlyError(e)
    phase.value = 'input'
  } finally {
    if (abortController === controller) abortController = null
  }
}

function cancelGenerate(): void {
  abortController?.abort()
}

function regenerate(): void {
  preview.value = null
  importError.value = ''
  errorMsg.value = ''
  phase.value = 'input'
}

async function importDeck(): Promise<void> {
  if (!preview.value || phase.value !== 'preview') return
  const payload = preview.value
  phase.value = 'importing'
  importError.value = ''
  try {
    await getRuntime().endpoints.importAiDeck(JSON.stringify(payload))
    phase.value = 'done'
  } catch (e) {
    importError.value = friendlyError(e)
    phase.value = 'preview'
  }
}

function finish(): void {
  // 与「取消不导入」一致：上一页是知识树时直接后退，避免完成后按返回又回到已完成页。
  goBack()
}

onBeforeUnmount(() => {
  abortController?.abort()
})
</script>

<template>
  <section class="ai-page">
    <header class="ai-head">
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
      <h2 class="ai-head-title">
        AI 生成卡组
      </h2>
      <span
        class="head-spacer"
        aria-hidden="true"
      />
    </header>

    <!-- 输入 -->
    <template v-if="phase === 'input'">
      <section class="panel">
        <div class="panel-head">
          卡组名称
        </div>
        <div class="panel-body">
          <input
            v-model="deckTitle"
            class="input"
            type="text"
            placeholder="给这份资料起个名字"
            maxlength="80"
            aria-label="卡组名称"
          >
          <p class="panel-hint">
            例如：Java 面试准备、操作系统复习
          </p>
        </div>
      </section>

      <section class="panel">
        <div class="panel-body input-mode-panel">
          <p class="panel-label">
            输入方式
          </p>
          <div
            class="segmented"
            role="group"
            aria-label="输入方式"
          >
            <button
              class="seg-btn"
              :class="{ active: inputMode === 'file' }"
              type="button"
              :aria-pressed="inputMode === 'file'"
              @click="inputMode = 'file'"
            >
              <Upload
                :size="16"
                aria-hidden="true"
              />
              上传文件
            </button>
            <button
              class="seg-btn"
              :class="{ active: inputMode === 'paste' }"
              type="button"
              :aria-pressed="inputMode === 'paste'"
              @click="inputMode = 'paste'"
            >
              <ClipboardPaste
                :size="16"
                aria-hidden="true"
              />
              粘贴文字
            </button>
          </div>

          <template v-if="inputMode === 'file'">
            <p class="panel-label">
              上传文件
            </p>
            <ul
              v-if="files.length > 0"
              class="file-list"
            >
              <li
                v-for="(file, index) in files"
                :key="file.name"
                class="file-row"
              >
                <component
                  :is="fileIcon(file.name)"
                  :size="20"
                  class="file-icon"
                  aria-hidden="true"
                />
                <div class="file-meta">
                  <div class="file-name">
                    {{ file.name }}
                  </div>
                  <div class="file-size">
                    {{ formatSize(file.size) }}
                  </div>
                </div>
                <button
                  class="icon-btn"
                  type="button"
                  :aria-label="`移除文件：${file.name}`"
                  @click="removeFile(index)"
                >
                  <X
                    :size="18"
                    aria-hidden="true"
                  />
                </button>
              </li>
            </ul>
            <button
              v-if="files.length === 0"
              class="pick-btn"
              type="button"
              @click="pickFiles"
            >
              <Upload
                :size="22"
                aria-hidden="true"
              />
              选择文件（可多选）
            </button>
            <button
              v-else
              class="add-file-btn"
              type="button"
              @click="pickFiles"
            >
              <Plus
                :size="17"
                aria-hidden="true"
              />
              继续添加文件
            </button>
            <p class="panel-hint">
              支持 PDF、Word(.docx)、PPT(.pptx)、TXT、Markdown，最多同时上传 10 个文件
            </p>
          </template>

          <template v-else>
            <p class="panel-label">
              粘贴学习内容
            </p>
            <textarea
              v-model="pastedText"
              class="textarea paste-area"
              placeholder="把你的笔记、讲义、知识点直接粘贴在这里，AI 会自动整理成卡片"
              aria-label="粘贴学习内容"
            />
            <div class="paste-actions">
              <button
                class="btn btn-ghost btn-sm"
                type="button"
                @click="pasteFromClipboard"
              >
                <ClipboardPaste
                  :size="16"
                  aria-hidden="true"
                />
                粘贴
              </button>
              <span class="paste-spacer" />
              <template v-if="pastedText !== ''">
                <span class="char-count">{{ pastedText.length }} 字</span>
                <button
                  class="clear-btn"
                  type="button"
                  @click="clearPasted"
                >
                  清空
                </button>
              </template>
            </div>
            <p class="panel-hint">
              把你的笔记、讲义、知识点直接粘贴在这里，AI 会自动整理成卡片
            </p>
          </template>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          生成强度
        </div>
        <div class="panel-body">
          <div class="control-block">
            <div class="control-row">
              <span class="control-title">卡片数量</span>
              <label class="switch-row">
                <span class="switch-text">自动</span>
                <span class="switch">
                  <input
                    v-model="aiDecideCount"
                    type="checkbox"
                    aria-label="自动决定卡片数量"
                  >
                  <span
                    class="switch-track"
                    aria-hidden="true"
                  />
                </span>
              </label>
            </div>
            <p
              v-if="aiDecideCount"
              class="control-hint"
            >
              AI 将根据内容信息量自动决定生成张数
            </p>
            <template v-else>
              <div class="control-row">
                <span class="control-value">{{ cardCount }} 张</span>
              </div>
              <input
                v-model.number="cardCount"
                class="range"
                type="range"
                min="5"
                max="100"
                step="5"
                aria-label="卡片数量"
              >
              <div class="range-labels">
                <span>5 张</span>
                <span>100 张</span>
              </div>
            </template>
          </div>

          <div class="divider" />

          <div class="control-block">
            <div class="control-row">
              <span class="control-title">答案详细程度</span>
              <span class="control-value">{{ currentDetailLabel }}</span>
            </div>
            <input
              v-model.number="detailLevel"
              class="range"
              type="range"
              min="0"
              max="4"
              step="1"
              aria-label="答案详细程度"
            >
            <div class="range-labels">
              <span>{{ detailLabels[0] }}</span>
              <span class="range-hint">{{ currentDetailHint }}</span>
              <span>{{ detailLabels[4] }}</span>
            </div>
          </div>
        </div>
        <p class="panel-hint panel-foot">
          卡片越多、越详细，AI 分析时间越长
        </p>
      </section>

      <section class="panel">
        <div class="panel-head">
          AI 设置
        </div>
        <div class="panel-body">
          <label class="switch-row custom-key-row">
            <span class="switch-text custom-key-text">
              <KeyRound
                :size="17"
                aria-hidden="true"
              />
              使用我自己的 API Key
            </span>
            <span class="switch">
              <input
                v-model="useCustomKey"
                type="checkbox"
                aria-label="使用我自己的 API Key"
              >
              <span
                class="switch-track"
                aria-hidden="true"
              />
            </span>
          </label>
          <input
            v-if="useCustomKey"
            v-model="customKey"
            class="input key-input"
            type="password"
            placeholder="DeepSeek / Qwen / 豆包 API Key"
            autocomplete="off"
            aria-label="自定义 API Key"
          >
          <div
            v-else
            class="system-ai"
          >
            <ShieldCheck
              :size="18"
              aria-hidden="true"
            />
            <span>使用系统 AI（每日 10 次免费）</span>
          </div>
        </div>
        <p class="panel-hint panel-foot">
          {{ useCustomKey
            ? '填入自己的 Key 享受无限次使用；Key 仅用于本次请求，不会保存'
            : '系统 AI 使用 DeepSeek，免费但有次数限制' }}
        </p>
      </section>

      <div
        v-if="errorMsg"
        class="error-box"
        role="alert"
      >
        <TriangleAlert
          :size="17"
          aria-hidden="true"
        />
        <span>{{ errorMsg }}</span>
      </div>

      <button
        class="btn btn-primary generate-btn"
        type="button"
        :disabled="!isReady"
        @click="startGenerate"
      >
        <Sparkles
          :size="19"
          aria-hidden="true"
        />
        开始 AI 生成
      </button>
    </template>

    <!-- 生成中 -->
    <div
      v-else-if="phase === 'generating'"
      class="center-state"
    >
      <LoaderCircle
        :size="46"
        class="spin done-loading"
        aria-hidden="true"
      />
      <h2 class="state-title">
        AI 正在分析你的资料…
      </h2>
      <p
        v-if="generatingProgress"
        class="progress-text"
        aria-live="polite"
      >
        {{ generatingProgress }}
      </p>
      <ProgressBar
        v-if="generateTotal > 1"
        class="generate-bar"
        :value="generateDone"
        :max="generateTotal"
      />
      <p class="muted">
        通常需要 10–30 秒，请稍候
      </p>
      <button
        class="btn btn-ghost"
        type="button"
        @click="cancelGenerate"
      >
        取消生成
      </button>
    </div>

    <!-- 预览 -->
    <template v-else-if="phase === 'preview' && preview">
      <section class="panel summary-panel">
        <div class="panel-head">
          卡组预览
        </div>
        <div class="panel-body summary-body">
          <div class="summary-row">
            <span class="summary-label">名称</span>
            <span class="summary-value">{{ preview.title }}</span>
          </div>
          <div class="summary-row">
            <span class="summary-label">分类</span>
            <span class="summary-value">{{ preview.category }}</span>
          </div>
          <p
            v-if="preview.description !== ''"
            class="summary-description"
          >
            {{ preview.description }}
          </p>
          <div class="summary-row">
            <span class="summary-label">共</span>
            <span class="summary-value">
              {{ totalCards }} 张卡片，{{ totalTopics }} 个主题
            </span>
          </div>
        </div>
      </section>

      <section
        v-for="(child, childIndex) in preview.children"
        :key="`${childIndex}-${child.title}`"
        class="panel child-panel"
      >
        <div class="child-head">
          <Folder
            :size="17"
            class="child-icon"
            aria-hidden="true"
          />
          <span class="child-title">{{ child.title }}</span>
          <span class="child-count">{{ child.cards.length }} 张</span>
        </div>
        <div
          v-if="child.cards.length === 0"
          class="empty-child"
        >
          该主题暂无卡片
        </div>
        <article
          v-for="(card, cardIndex) in child.cards"
          :key="cardIndex"
          class="preview-card"
        >
          <h3 class="preview-question">
            {{ card.question }}
          </h3>
          <p class="preview-answer">
            {{ card.answer }}
          </p>
        </article>
      </section>

      <div
        v-if="importError"
        class="error-box"
        role="alert"
      >
        <TriangleAlert
          :size="17"
          aria-hidden="true"
        />
        <span>{{ importError }}</span>
      </div>

      <div class="preview-actions">
        <button
          class="btn btn-primary action-btn"
          type="button"
          @click="importDeck"
        >
          <CheckCircle2
            :size="19"
            aria-hidden="true"
          />
          确认导入
        </button>
        <button
          class="btn btn-ghost action-btn"
          type="button"
          @click="regenerate"
        >
          <RotateCcw
            :size="18"
            aria-hidden="true"
          />
          重新生成
        </button>
        <button
          class="btn cancel-btn action-btn"
          type="button"
          @click="goBack"
        >
          取消，不导入
        </button>
      </div>
    </template>

    <!-- 导入中 -->
    <div
      v-else-if="phase === 'importing'"
      class="center-state"
    >
      <LoaderCircle
        :size="46"
        class="spin done-loading"
        aria-hidden="true"
      />
      <h2 class="state-title">
        正在保存卡组…
      </h2>
    </div>

    <!-- 完成 -->
    <div
      v-else-if="phase === 'done'"
      class="center-state"
    >
      <CheckCircle2
        :size="72"
        class="done-icon"
        aria-hidden="true"
      />
      <h2 class="done-title">
        导入成功！
      </h2>
      <p class="muted">
        卡组已添加到「我的卡组」
      </p>
      <button
        class="btn btn-primary done-btn"
        type="button"
        @click="finish"
      >
        完成
      </button>
    </div>
  </section>
</template>

<style scoped>
.ai-page {
  display: flex;
  flex-direction: column;
  gap: 14px;
  width: min(100%, 720px);
  min-width: 0;
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.ai-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  min-height: 44px;
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

.ai-head-title {
  font-size: 19px;
  font-weight: 800;
}

.head-spacer {
  width: 66px;
}

.panel {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.panel-head {
  padding: 12px 14px 0;
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 700;
}

.panel-body {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 14px;
}

.input-mode-panel {
  gap: 12px;
}

.panel-label {
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 600;
}

.panel-hint {
  color: var(--text-tertiary);
  font-size: 12px;
  line-height: 1.5;
}

.panel-foot {
  padding: 0 14px 12px;
}

.segmented {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px;
  padding: 4px;
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
}

.seg-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 44px;
  border: 0;
  border-radius: calc(var(--radius-sm) - 2px);
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
  font-weight: 600;
}

.seg-btn.active {
  background: var(--surface);
  color: var(--color-indigo);
  box-shadow: var(--shadow-sm);
}

.seg-btn:focus-visible,
.back-btn:focus-visible,
.icon-btn:focus-visible,
.add-file-btn:focus-visible,
.pick-btn:focus-visible,
.clear-btn:focus-visible,
.switch input:focus-visible + .switch-track,
.range:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

.file-list {
  display: flex;
  flex-direction: column;
  margin: 0;
  padding: 0;
  list-style: none;
}

.file-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 56px;
  padding: 6px 0;
  border-bottom: 1px solid var(--border);
}

.file-row:last-child {
  border-bottom: 0;
}

.file-icon {
  flex: none;
  color: var(--color-indigo);
}

.file-meta {
  flex: 1;
  min-width: 0;
}

.file-name {
  overflow: hidden;
  font-size: 14px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.file-size {
  color: var(--text-tertiary);
  font-size: 12px;
}

.icon-btn {
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

.icon-btn:hover {
  background: var(--surface-muted);
  color: var(--text-secondary);
}

.pick-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 96px;
  border: 1.5px dashed var(--border-strong);
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
}

.pick-btn:hover {
  border-color: var(--color-indigo);
}

.add-file-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  align-self: flex-start;
  min-height: 44px;
  padding: 0 4px;
  border: 0;
  background: transparent;
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
}

.paste-area {
  min-height: 180px;
  line-height: 1.6;
}

.paste-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.paste-spacer {
  flex: 1;
}

.char-count {
  color: var(--text-tertiary);
  font-size: 12px;
}

.clear-btn {
  min-width: 44px;
  min-height: 44px;
  padding: 0 4px;
  border: 0;
  background: transparent;
  color: var(--color-red);
  font-size: 12px;
  font-weight: 600;
}

.control-block {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.control-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 32px;
}

.control-title {
  font-size: 14px;
  font-weight: 600;
}

.control-value {
  color: var(--color-indigo);
  font-size: 20px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
}

.control-hint {
  color: var(--text-tertiary);
  font-size: 12px;
}

.divider {
  height: 1px;
  background: var(--border);
}

.range {
  width: 100%;
  height: 44px;
  margin: 0;
  accent-color: var(--color-indigo);
}

.range-labels {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--text-tertiary);
  font-size: 11px;
}

.range-hint {
  flex: 1;
  overflow: hidden;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.switch-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 44px;
  cursor: pointer;
}

.switch-text {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 600;
}

.custom-key-text {
  color: var(--text);
}

.switch {
  position: relative;
  display: inline-block;
  flex: none;
  width: 50px;
  height: 30px;
}

.switch input {
  position: absolute;
  inset: 0;
  z-index: 1;
  width: 100%;
  height: 100%;
  margin: 0;
  opacity: 0;
  cursor: pointer;
}

.switch-track {
  position: absolute;
  inset: 0;
  border-radius: 999px;
  background: var(--border-strong);
  transition: background 0.18s ease;
}

.switch-track::after {
  content: "";
  position: absolute;
  top: 3px;
  left: 3px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: var(--surface);
  box-shadow: var(--shadow-sm);
  transition: transform 0.18s ease;
}

.switch input:checked + .switch-track {
  background: var(--color-indigo);
}

.switch input:checked + .switch-track::after {
  transform: translateX(20px);
}

.key-input {
  font-family: var(--font-rounded);
}

.system-ai {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  color: var(--text-secondary);
  font-size: 14px;
}

.system-ai svg {
  flex: none;
  color: var(--color-green);
}

.error-box {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red);
  font-size: 13px;
  line-height: 1.5;
  overflow-wrap: anywhere;
}

.error-box svg {
  flex: none;
  margin-top: 1px;
}

.generate-btn {
  min-height: 50px;
  border-radius: var(--radius-md);
  font-size: 16px;
}

.generate-btn:focus-visible,
.action-btn:focus-visible,
.done-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

.center-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  min-height: 420px;
  padding: 40px 20px;
  text-align: center;
}

.state-title {
  font-size: 18px;
  font-weight: 700;
}

.done-loading {
  color: var(--color-indigo);
}

.spin {
  animation: ai-spin 1s linear infinite;
}

@keyframes ai-spin {
  to { transform: rotate(360deg); }
}

.progress-text {
  color: var(--color-indigo);
  font-size: 14px;
}

.generate-bar {
  max-width: 320px;
}

.summary-body {
  gap: 8px;
}

.summary-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  font-size: 14px;
}

.summary-label {
  flex: none;
  color: var(--text-secondary);
}

.summary-value {
  font-weight: 600;
  text-align: right;
  overflow-wrap: anywhere;
}

.summary-description {
  color: var(--text-secondary);
  font-size: 13px;
  line-height: 1.6;
}

.child-panel {
  padding-bottom: 2px;
}

.child-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 14px;
  background: var(--surface-muted);
  font-size: 14px;
  font-weight: 700;
}

.child-icon {
  flex: none;
  color: var(--color-indigo);
}

.child-title {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.child-count {
  margin-left: auto;
  color: var(--text-tertiary);
  font-size: 12px;
  font-weight: 600;
}

.empty-child {
  padding: 14px;
  color: var(--text-tertiary);
  font-size: 13px;
}

.preview-card {
  padding: 10px 14px;
  border-top: 1px solid var(--border);
}

.preview-question {
  font-size: 14px;
  font-weight: 600;
  line-height: 1.5;
}

.preview-answer {
  display: -webkit-box;
  margin-top: 3px;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 13px;
  line-height: 1.55;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
}

.preview-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.action-btn {
  width: 100%;
  min-height: 48px;
  font-size: 15px;
}

.cancel-btn {
  border-color: color-mix(in srgb, var(--color-red) 30%, transparent);
  background: transparent;
  color: var(--color-red);
}

.done-icon {
  color: var(--color-green);
}

.done-title {
  font-size: 22px;
  font-weight: 800;
}

.done-btn {
  min-width: 160px;
}

@media (min-width: 900px) {
  .ai-page {
    padding: 24px 16px 48px;
  }
}
</style>
