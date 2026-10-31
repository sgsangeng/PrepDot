import type { FilePort, PickedFile } from '@/adapters/types'

function toPickedFile(file: File): PickedFile {
  return {
    name: file.name,
    mime: file.type,
    size: file.size,
    bytes: () => file.arrayBuffer()
  }
}

export function createFilePort(): FilePort {
  return {
    pick(options) {
      return new Promise<PickedFile[]>((resolve) => {
        const input = document.createElement('input')
        input.type = 'file'
        input.multiple = options.multiple
        input.accept = options.accept.join(',')
        input.style.display = 'none'
        document.body.appendChild(input)

        let settled = false
        let safetyTimer: number | null = null

        const cleanup = (): void => {
          window.removeEventListener('focus', onWindowFocus)
          if (safetyTimer !== null) {
            window.clearTimeout(safetyTimer)
            safetyTimer = null
          }
          input.remove()
        }

        const finish = (files: PickedFile[]): void => {
          if (settled) return
          settled = true
          cleanup()
          resolve(files)
        }

        // 部分浏览器在用户取消选择时不会触发 change 事件，用窗口重新获得焦点兜底。
        const onWindowFocus = (): void => {
          window.setTimeout(() => {
            if (!settled) finish([])
          }, 300)
        }

        input.addEventListener('change', () => {
          finish(Array.from(input.files ?? []).map(toPickedFile))
        })
        input.addEventListener('cancel', () => finish([]))
        window.addEventListener('focus', onWindowFocus)

        // 兜底：对话框异常或用户长时间未操作时，避免隐藏 input 与监听器泄漏。
        safetyTimer = window.setTimeout(() => finish([]), 60_000)

        input.click()
      })
    }
  }
}
