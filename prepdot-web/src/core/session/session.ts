import type { Clock, HttpTransport, StoragePort } from '@/adapters/types'
import type { AuthUser } from '@/core/api/types'
import { ApiError } from '@/core/errors'
import type { TokenProvider } from '@/core/api/client'
import { shouldRefresh } from '@/core/auth/token'

const TOKEN_KEY = 'prepdot.token'
const USER_KEY = 'prepdot.user'

export class AuthSession implements TokenProvider {
  private token: string | null = null
  private user: AuthUser | null = null
  private refreshing: Promise<void> | null = null

  constructor(
    private readonly storage: StoragePort,
    private readonly http: HttpTransport,
    private readonly clock: Clock
  ) {}

  get currentUser(): AuthUser | null { return this.user }
  get isAuthenticated(): boolean { return this.token !== null }

  async restore(): Promise<AuthUser | null> {
    this.token = await this.storage.get(TOKEN_KEY)
    this.user = this.parseUser(await this.storage.get(USER_KEY))
    if (!this.token) return null
    if (shouldRefresh(this.token, this.clock.now())) {
      try { await this.refresh() } catch { await this.logout() }
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
      if (response.body.code !== 200 || !response.body.data) throw new ApiError(response.body.code, response.body.message)
      // 请求期间已登出或切换账号时丢弃过期响应，避免把旧会话写回存储。
      if (this.token !== token) return
      await this.persist(response.body.data)
    })().finally(() => { this.refreshing = null })
    return this.refreshing
  }

  async onUnauthorized(): Promise<void> { await this.logout() }

  async logout(): Promise<void> {
    this.token = null
    this.user = null
    await this.storage.remove(TOKEN_KEY)
    await this.storage.remove(USER_KEY)
  }
}
