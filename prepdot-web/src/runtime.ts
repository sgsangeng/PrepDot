import type { AppAdapters } from '@/adapters/types'
import { AuthSession } from '@/core/session/session'
import { ApiClient } from '@/core/api/client'
import { createApi } from '@/core/api/endpoints'

export interface Runtime {
  adapters: AppAdapters
  session: AuthSession
  api: ApiClient
  endpoints: ReturnType<typeof createApi>
}

let runtime: Runtime | null = null

export function setRuntime(value: Runtime): void {
  runtime = value
}

export function getRuntime(): Runtime {
  if (!runtime) throw new Error('runtime 尚未初始化')
  return runtime
}

export function createRuntime(adapters: AppAdapters): Runtime {
  const session = new AuthSession(adapters.storage, adapters.http, adapters.clock)
  const api = new ApiClient(adapters.http, session)
  return { adapters, session, api, endpoints: createApi(api) }
}
