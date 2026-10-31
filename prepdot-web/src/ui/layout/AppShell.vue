<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { Brain, Network, Sparkles, UserRound } from 'lucide-vue-next'
import { useAuthStore } from '@/ui/stores/auth'

const route = useRoute()
const auth = useAuthStore()

const navItems = [
  { name: 'review', label: '今日复习', icon: Brain, match: ['review'] },
  { name: 'decks', label: '知识树', icon: Network, match: ['decks', 'quiz', 'graph'] },
  { name: 'coach', label: '学习教练', icon: Sparkles, match: ['coach'] },
  { name: 'profile', label: '我的', icon: UserRound, match: ['profile', 'reminder', 'delete-account'] }
]

const titles: Record<string, string> = {
  review: '今日复习',
  decks: '我的卡组',
  quiz: '测验',
  coach: '学习教练',
  profile: '我的',
  reminder: '每日提醒',
  'delete-account': '注销账号',
  graph: '知识树',
  generate: 'AI 生成',
  community: '精选卡包'
}

const currentRoute = computed(() => String(route.name ?? ''))
const title = computed(() => titles[currentRoute.value] ?? 'PrepDot')

function isActive(item: (typeof navItems)[number]): boolean {
  return item.match.includes(currentRoute.value)
}

const nickname = computed(() => auth.user?.nickname || auth.user?.username || '未登录')
const initial = computed(() => nickname.value.trim().charAt(0).toUpperCase() || '?')
const avatarStyle = computed(() => ({
  background: auth.user?.avatarColor
    || 'linear-gradient(135deg, var(--color-indigo), var(--color-purple))'
}))
</script>

<template>
  <div class="shell">
    <aside class="sidebar">
      <RouterLink
        class="brand"
        :to="{ name: 'review' }"
      >
        <Brain
          class="brand-icon"
          :size="28"
          aria-hidden="true"
        />
        <span>PrepDot</span>
      </RouterLink>

      <nav
        class="nav"
        aria-label="主导航"
      >
        <RouterLink
          v-for="item in navItems"
          :key="item.name"
          class="nav-link"
          :class="{ active: isActive(item) }"
          :to="{ name: item.name }"
          :aria-current="isActive(item) ? 'page' : undefined"
        >
          <component
            :is="item.icon"
            :size="20"
            aria-hidden="true"
          />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <RouterLink
        class="user"
        :to="{ name: 'profile' }"
      >
        <span
          class="avatar"
          :style="avatarStyle"
          aria-hidden="true"
        >{{ initial }}</span>
        <span class="user-meta">
          <span class="user-name">{{ nickname }}</span>
          <span class="user-sub">查看个人中心</span>
        </span>
      </RouterLink>
    </aside>

    <div class="main-column">
      <header class="topbar">
        <h1 class="page-title">
          {{ title }}
        </h1>
      </header>
      <main class="main">
        <slot />
      </main>
    </div>

    <nav
      class="tabbar"
      aria-label="底部导航"
    >
      <RouterLink
        v-for="item in navItems"
        :key="item.name"
        class="tab-link"
        :class="{ active: isActive(item) }"
        :to="{ name: item.name }"
        :aria-current="isActive(item) ? 'page' : undefined"
      >
        <component
          :is="item.icon"
          :size="22"
          aria-hidden="true"
        />
        <span>{{ item.label }}</span>
      </RouterLink>
    </nav>
  </div>
</template>

<style scoped>
.shell {
  min-height: 100%;
  background: var(--bg);
}

.sidebar {
  display: none;
}

.main-column {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 100%;
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  min-height: 56px;
  padding: 8px 16px;
  background: color-mix(in srgb, var(--surface) 92%, transparent);
  border-bottom: 1px solid var(--border);
  -webkit-backdrop-filter: blur(18px);
  backdrop-filter: blur(18px);
}

.page-title {
  font-size: 18px;
  font-weight: 700;
}

.main {
  flex: 1;
  min-width: 0;
}

.tabbar {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 30;
  height: calc(var(--tab-height) + env(safe-area-inset-bottom));
  padding-bottom: env(safe-area-inset-bottom);
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  background: color-mix(in srgb, var(--surface) 92%, transparent);
  border-top: 1px solid var(--border);
  -webkit-backdrop-filter: blur(18px);
  backdrop-filter: blur(18px);
}

.tab-link {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 2px;
  min-height: 44px;
  font-size: 10px;
  color: var(--text-secondary);
  text-decoration: none;
}

.tab-link.active {
  color: var(--color-indigo);
}

@media (min-width: 900px) {
  .shell {
    display: grid;
    grid-template-columns: var(--sidebar-width) 1fr;
    align-items: start;
  }

  .sidebar {
    display: flex;
    flex-direction: column;
    gap: 20px;
    position: sticky;
    top: 0;
    z-index: 10;
    height: 100vh;
    border-right: 1px solid var(--border);
    background: var(--surface);
    padding: 20px 14px;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 0 10px;
    color: var(--text);
    font-family: var(--font-rounded);
    font-size: 20px;
    font-weight: 800;
    text-decoration: none;
  }

  .brand-icon {
    color: var(--color-indigo);
  }

  .nav {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .nav-link {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius-sm);
    color: var(--text-secondary);
    font-weight: 600;
    text-decoration: none;
  }

  .nav-link:hover {
    background: var(--surface-muted);
  }

  .nav-link.active {
    color: var(--color-indigo);
    background: color-mix(in srgb, var(--color-indigo) 10%, transparent);
  }

  .user {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 56px;
    margin-top: auto;
    padding: 8px 10px;
    border-radius: var(--radius-md);
    background: var(--surface-muted);
    color: var(--text);
    text-decoration: none;
  }

  .avatar {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    color: var(--on-primary);
    font-weight: 700;
  }

  .user-meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }

  .user-name {
    overflow: hidden;
    font-size: 14px;
    font-weight: 600;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .user-sub {
    font-size: 12px;
    color: var(--text-tertiary);
  }

  .main-column {
    min-height: 100vh;
  }

  .topbar {
    display: none;
  }

  .tabbar {
    display: none;
  }
}
</style>
