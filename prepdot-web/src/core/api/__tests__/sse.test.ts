import { describe, expect, it } from 'vitest'
import { createSseParser } from '../sse'

describe('sse parser', () => {
  it('handles chunk boundaries and multiline data', () => {
    const events: { event: string; data: string }[] = []
    const feed = createSseParser(e => events.push(e))
    feed('event: progress\ndata: 正在读取')
    feed('学习数据\n\n')
    feed('event: result\ndata: {"runId":1}\n\n')
    expect(events).toEqual([
      { event: 'progress', data: '正在读取学习数据' },
      { event: 'result', data: '{"runId":1}' }
    ])
  })
})
