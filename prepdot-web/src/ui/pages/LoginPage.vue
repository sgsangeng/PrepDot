<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { Brain } from 'lucide-vue-next'
import AuroraBackground from '@/ui/components/AuroraBackground.vue'
import { useAuthStore } from '@/ui/stores/auth'
import { friendlyError } from '@/core/errors'

const router = useRouter()
const auth = useAuthStore()

const mode = ref<'login' | 'register'>('login')
const nickname = ref('')
const username = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

const canSubmit = computed(() => username.value.trim().length > 0 && password.value.length >= 6)
const submitLabel = computed(() => {
  if (busy.value) return '请稍候…'
  return mode.value === 'login' ? '登录' : '注册'
})

function toggleMode(): void {
  mode.value = mode.value === 'login' ? 'register' : 'login'
  error.value = ''
}

async function submit(): Promise<void> {
  if (!canSubmit.value || busy.value) return
  error.value = ''
  busy.value = true
  try {
    const name = username.value.trim()
    if (mode.value === 'login') {
      await auth.login(name, password.value)
    } else {
      await auth.register(name, password.value, nickname.value.trim() || name)
    }
    await router.push({ name: 'review' })
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    busy.value = false
  }
}

async function demoLogin(): Promise<void> {
  mode.value = 'login'
  username.value = 'demo'
  password.value = 'PrepDot2026'
  await submit()
}
</script>

<template>
  <div class="login">
    <AuroraBackground />

    <main class="login-card">
      <svg
        width="0"
        height="0"
        aria-hidden="true"
      >
        <defs>
          <linearGradient
            id="brand-gradient"
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
      </svg>

      <header class="brand">
        <Brain
          class="brand-icon"
          :size="64"
          stroke="url(#brand-gradient)"
          aria-hidden="true"
        />
        <h1 class="brand-title">
          PrepDot
        </h1>
        <p class="muted">
          你的 AI 面试记忆助手
        </p>
      </header>

      <form
        class="form"
        @submit.prevent="submit"
      >
        <div v-if="mode === 'register'">
          <label
            class="label"
            for="nickname"
          >昵称</label>
          <input
            id="nickname"
            v-model="nickname"
            class="input"
            type="text"
            autocomplete="nickname"
            placeholder="怎么称呼你"
          >
        </div>

        <div>
          <label
            class="label"
            for="username"
          >用户名</label>
          <input
            id="username"
            v-model="username"
            class="input"
            type="text"
            autocomplete="username"
            placeholder="请输入用户名"
          >
        </div>

        <div>
          <label
            class="label"
            for="password"
          >密码</label>
          <input
            id="password"
            v-model="password"
            class="input"
            type="password"
            :autocomplete="mode === 'login' ? 'current-password' : 'new-password'"
            placeholder="至少 6 位"
          >
        </div>

        <p
          v-if="error"
          class="error"
          role="alert"
        >
          {{ error }}
        </p>

        <button
          class="btn btn-primary submit"
          type="submit"
          :disabled="!canSubmit || busy"
        >
          {{ submitLabel }}
        </button>
      </form>

      <button
        class="btn btn-ghost demo"
        type="button"
        :disabled="busy"
        @click="demoLogin"
      >
        使用演示账号
      </button>

      <p class="switch">
        {{ mode === 'login' ? '还没有账号？' : '已经有账号？' }}
        <button
          class="link"
          type="button"
          @click="toggleMode"
        >
          {{ mode === 'login' ? '注册' : '登录' }}
        </button>
      </p>
    </main>
  </div>
</template>

<style scoped>
.login {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100%;
  padding: 24px 16px calc(24px + env(safe-area-inset-bottom));
  overflow: hidden;
}

.login-card {
  position: relative;
  z-index: 1;
  width: 100%;
  max-width: 420px;
  padding: 28px 24px;
  background: color-mix(in srgb, var(--surface) 86%, transparent);
  border: 1px solid var(--glass-border);
  border-radius: var(--radius-xl);
  box-shadow: var(--shadow-lg);
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
}

.brand {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  margin-bottom: 24px;
  text-align: center;
}

.brand-icon {
  margin-bottom: 4px;
}

.brand-title {
  font-family: var(--font-rounded);
  font-size: 30px;
  font-weight: 800;
  letter-spacing: 0.02em;
  background: linear-gradient(135deg, var(--color-indigo), var(--color-purple));
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.form {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.error {
  padding: 10px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red);
  font-size: 14px;
}

.submit {
  width: 100%;
  margin-top: 4px;
}

.demo {
  width: 100%;
  margin-top: 12px;
}

.switch {
  margin-top: 16px;
  font-size: 14px;
  color: var(--text-secondary);
  text-align: center;
}

.link {
  min-height: 44px;
  padding: 0 4px;
  border: 0;
  background: transparent;
  color: var(--color-indigo);
  font-weight: 600;
}
</style>
