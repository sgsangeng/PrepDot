function base64UrlDecode(input: string): string {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (input.length % 4)) % 4)
  return atob(padded)
}

export function decodeJwtExp(token: string): number | null {
  const parts = token.split('.')
  if (parts.length < 2) return null
  try {
    const payload = JSON.parse(base64UrlDecode(parts[1])) as { exp?: unknown }
    return typeof payload.exp === 'number' ? payload.exp : null
  } catch {
    return null
  }
}

export function expiresAt(token: string, nowMs: number): number {
  void nowMs // 签名保留 nowMs 便于未来支持无 exp 的兜底策略；当前仅按 exp 计算。
  const exp = decodeJwtExp(token)
  return exp === null ? 0 : exp * 1000
}

export function shouldRefresh(token: string, nowMs: number): boolean {
  const expiry = expiresAt(token, nowMs)
  return expiry === 0 || expiry - nowMs < 3.5 * 24 * 3600 * 1000
}
