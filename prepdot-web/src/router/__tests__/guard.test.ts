import { describe, expect, it } from 'vitest'
import { resolveRedirect } from '../guard'

describe('route guard', () => {
  it('sends unauthenticated users to login', () => {
    expect(resolveRedirect(false, 'review')).toBe('login')
  })
  it('sends authenticated users away from login', () => {
    expect(resolveRedirect(true, 'login')).toBe('review')
  })
  it('keeps authenticated users on protected routes', () => {
    expect(resolveRedirect(true, 'decks')).toBeNull()
  })
})
