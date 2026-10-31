import type { StoragePort } from '@/adapters/types'

const UNIMPLEMENTED = 'desktop adapter 将在 Phase 2 实现'

export function createStorage(): StoragePort {
  return {
    async get(): Promise<string | null> {
      throw new Error(UNIMPLEMENTED)
    },
    async set(): Promise<void> {
      throw new Error(UNIMPLEMENTED)
    },
    async remove(): Promise<void> {
      throw new Error(UNIMPLEMENTED)
    }
  }
}
