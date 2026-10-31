import type { StoragePort } from '@/adapters/types'

export function createStorage(): StoragePort {
  return {
    async get(key: string): Promise<string | null> {
      return localStorage.getItem(key)
    },
    async set(key: string, value: string): Promise<void> {
      localStorage.setItem(key, value)
    },
    async remove(key: string): Promise<void> {
      localStorage.removeItem(key)
    }
  }
}
