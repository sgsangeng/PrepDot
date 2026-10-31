import type { ApiRequest, HttpTransport, MultipartRequest, RawResponse } from '@/adapters/types'

const BASE = import.meta.env.VITE_API_BASE_URL ?? '/api'

async function parse<T>(res: Response): Promise<RawResponse<T>> {
  const text = await res.text()
  try {
    return { status: res.status, body: JSON.parse(text) }
  } catch {
    return {
      status: res.status,
      body: { code: res.status, message: text || `请求失败（${res.status}）`, data: null }
    }
  }
}

export function createHttpTransport(): HttpTransport {
  return {
    async json<T>(req: ApiRequest) {
      return parse<T>(await fetch(BASE + req.path, {
        method: req.method,
        headers: { ...(req.body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...req.headers },
        body: req.body !== undefined ? JSON.stringify(req.body) : undefined,
        signal: req.signal
      }))
    },
    async multipart<T>(req: MultipartRequest) {
      const form = new FormData()
      for (const field of req.fields) form.append(field.name, field.value)
      form.append(req.file.field, new Blob([req.file.bytes], { type: req.file.mime }), req.file.name)
      return parse<T>(await fetch(BASE + req.path, {
        method: 'POST',
        headers: req.headers,
        body: form,
        signal: req.signal
      }))
    },
    async *streamText(req: ApiRequest) {
      const res = await fetch(BASE + req.path, {
        method: req.method,
        headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', ...req.headers },
        body: req.body !== undefined ? JSON.stringify(req.body) : undefined,
        signal: req.signal
      })
      if (!res.ok || !res.body) throw new Error(`流式请求失败（${res.status}）`)
      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          yield decoder.decode(value, { stream: true })
        }
      } finally {
        reader.releaseLock()
      }
    }
  }
}
