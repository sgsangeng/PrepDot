import type { ApiRequest, HttpTransport, MultipartRequest, RawResponse } from '@/adapters/types'

const BASE = import.meta.env.VITE_API_BASE_URL ?? '/api'

/**
 * 字符串视为已序列化的原始请求体（如 `/ai/import` 的原始 JSON 文本），
 * 与 iOS 及 curl `--data-binary` 的行为一致；其余值按 JSON 序列化。
 */
function bodyOf(body: unknown): BodyInit | undefined {
  if (body === undefined) return undefined
  return typeof body === 'string' ? body : JSON.stringify(body)
}

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
        body: bodyOf(req.body),
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
        body: bodyOf(req.body),
        signal: req.signal
      })
      if (!res.ok || !res.body) {
        let detail = ''
        try {
          const text = await res.text()
          try {
            const parsed = JSON.parse(text) as { message?: string }
            detail = (parsed.message ?? text).slice(0, 300)
          } catch {
            detail = text.slice(0, 300)
          }
        } catch {
          // 读取错误响应体失败时保留状态码信息即可。
        }
        throw new Error(`流式请求失败（${res.status}）${detail ? `：${detail}` : ''}`)
      }
      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          yield decoder.decode(value, { stream: true })
        }
        const tail = decoder.decode()
        if (tail) yield tail
      } finally {
        try {
          await reader.cancel()
        } catch {
          // 流可能已正常结束或被网络中断，取消失败不影响调用方。
        }
        reader.releaseLock()
      }
    }
  }
}
