/**
 * 流式请求在建立连接阶段失败时抛出，携带 HTTP 状态码。
 * core 依据该状态码判断 401 并触发统一登出。
 */
export class StreamRequestError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message)
    this.name = 'StreamRequestError'
  }
}
