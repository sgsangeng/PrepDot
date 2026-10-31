<script setup lang="ts">
/* global HTMLElement, MouseEvent */
import { nextTick, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft } from 'lucide-vue-next'
import EmptyState from '@/ui/components/EmptyState.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import PackDetailSheet from '@/ui/sheets/PackDetailSheet.vue'
import type { CommunityPack } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'

const CATEGORY_COLORS: Record<string, string> = {
  Java: 'var(--color-orange)',
  Spring: 'var(--color-green)',
  数据库: 'var(--color-blue)',
  网络: 'var(--color-purple)',
  缓存: 'var(--color-red)',
  算法: 'var(--color-indigo)'
}

const CATEGORY_EMOJIS: Record<string, string> = {
  Java: '☕️',
  Spring: '🌱',
  数据库: '🗄️',
  网络: '🌐',
  缓存: '⚡️',
  算法: '🧮'
}

const router = useRouter()

const packs = ref<CommunityPack[]>([])
const loading = ref(true)
const loadError = ref('')
const selectedPack = ref<CommunityPack | null>(null)

let lastTrigger: HTMLElement | null = null
let loadSeq = 0

function categoryColor(category: string): string {
  return CATEGORY_COLORS[category] ?? 'var(--color-indigo)'
}

function categoryEmoji(category: string): string {
  return CATEGORY_EMOJIS[category] ?? '📖'
}

async function loadPacks(): Promise<void> {
  const seq = ++loadSeq
  loading.value = true
  loadError.value = ''
  try {
    const loaded = await getRuntime().endpoints.communityPacks()
    // 只接受最新一次请求，避免重试乱序覆盖列表。
    if (seq !== loadSeq) return
    packs.value = loaded
  } catch (e) {
    if (seq !== loadSeq) return
    loadError.value = friendlyError(e)
  } finally {
    if (seq === loadSeq) loading.value = false
  }
}

function openPack(pack: CommunityPack, event: MouseEvent): void {
  lastTrigger = event.currentTarget instanceof HTMLElement ? event.currentTarget : null
  selectedPack.value = pack
}

/** 关闭详情后把键盘焦点还给触发它的卡包行。 */
function closeSheet(): void {
  if (selectedPack.value === null) return
  const trigger = lastTrigger
  lastTrigger = null
  selectedPack.value = null
  if (trigger) {
    void nextTick(() => trigger.focus())
  }
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
  void router.push({ name: 'decks' })
}

onMounted(() => {
  void loadPacks()
})
</script>

<template>
  <section class="community-page">
    <header class="community-head">
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
        精选卡包
      </h1>
    </header>

    <div
      v-if="loading"
      class="state-card"
    >
      <LoadingState text="加载卡包库…" />
    </div>

    <div
      v-else-if="loadError"
      class="state-card"
    >
      <ErrorState
        title="卡包加载失败"
        :message="loadError"
        retry-text="重新加载"
        show-retry
        @retry="loadPacks"
      />
    </div>

    <div
      v-else-if="packs.length === 0"
      class="state-card"
    >
      <EmptyState title="暂无卡包" />
    </div>

    <template v-else>
      <div class="banner">
        <div class="banner-text">
          <h2 class="banner-title">
            精选卡包库
          </h2>
          <p class="banner-desc">
            精心整理的面试知识点<br>一键导入，立即复习
          </p>
        </div>
        <span
          class="banner-emoji"
          aria-hidden="true"
        >📚</span>
      </div>

      <ul class="pack-list">
        <li
          v-for="pack in packs"
          :key="pack.id"
        >
          <button
            class="pack-row"
            type="button"
            :style="{ '--pack-color': categoryColor(pack.category) }"
            @click="openPack(pack, $event)"
          >
            <span
              class="pack-icon"
              aria-hidden="true"
            >{{ categoryEmoji(pack.category) }}</span>
            <span class="pack-main">
              <span class="pack-head">
                <span class="pack-title">{{ pack.title }}</span>
                <span class="pack-count">{{ pack.cardCount }} 张</span>
              </span>
              <span class="pack-desc">{{ pack.description }}</span>
              <span
                v-if="pack.tags.length > 0"
                class="pack-tags"
              >
                <span
                  v-for="tag in pack.tags"
                  :key="tag"
                  class="pack-tag"
                >{{ tag }}</span>
              </span>
            </span>
          </button>
        </li>
      </ul>
    </template>

    <PackDetailSheet
      v-if="selectedPack"
      :key="selectedPack.id"
      :pack="selectedPack"
      @imported="closeSheet"
      @close="closeSheet"
    />
  </section>
</template>

<style scoped>
.community-page {
  display: flex;
  flex-direction: column;
  gap: 14px;
  width: min(100%, 720px);
  min-width: 0;
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.community-head {
  display: flex;
  align-items: center;
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
  color: var(--color-indigo-text);
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

.state-card {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.banner {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 20px;
  border: 1px solid color-mix(in srgb, var(--color-indigo) 20%, transparent);
  border-radius: var(--radius-lg);
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--color-indigo) 15%, transparent),
    color-mix(in srgb, var(--color-purple) 10%, transparent)
  );
}

.banner-text {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.banner-title {
  font-size: 20px;
  font-weight: 800;
  line-height: 1.3;
}

.banner-desc {
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.8;
}

.banner-emoji {
  flex: none;
  font-size: 52px;
  line-height: 1;
}

.pack-list {
  display: flex;
  flex-direction: column;
  gap: 14px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.pack-row {
  display: flex;
  align-items: flex-start;
  gap: 14px;
  width: 100%;
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
  color: var(--text);
  text-align: left;
  transition: box-shadow 0.15s ease, transform 0.15s ease;
}

.pack-row:hover {
  box-shadow: var(--shadow-md);
}

.pack-row:active {
  transform: scale(0.99);
}

.pack-icon {
  display: grid;
  flex: none;
  place-items: center;
  width: 52px;
  height: 52px;
  border-radius: 12px;
  background: color-mix(in srgb, var(--pack-color) 15%, transparent);
  font-size: 26px;
  line-height: 1;
}

.pack-main {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.pack-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 8px;
}

.pack-title {
  min-width: 0;
  font-size: 16px;
  font-weight: 700;
  line-height: 1.35;
}

.pack-count {
  flex: none;
  padding: 3px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--pack-color) 15%, transparent);
  color: var(--pack-color);
  font-size: 12px;
  font-weight: 700;
  line-height: 1.4;
}

.pack-desc {
  display: -webkit-box;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.5;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
}

.pack-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.pack-tag {
  padding: 3px 7px;
  border-radius: 999px;
  background: var(--surface-muted);
  color: var(--text-secondary);
  font-size: 11px;
  line-height: 1.4;
}

.pack-row:focus-visible,
.back-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .community-page {
    padding: 24px 16px 48px;
  }

  .back-btn {
    display: none;
  }

  .head-title {
    display: block;
  }
}
</style>
