import { defineStore } from 'pinia'
import { ref } from 'vue'

const TOAST_DURATION = 2500

export const useToastStore = defineStore('toast', () => {
  const message = ref('')
  const visible = ref(false)
  let timer: ReturnType<typeof setTimeout> | null = null

  function clearTimer(): void {
    if (timer !== null) {
      clearTimeout(timer)
      timer = null
    }
  }

  function show(msg: string): void {
    message.value = msg
    visible.value = true
    clearTimer()
    timer = setTimeout(() => {
      visible.value = false
      message.value = ''
    }, TOAST_DURATION)
  }

  function hide(): void {
    clearTimer()
    visible.value = false
    message.value = ''
  }

  return { message, visible, show, hide }
})
