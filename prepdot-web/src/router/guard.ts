/**
 * 路由守卫的纯函数核心：根据登录态与目标路由名决定是否重定向。
 * 与 router/pinia 解耦，便于单测。
 */
export function resolveRedirect(authenticated: boolean, routeName: string): string | null {
  if (!authenticated && routeName !== 'login') return 'login'
  if (authenticated && routeName === 'login') return 'review'
  return null
}
