<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, ShieldAlert } from 'lucide-vue-next'
import { friendlyError } from '@/core/errors'
import { getRuntime } from '@/runtime'
import { useAuthStore } from '@/ui/stores/auth'

const router = useRouter()
const auth = useAuthStore()

const password = ref('')
const deleting = ref(false)
const error = ref('')

const canSubmit = computed(() => password.value.length > 0 && !deleting.value)

async function submit(): Promise<void> {
  if (!canSubmit.value) return
  error.value = ''
  deleting.value = true
  try {
    await getRuntime().endpoints.deleteAccount(password.value)
    await auth.logout()
    await router.replace({ name: 'login' })
  } catch (e) {
    error.value = friendlyError(e)
  } finally {
    deleting.value = false
  }
}

function goBack(): void {
  const profileHref = router.resolve({ name: 'profile' }).href
  const back = (router.options.history.state as { back?: unknown }).back
  if (
    typeof back === 'string'
    && (back === profileHref || back.startsWith(`${profileHref}?`) || back.startsWith(`${profileHref}#`))
  ) {
    router.back()
    return
  }
  void router.push({ name: 'profile' })
}

function cancel(): void {
  if (deleting.value) return
  goBack()
}
</script>

<template>
  <section class="delete-page">
    <header class="page-head">
      <button
        class="back-btn"
        type="button"
        @click="goBack"
      >
        <ArrowLeft
          :size="18"
          aria-hidden="true"
        />
        我的
      </button>
      <h1 class="head-title">
        注销账号
      </h1>
    </header>

    <div
      class="warning-card"
      role="note"
    >
      <ShieldAlert
        :size="22"
        aria-hidden="true"
      />
      <p>注销后，账号、卡组、卡片、复习记录和 AI 学习记录都会永久删除，无法恢复。</p>
    </div>

    <form
      class="delete-form"
      @submit.prevent="submit"
    >
      <div>
        <label
          class="label"
          for="delete-password"
        >确认身份</label>
        <input
          id="delete-password"
          v-model="password"
          class="input"
          type="password"
          autocomplete="current-password"
          placeholder="请输入当前密码"
          :disabled="deleting"
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
        class="btn btn-danger submit"
        type="submit"
        :disabled="!canSubmit"
      >
        {{ deleting ? '注销中…' : '永久注销账号' }}
      </button>

      <button
        class="btn btn-ghost"
        type="button"
        :disabled="deleting"
        @click="cancel"
      >
        取消
      </button>
    </form>
  </section>
</template>

<style scoped>
.delete-page {
  display: flex;
  flex-direction: column;
  gap: 16px;
  width: min(100%, 560px);
  min-width: 0;
  margin: 0 auto;
  padding: 16px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}

.page-head {
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

.warning-card {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 16px;
  border: 1px solid color-mix(in srgb, var(--color-red) 35%, transparent);
  border-radius: var(--radius-md);
  background: color-mix(in srgb, var(--color-red) 10%, var(--surface));
  color: var(--color-red-text);
  font-size: 14px;
  line-height: 1.7;
}

.warning-card svg {
  flex: none;
  margin-top: 2px;
}

.delete-form {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface);
  box-shadow: var(--shadow-sm);
}

.error {
  padding: 10px 14px;
  border: 1px solid color-mix(in srgb, var(--color-red) 40%, transparent);
  border-radius: var(--radius-sm);
  background: color-mix(in srgb, var(--color-red) 12%, var(--surface));
  color: var(--color-red-text);
  font-size: 14px;
}

.submit {
  width: 100%;
}

.back-btn:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}

@media (min-width: 900px) {
  .delete-page {
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
