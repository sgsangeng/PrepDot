import type { Clock, HttpTransport, StoragePort } from '@/adapters/types'
import type { AuthUser } from '@/core/api/types'
import { ApiError } from '@/core/errors'
import type { TokenProvider } from '@/core/api/client'
import { expiresAt, shouldRefresh } from '@/core/auth/token'

const TOKEN_KEY = 'prepdot.token'
const USER_KEY = 'prepdot.user'

/** 只有明确的鉴权失败才允许在恢复阶段登出；网络/5xx 不应清空会话。 */
function isDefinitiveAuthFailure(error: unknown): boolean {
  return error instanceof ApiError && error.code === 401
}

export class AuthSession implements TokenProvider {
  private token: string | null = null
  private user: AuthUser | null = null
  private refreshing: Promise<void> | null = null
  private readonly unauthorizedHandlers = new Set<() => void>()

  constructor(
    private readonly storage: StoragePort,
    private readonly http: HttpTransport,
    private readonly clock: Clock
  ) {}

  get currentUser(): AuthUser | null { return this.user }
  /** 鉴权状态要求 token 与用户缓存同时存在，避免「已登录但无用户」的半状态。 */
  get isAuthenticated(): boolean { return this.token !== null && this.user !== null }

  async restore(): Promise<AuthUser | null> {
    const token = await this.storage.get(TOKEN_KEY)
    if (!token) {
      this.token = null
      this.user = null
      return null
    }
    this.token = token
    this.user = this.parseUser(await this.storage.get(USER_KEY))
    if (!this.user) {
      // 缺 token 时上面已清空；有 token 但用户缓存缺失/损坏时保留 token 供重新登录复用，
      // 清空内存用户并视为未登录（isAuthenticated 同时要求 token 与 user）。
      return null
    }
    if (shouldRefresh(token, this.clock.now())) {
      try {
        await this.refresh()
      } catch (error) {
        const expired = expiresAt(token, this.clock.now()) <= this.clock.now()
        if (isDefinitiveAuthFailure(error) || expired) {
          await this.logout()
        }
        // 其余失败（网络/DNS/超时/5xx）保留 token 与缓存用户，
        // 等第一次真实 API 返回 401 时再由 onUnauthorized 统一登出。
      }
    }
    return this.user
  }

  async login(username: string, password: string): Promise<AuthUser> {
    return this.authenticate('/auth/login', { username, password })
  }

  async register(username: string, password: string, nickname: string): Promise<AuthUser> {
    return this.authenticate('/auth/register', { username, password, nickname })
  }

  private async authenticate(path: string, body: Record<string, string>): Promise<AuthUser> {
    const response = await this.http.json<AuthUser>({
      method: 'POST', path, body, headers: { 'Content-Type': 'application/json' }
    })
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message)
    const user = response.body.data as AuthUser
    await this.persist(user)
    return user
  }

  private parseUser(raw: string | null): AuthUser | null {
    if (!raw) return null
    try {
      return JSON.parse(raw) as AuthUser
    } catch {
      // 本地缓存损坏（被篡改/旧版本结构）时按未登录处理，避免启动崩溃。
      return null
    }
  }

  private async persist(user: AuthUser): Promise<void> {
    this.token = user.token
    this.user = user
    await this.storage.set(TOKEN_KEY, user.token)
    await this.storage.set(USER_KEY, JSON.stringify(user))
  }

  async getToken(): Promise<string | null> { return this.token }

  async maybeRefresh(): Promise<void> {
    if (!this.token || !shouldRefresh(this.token, this.clock.now())) return
    try { await this.refresh() } catch { /* 下一次 401 会统一登出 */ }
  }

  async refresh(): Promise<void> {
    const token = this.token
    if (!token) return
    if (this.refreshing) return this.refreshing
    this.refreshing = (async () => {
      const response = await this.http.json<AuthUser>({
        method: 'POST', path: '/auth/refresh',
        headers: { Authorization: `Bearer ${token}` }
      })
      if (response.status === 401 || response.body.code === 401) {
        throw new ApiError(401, response.body.message || '登录已失效，请重新登录')
      }
      if (response.body.code !== 200 || !response.body.data) throw new ApiError(response.body.code, response.body.message)
      // 请求期间已登出或切换账号时丢弃过期响应，避免把旧会话写回存储。
      if (this.token !== token) return
      await this.persist(response.body.data)
    })().finally(() => { this.refreshing = null })
    return this.refreshing
  }

  /**
   * 订阅「被动登出」（如任意请求返回 401）事件。返回取消订阅函数。
   * 手动 logout() 不触发，避免调用方自己清理状态时重复处理。
   */
  onUnauthorizedChange(handler: () => void): () => void {
    this.unauthorizedHandlers.add(handler)
    return () => { this.unauthorizedHandlers.delete(handler) }
  }

  async onUnauthorized(): Promise<void> {
    await this.logout()
    for (const handler of this.unauthorizedHandlers) handler()
  }

  async logout(): Promise<void> {
    this.token = null
    this.user = null
    await this.storage.remove(TOKEN_KEY)
    await this.storage.remove(USER_KEY)
  }
}
