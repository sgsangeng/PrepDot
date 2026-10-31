import { describe, expect, it } from 'vitest'
import type { ApiRequest } from '@/adapters/types'
import type { ApiClient } from '../client'
import { createApi } from '../endpoints'

function fakeClient() {
  const requests: ApiRequest[] = []
  const client = {
    request: async <T,>(req: ApiRequest) => {
      requests.push(req)
      return null as T
    },
    upload: async <T,>() => null as T,
    stream: async function* () {
      yield* [] as string[]
    }
  } as unknown as ApiClient
  return { client, requests }
}

describe('createApi.deleteCards', () => {
  it('skips the request for an empty id list', async () => {
    const { client, requests } = fakeClient()

    await createApi(client).deleteCards([])
    expect(requests).toHaveLength(0)
  })

  it('sends one ids query parameter per card', async () => {
    const { client, requests } = fakeClient()

    await createApi(client).deleteCards([1, 2])
    expect(requests).toHaveLength(1)
    expect(requests[0]).toMatchObject({ method: 'DELETE', path: '/cards/batch?ids=1&ids=2' })
  })
})
