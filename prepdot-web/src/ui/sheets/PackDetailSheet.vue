<script setup lang="ts">
/* global HTMLElement */
import { onMounted, ref } from 'vue'
import {
  ArrowDownToLine,
  CheckCircle2,
  LoaderCircle,
  X
} from 'lucide-vue-next'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import type { CommunityPack, CommunityPackDetail, Deck } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useToastStore } from '@/ui/stores/toast'

const props = defineProps<{ pack: CommunityPack }>()
const emit = defineEmits<{ imported: [deck: Deck]; close: [] }>()

const toast = useToastStore()

const detail = ref<CommunityPackDetail | null>(null)
const loading = ref(true)
const loadError = ref('')
const importing = ref(false)
const imported = ref(false)
const panelEl = ref<HTMLElement | null>(null)

async function loadDetail(): Promise<void> {
  loading.value = true
  loadError.value = ''
  try {
    detail.value = await getRuntime().endpoints.communityPack(props.pack.id)
  } catch (e) {
    detail.value = null
    loadError.value = friendlyError(e)
  } finally {
    loading.value = false
  }
}

async function importPack(): Promise<void> {
  if (importing.value || imported.value) return
  importing.value = true
  try {
    const deck = await getRuntime().endpoints.importCommunityPack(props.pack.id)
    imported.value = true
    toast.show(`✅「${props.pack.title}」已导入卡组`)
    emit('imported', deck)
  } catch {
    toast.show('❌ 导入失败，请重试')
  } finally {
    importing.value = false
  }
}

function close(): void {
  // 导入请求进行中不允许关闭，避免结果无处反馈。
  if (importing.value) return
  emit('close')
}

onMounted(() => {
  panelEl.value?.focus()
  void loadDetail()
})
</script>

<template>
  <Teleport to="body">
    <div
      class="sheet-backdrop"
      @click.self="close"
    >
      <div
        ref="panelEl"
        class="sheet-panel detail-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="pack-detail-title"
        tabindex="-1"
        @keydown.esc="close"
      >
        <header class="sheet-bar">
          <button
            class="icon-btn"
            type="button"
            aria-label="关闭"
            :disabled="importing"
            @click="close"
          >
            <X
              :size="20"
              aria-hidden="true"
            />
          </button>

          <h2
            id="pack-detail-title"
            class="sheet-title"
          >
            {{ pack.title }}
          </h2>

          <button
            class="import-btn"
            :class="{ imported }"
            type="button"
            :disabled="importing || imported"
            @click="importPack"
          >
            <LoaderCircle
              v-if="importing"
              class="spin"
              :size="17"
              aria-hidden="true"
            />
            <CheckCircle2
              v-else-if="imported"
              :size="17"
              aria-hidden="true"
            />
            <ArrowDownToLine
              v-else
              :size="17"
              aria-hidden="true"
            />
            <span>{{ importing ? '导入中…' : imported ? '已导入' : '一键导入' }}</span>
          </button>
        </header>

        <div class="sheet-body">
          <LoadingState
            v-if="loading"
            text="加载中…"
          />
          <ErrorState
            v-else-if="loadError"
            title="加载失败"
            :message="loadError"
            retry-text="重新加载"
            show-retry
            @retry="loadDetail"
          />
          <template v-else-if="detail">
            <p class="detail-desc">
              {{ detail.description }}
            </p>
            <ul
              v-if="detail.tags.length > 0"
              class="detail-tags"
            >
              <li
                v-for="tag in detail.tags"
                :key="tag"
                class="detail-tag"
              >
                {{ tag }}
              </li>
            </ul>

            <h3 class="cards-head">
              共 {{ detail.cards.length }} 张卡片
            </h3>
            <p
              v-if="detail.cards.length === 0"
              class="muted empty-cards"
            >
              该卡包暂无卡片
            </p>
            <ul
              v-else
              class="card-list"
            >
              <li
                v-for="(card, index) in detail.cards"
                :key="index"
                class="card-item"
              >
                <p class="card-q">
                  Q: {{ card.question }}
                </p>
                <p class="card-a">
                  A: {{ card.answer }}
                </p>
              </li>
            </ul>
          </template>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.detail-panel {
  display: flex;
  flex-direction: column;
  max-height: 90vh;
  padding: 0;
  overflow: hidden;
}

.detail-panel:focus {
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
  min-width: 0;
  overflow: hidden;
  font-size: 17px;
  font-weight: 700;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  color: var(--text-secondary);
}

.icon-btn:hover {
  background: var(--surface-muted);
}

.icon-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.import-btn {
  display: inline-flex;
  flex: none;
  align-items: center;
  gap: 6px;
  min-height: 44px;
  padding: 0 10px;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--color-indigo);
  font-size: 14px;
  font-weight: 600;
  white-space: nowrap;
}

.import-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.import-btn:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.import-btn.imported:disabled {
  color: var(--color-green);
  cursor: default;
  opacity: 1;
}

.spin {
  animation: pack-spin 1s linear infinite;
}

@keyframes pack-spin {
  to { transform: rotate(360deg); }
}

.sheet-body {
  flex: 1;
  padding: 20px 20px calc(20px + env(safe-area-inset-bottom));
  overflow-y: auto;
}

.detail-desc {
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.6;
}

.detail-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin: 12px 0 0;
  padding: 0;
  list-style: none;
}

.detail-tag {
  padding: 4px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  color: var(--color-indigo);
  font-size: 12px;
  line-height: 1.4;
}

.cards-head {
  margin: 20px 0 8px;
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 700;
}

.empty-cards {
  padding: 12px 0;
  font-size: 13px;
}

.card-list {
  margin: 0;
  padding: 0;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  list-style: none;
}

.card-item {
  padding: 12px 14px;
}

.card-item + .card-item {
  border-top: 1px solid var(--border);
}

.card-q {
  display: -webkit-box;
  overflow: hidden;
  font-size: 14px;
  font-weight: 600;
  line-height: 1.5;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.card-a {
  display: -webkit-box;
  margin-top: 4px;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 13px;
  line-height: 1.55;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
}

.icon-btn:focus-visible,
.import-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 640px) {
  .detail-panel {
    height: min(680px, 90vh);
  }
}
</style>
