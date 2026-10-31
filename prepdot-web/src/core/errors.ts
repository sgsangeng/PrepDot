export class ApiError extends Error {
  constructor(public readonly code: number, message: string) {
    super(message)
    this.name = 'ApiError'
  }
}

export function friendlyError(error: unknown): string {
  if (error instanceof ApiError) return error.message
  // 浏览器对网络失败通常抛出 "Failed to fetch"，大小写不固定，统一小写判断。
  if (error instanceof TypeError && error.message.toLowerCase().includes('fetch')) return '网络连接失败，请检查网络后重试。'
  if (error instanceof DOMException && error.name === 'AbortError') return '操作已取消。'
  if (error instanceof Error && error.message) return error.message
  return '服务暂时不可用，请稍后重试。'
}
