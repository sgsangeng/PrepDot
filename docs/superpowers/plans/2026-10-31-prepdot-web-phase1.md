# PrepDot Phase 1 Web 端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `prepdot.site` 上线一个与 iOS 视觉/功能对齐的 Vue 3 Web 应用，100% 复用现有 REST API，并通过 storage/notification/file adapter 为 Phase 2 桌面端预留边界。

**Architecture:** 新增 `prepdot-web/`，分为纯 TS `core/`（业务与协议）、`adapters/`（浏览器/桌面端口）、`ui/`（Vue 渲染）。生产环境由 Caddy 把 `prepdot.site/api/*` 反代到现有 Spring Boot，其余路径返回 SPA 静态文件；iOS 与 Web 共用同一后端与 MySQL。

**Tech Stack:** Vue 3.5、Vite 8、TypeScript 5.9、Vue Router 4、Pinia 3、markdown-it 15、lucide-vue-next、Vitest 5、Playwright 1.64、Caddy 2。

## Global Constraints

- 后端只允许一处改动：`JwtAuthFilter` 放行 `OPTIONS`；不得修改任何现有接口语义、DTO、数据库结构。
- 不得修改 `prepdot-ios/**` 下任何文件。
- `src/core/**` 禁止 import `vue`、`vue-router`、`pinia`、`src/adapters/web/**`，禁止使用 `window`、`document`、`localStorage`、`fetch`、`navigator`。
- `src/ui/**` 禁止直接使用 `fetch`、`localStorage`、`navigator.*`、`window.*`（布局读取视口宽度除外，优先 CSS）。
- 所有 API 响应按 `{ code, message, data }` 处理；`code !== 200` 必须抛出可读错误。
- 日期字段按 Asia/Shanghai 解释，不依赖浏览器本地时区。
- 视觉 Token 必须来自 `src/styles/tokens.css`；不得散落硬编码颜色。
- 移动端触控目标 ≥ 44×44px；支持 `prefers-color-scheme` 与 `prefers-reduced-motion`。
- 依赖版本锁定为本计划列出的精确版本；新增依赖需说明理由。
- 每个 Task 结束必须通过 `pnpm test`、`pnpm lint`、`pnpm build`（Task 2 建立后）。
- 不在本阶段实现 Tauri/Electron、SQLite、离线同步、推送服务、PWA。

---

## File Map

| 路径 | 责任 |
|---|---|
| `prepdot-backend/src/main/java/com/prepdot/config/JwtAuthFilter.java` | 放行 OPTIONS 预检 |
| `prepdot-backend/src/test/java/com/prepdot/config/JwtAuthFilterTest.java` | 预检与未授权行为测试 |
| `prepdot-web/package.json` | 依赖与脚本 |
| `prepdot-web/vite.config.ts` | Vue 插件、`@` 别名、开发代理 |
| `prepdot-web/tsconfig.json` | 严格 TS 配置 |
| `prepdot-web/eslint.config.js` | 边界规则 |
| `prepdot-web/index.html` | SPA 入口 |
| `prepdot-web/src/main.ts` | 组装 adapters/core/ui |
| `prepdot-web/src/App.vue` | 根组件 |
| `prepdot-web/src/styles/tokens.css` | 设计 Token |
| `prepdot-web/src/styles/base.css` | reset、排版、通用布局 |
| `prepdot-web/src/styles/components.css` | 按钮、卡片、表单、Sheet、Toast |
| `prepdot-web/src/adapters/types.ts` | 所有端口接口 |
| `prepdot-web/src/adapters/web/*.ts` | 浏览器实现 |
| `prepdot-web/src/adapters/desktop/*.ts` | Phase 2 空壳 |
| `prepdot-web/src/runtime.ts` | 单例组装：adapters + session + api |
| `prepdot-web/src/core/api/types.ts` | 后端 DTO 类型 |
| `prepdot-web/src/core/api/client.ts` | 解包、鉴权、401 |
| `prepdot-web/src/core/api/sse.ts` | SSE 解析 |
| `prepdot-web/src/core/api/endpoints.ts` | 所有接口函数 |
| `prepdot-web/src/core/session/session.ts` | 登录、续期、登出 |
| `prepdot-web/src/core/auth/token.ts` | JWT exp 解析 |
| `prepdot-web/src/core/errors.ts` | ApiError / 友好文案 |
| `prepdot-web/src/core/decks/tree.ts` | 卡组树 |
| `prepdot-web/src/core/review/session.ts` | 复习队列 |
| `prepdot-web/src/core/coach/*.ts` | 教练会话、进度、工具结果 |
| `prepdot-web/src/core/ai/preview.ts` | AI JSON 校验与合并 |
| `prepdot-web/src/core/quiz/quiz.ts` | 选择题生成/计分 |
| `prepdot-web/src/core/graph/plot.ts` | 掌握度坐标 |
| `prepdot-web/src/core/stats/week.ts` | 近 7 天补齐 |
| `prepdot-web/src/core/format/*.ts` | 日期、文本、Markdown |
| `prepdot-web/src/router/index.ts` | 路由与守卫 |
| `prepdot-web/src/ui/stores/auth.ts` | 登录态 |
| `prepdot-web/src/ui/stores/toast.ts` | Toast |
| `prepdot-web/src/ui/stores/coach.ts` | 教练历史会话 |
| `prepdot-web/src/ui/layout/AppShell.vue` | 侧栏/底栏 |
| `prepdot-web/src/ui/pages/*.vue` | 页面 |
| `prepdot-web/src/ui/sheets/*.vue` | 弹层 |
| `prepdot-web/src/ui/components/*.vue` | 通用组件 |
| `prepdot-web/scripts/deploy-web.sh` | 构建、rsync、切换 |
| `prepdot-web/playwright.config.ts` | E2E 配置 |
| `prepdot-web/e2e/smoke.spec.ts` | 冒烟测试 |
| `deploy/Caddyfile.prepdot` | 生产 Caddy 片段 |
| `deploy/demo/decks/*.json` | demo 卡组内容 |
| `deploy/demo/reset-demo.sh` | demo 重置 |
| `DEPLOY-WEB.md` | 部署与回滚文档 |
| `README.md` | 多端章节 |

---

## Task 1: 后端放行 CORS 预检

**Files:**
- Modify: `prepdot-backend/src/main/java/com/prepdot/config/JwtAuthFilter.java`
- Test: `prepdot-backend/src/test/java/com/prepdot/config/JwtAuthFilterTest.java`

**Interfaces:**
- Consumes: 现有 `JwtUtil`、`UserMapper`。
- Produces: `OPTIONS` 请求不经过 JWT 校验；其余请求行为不变。

- [ ] **Step 1: 写失败测试**

```java
package com.prepdot.config;

import com.prepdot.mapper.UserMapper;
import com.prepdot.util.JwtUtil;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

class JwtAuthFilterTest {

    private JwtAuthFilter filter() {
        return new JwtAuthFilter(mock(JwtUtil.class), mock(UserMapper.class));
    }

    @Test
    void optionsPreflightPassesWithoutToken() throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest("OPTIONS", "/api/plan/review");
        MockHttpServletResponse resp = new MockHttpServletResponse();
        AtomicBoolean passed = new AtomicBoolean(false);

        filter().doFilter(req, resp, (request, response) -> passed.set(true));

        assertTrue(passed.get(), "预检应放行到后续 CORS 处理");
        assertEquals(200, resp.getStatus());
    }

    @Test
    void getWithoutTokenStillReturns401() throws Exception {
        MockHttpServletRequest req = new MockHttpServletRequest("GET", "/api/decks");
        MockHttpServletResponse resp = new MockHttpServletResponse();
        AtomicBoolean passed = new AtomicBoolean(false);

        filter().doFilter(req, resp, (request, response) -> passed.set(true));

        assertFalse(passed.get());
        assertEquals(401, resp.getStatus());
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd prepdot-backend && mvn -q -Dtest=JwtAuthFilterTest test`
Expected: `optionsPreflightPassesWithoutToken` FAIL（passed=false，status=401）；第二个测试 PASS。

- [ ] **Step 3: 最小实现**

在 `JwtAuthFilter.doFilter` 读取 `uri` 之后、白名单判断之前加入：

```java
// 浏览器 CORS 预检不携带 Authorization；预检只做跨域协商，不执行业务。
if ("OPTIONS".equalsIgnoreCase(req.getMethod())) {
    chain.doFilter(req, resp);
    return;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd prepdot-backend && mvn -q -Dtest=JwtAuthFilterTest test`
Expected: 2 tests PASS。

- [ ] **Step 5: 跑全量后端测试**

Run: `cd prepdot-backend && mvn -q test`
Expected: BUILD SUCCESS。

- [ ] **Step 6: 提交**

```bash
git add prepdot-backend/src/main/java/com/prepdot/config/JwtAuthFilter.java \
        prepdot-backend/src/test/java/com/prepdot/config/JwtAuthFilterTest.java
git commit -m "fix: 放行 CORS 预检 OPTIONS 请求"
```

---

## Task 2: 工程脚手架、设计 Token、Adapter 与边界规则

**Files:**
- Create: `prepdot-web/package.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.node.json`, `eslint.config.js`, `index.html`, `src/env.d.ts`
- Create: `src/main.ts`, `src/App.vue`, `src/runtime.ts`
- Create: `src/styles/tokens.css`, `src/styles/base.css`, `src/styles/components.css`
- Create: `src/adapters/types.ts`, `src/adapters/web/{storage,http,file,notification,clipboard,clock}.ts`
- Create: `src/adapters/desktop/{README.md,storage.ts,file.ts,notification.ts}`

**Interfaces:**
- Produces: `AppAdapters`、`Runtime`、`createRuntime(adapters)`、`getRuntime()`、`setRuntime(runtime)`。
- Produces: CSS 变量 `--color-*`、`--radius-*`、`--shadow-*`。
- Produces: `.btn`、`.btn-primary`、`.card`、`.glass`、`.input`、`.sheet-*`、`.toast-*` 等通用类。

- [ ] **Step 1: 创建 package.json**

```json
{
  "name": "prepdot-web",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc --noEmit && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint .",
    "e2e": "playwright test"
  },
  "dependencies": {
    "lucide-vue-next": "1.0.0",
    "markdown-it": "15.0.3",
    "pinia": "3.0.4",
    "vue": "3.5.44",
    "vue-router": "4.6.4"
  },
  "devDependencies": {
    "@eslint/js": "9.39.5",
    "@playwright/test": "1.64.1",
    "@types/markdown-it": "14.2.0",
    "@types/node": "22.18.13",
    "@vitejs/plugin-vue": "6.0.10",
    "eslint": "9.39.5",
    "eslint-plugin-vue": "10.12.0",
    "typescript": "5.9.3",
    "typescript-eslint": "8.72.1",
    "vite": "8.3.5",
    "vitest": "5.0.5",
    "vue-eslint-parser": "10.4.1",
    "vue-tsc": "3.3.14"
  }
}
```

- [ ] **Step 2: 创建 Vite / TS 配置**

`vite.config.ts`：

```ts
import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) }
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: process.env.VITE_DEV_API_TARGET ?? 'http://127.0.0.1:8080',
        changeOrigin: true
      }
    }
  },
  build: { target: 'es2022', cssCodeSplit: true }
})
```

`tsconfig.json`：

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "types": ["vite/client"],
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] },
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts", "src/**/*.vue", "vite.config.ts", "playwright.config.ts", "e2e/**/*.ts"]
}
```

`src/env.d.ts`：

```ts
/// <reference types="vite/client" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>
  export default component
}
```

- [ ] **Step 3: 创建 ESLint 边界规则**

`eslint.config.js`：

```js
import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import tseslint from 'typescript-eslint'
import vueParser from 'vue-eslint-parser'

export default [
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, extraFileExtensions: ['.vue'] }
    }
  },
  {
    files: ['src/core/**/*.ts'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [
          { group: ['vue', 'vue-router', 'pinia'], message: 'core 必须与框架无关' },
          { group: ['@/adapters/web/*', '../adapters/web/*', '../../adapters/web/*'], message: 'core 不得依赖浏览器实现' }
        ]
      }],
      'no-restricted-globals': ['error',
        { name: 'window', message: '使用注入的 adapter' },
        { name: 'document', message: '使用注入的 adapter' },
        { name: 'localStorage', message: '使用 StoragePort' },
        { name: 'fetch', message: '使用 HttpTransport' },
        { name: 'navigator', message: '使用注入的 adapter' }
      ]
    }
  },
  {
    files: ['src/ui/**/*.{ts,vue}'],
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [{ group: ['@/adapters/web/*'], message: 'UI 只使用 runtime/store' }]
      }]
    }
  },
  { ignores: ['dist/**', 'node_modules/**', 'e2e-results/**'] }
]
```

- [ ] **Step 4: 创建设计 Token 与基础样式**

`src/styles/tokens.css`：

```css
:root {
  --color-indigo: #4f46e5;
  --color-indigo-strong: #4338ca;
  --color-purple: #7c3aed;
  --color-pink: #d946ef;
  --color-green: #10b981;
  --color-orange: #f59e0b;
  --color-red: #ef4444;
  --color-teal: #14b8a6;

  --bg: #f7f6fc;
  --surface: #ffffff;
  --surface-soft: rgba(255, 255, 255, 0.58);
  --surface-muted: #f1eff8;
  --text: #260d59;
  --text-secondary: #6b5a8e;
  --text-tertiary: #9a8cb5;
  --border: rgba(38, 13, 89, 0.1);
  --border-strong: rgba(38, 13, 89, 0.18);

  --radius-sm: 12px;
  --radius-md: 16px;
  --radius-lg: 20px;
  --radius-xl: 24px;
  --shadow-sm: 0 2px 8px rgba(38, 13, 89, 0.06);
  --shadow-md: 0 4px 16px rgba(38, 13, 89, 0.08);
  --shadow-lg: 0 12px 32px rgba(38, 13, 89, 0.14);

  --font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Segoe UI", sans-serif;
  --font-rounded: ui-rounded, "SF Pro Rounded", var(--font-sans);

  --tab-height: 49px;
  --sidebar-width: 240px;
  --content-max: 1100px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0a0a24;
    --surface: #141433;
    --surface-soft: rgba(255, 255, 255, 0.08);
    --surface-muted: rgba(255, 255, 255, 0.06);
    --text: #ffffff;
    --text-secondary: rgba(255, 255, 255, 0.66);
    --text-tertiary: rgba(255, 255, 255, 0.42);
    --border: rgba(255, 255, 255, 0.12);
    --border-strong: rgba(255, 255, 255, 0.2);
    --shadow-sm: 0 2px 8px rgba(0, 0, 0, 0.3);
    --shadow-md: 0 4px 16px rgba(0, 0, 0, 0.36);
    --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.45);
  }
}
```

`src/styles/base.css`：

```css
*, *::before, *::after { box-sizing: border-box; }
html, body, #app { height: 100%; }
body {
  margin: 0;
  font-family: var(--font-sans);
  background: var(--bg);
  color: var(--text);
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
button, input, textarea, select { font: inherit; color: inherit; }
button { cursor: pointer; }
a { color: var(--color-indigo); }
h1, h2, h3, p { margin: 0; }
ul, ol { margin: 0; padding-left: 1.2em; }
.num { font-variant-numeric: tabular-nums; }
.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
}
.page {
  width: min(100%, var(--content-max));
  margin: 0 auto;
  padding: 24px 16px calc(var(--tab-height) + env(safe-area-inset-bottom) + 24px);
}
@media (min-width: 900px) {
  .page { padding: 32px 32px 48px; }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

`src/styles/components.css` 至少包含以下完整定义：

```css
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
}
.glass {
  background: var(--surface-soft);
  border: 1px solid rgba(255, 255, 255, 0.7);
  border-radius: var(--radius-lg);
  backdrop-filter: blur(16px);
}
.btn {
  min-height: 44px;
  padding: 10px 18px;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
  color: var(--text);
  font-weight: 600;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  transition: transform 0.15s ease, opacity 0.15s ease;
}
.btn:active { transform: scale(0.98); }
.btn:disabled { opacity: 0.45; cursor: not-allowed; }
.btn-primary {
  background: linear-gradient(135deg, var(--color-indigo), var(--color-purple));
  color: #fff;
  box-shadow: 0 8px 20px rgba(79, 70, 229, 0.35);
}
.btn-ghost { background: transparent; border-color: var(--border-strong); }
.btn-danger { background: var(--color-red); color: #fff; }
.btn-sm { min-height: 36px; padding: 6px 12px; font-size: 14px; }
.input, .textarea, .select {
  width: 100%;
  min-height: 44px;
  padding: 10px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--surface-muted);
  color: var(--text);
  outline: none;
}
.input:focus, .textarea:focus, .select:focus {
  border-color: var(--color-indigo);
  box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.16);
}
.textarea { min-height: 120px; resize: vertical; }
.label { display: block; margin-bottom: 6px; font-size: 14px; color: var(--text-secondary); }
.muted { color: var(--text-secondary); }
.tiny { font-size: 12px; color: var(--text-tertiary); }
.row { display: flex; align-items: center; gap: 12px; }
.row-between { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.stack { display: flex; flex-direction: column; gap: 12px; }
.stack-lg { display: flex; flex-direction: column; gap: 20px; }
.pill {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 4px 10px; border-radius: 999px;
  background: var(--surface-muted); font-size: 13px;
}
.badge {
  display: inline-flex; align-items: center;
  padding: 2px 8px; border-radius: 999px;
  font-size: 12px; font-weight: 600;
}
.sheet-backdrop {
  position: fixed; inset: 0; z-index: 50;
  background: rgba(10, 10, 36, 0.45);
  display: flex; align-items: flex-end; justify-content: center;
  padding: 0;
}
.sheet-panel {
  width: 100%; max-height: 90vh; overflow: auto;
  background: var(--surface);
  border-radius: var(--radius-xl) var(--radius-xl) 0 0;
  padding: 20px 20px calc(20px + env(safe-area-inset-bottom));
  box-shadow: var(--shadow-lg);
}
@media (min-width: 640px) {
  .sheet-backdrop { align-items: center; padding: 24px; }
  .sheet-panel { max-width: 560px; border-radius: var(--radius-xl); }
}
.toast-host {
  position: fixed; left: 50%; bottom: calc(var(--tab-height) + env(safe-area-inset-bottom) + 20px);
  transform: translateX(-50%); z-index: 80; pointer-events: none;
}
.toast {
  padding: 10px 18px; border-radius: 999px;
  background: rgba(20, 20, 51, 0.92); color: #fff;
  font-size: 14px; box-shadow: var(--shadow-lg);
}
```

- [ ] **Step 5: 定义 Adapter 接口与 Web 实现**

`src/adapters/types.ts`：

```ts
export interface ApiRequest {
  method: 'GET' | 'POST' | 'PUT' | 'DELETE'
  path: string
  body?: unknown
  headers?: Record<string, string>
  signal?: AbortSignal
}

export interface RawResponse<T> {
  status: number
  body: { code: number; message: string; data: T | null }
}

export interface MultipartField {
  name: string
  value: string
}

export interface MultipartFile {
  field: string
  name: string
  mime: string
  bytes: ArrayBuffer
}

export interface MultipartRequest {
  path: string
  fields: MultipartField[]
  file: MultipartFile
  headers?: Record<string, string>
  signal?: AbortSignal
}

export interface HttpTransport {
  json<T>(req: ApiRequest): Promise<RawResponse<T>>
  multipart<T>(req: MultipartRequest): Promise<RawResponse<T>>
  streamText(req: ApiRequest): AsyncIterable<string>
}

export interface StoragePort {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  remove(key: string): Promise<void>
}

export interface PickedFile {
  name: string
  mime: string
  size: number
  bytes(): Promise<ArrayBuffer>
}

export interface FilePort {
  pick(options: { multiple: boolean; accept: string[] }): Promise<PickedFile[]>
}

export interface NotificationPort {
  permission(): Promise<'granted' | 'denied' | 'default'>
  requestPermission(): Promise<'granted' | 'denied' | 'default'>
  scheduleDaily(time: string, target: number): Promise<void>
  cancelDaily(): Promise<void>
}

export interface ClipboardPort {
  readText(): Promise<string>
}

export interface Clock {
  now(): number
}

export interface AppAdapters {
  storage: StoragePort
  http: HttpTransport
  file: FilePort
  notification: NotificationPort
  clipboard: ClipboardPort
  clock: Clock
}
```

`src/adapters/web/storage.ts`：直接包装 `localStorage` 的 `getItem/setItem/removeItem`，Promise 返回。

`src/adapters/web/http.ts`：

```ts
import type { ApiRequest, HttpTransport, MultipartRequest, RawResponse } from '@/adapters/types'

const BASE = import.meta.env.VITE_API_BASE_URL ?? '/api'

async function parse<T>(res: Response): Promise<RawResponse<T>> {
  const text = await res.text()
  try {
    return { status: res.status, body: JSON.parse(text) }
  } catch {
    return {
      status: res.status,
      body: { code: res.status, message: text || `请求失败（${res.status}）`, data: null }
    }
  }
}

export function createHttpTransport(): HttpTransport {
  return {
    async json<T>(req: ApiRequest) {
      return parse<T>(await fetch(BASE + req.path, {
        method: req.method,
        headers: { ...(req.body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...req.headers },
        body: req.body !== undefined ? JSON.stringify(req.body) : undefined,
        signal: req.signal
      }))
    },
    async multipart<T>(req: MultipartRequest) {
      const form = new FormData()
      for (const field of req.fields) form.append(field.name, field.value)
      form.append(req.file.field, new Blob([req.file.bytes], { type: req.file.mime }), req.file.name)
      return parse<T>(await fetch(BASE + req.path, {
        method: 'POST',
        headers: req.headers,
        body: form,
        signal: req.signal
      }))
    },
    async *streamText(req: ApiRequest) {
      const res = await fetch(BASE + req.path, {
        method: req.method,
        headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', ...req.headers },
        body: req.body !== undefined ? JSON.stringify(req.body) : undefined,
        signal: req.signal
      })
      if (!res.ok || !res.body) throw new Error(`流式请求失败（${res.status}）`)
      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          yield decoder.decode(value, { stream: true })
        }
      } finally {
        reader.releaseLock()
      }
    }
  }
}
```

`src/adapters/web/file.ts`：创建隐藏 `<input type=file multiple accept>`，监听 `change`，把 `File` 包装成 `PickedFile`；选择取消时 resolve `[]`。

`src/adapters/web/notification.ts`：保存一个模块级 `timer`；`scheduleDaily('09:00', target)` 计算下一个该时间点，`setTimeout` 后调用 `new Notification(...)`，然后递归安排次日；`cancelDaily` 清除定时器。`permission` 返回 `Notification.permission`；不支持时返回 `denied`。

`src/adapters/web/clipboard.ts`：`navigator.clipboard.readText()`，不支持时抛 `Error('当前浏览器不支持读取剪贴板')`。

`src/adapters/web/clock.ts`：`{ now: () => Date.now() }`。

`src/adapters/desktop/README.md`：说明 Phase 2 把 `storage` 映射 SQLite、`file` 映射系统对话框、`notification` 映射系统通知；空壳实现抛 `new Error('desktop adapter 将在 Phase 2 实现')`。

- [ ] **Step 6: 创建 runtime 与最小 App**

`src/runtime.ts`：

```ts
import type { AppAdapters } from '@/adapters/types'
import { AuthSession } from '@/core/session/session'
import { ApiClient } from '@/core/api/client'

export interface Runtime {
  adapters: AppAdapters
  session: AuthSession
  api: ApiClient
}

let runtime: Runtime | null = null

export function setRuntime(value: Runtime): void {
  runtime = value
}

export function getRuntime(): Runtime {
  if (!runtime) throw new Error('runtime 尚未初始化')
  return runtime
}

export function createRuntime(adapters: AppAdapters): Runtime {
  const session = new AuthSession(adapters.storage, adapters.http, adapters.clock)
  return { adapters, session, api: new ApiClient(adapters.http, session) }
}
```

`src/main.ts`：

```ts
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { createWebAdapters } from './adapters/web'
import { createRuntime, setRuntime } from './runtime'
import './styles/tokens.css'
import './styles/base.css'
import './styles/components.css'

setRuntime(createRuntime(createWebAdapters()))
createApp(App).use(createPinia()).mount('#app')
```

`src/adapters/web/index.ts`：

```ts
import type { AppAdapters } from '@/adapters/types'
import { createStorage } from './storage'
import { createHttpTransport } from './http'
import { createFilePort } from './file'
import { createNotificationPort } from './notification'
import { createClipboardPort } from './clipboard'
import { createClock } from './clock'

export function createWebAdapters(): AppAdapters {
  return {
    storage: createStorage(),
    http: createHttpTransport(),
    file: createFilePort(),
    notification: createNotificationPort(),
    clipboard: createClipboardPort(),
    clock: createClock()
  }
}
```

`src/App.vue` 先放最小占位结构，Task 4 替换：

```vue
<template>
  <main class="page">
    <h1>PrepDot</h1>
    <p class="muted">Web 端正在构建中</p>
  </main>
</template>
```

`index.html`：

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <meta name="theme-color" content="#f7f6fc" />
    <title>序岛 PrepDot</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.ts"></script>
  </body>
</html>
```

- [ ] **Step 7: 安装依赖并验证**

Run:
```bash
cd prepdot-web && pnpm install && pnpm build && pnpm lint
```
Expected: 构建与 lint 成功。若 `AuthSession`/`ApiClient` 尚未实现导致类型错误，允许本 Task 先创建空类（Task 3 填充），但必须保留导出签名：

```ts
export class AuthSession { constructor(..._args: unknown[]) {} }
export class ApiClient { constructor(..._args: unknown[]) {} }
```

- [ ] **Step 8: 提交**

```bash
git add prepdot-web
git commit -m "feat(web): 搭建 Vue 工程、设计 Token 与 adapter 边界"
```

---

## Task 3: Core API、会话、SSE、格式化与单测

**Files:**
- Create: `src/core/api/types.ts`, `src/core/api/client.ts`, `src/core/api/endpoints.ts`, `src/core/api/sse.ts`
- Create: `src/core/auth/token.ts`, `src/core/session/session.ts`, `src/core/errors.ts`
- Create: `src/core/format/{date,text,markdown}.ts`
- Test: `src/core/**/__tests__/*.test.ts`
- Modify: `src/runtime.ts`（接入真实类）

**Interfaces:**
- Produces: `AuthUser`、`Deck`、`Flashcard`、`TodayPlan`、`ReviewSummary`、`UserStats`、`AgentRun`、`CommunityPack`、`CommunityPackDetail`、`AiPreviewDeck`。
- Produces: `ApiError`、`ApiClient.request<T>(req)`、`ApiClient.upload<T>(req)`、`ApiClient.stream(req)`。
- Produces: `AuthSession` 实现 `TokenProvider`：`login`、`register`、`restore`、`logout`、`getToken`、`maybeRefresh`、`onUnauthorized`。
- Produces: `createSseParser(onEvent)`、`formatServerDate`、`formatRelativeDay`、`cardDisplayText`、`renderMarkdown`、`renderInlineMarkdown`。

- [ ] **Step 1: 写 token 与 SSE 的失败测试**

`src/core/auth/__tests__/token.test.ts`：

```ts
import { describe, expect, it } from 'vitest'
import { decodeJwtExp, expiresAt, shouldRefresh } from '../token'

function jwt(payload: object): string {
  const enc = (v: object) => btoa(JSON.stringify(v)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  return `${enc({ alg: 'HS256' })}.${enc(payload)}.sig`
}

describe('jwt token helpers', () => {
  it('reads exp seconds', () => {
    expect(decodeJwtExp(jwt({ exp: 1700000000 }))).toBe(1700000000)
  })
  it('treats malformed token as expired', () => {
    expect(expiresAt('nope', 0)).toBe(0)
  })
  it('refreshes with less than 3.5 days left', () => {
    const now = 1_700_000_000_000
    expect(shouldRefresh(jwt({ exp: now / 1000 + 3 * 86400 }), now)).toBe(true)
    expect(shouldRefresh(jwt({ exp: now / 1000 + 5 * 86400 }), now)).toBe(false)
  })
})
```

`src/core/api/__tests__/sse.test.ts`：

```ts
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/auth/__tests__/token.test.ts src/core/api/__tests__/sse.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现 token 与 SSE**

`src/core/auth/token.ts`：

```ts
function base64UrlDecode(input: string): string {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (input.length % 4)) % 4)
  return atob(padded)
}

export function decodeJwtExp(token: string): number | null {
  const parts = token.split('.')
  if (parts.length < 2) return null
  try {
    const payload = JSON.parse(base64UrlDecode(parts[1])) as { exp?: unknown }
    return typeof payload.exp === 'number' ? payload.exp : null
  } catch {
    return null
  }
}

export function expiresAt(token: string, nowMs: number): number {
  const exp = decodeJwtExp(token)
  return exp === null ? 0 : exp * 1000
}

export function shouldRefresh(token: string, nowMs: number): boolean {
  const expiry = expiresAt(token, nowMs)
  return expiry === 0 || expiry - nowMs < 3.5 * 24 * 3600 * 1000
}
```

`src/core/api/sse.ts`：

```ts
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
```

- [ ] **Step 4: 写 ApiClient 与格式化测试**

`src/core/api/__tests__/client.test.ts`：用假 transport 验证成功解包、业务错误、401 触发 `onUnauthorized`。

`src/core/format/__tests__/date.test.ts`：固定 `now = Date.UTC(2026, 9, 31, 4, 0)`，验证 `formatServerDate('2026-10-31T12:30:00')` 返回 `10月31日 12:30`；`formatRelativeDay('2026-11-02T12:00:00', now)` 返回 `2 天后`。

`src/core/format/__tests__/text.test.ts`：验证 `cardDisplayText('A；②B；③C')` 在编号前换行；`normalizeCardType('选择题') === 'choice'`。

- [ ] **Step 5: 实现 types、errors、client、format**

`src/core/api/types.ts` 至少定义：

```ts
export interface AuthUser {
  token: string
  userId: number
  username: string
  nickname: string
  avatarColor: string
  studyTarget: number
}

export interface Deck {
  id: number
  parentId: number | null
  depth: number
  title: string
  type: string
  category: string
  description: string | null
  cardCount: number
  reviewedCount: number
  dueCount: number
  avgMemoryScore: number
  createdAt: string
}

export interface Flashcard {
  id: number
  deckId: number
  question: string
  answer: string
  cardType: 'qa' | 'choice' | 'blank' | string
  options: string | null
  category: string
  memoryScore: number
  difficulty: number | null
  stability: number | null
  note: string | null
  reviewCount: number
  lastReviewedAt: string | null
  nextReviewAt: string | null
  createdAt: string
}

export interface TodayPlan {
  planId: number
  planDate: string
  totalCount: number
  completedCount: number
  estimatedMinutes: number
  cards: Flashcard[]
  deckProgress: { deckId: number; deckTitle: string; totalCount: number; completedCount: number }[]
}

export interface ReviewSummary {
  totalCount: number
  decks: { deckId: number; deckTitle: string; count: number }[]
}

export interface AgentStep {
  stepNo: number
  stepType: 'MODEL' | 'TOOL' | string
  modelContent: string | null
  toolName: string | null
  toolArguments: string | null
  toolResult: string | null
  durationMs: number | null
}

export interface AgentRun {
  runId: number
  status: string
  output: string | null
  stepCount: number
  steps: AgentStep[]
}

export interface UserStats {
  streakDays: number
  todayReviewed: number
  totalReviewed: number
  totalDecks: number
  totalCards: number
  avgMemoryScore: number
  weeklyData: { day: string; count: number }[]
  memoryDistribution: { low: number; mid: number; high: number }
}

export interface CommunityPack {
  id: number
  title: string
  category: string
  description: string
  cardCount: number
  tags: string[]
}

export interface CommunityPackDetail extends CommunityPack {
  cards: { question: string; answer: string }[]
}

export interface AiPreviewCard { question: string; answer: string }
export interface AiPreviewChild { title: string; cards: AiPreviewCard[] }
export interface AiPreviewDeck {
  title: string
  category: string
  description: string
  children: AiPreviewChild[]
}
```

`src/core/errors.ts`：

```ts
export class ApiError extends Error {
  constructor(public readonly code: number, message: string) {
    super(message)
    this.name = 'ApiError'
  }
}

export function friendlyError(error: unknown): string {
  if (error instanceof ApiError) return error.message
  if (error instanceof TypeError && error.message.includes('fetch')) return '网络连接失败，请检查网络后重试。'
  if (error instanceof DOMException && error.name === 'AbortError') return '操作已取消。'
  if (error instanceof Error && error.message) return error.message
  return '服务暂时不可用，请稍后重试。'
}
```

`src/core/api/client.ts`：

```ts
import type { ApiRequest, HttpTransport, MultipartRequest } from '@/adapters/types'
import { ApiError } from '@/core/errors'

export interface TokenProvider {
  getToken(): Promise<string | null>
  onUnauthorized(): Promise<void>
  maybeRefresh(): Promise<void>
}

export class ApiClient {
  constructor(private readonly http: HttpTransport, private readonly tokens: TokenProvider) {}

  async request<T>(req: ApiRequest): Promise<T> {
    const token = await this.tokens.getToken()
    const response = await this.http.json<T>({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
    if (response.status === 401) {
      await this.tokens.onUnauthorized()
      throw new ApiError(401, '登录已失效，请重新登录')
    }
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message || '请求失败')
    void this.tokens.maybeRefresh()
    return response.body.data as T
  }

  async upload<T>(req: MultipartRequest): Promise<T> {
    const token = await this.tokens.getToken()
    const response = await this.http.multipart<T>({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
    if (response.status === 401) {
      await this.tokens.onUnauthorized()
      throw new ApiError(401, '登录已失效，请重新登录')
    }
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message || '请求失败')
    return response.body.data as T
  }

  async *stream(req: ApiRequest): AsyncIterable<string> {
    const token = await this.tokens.getToken()
    yield* this.http.streamText({
      ...req,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...req.headers }
    })
  }
}
```

`src/core/format/date.ts`：

```ts
const SERVER_TIME_ZONE = 'Asia/Shanghai'

function partsOf(value: string): { y: number; mo: number; d: number; h: number; mi: number; s: number } | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/.exec(value)
  if (!match) return null
  return {
    y: Number(match[1]), mo: Number(match[2]), d: Number(match[3]),
    h: Number(match[4]), mi: Number(match[5]), s: Number(match[6] ?? 0)
  }
}

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
```

`src/core/format/text.ts`：

```ts
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
```

`src/core/format/markdown.ts`：

```ts
import MarkdownIt from 'markdown-it'

const md = new MarkdownIt({ html: false, linkify: true, breaks: true })

export function renderMarkdown(source: string): string {
  return md.render(source)
}

export function renderInlineMarkdown(source: string): string {
  return md.renderInline(source)
}
```

- [ ] **Step 6: 实现 AuthSession**

`src/core/session/session.ts`：

```ts
import type { Clock, HttpTransport, StoragePort } from '@/adapters/types'
import type { AuthUser } from '@/core/api/types'
import { ApiError } from '@/core/errors'
import { ApiClient, type TokenProvider } from '@/core/api/client'
import { expiresAt, shouldRefresh } from '@/core/auth/token'

const TOKEN_KEY = 'prepdot.token'
const USER_KEY = 'prepdot.user'

export class AuthSession implements TokenProvider {
  private token: string | null = null
  private user: AuthUser | null = null
  private refreshing: Promise<void> | null = null

  constructor(
    private readonly storage: StoragePort,
    private readonly http: HttpTransport,
    private readonly clock: Clock
  ) {}

  get currentUser(): AuthUser | null { return this.user }
  get isAuthenticated(): boolean { return this.token !== null }

  async restore(): Promise<AuthUser | null> {
    this.token = await this.storage.get(TOKEN_KEY)
    const raw = await this.storage.get(USER_KEY)
    this.user = raw ? JSON.parse(raw) as AuthUser : null
    const token = this.token
    if (!token) { this.user = null; return null }
    const now = this.clock.now()
    if (shouldRefresh(token, now)) {
      try {
        await this.refresh()
      } catch (error) {
        // 只有明确的认证失败或 token 已过期才登出；离线/5xx 保留缓存会话。
        if ((error instanceof ApiError && error.code === 401) || expiresAt(token, now) <= now) {
          await this.logout()
          return null
        }
      }
    }
    return this.user
  }

  async login(username: string, password: string): Promise<AuthUser> {
    return this.authenticate('/auth/login', { username, password })
  }

  async register(username: string, password: string, nickname: string): Promise<AuthUser> {
    return this.authenticate('/auth/register', { username, password, nickname })
  }

  private async authenticate(path: string, body: Record<string, string>): Promise<AuthUser> {
    const response = await this.http.json<AuthUser>({
      method: 'POST', path, body, headers: { 'Content-Type': 'application/json' }
    })
    if (response.body.code !== 200) throw new ApiError(response.body.code, response.body.message)
    const user = response.body.data as AuthUser
    await this.persist(user)
    return user
  }

  private async persist(user: AuthUser): Promise<void> {
    this.token = user.token
    this.user = user
    await this.storage.set(TOKEN_KEY, user.token)
    await this.storage.set(USER_KEY, JSON.stringify(user))
  }

  async getToken(): Promise<string | null> { return this.token }

  async maybeRefresh(): Promise<void> {
    if (!this.token || !shouldRefresh(this.token, this.clock.now())) return
    try { await this.refresh() } catch { /* 下一次 401 会统一登出 */ }
  }

  async refresh(): Promise<void> {
    if (!this.token) return
    if (this.refreshing) return this.refreshing
    this.refreshing = (async () => {
      const response = await this.http.json<AuthUser>({
        method: 'POST', path: '/auth/refresh',
        headers: { Authorization: `Bearer ${this.token}` }
      })
      if (response.body.code !== 200 || !response.body.data) throw new ApiError(response.body.code, response.body.message)
      await this.persist(response.body.data)
    })().finally(() => { this.refreshing = null })
    return this.refreshing
  }

  async onUnauthorized(): Promise<void> { await this.logout() }

  async logout(): Promise<void> {
    this.token = null
    this.user = null
    await this.storage.remove(TOKEN_KEY)
    await this.storage.remove(USER_KEY)
  }
}
```

- [ ] **Step 7: 实现 endpoints**

`src/core/api/endpoints.ts` 按以下签名实现（全部调用 `ApiClient`）：

```ts
export function createApi(client: ApiClient) {
  return {
    decks: () => client.request<Deck[]>({ method: 'GET', path: '/decks' }),
    createDeck: (body: DeckPayload) => client.request<Deck>({ method: 'POST', path: '/decks', body }),
    updateDeck: (id: number, body: DeckPayload) => client.request<Deck>({ method: 'PUT', path: `/decks/${id}`, body }),
    moveDeck: (id: number, parentId: number | null) => client.request<Deck>({ method: 'PUT', path: `/decks/${id}/parent`, body: { parentId } }),
    deleteDeck: (id: number) => client.request<void>({ method: 'DELETE', path: `/decks/${id}` }),
    cards: (deckId: number, deep = false) => client.request<Flashcard[]>({ method: 'GET', path: `/decks/${deckId}/cards${deep ? '?deep=true' : ''}` }),
    createCard: (body: CardPayload) => client.request<Flashcard>({ method: 'POST', path: '/cards', body }),
    updateCard: (id: number, body: CardPayload) => client.request<Flashcard>({ method: 'PUT', path: `/cards/${id}`, body }),
    deleteCard: (id: number) => client.request<void>({ method: 'DELETE', path: `/cards/${id}` }),
    deleteCards: (ids: number[]) => client.request<void>({ method: 'DELETE', path: `/cards/batch?${ids.map(id => `ids=${id}`).join('&')}` }),
    updateCardNote: (id: number, note: string) => client.request<Flashcard>({ method: 'PUT', path: `/cards/${id}/note`, body: { note } }),
    todayPlan: () => client.request<TodayPlan>({ method: 'GET', path: '/plan/today' }),
    submitReview: (cardId: number, rating: string) => client.request<Flashcard>({ method: 'POST', path: '/plan/review', body: { cardId, rating } }),
    todaySummary: () => client.request<ReviewSummary>({ method: 'GET', path: '/plan/summary' }),
    stats: () => client.request<UserStats>({ method: 'GET', path: '/auth/stats' }),
    deleteAccount: (password: string) => client.request<void>({ method: 'DELETE', path: '/auth/account', body: { password } }),
    coach: (message: string, mode = 'LEARNING_COACH') => client.request<AgentRun>({ method: 'POST', path: '/agent/coach', body: { message, mode } }),
    coachStream: (message: string, mode = 'LEARNING_COACH') => client.stream({ method: 'POST', path: '/agent/coach/stream', body: { message, mode } }),
    generate: (req: { file: PickedFile; deckTitle: string; customKey?: string; cardCount: number; detailHint: string; signal?: AbortSignal }) =>
      client.upload<string>({
        path: '/ai/generate',
        fields: [
          { name: 'deckTitle', value: req.deckTitle },
          { name: 'customKey', value: req.customKey ?? '' },
          { name: 'cardCount', value: String(req.cardCount) },
          { name: 'detailHint', value: req.detailHint }
        ],
        file: { field: 'file', name: req.file.name, mime: req.file.mime, bytes: await req.file.bytes() },
        signal: req.signal
      }),
    importAiDeck: (rawJson: string) => client.request<Deck>({ method: 'POST', path: '/ai/import', body: rawJson, headers: { 'Content-Type': 'application/json' } }),
    communityPacks: () => client.request<CommunityPack[]>({ method: 'GET', path: '/community/packs' }),
    communityPack: (id: number) => client.request<CommunityPackDetail>({ method: 'GET', path: `/community/packs/${id}` }),
    importCommunityPack: (id: number) => client.request<Deck>({ method: 'POST', path: `/community/packs/${id}/import` })
  }
}
```

注意 `generate` 内 `await req.file.bytes()` 需要方法为 `async`；实现时写成 `async generate(...)`。

- [ ] **Step 8: 接入 runtime**

修改 `src/runtime.ts`，加入 `api`（已是 `ApiClient`）与 `endpoints`：

```ts
import { createApi } from '@/core/api/endpoints'
export interface Runtime { adapters: AppAdapters; session: AuthSession; api: ApiClient; endpoints: ReturnType<typeof createApi> }
export function createRuntime(adapters: AppAdapters): Runtime {
  const session = new AuthSession(adapters.storage, adapters.http, adapters.clock)
  const api = new ApiClient(adapters.http, session)
  return { adapters, session, api, endpoints: createApi(api) }
}
```

- [ ] **Step 9: 运行全部测试与构建**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。

- [ ] **Step 10: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 实现核心 API 客户端、会话续期与纯 TS 工具"
```

---

## Task 4: 路由、登录态、App Shell 与登录页

**Files:**
- Create: `src/router/index.ts`, `src/ui/stores/auth.ts`, `src/ui/stores/toast.ts`, `src/ui/layout/AppShell.vue`, `src/ui/pages/LoginPage.vue`, `src/ui/components/{AuroraBackground,ToastHost,LoadingState,ErrorState,EmptyState}.vue`
- Modify: `src/main.ts`, `src/App.vue`

**Interfaces:**
- Consumes: `getRuntime()`、`ApiError`、`friendlyError`。
- Produces: `useAuthStore()`：`user`、`ready`、`isAuthenticated`、`restore()`、`login()`、`register()`、`logout()`。
- Produces: 路由名 `login`、`review`、`decks`、`deck-detail`、`coach`、`profile`、`reminder`、`delete-account`、`graph`、`quiz`、`generate`、`community`。

- [ ] **Step 1: 写路由守卫测试**

`src/router/__tests__/guard.test.ts`：

```ts
import { describe, expect, it } from 'vitest'
import { resolveRedirect } from '../guard'

describe('route guard', () => {
  it('sends unauthenticated users to login', () => {
    expect(resolveRedirect(false, 'review')).toBe('login')
  })
  it('sends authenticated users away from login', () => {
    expect(resolveRedirect(true, 'login')).toBe('review')
  })
  it('keeps authenticated users on protected routes', () => {
    expect(resolveRedirect(true, 'decks')).toBeNull()
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/router/__tests__/guard.test.ts`
Expected: FAIL（模块不存在）。

- [ ] **Step 3: 实现路由与守卫**

`src/router/guard.ts`：

```ts
export function resolveRedirect(authenticated: boolean, routeName: string): string | null {
  if (!authenticated && routeName !== 'login') return 'login'
  if (authenticated && routeName === 'login') return 'review'
  return null
}
```

`src/router/index.ts` 使用 `createRouter` + `createWebHistory`，路由表：

```ts
const routes = [
  { path: '/login', name: 'login', component: () => import('@/ui/pages/LoginPage.vue') },
  { path: '/', redirect: { name: 'review' } },
  { path: '/review', name: 'review', component: () => import('@/ui/pages/ReviewPage.vue') },
  { path: '/decks/:id?', name: 'decks', component: () => import('@/ui/pages/DecksPage.vue') },
  { path: '/decks/:id/quiz', name: 'quiz', component: () => import('@/ui/pages/QuizPage.vue') },
  { path: '/coach', name: 'coach', component: () => import('@/ui/pages/CoachPage.vue') },
  { path: '/profile', name: 'profile', component: () => import('@/ui/pages/ProfilePage.vue') },
  { path: '/profile/reminder', name: 'reminder', component: () => import('@/ui/pages/ReminderPage.vue') },
  { path: '/profile/delete', name: 'delete-account', component: () => import('@/ui/pages/DeleteAccountPage.vue') },
  { path: '/graph', name: 'graph', component: () => import('@/ui/pages/MasteryMapPage.vue') },
  { path: '/generate', name: 'generate', component: () => import('@/ui/pages/AiGeneratePage.vue') },
  { path: '/community', name: 'community', component: () => import('@/ui/pages/CommunityPage.vue') },
  { path: '/:pathMatch(.*)*', redirect: { name: 'review' } }
]
```

守卫：

```ts
router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.restore()
  const redirect = resolveRedirect(auth.isAuthenticated, String(to.name))
  return redirect ? { name: redirect } : true
})
```

Task 4 尚未实现的页面用最小同构占位组件，Task 5+ 替换；占位必须可构建且显示标题。

- [ ] **Step 4: 实现 auth / toast store**

`src/ui/stores/auth.ts`：

```ts
import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { AuthUser } from '@/core/api/types'
import { getRuntime } from '@/runtime'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const ready = ref(false)
  const isAuthenticated = computed(() => user.value !== null)
  let restored = false

  async function restore(): Promise<void> {
    if (restored) { ready.value = true; return }
    restored = true
    try {
      user.value = await getRuntime().session.restore()
    } catch {
      user.value = null
    } finally {
      ready.value = true
    }
  }

  async function login(username: string, password: string): Promise<void> {
    user.value = await getRuntime().session.login(username, password)
  }

  async function register(username: string, password: string, nickname: string): Promise<void> {
    user.value = await getRuntime().session.register(username, password, nickname)
  }

  async function logout(): Promise<void> {
    await getRuntime().session.logout()
    user.value = null
    restored = true
  }

  return { user, ready, isAuthenticated, restore, login, register, logout }
})
```

`toast.ts`：`message`、`visible`、`show(msg)`，`setTimeout` 2.5 秒清空。

- [ ] **Step 5: 实现 AppShell**

- 桌面 ≥900px：左侧 `aside.sidebar`（品牌、4 个导航、底部用户）；主内容 `<slot>`。
- 移动：顶部页头（标题 + 可选操作）+ 内容 + 固定底部 `.tabbar` 4 项。
- 导航项：`Brain` 今日复习、`Network` 知识树、`Sparkles` 学习教练、`UserRound` 我的。
- 当前项用 `route.name` 判断；`decks`/`quiz`/`graph` 都视为知识树选中。
- 底部 `env(safe-area-inset-bottom)`。
- 用户区显示头像首字与昵称，点击去 `/profile`。

关键 CSS（写入组件 scoped）：

```css
.shell { min-height: 100%; background: var(--bg); }
.sidebar { display: none; }
.tabbar {
  position: fixed; left: 0; right: 0; bottom: 0; z-index: 30;
  height: calc(var(--tab-height) + env(safe-area-inset-bottom));
  padding-bottom: env(safe-area-inset-bottom);
  display: grid; grid-template-columns: repeat(4, 1fr);
  background: color-mix(in srgb, var(--surface) 92%, transparent);
  border-top: 1px solid var(--border);
  backdrop-filter: blur(18px);
}
.tabbar a {
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 2px; font-size: 10px; color: var(--text-secondary); text-decoration: none;
}
.tabbar a.active { color: var(--color-indigo); }
@media (min-width: 900px) {
  .shell { display: grid; grid-template-columns: var(--sidebar-width) 1fr; }
  .sidebar { display: flex; flex-direction: column; position: sticky; top: 0; height: 100vh;
    border-right: 1px solid var(--border); background: var(--surface); padding: 20px 14px; }
  .tabbar { display: none; }
  .main { min-width: 0; }
}
```

- [ ] **Step 6: 实现登录页**

- 全屏渐变极光背景。
- 品牌：`Brain` 图标 64px，indigo→purple 渐变文字/图标，标题 PrepDot，副标题“你的 AI 面试记忆助手”。
- 表单：昵称（注册时）、用户名、密码；错误条；主按钮；切换链接。
- `canSubmit = username.trim() && password.length >= 6`。
- 演示按钮：填入 `demo` / `PrepDot2026` 并调用登录。
- 登录成功 `router.push({ name: 'review' })`。
- 表单使用 `.input`、`.btn-primary`，移动端宽度 100%，桌面最大 420px。

- [ ] **Step 7: 更新 App.vue 与 main.ts**

`App.vue`：

```vue
<template>
  <RouterView v-if="route.name === 'login'" />
  <AppShell v-else-if="auth.isAuthenticated">
    <RouterView />
  </AppShell>
  <div v-else class="page"><LoadingState text="正在恢复登录状态…" /></div>
  <ToastHost />
</template>
```

`main.ts` 安装 router：

```ts
createApp(App).use(createPinia()).use(router).mount('#app')
```

- [ ] **Step 8: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。若本地无后端，登录页仍可渲染；登录会显示网络错误。

- [ ] **Step 9: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 加入路由守卫、登录页与响应式 App Shell"
```

---

## Task 5: 今日复习（概览、翻转卡片、评分、完成页、问 AI、笔记）

**Files:**
- Create: `src/core/review/session.ts`, `src/core/review/__tests__/session.test.ts`
- Create: `src/ui/pages/ReviewPage.vue`
- Create: `src/ui/components/{ProgressRing,ProgressBar,AuroraBackground}.vue`
- Create: `src/ui/sheets/{CardFormSheet,CardNoteSheet,CoachChatSheet}.vue`
- Create: `src/ui/sheets/__tests__`（可选，无）

**Interfaces:**
- Produces: `advanceReview(index, total)`、`ratingOptions`、`isReviewComplete(plan)`。
- Produces: `CardFormSheet` props `{ deckId: number; card?: Flashcard }`，emit `saved(card)`。
- Produces: `CardNoteSheet` props `{ card: Flashcard }`，emit `saved(card)`。
- Produces: `CoachChatSheet` props `{ card: Flashcard }`。

- [ ] **Step 1: 写复习队列测试**

```ts
import { describe, expect, it } from 'vitest'
import { advanceReview, ratingOptions } from '../session'

describe('review session', () => {
  it('advances until the last card', () => {
    expect(advanceReview(0, 3)).toEqual({ index: 1, done: false })
    expect(advanceReview(2, 3)).toEqual({ index: 2, done: true })
  })
  it('exposes four ratings in iOS order', () => {
    expect(ratingOptions.map(r => r.rating)).toEqual(['again', 'hard', 'good', 'easy'])
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/review/__tests__/session.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现复习核心**

```ts
export const ratingOptions = [
  { rating: 'again', label: 'Again', sub: '重新学', color: 'red' },
  { rating: 'hard', label: 'Hard', sub: '明天', color: 'orange' },
  { rating: 'good', label: 'Good', sub: '2–4 天', color: 'green' },
  { rating: 'easy', label: 'Easy', sub: '5–10 天', color: 'indigo' }
] as const

export function advanceReview(index: number, total: number): { index: number; done: boolean } {
  const next = index + 1
  return next >= total ? { index, done: true } : { index: next, done: false }
}
```

- [ ] **Step 4: 实现概览页**

ReviewPage 状态：

```ts
const plan = ref<TodayPlan | null>(null)
const loading = ref(true)
const error = ref('')
const mode = ref<'overview' | 'session' | 'done'>('overview')
const index = ref(0)
const summary = ref<ReviewSummary | null>(null)

async function loadPlan() {
  loading.value = true; error.value = ''
  try { plan.value = await getRuntime().endpoints.todayPlan() }
  catch (e) { error.value = friendlyError(e) }
  finally { loading.value = false }
}
```

概览模板要求：
- `AuroraBackground` 背景。
- 日期：`new Intl.DateTimeFormat('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }).format(new Date())`。
- `ProgressRing` props `{ value: pending, max: plan.totalCount, percent }`，190px，中心大号数字与“张待复习”。
- 两个统计胶囊：今日进度、预计时间。
- 卡组进度列表：每项标题、剩余/已完成、`completed/total`、`ProgressBar`。
- 主按钮：`plan.completedCount > 0 ? '继续复习' : '开始复习'`。
- `plan.cards.length === 0` 时显示 EmptyState，“今天没有到期卡片”，按钮去知识树。

- [ ] **Step 5: 实现复习会话**

- 顶部：`index+1 / cards.length`、`记忆度 {memoryScore}`、ProgressBar。
- 卡片：`.flashcard` 容器，`aspect-ratio` 不固定，`min-height: 260px; max-height: 560px`；内部 `.flashcard-inner` 使用 `transform-style: preserve-3d; transition: transform .45s`；`.flipped` 时 `rotateY(180deg)`；正反面 `backface-visibility: hidden`。
- 正面：类型徽标、提示“点击翻转查看答案”、问题（`renderInlineMarkdown`，居中）。
- 背面：问题小字、分隔线、答案（`renderInlineMarkdown`）、选择题选项（正确项 indigo）、笔记块（teal 背景）。
- 翻面后显示操作条：问 AI / 编辑 / 笔记；三个胶囊按钮。
- 评分按钮四列，颜色按 `ratingOptions`；提交时禁用全部。
- 提交调用 `endpoints.submitReview(card.id, rating)`；成功后 `advanceReview`；完成时 `mode='done'` 并加载 `todaySummary`。
- 失败：显示错误条与“重试”按钮，不推进。
- 退出按钮：`confirm('退出复习？本次未提交的评分不会保存。')` 后回概览。

- [ ] **Step 6: 完成页**

- 极光背景；🎉；标题“今日复习完成！”；副标题。
- 小结卡：总张数 + 按卡组列表；加载失败不阻塞。
- “查看卡组”按钮 → `/decks`。

- [ ] **Step 7: 三个 Sheet**

`CardNoteSheet`：
- 文本域预填 `card.note ?? ''`；说明“不会改动原始问题/答案”；字数；清空；取消/保存；保存调用 `endpoints.updateCardNote`，emit `saved`。

`CardFormSheet`：
- props `deckId`、可选 `card`。
- 类型分段：问答/选择题/填空。
- 问答：问题 + 答案。
- 选择题：问题 + A/B/C/D（至少 A、B）+ 正确项单选；保存时 `answer=正确选项文本`，`options=JSON.stringify(选项数组)`。
- 填空：问题 + 插入 `____` 按钮 + 答案。
- Markdown 工具条：加粗 `**重点**`、列表 `- `、编号 `1. `、代码 `` `代码` ``。
- 保存调用 `createCard` 或 `updateCard`；emit `saved`。
- 校验：问题非空；问答/填空答案非空；选择题 A、B 与正确项非空。

`CoachChatSheet`：
- 顶部显示卡片问题。
- 快捷问题：“帮我讲透这道题”“面试官可能会怎么追问？”“出一道同考点的题目考考我”。
- 消息列表；用户右侧 indigo，教练左侧浅色；支持 Markdown。
- 发送时把卡片问题/答案拼进消息，调用 `endpoints.coach(prompt, 'CARD_QA')`。
- 显示工具摘要（`本次调用：...`）。
- 失败显示友好错误。
- 输入框 + 发送按钮。

- [ ] **Step 8: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：`pnpm dev` 后登录 demo，检查概览、翻面、评分、完成页。

- [ ] **Step 9: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻今日复习、翻转卡片、评分与卡片问答"
```

---

## Task 6: 知识树列表、搜索与卡组 CRUD

**Files:**
- Create: `src/core/decks/tree.ts`, `src/core/decks/__tests__/tree.test.ts`
- Create: `src/ui/pages/DecksPage.vue`
- Create: `src/ui/sheets/{CreateDeckSheet,EditDeckSheet}.vue`
- Create: `src/ui/components/{DeckRow,TreeItem,EmptyState}.vue`（EmptyState 已有则复用）

**Interfaces:**
- Produces: `buildDeckTree(decks)`、`filterDeckTree(nodes, query)`、`descendantIds(rootId, decks)`。
- Produces: `DeckNode`、`useDeckStore`（可选；直接在页面维护）。

- [ ] **Step 1: 写树测试**

```ts
import { describe, expect, it } from 'vitest'
import { buildDeckTree, descendantIds, filterDeckTree } from '../tree'
import type { Deck } from '@/core/api/types'

const deck = (id: number, parentId: number | null, title = `D${id}`): Deck => ({
  id, parentId, depth: parentId ? 1 : 0, title, type: '自建', category: '综合',
  description: null, cardCount: 0, reviewedCount: 0, dueCount: 0, avgMemoryScore: 0, createdAt: ''
})

describe('deck tree', () => {
  it('builds and sorts roots and children', () => {
    const roots = buildDeckTree([deck(2, null, 'B'), deck(1, null, 'A'), deck(3, 1, 'C')])
    expect(roots.map(n => n.deck.id)).toEqual([1, 2])
    expect(roots[0].children[0].deck.id).toBe(3)
  })
  it('does not loop on cyclic parents', () => {
    const roots = buildDeckTree([deck(1, 2), deck(2, 1)])
    expect(roots).toHaveLength(0)
  })
  it('filters while keeping matched ancestors', () => {
    const roots = buildDeckTree([deck(1, null, 'Java'), deck(2, 1, 'JVM')])
    expect(filterDeckTree(roots, 'jvm')[0].children[0].deck.title).toBe('JVM')
  })
  it('collects descendants', () => {
    expect([...descendantIds(1, [deck(1, null), deck(2, 1), deck(3, 2)])]).toEqual([2, 3])
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/decks/__tests__/tree.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 tree.ts**

实现 `buildDeckTree`（按 `localeCompare('zh-CN', { numeric: true })` 排序、祖先集合防环、父节点不存在的节点视为根）、`filterDeckTree`（匹配标题/分类/描述或子节点命中）、`descendantIds`（BFS/DFS 去重）。

- [ ] **Step 4: 实现 DecksPage（含桌面双栏）**

- 加载 `endpoints.decks()`；维护 `decks`、`loading`、`error`、`query`。
- `tree = computed(() => filterDeckTree(buildDeckTree(decks.value), query.value))`。
- 顶部工具栏：
  - 左侧“掌握度地图”按钮 → `/graph`。
  - 右侧 `+` 菜单：手动新建、AI 上传生成、导入精选卡包。
- 搜索框。
- 树：递归组件 `TreeItem`，支持展开/收起（本地 `Set<number>`）；行内显示：
  - 图标（有子节点 `Network`，否则 `Layers`）；
  - 标题、分类胶囊；
  - 描述（可选，2 行）；
  - 统计：卡片/到期/记忆度 + 记忆度进度条（红 <40、橙 <70、绿）。
  - 操作按钮（hover/移动端常显）：编辑、删除。
- 点击行：`router.push({ name: 'decks', params: { id } })`。
- 删除：`confirm` 后调用 `deleteDeck`，刷新。
- 空状态/错误状态/加载态。
- 桌面（≥900px）：左侧列表 360px，右侧渲染 `<DeckDetailPage :deck-id="route.params.id" />`；移动端有 id 时只渲染详情，无 id 时只渲染列表。
- 本 Task 中 DeckDetailPage 先用 Task 7 的占位；占位显示“选择节点”。

- [ ] **Step 5: 实现新建/编辑卡组 Sheet**

- 字段：标题（必填）、分类（默认“综合”）、描述、父节点下拉（根节点 + `depth < 2` 的卡组，缩进展示）。
- 编辑时预填；保存调用 `updateDeck` 或 `createDeck`，emit `saved`。
- 错误显示在表单底部。
- 关闭：遮罩点击、Esc、取消按钮。

- [ ] **Step 6: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动用 demo 账号检查树、搜索、新建、编辑、删除。

- [ ] **Step 7: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻知识树、搜索与卡组 CRUD"
```

---

## Task 7: 卡组详情、卡片 CRUD、批量删除与选择题模式

**Files:**
- Create: `src/core/quiz/quiz.ts`, `src/core/quiz/__tests__/quiz.test.ts`
- Create: `src/ui/pages/DeckDetailPage.vue`, `src/ui/pages/QuizPage.vue`
- Create: `src/ui/components/{CardRow,TypeBadge,SelectCircle}.vue`
- Modify: `src/router/index.ts`（接入真实页面）

**Interfaces:**
- Produces: `buildQuiz(cards, max, rng)`、`scoreQuiz(questions, answers)`、`QuizQuestion`。
- Produces: `DeckDetailPage` props `{ deckId: number }`。

- [ ] **Step 1: 写选择题测试**

```ts
import { describe, expect, it } from 'vitest'
import { buildQuiz, scoreQuiz } from '../quiz'
import type { Flashcard } from '@/core/api/types'

const card = (id: number, answer: string): Flashcard => ({
  id, deckId: 1, question: `Q${id}`, answer, cardType: 'qa', options: null, category: '综合',
  memoryScore: 50, difficulty: 5, stability: 2, note: null, reviewCount: 1,
  lastReviewedAt: null, nextReviewAt: null, createdAt: ''
})

describe('quiz', () => {
  it('builds at most 10 questions with 4 unique options', () => {
    const cards = [1, 2, 3, 4, 5].map(i => card(i, `A${i}`))
    const quiz = buildQuiz(cards, 10, () => 0.5)
    expect(quiz).toHaveLength(5)
    for (const q of quiz) {
      expect(new Set(q.options).size).toBe(q.options.length)
      expect(q.options[q.correctIndex]).toBe(q.answer)
    }
  })
  it('scores answers', () => {
    const quiz = buildQuiz([card(1, 'x'), card(2, 'y')], 10, () => 0.5)
    expect(scoreQuiz(quiz, quiz.map(q => q.correctIndex))).toBe(quiz.length)
    expect(scoreQuiz(quiz, quiz.map(() => 0))).toBeLessThanOrEqual(quiz.length)
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/quiz/__tests__/quiz.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 quiz.ts**

```ts
import type { Flashcard } from '@/core/api/types'

export interface QuizQuestion {
  cardId: number
  question: string
  options: string[]
  correctIndex: number
  answer: string
}

export function buildQuiz(cards: Flashcard[], max = 10, rng: () => number = Math.random): QuizQuestion[] {
  const shuffled = [...cards].sort(() => rng() - 0.5).slice(0, max)
  return shuffled.map(card => {
    const distractors = cards
      .filter(c => c.id !== card.id && c.answer !== card.answer)
      .sort(() => rng() - 0.5)
      .slice(0, 3)
      .map(c => c.answer)
    const options = [card.answer, ...distractors]
    for (let i = options.length - 1; i > 0; i -= 1) {
      const j = Math.floor(rng() * (i + 1))
      ;[options[i], options[j]] = [options[j], options[i]]
    }
    return {
      cardId: card.id, question: card.question, answer: card.answer,
      options, correctIndex: options.indexOf(card.answer)
    }
  })
}

export function scoreQuiz(questions: QuizQuestion[], answers: number[]): number {
  return questions.reduce((score, q, i) => score + (answers[i] === q.correctIndex ? 1 : 0), 0)
}
```

- [ ] **Step 4: 实现 DeckDetailPage**

- 从 `decks()` 找到当前 `deckId`；找不到则错误。
- 并行加载 `cards(deckId)` 与 `decks()` 过滤子卡组。
- 有子卡组：显示子卡组列表（`DeckRow`），点击进入。
- 无子卡组：卡片列表；`CardRow` 显示类型徽标、问题、答案/选项、记忆度、复习次数。
- 点击卡片：打开 `CardFormSheet` 编辑；删除：确认后 `deleteCard`。
- 管理模式：多选圆圈、全选/取消、批量删除（`deleteCards`）。
- 底部“添加卡片”按钮；卡片 ≥2 且无子卡组时显示“测验”按钮 → `/decks/:id/quiz`。
- 顶部返回按钮（移动端）→ `/decks`；标题 + 分类。
- 空状态：无卡片。

- [ ] **Step 5: 实现 QuizPage**

- 加载卡片；`buildQuiz(cards, 10)`。
- 进度条；题号；问题卡；A/B/C/D 选项按钮；选择后显示正确/错误底色和正确答案；下一题；结果页。
- 结果页：得分环（SVG）、正确率、评价文案、再来一次、退出。
- `<2` 张卡片显示 EmptyState。

- [ ] **Step 6: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：demo 账号进入叶卡组，增删改卡片、批量删除、选择题。

- [ ] **Step 7: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻卡组详情、卡片管理与选择题模式"
```

---

## Task 8: AI 生成卡组

**Files:**
- Create: `src/core/ai/preview.ts`, `src/core/ai/__tests__/preview.test.ts`
- Create: `src/ui/pages/AiGeneratePage.vue`

**Interfaces:**
- Produces: `parseAiPreview(raw)`、`mergePreviews(title, previews)`。
- Produces: `detailHints`、`detailLabels`。

- [ ] **Step 1: 写预览解析测试**

```ts
import { describe, expect, it } from 'vitest'
import { mergePreviews, parseAiPreview } from '../preview'

describe('ai preview', () => {
  it('parses and trims cards', () => {
    const preview = parseAiPreview(JSON.stringify({
      title: ' T ', category: ' Java ', description: ' d ',
      children: [{ title: ' C ', cards: [{ question: ' q ', answer: ' a ' }, { question: '', answer: 'x' }] }]
    }))
    expect(preview.title).toBe('T')
    expect(preview.children[0].cards).toEqual([{ question: 'q', answer: 'a' }])
  })
  it('rejects non-json', () => {
    expect(() => parseAiPreview('not json')).toThrow('AI 返回的内容不是有效 JSON')
  })
  it('merges children and keeps user title', () => {
    const merged = mergePreviews('Mine', [
      { title: 'a', category: 'Java', description: 'd1', children: [{ title: 'c1', cards: [] }] },
      { title: 'b', category: 'Java', description: 'd2', children: [{ title: 'c2', cards: [] }] }
    ])
    expect(merged.title).toBe('Mine')
    expect(merged.children.map(c => c.title)).toEqual(['c1', 'c2'])
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/ai/__tests__/preview.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 preview.ts**

- `parseAiPreview`: `JSON.parse`，失败抛指定文案；校验 `title` 字符串；`category` 默认“综合”；`description` 默认空；`children` 数组，过滤无标题子卡组；卡片 question/answer trim 后非空。
- `mergePreviews(title, previews)`: 根标题用用户输入；category/description 取第一个；children 拼接。
- `detailLabels` / `detailHints` 与 iOS 完全一致。

- [ ] **Step 4: 实现页面**

- 输入模式分段：上传文件 / 粘贴文字。
- 文件：`getRuntime().adapters.file.pick({ multiple: true, accept: [...] })`；最多 10 个；显示文件名/大小/移除。
- 粘贴：文本域、从剪贴板粘贴（`adapters.clipboard.readText()`）、字数、清空。
- 卡组名称必填。
- 卡片数量：开关“自动”（传 0）；手动 5–100 步长 5。
- 详细程度：5 档滑块 0–4。
- AI 设置：默认系统；可选自定义 Key（仅请求内使用，不存）。
- 生成：逐文件调用 `endpoints.generate`，显示“第 i/n 个文件”；`AbortController` 支持取消。
- 预览：卡组摘要、子卡组与卡片、总卡片数；确认导入 / 重新生成 / 取消。
- 导入：`endpoints.importAiDeck(JSON.stringify(preview))`；成功页；返回知识树。
- 错误显示在输入页。

- [ ] **Step 5: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：粘贴一段文字，生成 5 张卡，预览并导入。该链路会调用真实 AI，注意额度。

- [ ] **Step 6: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻 AI 上传/粘贴生成与预览导入"
```

---

## Task 9: 精选卡包

**Files:**
- Create: `src/ui/pages/CommunityPage.vue`, `src/ui/sheets/PackDetailSheet.vue`

**Interfaces:**
- Consumes: `endpoints.communityPacks()`、`communityPack(id)`、`importCommunityPack(id)`。
- Produces: 无公开导出。

- [ ] **Step 1: 实现列表页**

- 加载卡包；loading/error/empty。
- Banner：渐变卡片、标题“精选卡包库”、说明、📚。
- 列表行：分类色块 + emoji、标题、卡片数胶囊、描述、标签。
- 分类颜色与 emoji 按 spec。
- 点击打开 `PackDetailSheet`。

- [ ] **Step 2: 实现详情 Sheet**

- 加载详情；描述、标签、全部卡片 Q/A。
- “一键导入”按钮：调用导入，成功后 emit `imported`、显示 Toast“✅「标题」已导入卡组”；失败“❌ 导入失败，请重试”。
- 导入中禁用；已导入显示“已导入”。

- [ ] **Step 3: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：demo 账号打开卡包、导入，返回知识树可见新卡组。

- [ ] **Step 4: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻精选卡包列表、详情与一键导入"
```

---

## Task 10: AI 学习教练（流式、历史会话、图表）

**Files:**
- Create: `src/core/coach/{sessions,progress,tools}.ts`, `src/core/coach/__tests__/*.test.ts`
- Create: `src/ui/pages/CoachPage.vue`, `src/ui/stores/coach.ts`
- Create: `src/ui/components/charts/BarChart.vue`

**Interfaces:**
- Produces: `CoachSession`、`CoachMessage`、`upsertSession`、`sessionTitle`、`toolSummary`、`extractToolResult`、`localizeProgress`。
- Produces: `useCoachStore()`：`sessions`、`currentId`、`messages`、`newSession`、`switchSession`、`deleteSession`、`persist`。

- [ ] **Step 1: 写教练工具测试**

```ts
import { describe, expect, it } from 'vitest'
import { extractToolResult, localizeProgress, sessionTitle, toolSummary } from '../tools'
import type { AgentRun } from '@/core/api/types'

const run: AgentRun = {
  runId: 1, status: 'SUCCEEDED', output: 'ok', stepCount: 2,
  steps: [
    { stepNo: 1, stepType: 'TOOL', modelContent: null, toolName: 'get_weak_cards', toolArguments: null, toolResult: '[{"question":"Q"}]', durationMs: 1 },
    { stepNo: 2, stepType: 'MODEL', modelContent: 'done', toolName: null, toolArguments: null, toolResult: null, durationMs: 1 }
  ]
}

describe('coach tools', () => {
  it('extracts tool result arrays', () => {
    expect(extractToolResult(run, 'get_weak_cards')).toEqual([{ question: 'Q' }])
  })
  it('summarizes tools in Chinese', () => {
    expect(toolSummary(run)).toBe('本次调用：薄弱卡片诊断')
  })
  it('localizes progress', () => {
    expect(localizeProgress('calling get_review_trend')).toBe('calling 复习趋势统计')
  })
  it('derives a short session title', () => {
    expect(sessionTitle('分析我最近掌握得最差的知识点，并给出建议')).toBe('分析我最近掌握得最差的知识点，并给出建议'.slice(0, 24))
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/coach`
Expected: FAIL。

- [ ] **Step 3: 实现 coach 核心**

- 工具名映射：`get_weak_cards`→薄弱卡片诊断、`get_review_trend`→复习趋势统计、`get_neglected_decks`→冷落卡组检查、`generate_supplement_cards`→补强卡片生成与质检。
- `toolSummary` 去重、按顺序、无工具返回 `undefined`。
- `extractToolResult<T>(run, name)` 取最后一个同名 TOOL step 的 `toolResult`，JSON 解析失败返回 `[]`。
- `localizeProgress` 逐项替换。
- `CoachSession`：`{ id, title, updatedAt, messages }`；`upsertSession` 更新消息与时间。

- [ ] **Step 4: 实现 coach store**

- 从 `adapters.storage` 读取 `prepdot.coach.sessions.v1`；无则创建“新会话”。
- `persist()` 写回；`newSession`、`switchSession`、`deleteSession`。
- 首次进入加载最近会话。

- [ ] **Step 5: 实现 CoachPage**

- 安全说明条。
- 空状态：标题、说明、4 个快捷问题。
- 消息列表：用户右侧 indigo、教练左侧浅色、Markdown。
- 发送：
  - 追加用户消息；
  - `thinking=true`，`progress='正在连接学习教练…'`；
  - 用 `createSseParser` 消费 `endpoints.coachStream(text)`：
    - `progress` → 本地化文案；
    - `result` → `JSON.parse` 为 `AgentRun`，追加回答，提取 `get_review_trend` / `get_weak_cards`；
    - `error` → 抛错。
  - SSE 失败 → 回退 `endpoints.coach(text)`；
  - 再失败 → 友好错误消息；
  - 持久化会话。
- 图表：
  - `BarChart` 输入 `{ label, value }[]`，SVG 柱状，indigo→purple 渐变，高 150。
  - 趋势数据字段：`date`、`total`；薄弱卡片字段：`question`、`memoryScore`，取前 8。
- 历史会话 Sheet：按更新时间排序，显示标题和相对时间；点击切换；删除；新建。
- 输入框：多行、Enter 发送（Shift+Enter 换行）、发送中禁用。

- [ ] **Step 6: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：demo 账号提问“哪些卡组很久没有复习了？”，观察流式进度和回答。

- [ ] **Step 7: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻 AI 学习教练流式对话与历史会话"
```

---

## Task 11: 个人中心、统计图表、每日提醒、注销账号

**Files:**
- Create: `src/core/stats/week.ts`, `src/core/stats/__tests__/week.test.ts`
- Create: `src/ui/pages/{ProfilePage,ReminderPage,DeleteAccountPage}.vue`
- Create: `src/ui/components/{StatCard,MemoryDistribution}.vue`
- Reuse: `BarChart.vue`

**Interfaces:**
- Produces: `last7Days(data, nowMs, timeZone?)`；输入 `day` 兼容后端实际格式 `MM-DD`，输出统一为 `YYYY-MM-DD`。
- Produces: `useAuthStore` 的 `user` 提供 `studyTarget`、`avatarColor`。

- [ ] **Step 1: 写近 7 天测试**

```ts
import { describe, expect, it } from 'vitest'
import { last7Days } from '../week'

describe('last7Days', () => {
  it('fills missing days and labels them', () => {
    const now = Date.UTC(2026, 9, 31, 4, 0)
    // 后端 UserStatsVO.weeklyData 实际返回 "MM-DD"
    const rows = last7Days([{ day: '10-31', count: 5 }, { day: '10-29', count: 2 }], now)
    expect(rows).toHaveLength(7)
    expect(rows.at(-1)).toEqual({ day: '2026-10-31', label: '10/31', count: 5 })
    expect(rows.find(r => r.day === '2026-10-30')?.count).toBe(0)
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/stats/__tests__/week.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 week.ts**

用 `Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai', ... })` 生成每天 `YYYY-MM-DD`；从 6 天前到今天；标签 `MM/DD`；缺失计数补 0。输入 key 取 `day.slice(-5)`（即 `MM-DD`）匹配，避免跨年时推断年份出错；输出保留生成的完整 `YYYY-MM-DD`。

- [ ] **Step 4: 实现 ProfilePage**

- 头像：`user.nickname` 首字，背景 `linear-gradient(135deg, user.avatarColor, user.avatarColor + 'b3')`；88px 圆形；阴影。
- 昵称、`@username`。
- 连续打卡卡：48px 进度环（今日已复习/目标）、🔥 + `streakDays` 天、今日已复习与目标。
- 四格统计：卡组、卡片、总复习、平均记忆度；图标 `Folder`、`Layers`、`CheckCircle2`、`Brain`。
- 近 7 天柱状图。
- 记忆度分布：三段条（粉/紫/indigo）+ 图例与数量。
- 设置列表：每日提醒、退出登录、注销账号。
- 加载失败显示可重试错误；401 自动跳登录。
- 下拉刷新不做（移动浏览器原生手势即可）；提供刷新按钮。

- [ ] **Step 5: 实现 ReminderPage**

- 读取 `prepdot.reminder` JSON `{ enabled, time }`。
- 开关：开启时请求权限；拒绝显示橙色提示并关闭。
- 时间输入 `<input type="time">`。
- 保存调用 `adapters.notification.scheduleDaily(time, user.studyTarget)`；关闭调用 `cancelDaily()`。
- 说明浏览器限制。

- [ ] **Step 6: 实现 DeleteAccountPage**

- 红色警告文案；密码输入；确认按钮。
- 调用 `endpoints.deleteAccount(password)`；成功 `auth.logout()` 并 `router.push('/login')`；失败显示错误。
- 取消返回 `/profile`。

- [ ] **Step 7: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：demo 账号查看统计图、切换提醒、注销用测试账号验证（不要注销 demo）。

- [ ] **Step 8: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻个人中心统计、提醒与注销账号"
```

---

## Task 12: 掌握度地图

**Files:**
- Create: `src/core/graph/plot.ts`, `src/core/graph/__tests__/plot.test.ts`
- Create: `src/ui/pages/MasteryMapPage.vue`
- Create: `src/ui/components/charts/ScatterChart.vue`（或页面内 SVG）

**Interfaces:**
- Produces: `buildPlot(cards, width, height, padding)`、`scoreColor(score)`。

- [ ] **Step 1: 写坐标测试**

```ts
import { describe, expect, it } from 'vitest'
import { buildPlot, scoreColor } from '../plot'
import type { Flashcard } from '@/core/api/types'

const card = (id: number, difficulty: number | null, stability: number | null, score = 50): Flashcard => ({
  id, deckId: 1, question: `Q${id}`, answer: 'A', cardType: 'qa', options: null, category: '综合',
  memoryScore: score, difficulty, stability, note: null, reviewCount: 1,
  lastReviewedAt: null, nextReviewAt: null, createdAt: ''
})

describe('plot', () => {
  it('drops unreviewed cards', () => {
    expect(buildPlot([card(1, null, null), card(2, 5, 10)], 400, 300, 40)).toHaveLength(1)
  })
  it('keeps points inside the plot area', () => {
    const points = buildPlot([card(1, 1, 0.1), card(2, 10, 1000)], 400, 300, 40)
    for (const p of points) {
      expect(p.x).toBeGreaterThanOrEqual(40)
      expect(p.x).toBeLessThanOrEqual(360)
      expect(p.y).toBeGreaterThanOrEqual(40)
      expect(p.y).toBeLessThanOrEqual(260)
    }
  })
  it('is deterministic and changes color with score', () => {
    const a = buildPlot([card(7, 5, 10, 0)], 400, 300, 40)[0]
    const b = buildPlot([card(7, 5, 10, 0)], 400, 300, 40)[0]
    expect([a.x, a.y]).toEqual([b.x, b.y])
    expect(scoreColor(0)).not.toBe(scoreColor(100))
  })
})
```

- [ ] **Step 2: 运行确认失败**

Run: `cd prepdot-web && pnpm vitest run src/core/graph/__tests__/plot.test.ts`
Expected: FAIL。

- [ ] **Step 3: 实现 plot.ts**

- 过滤 `difficulty !== null && stability !== null`。
- X：`(difficulty - 1) / 9`。
- Y：`log10(max(stability, 0.01))`，按所有点 min/max 归一化；相等时 ±0.5。
- 抖动：`hash(id * 12.9898)` / `hash(id * 78.233)`，范围 ±6px，使用 `Math.sin(seed) * 43758.5453` 取小数。
- 颜色：`t = score/100`；`rgb(0.85-0.50t, 0.38-0.10t, 0.82+0.14t)` 转 0–255。

- [ ] **Step 4: 实现 MasteryMapPage**

- 加载 `decks()`，根卡组（`parentId === null`）。
- 横向胶囊选择根卡组；切换时 `cards(rootId, true)`。
- 统计条：已复习/总卡片、待复习数。
- SVG：
  - 4×4 网格、轴线、轴标签“难度 →”“稳定性 ↑”。
  - 点：圆半径 5.5（选中 8），填充颜色，白色描边选中；点击选中。
  - 使用 `viewBox` 自适应；容器高度 `min(60vh, 520px)`。
- 详情面板：掌握度、问题、难度（1 位小数）、稳定性（天）、复习次数、类型。
- 图例：待加强/进行中/已掌握。
- 空状态：无卡组、无卡片、无复习记录三种文案。
- 返回按钮（移动端）→ `/decks`。

- [ ] **Step 5: 验证**

Run: `cd prepdot-web && pnpm test && pnpm lint && pnpm build`
Expected: 全绿。手动：demo 账号查看散点、点击节点。

- [ ] **Step 6: 提交**

```bash
git add prepdot-web/src
git commit -m "feat(web): 复刻掌握度散点地图"
```

---

## Task 13: 视觉打磨、响应式、无障碍与 Playwright 冒烟

**Files:**
- Modify: `src/styles/components.css`、各页面 scoped CSS
- Create: `playwright.config.ts`, `e2e/smoke.spec.ts`

**Interfaces:**
- Consumes: 所有页面。
- Produces: `pnpm e2e` 可运行。

- [ ] **Step 1: 视觉对齐检查**

逐项确认：

- 浅色/深色下文字对比度 ≥ 4.5:1（正文）。
- 所有按钮/输入 ≥ 44px 高。
- 卡片圆角、阴影、间距与 iOS 一致（24/20/16）。
- 极光背景在复习概览、完成页、登录页出现。
- 进度环、评分按钮、翻转卡片、类型徽标、玻璃卡片的视觉与 spec 一致。
- 移动端底部 Tab 不遮挡内容（`.page` 已留 padding）。
- 桌面端双栏知识树、侧栏、Modal 居中。
- 暗色模式下图表、散点、边框可见。
- `prefers-reduced-motion` 下动画关闭。

- [ ] **Step 2: 无障碍**

- 所有图标按钮有 `aria-label`。
- Sheet 有 `role="dialog" aria-modal="true"`，打开时焦点进入，Esc 关闭，关闭后焦点还原。
- 表单 label 关联输入（`for`/`id`）。
- 错误消息使用 `role="alert"`。
- 评分按钮可通过键盘访问；卡片翻转同时提供“显示答案”按钮（不仅靠点击卡片）。
- 图片/图标装饰性使用 `aria-hidden="true"`。

- [ ] **Step 3: 配置 Playwright**

`playwright.config.ts`：

```ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
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
```

- [ ] **Step 4: 写冒烟测试**

`e2e/smoke.spec.ts`：

```ts
import { expect, test } from '@playwright/test'

test('demo login, decks, review', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: '体验演示账号' }).click()
  await expect(page).toHaveURL(/\/review/)
  await expect(page.getByText('今日复习')).toBeVisible()

  await page.getByRole('link', { name: '知识树' }).click()
  await expect(page).toHaveURL(/\/decks/)
  await expect(page.getByPlaceholder('搜索知识节点')).toBeVisible()

  await page.getByRole('link', { name: '今日复习' }).click()
  const start = page.getByRole('button', { name: /开始复习|继续复习/ })
  if (await start.isVisible()) {
    await start.click()
    await expect(page.getByText(/1 \/ \d+/)).toBeVisible()
  }
})

test('profile renders stats', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: '体验演示账号' }).click()
  await page.getByRole('link', { name: '我的' }).click()
  await expect(page.getByText('近 7 天复习')).toBeVisible()
  await expect(page.getByText('记忆度分布')).toBeVisible()
})
```

- [ ] **Step 5: 运行验证**

Run:
```bash
cd prepdot-web && pnpm lint && pnpm build
```
Expected: 全绿。`pnpm e2e` 依赖 Task 15 的 demo 数据，统一在 Task 16 Step 6 执行；本 Task 只创建配置与用例，不要求通过。

- [ ] **Step 6: 提交**

```bash
git add prepdot-web/src prepdot-web/playwright.config.ts prepdot-web/e2e
git commit -m "feat(web): 打磨响应式视觉与无障碍，加入移动端冒烟测试"
```

---

## Task 14: 部署配置、脚本与文档

**Files:**
- Modify: `deploy/Caddyfile.prepdot`
- Create: `prepdot-web/scripts/deploy-web.sh`
- Create: `DEPLOY-WEB.md`
- Modify: `README.md`

**Interfaces:**
- Produces: `deploy-web.sh` 读取 `PREPDOT_SSH_HOST`（默认 `ubuntu@62.234.146.153`）、`PREPDOT_SSH_KEY`（默认 `~/.ssh/id_ed25519`）、`YES=1` 跳过确认。

- [ ] **Step 1: 更新 Caddy 配置**

`deploy/Caddyfile.prepdot` 完整内容：

```caddyfile
api.prepdot.site {
    encode zstd gzip
    reverse_proxy prepdot-backend:8080
}

prepdot.site, www.prepdot.site {
    encode zstd gzip

    handle /api/* {
        reverse_proxy prepdot-backend:8080
    }

    handle /welcome {
        redir /welcome/ permanent
    }

    handle /welcome/* {
        root * /srv/legal/prepdot-site
        file_server
    }

    handle {
        root * /srv/legal/prepdot-site/app
        try_files {path} /index.html
        file_server
    }

    header {
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        X-Frame-Options DENY
    }
}
```

- [ ] **Step 2: 写部署脚本**

`prepdot-web/scripts/deploy-web.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

HOST="${PREPDOT_SSH_HOST:-ubuntu@62.234.146.153}"
KEY="${PREPDOT_SSH_KEY:-$HOME/.ssh/id_ed25519}"
ROOT="/opt/adeer/legal/prepdot-site"

cd "$(dirname "$0")/.."
pnpm install --frozen-lockfile
pnpm lint
pnpm build

if [[ "${YES:-0}" != "1" ]]; then
  read -r -p "发布到 ${HOST}? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 1
fi

ssh -i "$KEY" "$HOST" "mkdir -p '$ROOT/app.new' '$ROOT/welcome'"

# 首次部署：把旧落地页移动到 welcome/
ssh -i "$KEY" "$HOST" "
  cd '$ROOT'
  if [ ! -f welcome/index.html ] && [ -f index.html ]; then
    mv index.html site.css site.js app-icon.png welcome/ 2>/dev/null || true
  fi
"

rsync -az --delete -e "ssh -i $KEY" dist/ "$HOST:$ROOT/app.new/"

ssh -i "$KEY" "$HOST" "
  cd '$ROOT'
  rm -rf app.prev
  [ -d app ] && mv app app.prev || true
  mv app.new app
"

curl -fsS https://prepdot.site/api/health >/dev/null
curl -fsS -o /dev/null https://prepdot.site/
curl -fsS -o /dev/null https://prepdot.site/welcome/
echo "发布完成：https://prepdot.site"
```

执行 `chmod +x prepdot-web/scripts/deploy-web.sh`。

- [ ] **Step 3: 写 DEPLOY-WEB.md**

必须包含：
- 架构图（iOS/Web/Desktop → Caddy → Spring Boot → MySQL）。
- 为什么用 Caddy 而不是 nginx。
- 首次部署步骤：备份 Caddyfile、创建 `app/`/`welcome/`、移动宣传页、`caddy validate`、`caddy reload`。
- 日常发布：`./scripts/deploy-web.sh`。
- 回滚：`app.prev` + Caddyfile 备份。
- 演示账号与重置脚本、cron。
- 验证命令（health、首页、welcome、API 预检）。
- 常见问题：刷新 404、API 401、跨域、上传超限、AI 超时、HTTPS 证书。
- 安全说明：明文 API Key 风险、demo 额度、token 存储。
- 不修改 iOS、不改后端接口。

- [ ] **Step 4: 更新 README 多端章节**

新增“多端架构”小节：
- iOS / Web / 桌面端路线图。
- `prepdot-web/` 开发与构建命令。
- 生产地址。
- 指向 `DEPLOY-WEB.md`。
- 说明 Phase 2 尚未开始。

- [ ] **Step 5: 语法检查**

Run:
```bash
bash -n prepdot-web/scripts/deploy-web.sh
cd prepdot-web && pnpm lint && pnpm build
```
Expected: 无语法错误，构建成功。

- [ ] **Step 6: 提交**

```bash
git add deploy/Caddyfile.prepdot prepdot-web/scripts/deploy-web.sh DEPLOY-WEB.md README.md
git commit -m "feat(web): 增加 Caddy 部署配置、发布脚本与多端文档"
```

---

## Task 15: 演示账号数据与每日重置

**Files:**
- Create: `deploy/demo/decks/java-backend.json`, `spring-boot.json`, `computer-network.json`
- Create: `deploy/demo/reset-demo.sh`, `deploy/demo/demo-backdate.sql`
- Modify: `prepdot-web/scripts/deploy-web.sh`（同步 demo 文件到服务器）

**Interfaces:**
- Produces: 服务器 `/opt/prepdot/demo/` 下的 JSON 与脚本；cron 每日 04:17。
- 账号：`demo` / `PrepDot2026`。

- [ ] **Step 1: 编写 3 个层级 JSON**

每个文件符合 `/ai/import` 结构：

```json
{
  "title": "Java 后端面试",
  "category": "Java",
  "description": "集合、JVM、并发与语言基础的高频考点",
  "children": [
    {
      "title": "集合框架",
      "cards": [
        { "question": "HashMap 的底层数据结构？", "answer": "JDK 1.8 后为数组 + 链表 + 红黑树；链表长度 ≥ 8 且数组长度 ≥ 64 时转红黑树。" }
      ]
    }
  ]
}
```

内容要求：
- `java-backend.json`：4 个子卡组 × 6 张 = 24 张。
- `spring-boot.json`：4 个子卡组 × 5 张 = 20 张。
- `computer-network.json`：3 个子卡组 × 5–6 张 = 16 张。
- 总计 60 张，问题与答案真实、互不重复。
- Java/Spring 内容可复用 `prepdot-backend/src/main/resources/community-packs.json` 的现有题目，按主题拆分。

- [ ] **Step 2: 写回填 SQL**

`deploy/demo/demo-backdate.sql`：

```sql
SET @demo_id = (SELECT id FROM user WHERE username = 'demo');

-- 18 张：已复习且今天到期
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = 3 + (f.id % 5),
    f.stability = 0.8 + (f.id % 7),
    f.review_count = 1 + (f.id % 4),
    f.last_reviewed_at = NOW() - INTERVAL (1 + f.id % 10) DAY,
    f.next_review_at = NOW() - INTERVAL (f.id % 3) HOUR
WHERE d.user_id = @demo_id AND f.id % 10 IN (0, 1, 2);

-- 24 张：已复习且未来到期
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = 4 + (f.id % 6),
    f.stability = 2 + (f.id % 20),
    f.review_count = 2 + (f.id % 6),
    f.last_reviewed_at = NOW() - INTERVAL (2 + f.id % 12) DAY,
    f.next_review_at = NOW() + INTERVAL (1 + f.id % 20) DAY
WHERE d.user_id = @demo_id AND f.id % 10 IN (3, 4, 5, 6);

-- 18 张：从未复习，安排到未来，避免今日队列过大
UPDATE flashcard f JOIN deck d ON f.deck_id = d.id
SET f.difficulty = NULL,
    f.stability = NULL,
    f.review_count = 0,
    f.last_reviewed_at = NULL,
    f.next_review_at = NOW() + INTERVAL (1 + f.id % 7) DAY
WHERE d.user_id = @demo_id AND f.id % 10 IN (7, 8, 9);

-- 过去 14 天的复习历史：每张已复习卡片 8 条
INSERT INTO review_record (user_id, card_id, rating, memory_score_before, memory_score_after, reviewed_at)
SELECT @demo_id,
       f.id,
       ELT(1 + ((f.id + n.n) % 4), 'again', 'hard', 'good', 'easy'),
       25 + ((f.id * 7 + n.n * 11) % 50),
       35 + ((f.id * 5 + n.n * 13) % 55),
       NOW() - INTERVAL ((f.id + n.n * 2) % 14) DAY - INTERVAL (n.n * 37) MINUTE
FROM flashcard f
JOIN deck d ON f.deck_id = d.id
JOIN (
  SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
  UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7
) n
WHERE d.user_id = @demo_id AND f.difficulty IS NOT NULL;
```

- [ ] **Step 3: 写重置脚本**

`deploy/demo/reset-demo.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

API="https://api.prepdot.site/api"
DEMO_USER="demo"
DEMO_PASS="PrepDot2026"
DEMO_DIR="/opt/prepdot/demo"

set -a
# shellcheck disable=SC1091
. /opt/prepdot/.env.production
set +a

mysql_exec() {
  docker exec -i prepdot-mysql sh -c \
    'MYSQL_PWD="$MYSQL_PASSWORD" mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" --default-character-set=utf8mb4' "$@"
}

mysql_exec <<'SQL'
SET @demo_id = (SELECT id FROM user WHERE username = 'demo');
DELETE FROM agent_step WHERE run_id IN (SELECT id FROM agent_run WHERE user_id = @demo_id);
DELETE FROM agent_run WHERE user_id = @demo_id;
DELETE FROM daily_plan WHERE user_id = @demo_id;
DELETE FROM review_record WHERE user_id = @demo_id;
DELETE FROM deck WHERE user_id = @demo_id;
DELETE FROM user WHERE id = @demo_id;
SQL

# 重新注册 demo，确保密码固定
curl -fsS -X POST "$API/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\",\"nickname\":\"演示用户\"}" >/dev/null

TOKEN="$(curl -fsS -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\"}" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"

[ -n "$TOKEN" ] || { echo "登录 demo 失败" >&2; exit 1; }

for file in "$DEMO_DIR"/decks/*.json; do
  curl -fsS -X POST "$API/ai/import" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$file" >/dev/null
done

mysql_exec < "$DEMO_DIR/demo-backdate.sql"

echo "demo 数据已重置：$(date '+%F %T')"
```

执行 `chmod +x`。

- [ ] **Step 4: 同步 demo 文件**

在 `deploy-web.sh` 中加入：

```bash
ssh -i "$KEY" "$HOST" "mkdir -p /opt/prepdot/demo/decks"
rsync -az -e "ssh -i $KEY" deploy/demo/ "$HOST:/opt/prepdot/demo/"
```

- [ ] **Step 5: 安装 cron（首次手动）**

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  (crontab -l 2>/dev/null | grep -v "/opt/prepdot/demo/reset-demo.sh"; \
   echo "17 4 * * * /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1") | crontab -
  crontab -l | tail -3
'
```

- [ ] **Step 6: 本地验证脚本语法**

Run: `bash -n deploy/demo/reset-demo.sh && bash -n prepdot-web/scripts/deploy-web.sh`
Expected: 无输出、退出码 0。

- [ ] **Step 7: 提交**

```bash
git add deploy/demo prepdot-web/scripts/deploy-web.sh
git commit -m "feat: 增加演示账号数据与每日重置脚本"
```

---

## Task 16: 生产发布与验收

**Files:**
- Modify: `DEPLOY-WEB.md`（补充实际发布记录与验证结果）
- Modify: `README.md`（实际地址）

**Interfaces:**
- Consumes: 前 15 个 Task。
- Produces: 线上可访问的 Web 端、demo 数据、验收记录。

**前置确认：** 本 Task 会推送到 `main`（触发后端自动部署）并修改生产 Caddy。执行前向用户确认一次。

- [ ] **Step 1: 合并分支并触发后端部署**

```bash
git switch main
git merge --no-ff feat/web-multiplatform
git push origin main
```

等待 GitHub Actions 完成；确认 `https://api.prepdot.site/api/health` 返回 200。

- [ ] **Step 2: 验证 OPTIONS 预检**

```bash
curl -sS -i -X OPTIONS https://api.prepdot.site/api/plan/review \
  -H 'Origin: https://prepdot.site' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,content-type'
```

Expected: HTTP 2xx，包含 `Access-Control-Allow-Origin`，不再返回 401。

- [ ] **Step 3: 首次部署 Caddy 配置**

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  cd /opt/adeer
  cp Caddyfile "Caddyfile.backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p legal/prepdot-site/welcome
  if [ ! -f legal/prepdot-site/welcome/index.html ] && [ -f legal/prepdot-site/index.html ]; then
    mv legal/prepdot-site/index.html legal/prepdot-site/site.css \
       legal/prepdot-site/site.js legal/prepdot-site/app-icon.png \
       legal/prepdot-site/welcome/
  fi
'
```

用 `deploy/Caddyfile.prepdot` 的 `prepdot.site` 块替换线上 `Caddyfile` 中对应块（保留 `{$SITE_ADDRESS}`、`adeer.site`、`sssangeng.online` 等无关配置）。

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  docker exec adeer-caddy-1 caddy validate --config /etc/caddy/Caddyfile &&
  docker exec adeer-caddy-1 caddy reload --config /etc/caddy/Caddyfile
'
```

- [ ] **Step 4: 发布 Web**

```bash
cd prepdot-web && YES=1 ./scripts/deploy-web.sh
```

- [ ] **Step 5: 初始化 demo 数据**

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  mkdir -p /opt/prepdot/demo/decks
  chmod +x /opt/prepdot/demo/reset-demo.sh
  /opt/prepdot/demo/reset-demo.sh
'
```

- [ ] **Step 6: 线上验证**

```bash
for url in \
  https://prepdot.site/ \
  https://prepdot.site/welcome/ \
  https://prepdot.site/api/health \
  https://api.prepdot.site/api/health; do
  printf '%s -> ' "$url"
  curl -sS -o /dev/null -w '%{http_code}\n' "$url"
done
```

Expected: 全部 200。

运行移动端冒烟测试（demo 数据已就绪）：

```bash
cd prepdot-web && pnpm e2e
```

Expected: 2 个用例通过。若失败，先核对 demo 账号密码与今日到期卡片数。

浏览器验证：
1. 登录 `demo` / `PrepDot2026`。
2. 今日复习显示 18 张到期，进度环有数据。
3. 知识树有 3 个根卡组、12 个子卡组、60 张卡。
4. 掌握度地图有散点。
5. AI 教练提问一次，收到流式回答。
6. 上传 `docs/PrepDot_AI卡组导入测试资料.txt` 生成并导入卡组。
7. 手机视口 390×844 检查底部 Tab、翻转卡片、评分。
8. 刷新 `/decks` 不 404。
9. 真机 4G 打开 `https://prepdot.site`，重复 1–6。

- [ ] **Step 7: iOS 模拟器交叉验收**

```bash
cd /Users/tangzishan/Project/PrepDot
./prepdot.sh start
```

在模拟器中登录同一账号，下拉刷新知识树，确认能看到 Web 新建的卡组。不得修改 iOS 代码。

- [ ] **Step 8: 更新文档**

在 `DEPLOY-WEB.md` 记录：
- 实际发布时间与 commit。
- Caddy 备份文件名。
- demo 重置 cron。
- 验证结果（HTTP 状态、验收项）。
- 回滚命令。

在 README 写入线上地址与截图占位说明（文字即可）。

- [ ] **Step 9: 提交**

```bash
git add DEPLOY-WEB.md README.md
git commit -m "docs: 记录 Web 端生产发布与验收结果"
```

---

## Self-Review

### Spec coverage

| Spec 章节 | 对应 Task |
|---|---|
| 目标 1–5 | Task 2–16 |
| 现状核实（API/部署） | 设计文档；Task 1、14、16 验证 |
| 总体架构 | Task 14 Caddy、Task 2 runtime |
| 技术栈 | Task 2 |
| 代码结构 / 边界 | Task 2 ESLint、Task 3 core |
| Adapter 接口 | Task 2 |
| 视觉 Token / 组件 | Task 2、5、13 |
| 响应式断点 | Task 2、4、6、13 |
| 登录/注册 | Task 4 |
| 今日复习 | Task 5 |
| 知识树 / 卡组 CRUD | Task 6 |
| 卡组详情 / 卡片 CRUD / 选择题 | Task 7 |
| AI 生成 | Task 8 |
| 精选卡包 | Task 9 |
| AI 教练 | Task 10 |
| 个人中心 / 提醒 / 注销 | Task 11 |
| 掌握度地图 | Task 12 |
| API 清单 | Task 3 endpoints；Task 5–12 使用 |
| 后端 OPTIONS | Task 1、16 |
| 部署 / 回滚 | Task 14、16 |
| demo 账号与数据 | Task 15、16 |
| 测试与验收 | Task 3、5–12 单测；Task 13 E2E；Task 16 人工 |
| 风险 | Task 14 DEPLOY-WEB.md、Task 16 |
| Phase 2 预留 | Task 2 desktop 空壳 |
| 实施顺序 | 本计划 Task 1–16 |

### Type consistency

- `AuthSession` 实现 `TokenProvider`（`getToken`/`onUnauthorized`/`maybeRefresh`），`ApiClient` 构造参数一致。
- `HttpTransport.json/multipart` 返回 `RawResponse<T>`，`ApiClient` 解包一致。
- `endpoints.generate` 使用 `PickedFile`；`FilePort.pick` 返回 `PickedFile[]`。
- `CoachSession`/`CoachMessage` 在 core/coach 与 store 中同名同字段。
- `QuizQuestion` 在 core/quiz 与 QuizPage 中同名同字段。
- `buildPlot` 返回 `{ card, x, y, color }`；MasteryMapPage 按此渲染。
- 路由名与 `AppShell` 导航判断一致。

### Placeholder scan

- 无 TBD/TODO。
- 所有 UI Task 均给出组件结构、状态、接口与关键 CSS；颜色/圆角引用 `tokens.css`。
- Task 8/9/10/11/12 的具体内容由 spec 的视觉与功能清单约束，不含“按需实现”类描述。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-31-prepdot-web-phase1.md`.
