<script setup lang="ts">
import { computed, onMounted, ref, useId } from 'vue'
import { useRouter } from 'vue-router'
import {
  Bell,
  Brain,
  CheckCircle2,
  ChevronRight,
  Folder,
  Layers,
  LogOut,
  RefreshCw,
  Trash2
} from 'lucide-vue-next'
import BarChart from '@/ui/components/charts/BarChart.vue'
import ErrorState from '@/ui/components/ErrorState.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import MemoryDistribution from '@/ui/components/MemoryDistribution.vue'
import StatCard from '@/ui/components/StatCard.vue'
import type { UserStats } from '@/core/api/types'
import { friendlyError } from '@/core/errors'
import { last7Days } from '@/core/stats/week'
import { getRuntime } from '@/runtime'
import { useAuthStore } from '@/ui/stores/auth'

const auth = useAuthStore()
const router = useRouter()

const stats = ref<UserStats | null>(null)
const loading = ref(true)
const loadError = ref('')
let loadSeq = 0

// 48px 进度环：r = (48 - stroke) / 2，stroke = 5。
const RING_RADIUS = 21.5
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS
const ringGradientId = `streak-ring-${useId()}`

const user = computed(() => auth.user)
const nickname = computed(() => user.value?.nickname?.trim() || user.value?.username || '')
const initial = computed(() => Array.from(nickname.value)[0]?.toUpperCase() ?? '?')
const avatarStyle = computed<Record<string, string>>(() => ({
  '--avatar-color': user.value?.avatarColor || 'var(--color-indigo)'
}))

const studyTarget = computed(() => {
  const target = user.value?.studyTarget
  return typeof target === 'number' && target > 0 ? target : 20
})

const weekly = computed(() => {
  if (!stats.value) return []
  return last7Days(stats.value.weeklyData ?? [], getRuntime().adapters.clock.now())
})
const chartData = computed(() => weekly.value.map(point => ({ label: point.label, value: point.count })))

const todayPercent = computed(() => {
  if (!stats.value) return 0
  return Math.min(100, Math.round((stats.value.todayReviewed / studyTarget.value) * 100))
})
const ringDash = computed(() => (todayPercent.value / 100) * RING_CIRCUMFERENCE)

const memory = computed(() => stats.value?.memoryDistribution ?? { low: 0, mid: 0, high: 0 })

async function loadStats(): Promise<void> {
  const seq = ++loadSeq
  loading.value = true
  loadError.value = ''
  try {
    const loaded = await getRuntime().endpoints.stats()
    // 只接受最新一次请求，避免连续刷新时旧响应覆盖新数据。
    if (seq !== loadSeq) return
    stats.value = loaded
  } catch (e) {
    if (seq !== loadSeq) return
    // 401 由 API 客户端 + 全局监听统一处理，这里只展示统计区错误；
    // 设置区不依赖统计数据，失败时仍然可用。
    stats.value = null
    loadError.value = friendlyError(e)
  } finally {
    if (seq === loadSeq) loading.value = false
  }
}

onMounted(() => {
  void loadStats()
})

async function logout(): Promise<void> {
  await auth.logout()
  await router.replace({ name: 'login' })
}
</script>

<template>
  <section class="profile-page">
    <header class="profile-head">
      <h1 class="head-title">
        我的
      </h1>
      <button
        class="refresh-btn"
        type="button"
        :disabled="loading"
        @click="loadStats"
      >
        <RefreshCw
          :size="16"
          :class="{ spinning: loading }"
          aria-hidden="true"
        />
        {{ loading ? '刷新中…' : '刷新' }}
      </button>
    </header>

    <template v-if="user">
      <div class="avatar-section">
        <div
          class="avatar"
          :style="avatarStyle"
          aria-hidden="true"
        >
          {{ initial }}
        </div>
        <p class="nickname">
          {{ nickname }}
        </p>
        <p class="username">
          @{{ user.username }}
        </p>
      </div>

      <div
        v-if="loading && !stats"
        class="state-card"
      >
        <LoadingState text="加载学习数据…" />
      </div>

      <div
        v-else-if="loadError"
        class="state-card"
      >
        <ErrorState
          title="统计数据加载失败"
          :message="loadError"
          retry-text="重新加载"
          show-retry
          @retry="loadStats"
        />
      </div>

      <template v-else-if="stats">
        <section class="streak-card">
          <div class="streak-ring">
            <svg
              viewBox="0 0 48 48"
              role="img"
              :aria-label="`今日复习进度 ${todayPercent}%`"
            >
              <defs>
                <linearGradient
                  :id="ringGradientId"
                  x1="0"
                  y1="0"
                  x2="1"
                  y2="1"
                >
                  <stop
                    offset="0"
                    style="stop-color: var(--color-indigo)"
                  />
                  <stop
                    offset="1"
                    style="stop-color: var(--color-purple)"
                  />
                </linearGradient>
              </defs>
              <circle
                class="ring-track"
                cx="24"
                cy="24"
                :r="RING_RADIUS"
              />
              <circle
                class="ring-value"
                cx="24"
                cy="24"
                :r="RING_RADIUS"
                :stroke="`url(#${ringGradientId})`"
                :stroke-dasharray="`${ringDash} ${RING_CIRCUMFERENCE}`"
                transform="rotate(-90 24 24)"
              />
            </svg>
            <span class="ring-label">{{ todayPercent }}%</span>
          </div>

          <div class="streak-copy">
            <p class="streak-title">
              <span aria-hidden="true">🔥</span> {{ stats.streakDays }} 天连续打卡
            </p>
            <p class="streak-sub">
              今日已复习 {{ stats.todayReviewed }} 张 · 目标 {{ studyTarget }} 张
            </p>
          </div>
        </section>

        <div class="overview-grid">
          <StatCard
            :value="stats.totalDecks"
            label="卡组"
            tone="indigo"
          >
            <Folder :size="20" />
          </StatCard>
          <StatCard
            :value="stats.totalCards"
            label="卡片"
            tone="purple"
          >
            <Layers :size="20" />
          </StatCard>
          <StatCard
            :value="stats.totalReviewed"
            label="总复习"
            tone="blue"
          >
            <CheckCircle2 :size="20" />
          </StatCard>
          <StatCard
            :value="`${stats.avgMemoryScore}%`"
            label="记忆度"
            tone="pink"
          >
            <Brain :size="20" />
          </StatCard>
        </div>

        <section class="chart-card">
          <h2 class="card-title">
            近 7 天复习
          </h2>
          <BarChart
            :data="chartData"
            label="近 7 天每日复习数量"
            :height="140"
          />
        </section>

        <MemoryDistribution
          :low="memory.low"
          :mid="memory.mid"
          :high="memory.high"
        />
      </template>

      <section
        class="settings-card"
        aria-label="账号设置"
      >
        <RouterLink
          class="settings-row"
          :to="{ name: 'reminder' }"
        >
          <span
            class="settings-icon icon-indigo"
            aria-hidden="true"
          >
            <Bell :size="18" />
          </span>
          <span class="settings-label">每日提醒</span>
          <ChevronRight
            class="settings-chevron"
            :size="16"
            aria-hidden="true"
          />
        </RouterLink>

        <div class="settings-divider" />

        <button
          class="settings-row settings-button"
          type="button"
          @click="logout"
        >
          <span
            class="settings-icon icon-pink"
            aria-hidden="true"
          >
            <LogOut :size="18" />
          </span>
          <span class="settings-label destructive-pink">退出登录</span>
        </button>

        <div class="settings-divider" />

        <RouterLink
          class="settings-row"
          :to="{ name: 'delete-account' }"
        >
          <span
            class="settings-icon icon-red"
            aria-hidden="true"
          >
            <Trash2 :size="18" />
          </span>
          <span class="settings-label destructive-red">注销账号</span>
          <ChevronRight
            class="settings-chevron"
            :size="16"
            aria-hidden="true"
          />
        </RouterLink>
      </section>
    </template>
  </section>
</template>

<style scoped>
.profile-page {
  display: flex;
  flex-direction: column;
  gap: 18px;
  width: min(100%, 720px);
  min-width: 0;
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.profile-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 44px;
}

.head-title {
  display: none;
  font-size: 20px;
  font-weight: 800;
}

.refresh-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 44px;
  margin-left: auto;
  padding: 0 16px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--surface);
  color: var(--color-indigo-text);
  font-size: 14px;
  font-weight: 600;
}

.refresh-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.spinning {
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.avatar-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding-top: 4px;
  text-align: center;
}

.avatar {
  display: grid;
  place-items: center;
  width: 88px;
  height: 88px;
  border-radius: 50%;
  background: linear-gradient(
    135deg,
    var(--avatar-color),
    color-mix(in srgb, var(--avatar-color) 70%, transparent)
  );
  box-shadow: 0 8px 24px color-mix(in srgb, var(--avatar-color) 40%, transparent);
  color: var(--on-primary);
  font-family: var(--font-rounded);
  font-size: 36px;
  font-weight: 700;
  line-height: 1;
  text-transform: uppercase;
}

.nickname {
  font-size: 22px;
  font-weight: 700;
  line-height: 1.3;
}

.username {
  color: var(--text-secondary);
  font-size: 12px;
}

.state-card {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.streak-card {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px;
  border: 1px solid color-mix(in srgb, var(--color-indigo) 12%, transparent);
  border-radius: var(--radius-md);
  background: linear-gradient(
    90deg,
    color-mix(in srgb, var(--color-indigo) 8%, transparent),
    color-mix(in srgb, var(--color-purple) 5%, transparent)
  );
}

.streak-ring {
  position: relative;
  flex: none;
  width: 48px;
  height: 48px;
}

.streak-ring svg {
  display: block;
  width: 100%;
  height: 100%;
}

.ring-track {
  fill: none;
  stroke: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  stroke-width: 5;
}

.ring-value {
  fill: none;
  stroke-width: 5;
  stroke-linecap: round;
  transition: stroke-dasharray 0.6s ease-out;
}

.ring-label {
  position: absolute;
  inset: 0;
  display: grid;
  place-items: center;
  color: var(--color-indigo-text);
  font-family: var(--font-rounded);
  font-size: 10px;
  font-weight: 700;
}

.streak-copy {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}

.streak-title {
  font-size: 16px;
  font-weight: 700;
  line-height: 1.3;
}

.streak-sub {
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.5;
}

.overview-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
}

.chart-card {
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.card-title {
  margin-bottom: 12px;
  font-size: 16px;
  font-weight: 700;
}

.settings-card {
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.settings-row {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  min-height: 56px;
  padding: 0 16px;
  border: 0;
  background: transparent;
  color: var(--text);
  font-size: 15px;
  text-align: left;
  text-decoration: none;
}

.settings-row:hover {
  background: var(--surface-muted);
}

.settings-button {
  font-weight: 400;
}

.settings-icon {
  display: grid;
  flex: none;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 8px;
}

.icon-indigo {
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  color: var(--color-indigo);
}

.icon-pink {
  background: color-mix(in srgb, var(--color-pink) 12%, transparent);
  color: var(--color-pink);
}

.icon-red {
  background: color-mix(in srgb, var(--color-red) 12%, transparent);
  color: var(--color-red);
}

.settings-label {
  flex: 1;
  font-weight: 600;
}

.destructive-pink {
  color: var(--color-pink-text);
}

.destructive-red {
  color: var(--color-red-text);
}

.settings-chevron {
  flex: none;
  color: var(--text-tertiary);
}

.settings-divider {
  height: 1px;
  margin-left: 64px;
  background: var(--border);
}

.refresh-btn:focus-visible,
.settings-row:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .profile-page {
    padding: 24px 16px 48px;
  }

  .head-title {
    display: block;
  }
}
</style>
