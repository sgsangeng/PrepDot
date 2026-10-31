import type { StoragePort } from '@/adapters/types'

/**
 * 契约：
 * - `get` 在 localStorage 不可访问（隐私模式、被禁用等）时返回 null，让调用方按“未登录”处理；
 * - `set` / `remove` 失败时抛出带可读原因的错误，由上层展示给用户。
 */
export function createStorage(): StoragePort {
  return {
    async get(key: string): Promise<string | null> {
      try {
        return localStorage.getItem(key)
      } catch {
        return null
      }
    },
    async set(key: string, value: string): Promise<void> {
      try {
        localStorage.setItem(key, value)
      } catch (error) {
        throw new Error(`无法写入本地存储（可能是隐私模式或空间不足）：${describe(error)}`)
      }
    },
    async remove(key: string): Promise<void> {
      try {
        localStorage.removeItem(key)
      } catch (error) {
        throw new Error(`无法清除本地存储（可能是隐私模式或空间不足）：${describe(error)}`)
      }
    }
  }
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
