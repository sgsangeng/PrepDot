import type { FilePort, PickedFile } from '@/adapters/types'

const UNIMPLEMENTED = 'desktop adapter 将在 Phase 2 实现'

export function createFilePort(): FilePort {
  return {
    async pick(): Promise<PickedFile[]> {
      throw new Error(UNIMPLEMENTED)
    }
  }
}
