<script setup lang="ts">
import { useRoute } from 'vue-router'
import AppShell from '@/ui/layout/AppShell.vue'
import LoadingState from '@/ui/components/LoadingState.vue'
import ToastHost from '@/ui/components/ToastHost.vue'
import { useAuthStore } from '@/ui/stores/auth'

const route = useRoute()
const auth = useAuthStore()
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
