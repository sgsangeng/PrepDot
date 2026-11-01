import type { Clock } from '@/adapters/types'

export function createClock(): Clock {
  return { now: () => Date.now() }
}
