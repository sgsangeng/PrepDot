import { describe, expect, it } from 'vitest'
import type { ApiRequest, HttpTransport, MultipartRequest, RawResponse } from '@/adapters/types'
import { StreamRequestError } from '@/adapters/errors'
import { ApiError } from '@/core/errors'
import { ApiClient, type TokenProvider } from '../client'

function transportWith(
  respond: (req: ApiRequest) => Promise<RawResponse<unknown>>,
  sent: ApiRequest[] = []
): HttpTransport {
  return {
    json: <T>(req: ApiRequest) => {
      sent.push(req)
      return respond(req) as Promise<RawResponse<T>>
    },
    multipart: <T>() => Promise.reject(new Error('unexpected multipart')) as Promise<RawResponse<T>>,
    streamText: async function* () {
      yield* [] as string[]
    }
  }
}

function tokenProvider(token: string | null = 'token-1') {
  const calls = { unauthorized: 0, refresh: 0 }
  const provider: TokenProvider = {
    getToken: async () => token,
    onUnauthorized: async () => { calls.unauthorized += 1 },
    maybeRefresh: async () => { calls.refresh += 1 }
  }
  return { provider, calls }
}

const ok = <T,>(data: T): RawResponse<T> => ({ status: 200, body: { code: 200, message: 'ok', data } })

describe('ApiClient.request', () => {
  it('unwraps data and attaches the bearer token', async () => {
    const sent: ApiRequest[] = []
    const { provider, calls } = tokenProvider('abc')
    const client = new ApiClient(transportWith(async () => ok({ id: 7 }), sent), provider)

    await expect(client.request<{ id: number }>({ method: 'GET', path: '/decks' })).resolves.toEqual({ id: 7 })
    expect(sent[0].headers).toEqual({ Authorization: 'Bearer abc' })
    expect(calls.refresh).toBe(1)
  })

  it('omits Authorization when logged out', async () => {
    const sent: ApiRequest[] = []
    const { provider } = tokenProvider(null)
    const client = new ApiClient(transportWith(async () => ok([]), sent), provider)

    await client.request({ method: 'GET', path: '/decks' })
    expect(sent[0].headers).toEqual({})
  })

  it('throws ApiError for a non-200 business code', async () => {
    const { provider } = tokenProvider()
    const client = new ApiClient(
      transportWith(async () => ({ status: 200, body: { code: 400, message: '卡组不存在', data: null } })),
      provider
    )

    const error = await client.request({ method: 'GET', path: '/decks/1' }).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ code: 400, message: '卡组不存在' })
  })

  it('notifies the session and throws on 401', async () => {
    const { provider, calls } = tokenProvider('expired')
    const client = new ApiClient(
      transportWith(async () => ({ status: 401, body: { code: 401, message: 'unauthorized', data: null } })),
      provider
    )

    const error = await client.request({ method: 'GET', path: '/decks' }).catch((e: unknown) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ code: 401 })
    expect(calls.unauthorized).toBe(1)
    expect(calls.refresh).toBe(0)
  })
})

describe('ApiClient.upload', () => {
  it('unwraps a successful upload and triggers refresh', async () => {
    const sent: MultipartRequest[] = []
    const { provider, calls } = tokenProvider('abc')
    const client = new ApiClient({
      json: async <T,>() => ok(null as T),
      multipart: async <T,>(req: MultipartRequest) => {
        sent.push(req)
        return ok('deck-json') as RawResponse<T>
      },
      streamText: async function* () {
        yield* [] as string[]
      }
    }, provider)

    await expect(client.upload<string>({
      path: '/ai/generate',
      fields: [{ name: 'deckTitle', value: 't' }],
      file: { field: 'file', name: 'a.txt', mime: 'text/plain', bytes: new ArrayBuffer(0) }
    })).resolves.toBe('deck-json')
    expect(sent[0].headers).toEqual({ Authorization: 'Bearer abc' })
    expect(calls.refresh).toBe(1)
  })
})

describe('ApiClient.stream', () => {
  function streamTransport(failure: Error): HttpTransport {
    return {
      json: async <T,>() => ok(null as T),
      multipart: async <T,>() => ok(null as T),
      streamText: async function* () {
        yield* [] as string[]
        throw failure
      }
    }
  }

  async function consume(iterable: AsyncIterable<string>): Promise<void> {
    for await (const chunk of iterable) void chunk
  }

  it('logs out and throws a readable error on a 401 stream', async () => {
    const { provider, calls } = tokenProvider('expired')
    const client = new ApiClient(streamTransport(new StreamRequestError(401, '流式请求失败（401）')), provider)

    const error = await consume(client.stream({ method: 'POST', path: '/agent/coach/stream' }))
      .catch((e: unknown) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ code: 401, message: '登录已失效，请重新登录' })
    expect(calls.unauthorized).toBe(1)
  })

  it('passes non-401 stream failures through unchanged', async () => {
    const { provider, calls } = tokenProvider('abc')
    const failure = new StreamRequestError(500, '流式请求失败（500）')
    const client = new ApiClient(streamTransport(failure), provider)

    const error = await consume(client.stream({ method: 'POST', path: '/agent/coach/stream' }))
      .catch((e: unknown) => e)
    expect(error).toBe(failure)
    expect(calls.unauthorized).toBe(0)
  })
})
