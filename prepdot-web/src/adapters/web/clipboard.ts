import type { ClipboardPort } from '@/adapters/types'

export function createClipboardPort(): ClipboardPort {
  return {
    async readText(): Promise<string> {
      if (!navigator.clipboard?.readText) {
        throw new Error('当前浏览器不支持读取剪贴板')
      }
      return navigator.clipboard.readText()
    }
  }
}
