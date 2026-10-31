const SERVER_TIME_ZONE = 'Asia/Shanghai'

function partsOf(value: string): { y: number; mo: number; d: number; h: number; mi: number; s: number } | null {
  // 时间部分可选：纯日期（如 `2026-10-31`）按上海时区当天 00:00 处理。
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(value)
  if (!match) return null
  return {
    y: Number(match[1]), mo: Number(match[2]), d: Number(match[3]),
    h: Number(match[4] ?? 0), mi: Number(match[5] ?? 0), s: Number(match[6] ?? 0)
  }
}

/**
 * 把绝对时间转换为「上海时区的墙上时间」，并以 UTC 字段承载，
 * 便于不依赖浏览器时区做日期比较。
 */
function serverNowMs(nowMs: number): number {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: SERVER_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
  })
  const parts = Object.fromEntries(formatter.formatToParts(new Date(nowMs)).map(p => [p.type, p.value]))
  return Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day),
    Number(parts.hour === '24' ? '0' : parts.hour), Number(parts.minute), Number(parts.second))
}

export function formatServerDate(value: string | null): string {
  if (!value) return '—'
  const p = partsOf(value)
  if (!p) return value
  return `${p.mo}月${p.d}日 ${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`
}

export function formatRelativeDay(value: string | null, nowMs: number): string {
  if (!value) return '—'
  const p = partsOf(value)
  if (!p) return value
  const target = Date.UTC(p.y, p.mo - 1, p.d)
  const today = serverNowMs(nowMs)
  const days = Math.round((target - Date.UTC(new Date(today).getUTCFullYear(), new Date(today).getUTCMonth(), new Date(today).getUTCDate())) / 86400000)
  if (days === 0) return '今天'
  if (days === 1) return '明天'
  if (days === -1) return '昨天'
  return days > 0 ? `${days} 天后` : `${Math.abs(days)} 天前`
}
