import type { ApiRequest, HttpTransport, MultipartRequest } from '@/adapters/types'
import { ApiError } from '@/core/errors'

export interface TokenProvider {
  getToken(): Promise<string | null>
  onUnauthorized(): Promise<void>
  maybeRefresh(): Promise<void>
}

export class ApiClient {
  constructor(private readonly http: HttpTransport, private readonly tokens: TokenProvider) {}

  async request<T>(req: ApiRequest): Promise<T> {
    const token = await this.tokens.getToken()
    const response = await this.http.json<T>({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
    if (response.status === 401) {
      await this.tokens.onUnauthorized()
      throw new ApiError(401, '登录已失效，请重新登录')
    }
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message || '请求失败')
    void this.tokens.maybeRefresh()
    return response.body.data as T
  }

  async upload<T>(req: MultipartRequest): Promise<T> {
    const token = await this.tokens.getToken()
    const response = await this.http.multipart<T>({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
    if (response.status === 401) {
      await this.tokens.onUnauthorized()
      throw new ApiError(401, '登录已失效，请重新登录')
    }
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message || '请求失败')
    return response.body.data as T
  }

  async *stream(req: ApiRequest): AsyncIterable<string> {
    const token = await this.tokens.getToken()
    yield* this.http.streamText({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
  }
}
