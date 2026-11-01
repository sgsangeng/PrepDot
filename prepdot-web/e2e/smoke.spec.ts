import { expect, test } from '@playwright/test'

/**
 * 移动端冒烟：演示账号登录 → 今日复习 → 知识树搜索 → 开始复习。
 *
 * 每个用例使用全新的浏览器上下文（不共享 storageState），
 * 因此两个用例彼此独立，可以并行执行。
 */
test('demo login, knowledge tree search, review session', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: '使用演示账号' }).click()
  await expect(page).toHaveURL(/\/review/)

  // 顶栏标题与页面内标题同名，用 banner 限定到顶栏，避免 strict mode 冲突。
  await expect(page.getByRole('banner').getByRole('heading', { name: '今日复习' })).toBeVisible()

  await page.getByRole('link', { name: '知识树', exact: true }).click()
  await expect(page).toHaveURL(/\/decks/)

  const search = page.getByRole('searchbox', { name: '搜索知识节点' })
  await expect(search).toBeVisible()
  await search.fill('Java')
  await expect(search).toHaveValue('Java')

  await page.getByRole('link', { name: '今日复习', exact: true }).click()
  await expect(page).toHaveURL(/\/review/)

  const start = page.getByRole('button', { name: /^(开始复习|继续复习)$/ })
  const empty = page.getByText('今天没有到期卡片')
  // 等待概览加载完成：有到期卡片时出现开始按钮，否则出现空状态。
  await expect(start.or(empty)).toBeVisible()

  if (await start.isVisible()) {
    await start.click()
    // 会话头部的进度是「当前序号 / 卡片总数」，与概览的「已完成/总数」格式不同。
    await expect(page.locator('.session-count')).toHaveText(/^1 \/ \d+$/)
    await expect(page.getByRole('progressbar').first()).toHaveAttribute('aria-valuenow', '1')
  }
})

test('profile renders stats sections', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: '使用演示账号' }).click()
  await expect(page).toHaveURL(/\/review/)

  await page.getByRole('link', { name: '我的', exact: true }).click()
  await expect(page).toHaveURL(/\/profile/)
  await expect(page.getByRole('heading', { name: '近 7 天复习' })).toBeVisible()
  await expect(page.getByRole('heading', { name: '记忆度分布' })).toBeVisible()
})
