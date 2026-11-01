import type { ApiRequest, HttpTransport, MultipartRequest, RawResponse } from '@/adapters/types'
import { StreamRequestError } from '@/adapters/errors'
import { ApiError } from '@/core/errors'

export interface TokenProvider {
  getToken(): Promise<string | null>
  onUnauthorized(): Promise<void>
  maybeRefresh(): Promise<void>
}

const UNAUTHORIZED_MESSAGE = '登录已失效，请重新登录'

export class ApiClient {
  constructor(private readonly http: HttpTransport, private readonly tokens: TokenProvider) {}

  async request<T>(req: ApiRequest): Promise<T> {
    const response = await this.http.json<T>({ ...req, headers: await this.authHeaders(req.headers) })
    return this.unwrap(response, true)
  }

  async upload<T>(req: MultipartRequest): Promise<T> {
    const response = await this.http.multipart<T>({ ...req, headers: await this.authHeaders(req.headers) })
    return this.unwrap(response, true)
  }

  async *stream(req: ApiRequest): AsyncIterable<string> {
    try {
      yield* this.http.streamText({ ...req, headers: await this.authHeaders(req.headers) })
    } catch (error) {
      if (error instanceof StreamRequestError && error.status === 401) {
        await this.tokens.onUnauthorized()
        throw new ApiError(401, UNAUTHORIZED_MESSAGE)
      }
      throw error
    }
  }

  /** 统一附加 Bearer Token，允许调用方通过 headers 覆盖。 */
  private async authHeaders(extra?: Record<string, string>): Promise<Record<string, string>> {
    const token = await this.tokens.getToken()
    return { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extra }
  }

  /** 统一 401 / 业务码 / 解包 / 续期逻辑，request 与 upload 共用避免漂移。 */
  private async unwrap<T>(response: RawResponse<T>, refresh: boolean): Promise<T> {
    if (response.status === 401) {
      await this.tokens.onUnauthorized()
      throw new ApiError(401, UNAUTHORIZED_MESSAGE)
    }
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message || '请求失败')
    if (refresh) void this.tokens.maybeRefresh()
    return response.body.data as T
  }
}
