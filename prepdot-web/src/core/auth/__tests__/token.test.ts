import { describe, expect, it } from 'vitest'
import { decodeJwtExp, expiresAt, shouldRefresh } from '../token'

function jwt(payload: object): string {
  const enc = (v: object) => btoa(JSON.stringify(v)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  return `${enc({ alg: 'HS256' })}.${enc(payload)}.sig`
}

describe('jwt token helpers', () => {
  it('reads exp seconds', () => {
    expect(decodeJwtExp(jwt({ exp: 1700000000 }))).toBe(1700000000)
  })
  it('treats malformed token as expired', () => {
    expect(expiresAt('nope', 0)).toBe(0)
  })
  it('refreshes with less than 3.5 days left', () => {
    const now = 1_700_000_000_000
    expect(shouldRefresh(jwt({ exp: now / 1000 + 3 * 86400 }), now)).toBe(true)
    expect(shouldRefresh(jwt({ exp: now / 1000 + 5 * 86400 }), now)).toBe(false)
  })
})
