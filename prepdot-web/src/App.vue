<script setup lang="ts">
import { watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppShell from '@/ui/layout/AppShell.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import ToastHost from '@/ui/components/ToastHost.vue'
import { useAuthStore } from '@/ui/stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

// 401 被动登出或手动登出后，立即离开需要登录的页面。
// 初始导航交给路由守卫：此时 route.name 可能尚未解析，watcher 不参与。
watch(
  () => auth.ready && !auth.isAuthenticated,
  (loggedOut) => {
    if (loggedOut && route.name != null && route.name !== 'login') {
      void router.replace({ name: 'login' })
    }
  }
)
</script>

<template>
  <RouterView v-if="route.name === 'login'" />
  <AppShell v-else-if="auth.isAuthenticated">
    <RouterView />
  </AppShell>
  <div
    v-else
    class="page"
  >
    <LoadingState text="正在恢复登录状态…" />
  </div>
  <ToastHost />
</template>
