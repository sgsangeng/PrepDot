export function normalizeCardType(type: string): 'qa' | 'choice' | 'blank' {
  const value = type.toLowerCase()
  if (value === 'choice' || type === '选择' || type === '选择题') return 'choice'
  if (value === 'blank' || type === '填空' || type === '填空题') return 'blank'
  return 'qa'
}

export function cardDisplayText(value: string): string {
  return value.replace(/([；;])\s*([②③④⑤⑥⑦⑧⑨⑩])/g, '$1\n$2')
}

export function typeLabel(type: string): string {
  const normalized = normalizeCardType(type)
  return normalized === 'choice' ? '选择' : normalized === 'blank' ? '填空' : '问答'
}
