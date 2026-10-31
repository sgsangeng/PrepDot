export interface SseEvent { event: string; data: string }

export function createSseParser(onEvent: (event: SseEvent) => void): (chunk: string) => void {
  let buffer = ''
  return (chunk: string) => {
    buffer += chunk.replace(/\r\n/g, '\n')
    let index = buffer.indexOf('\n\n')
    while (index >= 0) {
      const raw = buffer.slice(0, index)
      buffer = buffer.slice(index + 2)
      let event = 'message'
      const data: string[] = []
      for (const line of raw.split('\n')) {
        if (line.startsWith('event:')) event = line.slice(6).trim()
        else if (line.startsWith('data:')) data.push(line.slice(5).replace(/^ /, ''))
      }
      if (data.length > 0) onEvent({ event, data: data.join('\n') })
      index = buffer.indexOf('\n\n')
    }
  }
}
