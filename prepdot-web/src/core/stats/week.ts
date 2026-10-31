/**
 * 后端 `UserStats.weeklyData[].day` 实际返回 `MM-DD`（如 `10-31`），
 * 前端图表需要补齐缺失日期并统一成 `YYYY-MM-DD`。
 *
 * 年份不能从 `MM-DD` 推断（跨年时会猜错），因此以「今天」为锚点倒推 6 天，
 * 全部日期都在目标时区的墙上时间里计算；输入只按 `MM-DD`（`day.slice(-5)`）
 * 匹配。重复的 `MM-DD` 计数相加。
 */

export interface WeeklyCount {
  day: string
  count: number
}

export interface DailyCount {
  /** `YYYY-MM-DD`，由本函数生成，跨年也正确。 */
  day: string
  /** 图表横轴标签，`MM/DD`。 */
  label: string
  count: number
}

const DAY_MS = 86_400_000
const DEFAULT_TIME_ZONE = 'Asia/Shanghai'

/** 把 `nowMs` 换算成目标时区的「当天 00:00」，以 UTC 字段承载，避免浏览器时区干扰。 */
function startOfDayInTimeZone(nowMs: number, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).formatToParts(new Date(nowMs))
  const values: Record<string, string> = {}
  for (const part of parts) {
    if (part.type !== 'literal') values[part.type] = part.value
  }
  return Date.UTC(Number(values.year), Number(values.month) - 1, Number(values.day))
}

function formatWallDay(wallMs: number): { day: string; label: string } {
  const date = new Date(wallMs)
  const year = date.getUTCFullYear()
  const month = String(date.getUTCMonth() + 1).padStart(2, '0')
  const day = String(date.getUTCDate()).padStart(2, '0')
  return { day: `${year}-${month}-${day}`, label: `${month}/${day}` }
}

/**
 * 返回含今天在内的连续 7 天（升序），缺失日期计数补 0。
 *
 * @param data 后端 `weeklyData`，`day` 为 `MM-DD`（也兼容完整的 `YYYY-MM-DD`）。
 * @param nowMs 当前时间（毫秒）。
 * @param timeZone 计算「今天」所用的时区，默认与后端一致：Asia/Shanghai。
 */
export function last7Days(
  data: WeeklyCount[],
  nowMs: number,
  timeZone: string = DEFAULT_TIME_ZONE
): DailyCount[] {
  const lookup = new Map<string, number>()
  for (const item of data) {
    const key = item.day.slice(-5)
    lookup.set(key, (lookup.get(key) ?? 0) + item.count)
  }

  const today = startOfDayInTimeZone(nowMs, timeZone)
  const rows: DailyCount[] = []
  for (let offset = 6; offset >= 0; offset -= 1) {
    const { day, label } = formatWallDay(today - offset * DAY_MS)
    rows.push({ day, label, count: lookup.get(day.slice(-5)) ?? 0 })
  }
  return rows
}
