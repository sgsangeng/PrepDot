import { defineConfig, devices } from '@playwright/test'

/**
 * 移动端冒烟测试。默认复用已在 4173 端口运行的 dev server；
 * 未运行时通过 Vite 代理指向演示环境，避免误连本地空库。
 *
 * 完整的 demo 数据与端到端流程在 Task 16 统一执行。
 */
export default defineConfig({
  testDir: './e2e',
  outputDir: 'e2e-results',
  timeout: 60_000,
  use: {
    baseURL: 'http://127.0.0.1:4173',
    trace: 'retain-on-failure'
  },
  projects: [{ name: 'mobile', use: { ...devices['iPhone 13'] } }],
  webServer: {
    command: 'pnpm dev --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: true,
    env: { VITE_DEV_API_TARGET: 'https://api.prepdot.site' }
  }
})
