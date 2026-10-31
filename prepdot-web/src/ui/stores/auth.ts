import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { AuthUser } from '@/core/api/types'
import { getRuntime } from '@/runtime'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const ready = ref(false)
  const isAuthenticated = computed(() => user.value !== null)
  let restored = false
  let restoring: Promise<void> | null = null

  async function restore(): Promise<void> {
    if (restored) {
      // ApiClient 遇到 401 会让 AuthSession 自行登出；下次导航时同步清掉 store 中的旧用户，
      // 避免界面停留在「已登录」状态而守卫又不再读取存储。
      if (user.value && !getRuntime().session.isAuthenticated) user.value = null
      ready.value = true
      return
    }
    if (!restoring) {
      // 恢复涉及存储读取和（可能较慢的）token 续期；并发导航共用同一个 Promise，
      // 避免后来的守卫在恢复完成前误判为未登录。
      restoring = (async () => {
        try {
          user.value = await getRuntime().session.restore()
        } catch {
          user.value = null
        } finally {
          ready.value = true
          restored = true
          restoring = null
        }
      })()
    }
    await restoring
  }

  async function login(username: string, password: string): Promise<void> {
    user.value = await getRuntime().session.login(username, password)
  }

  async function register(username: string, password: string, nickname: string): Promise<void> {
    user.value = await getRuntime().session.register(username, password, nickname)
  }

  async function logout(): Promise<void> {
    await getRuntime().session.logout()
    user.value = null
    restored = true
  }

  return { user, ready, isAuthenticated, restore, login, register, logout }
})
