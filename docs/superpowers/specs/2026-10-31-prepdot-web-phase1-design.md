# PrepDot 多端化 Phase 1：Web 端设计

- 日期：2026-10-31
- 状态：已确认，进入实施
- 范围：Web 端上线 + 为桌面端预留 adapter 边界
- 不在本阶段：Tauri / Electron、桌面安装包、离线同步、iOS 改动

## 1. 目标

1. `https://prepdot.site` 打开即是可用的 Web 应用，HTTPS，手机浏览器可用。
2. Web 端在视觉和功能上尽量复刻 iOS 端，100% 复用现有 REST API，不新写业务逻辑。
3. 页面逻辑写成与浏览器 API 解耦的纯 TypeScript 模块；存储、通知、文件、HTTP 全部通过 adapter 接口访问。
4. 后端只做一处加法式改动（放行 CORS 预检 `OPTIONS`），不改任何现有接口语义，不动 iOS。
5. 产出 `DEPLOY-WEB.md`、README 多端章节、可回滚的部署方式、含 FSRS 历史的演示账号。

## 2. 现状核实结论

### 2.1 后端

- Spring Boot 3.3.4 + MyBatis-Plus + MySQL 8 + Flyway，JWT 鉴权，响应统一为 `{code, message, data}`。
- 白名单：`/api/health`、`/api/auth/login`、`/api/auth/register`。
- Token 有效期 7 天，滑动续期：`POST /api/auth/refresh`。
- 业务错误常见形态是 HTTP 200 + `code != 200`，前端必须判断 `code`。
- 文件上传限制：单文件 20MB，单请求 20MB。
- 所有 Web 所需能力均已有接口，不需要新增业务接口。

### 2.2 iOS

- iOS 实际请求 `https://api.adeer.site/prepdot/api`，经 Caddy 反代到同一个 `prepdot-backend` 容器，与 `api.prepdot.site` 共用同一数据库。
- iOS 已有页面：登录/注册、今日复习、知识树、卡组详情、卡片 CRUD、卡片笔记、选择题模式、掌握度地图、AI 学习教练、复习中问 AI、AI 生成卡组、精选卡包、个人中心、每日提醒、注销账号。
- Web 按同样的信息架构复刻，不新增 iOS 没有的业务概念。

### 2.3 线上部署

- DNS：`prepdot.site`、`www.prepdot.site`、`api.prepdot.site` 均解析到 `62.234.146.153`。
- 80/443 由 Docker 中的 Caddy 2（容器 `adeer-caddy-1`）监听并自动签发 HTTPS。
- `prepdot.site` 当前是静态宣传页，根目录映射为容器内 `/srv/legal/prepdot-site`，宿主机路径 `/opt/adeer/legal/prepdot-site`。
- `api.prepdot.site` 反代 `prepdot-backend:8080`。
- 线上没有 nginx。本阶段沿用 Caddy，不引入第二个反向代理。

### 2.4 已确认的阻塞问题

浏览器跨域请求会先发 `OPTIONS` 预检，预检按规范不携带 `Authorization`。当前 `JwtAuthFilter` 在 CORS 处理之前拦截并返回 `401`。实测：

```text
OPTIONS https://api.prepdot.site/api/plan/review
-> 401 {"code":401,"message":"缺少登录凭证"}
```

生产 Web 走同源 `/api` 可以完全绕开跨域；同时仍需放行 `OPTIONS`，供本地开发（`localhost:5173`）和 Phase 2 桌面端使用。

## 3. 总体架构

```text
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ iOS (SwiftUI)    │   │ Web (Vue 3)      │   │ Desktop (Phase2) │
│ 现有代码不改      │   │ 同源 /api        │   │ Tauri/Electron   │
└────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
         │                      │                      │
         │ api.adeer.site       │ prepdot.site/api     │ api.prepdot.site
         └──────────────┬───────┴──────────────────────┘
                        ▼
                ┌───────────────┐
                │ Caddy 2 :443  │  HTTPS 自动证书
                └───────┬───────┘
                        │ /api/*
                        ▼
                ┌───────────────┐
                │ Spring Boot   │  JWT + REST + SSE
                └───────┬───────┘
                        ▼
                ┌───────────────┐
                │ MySQL 8       │
                └───────────────┘
```

- Web 生产环境请求 `https://prepdot.site/api/...`，同源，不触发 CORS。
- iOS 继续请求 `https://api.adeer.site/prepdot/api/...`，行为不变。
- 桌面端 Phase 2 请求 `https://api.prepdot.site/api/...`，依赖本阶段修好的 `OPTIONS` 预检。

## 4. 技术栈

| 层 | 选择 | 理由 |
|---|---|---|
| 框架 | Vue 3 + `<script setup>` | 用户熟悉，排错成本低 |
| 构建 | Vite 7 + TypeScript | 快、产物小、静态部署简单 |
| 路由 | Vue Router 4 | 官方方案，支持 history 模式 |
| 状态 | Pinia（仅 UI 层） | 登录态、Toast 等跨页状态；核心逻辑仍在纯 TS |
| 样式 | 手写 CSS + CSS 变量 | 精确复刻 iOS 视觉，不引入 UI 组件库 |
| 图标 | `lucide-vue-next` | 免费、MIT、风格接近 SF Symbols |
| Markdown | `markdown-it`（`html: false`） | 渲染卡片/教练回答，禁用原始 HTML |
| 图表 | 自绘 SVG | 复刻 iOS Charts 的柱状图与散点图，产物小 |
| 单测 | Vitest | 纯 TS 模块直接测 |
| 端到端 | Playwright（移动视口冒烟） | 登录、卡组、复习主链路 |

不引入 Tailwind、Element Plus、ECharts、Pinia 之外的全局状态库。

## 5. 代码结构

新增 `prepdot-web/`：

```text
prepdot-web/
  index.html
  package.json
  vite.config.ts
  tsconfig.json
  eslint.config.js
  scripts/
    deploy-web.sh              # 构建 + rsync + 切换目录
  src/
    main.ts
    App.vue
    router/
      index.ts
    core/                      # 纯 TS：禁止 import Vue / DOM / adapters/web
      api/
        types.ts               # 与 Java DTO 对应的类型
        client.ts              # ApiClient：解包 {code,message,data}、401、续期
        endpoints.ts           # 所有接口函数
        sse.ts                 # SSE 分行/分块解析
      session/
        session.ts             # 登录、注册、续期、过期判断、登出
      auth/
        token.ts               # JWT payload 解析（只读 exp）
      decks/
        tree.ts                # 扁平数组 -> 树、搜索过滤、后代集合
      review/
        session.ts             # 复习队列状态机、评分提交、完成判断
      coach/
        sessions.ts            # 本地会话模型、标题生成、工具结果提取
        progress.ts            # 工具名 -> 中文进度文案
      ai/
        preview.ts             # AI JSON 校验、多文件合并
      quiz/
        quiz.ts                # 选择题生成与计分
      graph/
        plot.ts                # 难度/稳定性 -> 坐标、抖动、颜色
      stats/
        week.ts                # 近 7 天补齐
      format/
        date.ts                # 服务端 LocalDateTime 展示（按 Asia/Shanghai）
        text.ts                # 分号编号换行、类型归一化
        markdown.ts            # markdown-it 封装，输出安全 HTML
      errors.ts                # ApiError、网络错误文案
    adapters/
      types.ts                 # StoragePort / HttpTransport / FilePort /
                               # NotificationPort / ClipboardPort / Clock
      web/
        storage.ts             # localStorage
        http.ts                # fetch：JSON、multipart、SSE 流
        file.ts                # input[type=file] + File.arrayBuffer
        notification.ts        # Web Notification + 页面内定时器
        clipboard.ts           # navigator.clipboard
        clock.ts
      desktop/
        README.md              # Phase 2 映射说明，不实现
        storage.ts             # 抛 NotImplementedError 的空壳
        file.ts
        notification.ts
    ui/
      layout/
        AppShell.vue           # 侧边栏 + 移动端底部 Tab
        PageHeader.vue
      components/
        AuroraBackground.vue
        BottomSheet.vue
        Modal.vue
        ToastHost.vue
        ProgressRing.vue
        ProgressBar.vue
        SegmentedControl.vue
        EmptyState.vue
        ErrorState.vue
        LoadingState.vue
        MarkdownText.vue
        StatCard.vue
        TypeBadge.vue
        Icon.vue
        charts/
          BarChart.vue
          ScatterChart.vue
      pages/
        LoginPage.vue
        ReviewPage.vue
        DecksPage.vue
        DeckDetailPage.vue
        CoachPage.vue
        ProfilePage.vue
        ReminderPage.vue
        DeleteAccountPage.vue
        MasteryMapPage.vue
        QuizPage.vue
        AiGeneratePage.vue
        CommunityPage.vue
      sheets/
        CreateDeckSheet.vue
        EditDeckSheet.vue
        CardFormSheet.vue
        CardNoteSheet.vue
        CoachChatSheet.vue
        PackDetailSheet.vue
      stores/
        auth.ts                # Pinia：包 core/session + StoragePort
        toast.ts
        coachSessions.ts       # 包 core/coach + StoragePort
    styles/
      tokens.css
      base.css
      components.css
```

### 5.1 边界规则

- `core/**` 禁止 import `vue`、`vue-router`、`pinia`、`adapters/web/**`、`window`、`document`、`localStorage`、`fetch`。
- `ui/**` 禁止直接调用 `fetch`、`localStorage`、`navigator.*`；只能调用 `core/**` 和 `adapters/types.ts` 暴露的端口。
- 通过 ESLint `no-restricted-imports` + `no-restricted-globals` 强制。
- 组装只在 `src/main.ts` 和 Pinia store 内完成：选择 `adapters/web` 实现注入 `core`。

### 5.2 Adapter 接口

```ts
interface StoragePort {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  remove(key: string): Promise<void>
}

interface HttpTransport {
  json<T>(req: ApiRequest): Promise<ApiResponse<T>>
  multipart<T>(req: MultipartRequest): Promise<ApiResponse<T>>
  stream(req: ApiRequest): AsyncIterable<SseEvent>
}

interface PickedFile {
  name: string
  mime: string
  size: number
  bytes(): Promise<ArrayBuffer>
}

interface FilePort {
  pick(opts: { multiple: boolean; accept: string[] }): Promise<PickedFile[]>
}

interface NotificationPort {
  permission(): Promise<'granted' | 'denied' | 'default'>
  requestPermission(): Promise<'granted' | 'denied' | 'default'>
  scheduleDaily(time: string, target: number): Promise<void>
  cancelDaily(): Promise<void>
}

interface ClipboardPort {
  readText(): Promise<string>
}

interface Clock {
  now(): number
}
```

Phase 2 只新增 `adapters/desktop/*` 实现并在组装处替换，`core` 与 `ui` 不改。

## 6. 视觉复刻规范

### 6.1 设计 Token

| Token | 值 |
|---|---|
| 主色 indigo | `#4F46E5` |
| 辅色 purple | `#7C3AED` |
| 强调 pink | `#D946EF` |
| 成功 green | `#10B981` |
| 警告 orange | `#F59E0B` |
| 错误 red | `#EF4444` |
| 填空 teal | `#14B8A6` |
| 浅色背景 | `#F7F6FC` |
| 浅色卡片 | `#FFFFFF` |
| 深色背景 | `#0A0A24` |
| 深色卡片 | `rgba(255,255,255,0.08)` |
| 主文字（浅） | `#260D59` |
| 次文字（浅） | `#6B5A8E` |
| 圆角 | 12 / 16 / 20 / 24px |
| 阴影 | `0 4px 16px rgba(38,13,89,.08)` |
| 触控目标 | ≥ 44×44px |

- 字体栈：`-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Segoe UI", sans-serif`。
- 数字使用 `font-variant-numeric: tabular-nums`；标题可用 `ui-rounded`（支持的平台）。
- 支持 `prefers-color-scheme: dark`，配色对齐 iOS 深色模式。
- 支持 `prefers-reduced-motion: reduce`，关闭极光动画和翻转动画。

### 6.2 关键视觉组件

1. **极光背景**：3 个高斯模糊色块（indigo / purple / pink），20–30 秒缓慢位移；用于今日复习与完成页。
2. **进度环**：SVG 圆环，indigo→purple→pink 角向渐变，中心显示待复习数与完成百分比。
3. **翻转卡片**：CSS 3D `rotateY`，正面问题、背面答案；背面保留问题小字；答案解析支持 Markdown；选择题选项标出正确项；笔记用 teal 底色块。
4. **评分按钮**：四档，Again 红、Hard 橙、Good 绿、Easy indigo；主标签 + 辅助说明（重新学/明天/2–4 天/5–10 天）。
5. **玻璃卡片**：`background: rgba(255,255,255,.58)` + `backdrop-filter: blur(16px)` + 1px 白色描边，用于复习概览、卡组进度、掌握度详情。
6. **底部 Tab Bar**：4 项，49px 高 + `env(safe-area-inset-bottom)`；选中 indigo，未选次文字色。
7. **侧边栏**：≥900px 时替换底部 Tab，宽 240px，顶部品牌，底部用户信息。
8. **Sheet**：移动端从底部滑入、最大高度 90vh；桌面端居中 Modal；带遮罩、Esc 关闭、焦点锁定。
9. **Toast**：底部胶囊，2.5 秒自动消失，用于导入成功/失败。
10. **骨架/加载**：居中 spinner + 文案，避免布局跳动。

### 6.3 响应式断点

| 宽度 | 布局 |
|---|---|
| < 640px | 单列；底部 Tab；全宽卡片；Sheet 底部弹出 |
| 640–899px | 单列加宽，最大 720px；底部 Tab |
| ≥ 900px | 左侧栏 + 主内容；知识树为 360px 列表 + 详情双栏 |
| ≥ 1280px | 主内容最大 1100px 居中，留白增加 |

## 7. 功能复刻清单

### 7.1 路由

| 路由 | 页面 | 来源 iOS |
|---|---|---|
| `/` | 重定向到 `/review` | `ContentView` 默认 Tab |
| `/login` | 登录/注册 | `LoginView` |
| `/review` | 今日复习（默认首页） | `ReviewView` + `PlanOverviewView` |
| `/decks` | 知识树 | `DecksView` 主列 |
| `/decks/:id` | 卡组详情（子卡组或卡片） | `DeckDetailView` |
| `/decks/:id/quiz` | 选择题模式 | `QuizModeView` |
| `/coach` | AI 学习教练 | `LearningCoachView` |
| `/profile` | 我的 | `ProfileView` |
| `/profile/reminder` | 每日提醒 | `NotificationSettingsView` |
| `/profile/delete` | 注销账号 | `DeleteAccountView` |
| `/graph` | 掌握度地图 | `KnowledgeGraphView` |
| `/generate` | AI 生成卡组 | `AIGenerateView` |
| `/community` | 精选卡包 | `CommunityView` |

未登录访问任何业务路由 → 重定向 `/login`。

### 7.2 登录/注册

- 品牌区：渐变大脑图标、PrepDot、副标题。
- 登录/注册切换；注册多一个昵称输入。
- 用户名、密码（≥6 位）、错误提示、加载态、禁用态。
- 额外的“体验演示账号”按钮：填入 `demo` / `PrepDot2026` 并登录。
- 登录成功保存 token 和用户信息；启动时恢复并静默续期。

### 7.3 今日复习

**概览页**
- 日期（`M月d日 EEEE`，中文）。
- 进度环：待复习张数、完成百分比。
- 两个统计胶囊：今日进度 `completed/total`、预计时间。
- 卡组进度列表：每项标题、剩余/已完成、`completed/total`、进度条；完成项绿色勾。
- 主按钮：开始复习 / 继续复习；无到期卡片时展示空状态并可去知识树。
- 下拉刷新（移动端）/刷新按钮（桌面端）。

**复习会话**
- 顶部 `当前/总数`、实时记忆度、进度条。
- 卡片翻转；翻面前提示“点击卡片查看答案”。
- 翻面后操作条：问 AI、编辑、笔记。
- 四档评分；提交中禁用；失败提示“本次评分未记录，请重试”，可重试。
- 评分成功进入下一张；最后一张进入完成页。
- 卡片内容/笔记编辑后就地刷新当前卡。
- 退出复习需确认（避免误触丢失进度）。

**完成页**
- 庆祝文案；今日小结：总张数、按卡组分组；查看卡组按钮。

**复习中问 AI**
- 顶部显示当前卡片问题。
- 快捷问题：讲透这道题 / 面试官会怎么追问 / 出一道同考点题目。
- 调用 `POST /agent/coach`，`mode=CARD_QA`；把题目与答案拼进消息。
- 显示工具调用摘要。
- 无流式（与 iOS 一致）。

### 7.4 知识树

**列表**
- 搜索框：按标题、分类、描述过滤；保留命中子节点。
- 层级树：展开/收起；节点显示标题、分类、描述、卡片数、到期数、记忆度、记忆度进度条；有子节点用树图标，否则用卡片堆图标。
- 右侧/悬浮操作：编辑、删除（删除需确认）。
- 工具栏：
  - 掌握度地图入口。
  - `+` 菜单：手动新建卡组、AI 上传生成、导入精选卡包。
- 空状态、加载失败可重试。

**卡组详情**
- 有子卡组：列出子卡组（同样统计信息），可逐层进入。
- 无子卡组：卡片列表；每行类型徽标（选择/填空）、问题、答案或选项、记忆度、复习次数。
- 点击卡片打开编辑；删除卡片；管理模式支持多选与批量删除。
- 底部“添加卡片”按钮。
- 卡片 ≥2 时提供“测验”入口。
- 卡组编辑：标题、分类、描述、父节点（depth<2），保存即更新/移动。
- 没卡片时空状态。

**新建/编辑卡组**
- 字段：标题（必填）、分类（默认“综合”）、描述、父节点（根节点或 depth<2 的卡组）。
- 新建类型固定 `自建`。

**新建/编辑卡片**
- 三种类型：问答 / 选择题 / 填空。
- 问答：问题 + 答案。
- 选择题：问题 + 2–4 个选项 + 单选正确答案；提交时 `answer` 存正确选项文本，`options` 存 JSON 数组字符串。
- 填空：问题（含 `____`）+ 答案（多个答案用分号分隔）。
- Markdown 编辑工具条：加粗、列表、编号、代码；插入填空符。
- 编辑时预填；保存后刷新列表。

**卡片笔记**
- 独立于原始问题/答案；可清空；显示字数；保存后更新当前卡。

### 7.5 AI 生成卡组

- 两种输入模式：上传文件 / 粘贴文字。
- 文件：多选，最多 10 个；支持 PDF、DOCX、PPTX、TXT、MD；显示文件名和大小；可移除。
- 粘贴：文本框、从剪贴板粘贴、字数、清空。
- 卡组名称必填。
- 卡片数量：默认“自动”（传 0）；手动 5–100，步长 5。
- 答案详细程度：5 档（极简/简洁/标准/详细/极详），映射到后端 `detailHint`。
- AI 设置：默认系统 AI；可选自定义 API Key（仅当前请求传递，不持久化）。
- 生成中：进度文案；多文件逐个调用并显示“第 i/n 个文件”；可取消（AbortController）。
- 预览：根卡组信息、子卡组与卡片树、总卡片数；确认导入 / 重新生成 / 取消。
- 导入成功页；返回知识树并刷新。
- 多文件结果按 iOS 逻辑合并子卡组，根标题使用用户输入，分类/描述取第一个文件。

### 7.6 精选卡包

- 列表：分类色块与 emoji、标题、卡片数、描述、标签。
- 详情：描述、标签、全部卡片 Q/A 预览。
- 一键导入；成功 Toast；列表刷新。
- 分类颜色映射：Java 橙、Spring 绿、数据库 蓝、网络 紫、缓存 红、算法 indigo。

### 7.7 AI 学习教练

- 顶部安全说明条。
- 空状态：标题、说明、4 个快捷问题。
- 消息流：用户右侧 indigo 气泡；教练左侧浅色气泡；Markdown。
- 流式：显示进度文案（工具名转中文）；最终结果显示工具摘要。
- 图表：若 `get_review_trend` 有结果，渲染近 7 天柱状图；若 `get_weak_cards` 有结果，渲染前 8 张薄弱卡片横向条形图。
- 失败回退：SSE 失败自动调用非流式 `/agent/coach`；再失败显示友好错误。
- 历史会话：本地持久化（StoragePort）；可新建、切换、删除；标题取首条消息前 24 字。
- 安全边界：补强卡片仅预览，不自动写入。

### 7.8 我的

- 头像：昵称首字、`avatarColor` 渐变。
- 昵称、`@username`。
- 连续打卡卡：今日目标进度环、`streakDays`、今日已复习/目标。
- 四格统计：卡组、卡片、总复习、平均记忆度。
- 近 7 天复习柱状图（补零）。
- 记忆度分布条与图例（待加强/进行中/已掌握）。
- 设置：每日提醒、退出登录、注销账号。
- 注销：红色警告、密码确认、失败提示；成功后清空登录态。

### 7.9 每日提醒（Web 限制）

- 开关、时间选择、权限状态。
- 使用 Web Notification API 请求权限。
- 页面打开期间用定时器在设定时间弹通知；关闭标签页后无法保证提醒。
- 页面明确说明：“浏览器版仅在页面打开时提醒；桌面端将在 Phase 2 提供系统级提醒。”
- 设置存 `StoragePort`，键与 iOS 语义一致。

### 7.10 掌握度地图

- 只绘制已复习（`difficulty`、`stability` 非空）的卡片。
- 根卡组横向胶囊选择器。
- 统计条：已复习/总卡片、待复习数。
- SVG 散点：
  - X = 难度 1–10；
  - Y = `log10(stability)` 归一化；
  - 颜色 = 实时记忆度，粉→紫；
  - 按卡片 id 生成确定性抖动，避免重叠。
- 点击节点显示详情面板：掌握度、问题、难度、稳定性、复习次数、类型。
- 图例、空状态、加载态。
- 用 SVG + 绝对定位点，支持移动端点击。

### 7.11 选择题模式

- 仅叶卡组且卡片 ≥2 时入口可见。
- 随机取最多 10 张；每题 4 个选项（正确答案 + 3 个其他卡答案），随机排序。
- 选择后立即判分并显示正确答案；下一题；结果页显示得分环、正确率、评价、再来一次/退出。
- 纯本地逻辑，不写复习记录（与 iOS 一致）。

## 8. API 清单与调用映射

| 功能 | 接口 |
|---|---|
| 注册 / 登录 / 续期 | `POST /auth/register`、`POST /auth/login`、`POST /auth/refresh` |
| 个人统计 | `GET /auth/stats` |
| 更新资料 | `PUT /auth/profile`（Web 暂不做 UI，仅 core 支持） |
| 注销 | `DELETE /auth/account` |
| 卡组列表 | `GET /decks` |
| 新建 / 编辑 / 移动 / 删除卡组 | `POST /decks`、`PUT /decks/{id}`、`PUT /decks/{id}/parent`、`DELETE /decks/{id}` |
| 卡片列表 | `GET /decks/{id}/cards`、`GET /decks/{id}/cards?deep=true` |
| 新建 / 编辑 / 删除卡片 | `POST /cards`、`PUT /cards/{id}`、`DELETE /cards/{id}` |
| 批量删除 | `DELETE /cards/batch?ids=1&ids=2` |
| 卡片笔记 | `PUT /cards/{id}/note` |
| 今日计划 | `GET /plan/today` |
| 提交评分 | `POST /plan/review` |
| 今日小结 | `GET /plan/summary` |
| AI 教练 | `POST /agent/coach`、`POST /agent/coach/stream`、`GET /agent/runs/{id}` |
| AI 生成 / 导入 | `POST /ai/generate`（multipart）、`POST /ai/import`（原始 JSON 字符串） |
| 精选卡包 | `GET /community/packs`、`GET /community/packs/{id}`、`POST /community/packs/{id}/import` |
| 健康检查 | `GET /health` |

约定：

- `ApiClient` 统一解包 `{code,message,data}`；`code !== 200` 抛 `ApiError(message, code)`。
- HTTP 401 统一清空会话并跳转登录。
- 请求成功后按 iOS 相同阈值（剩余不足 3.5 天）静默续期；并发请求共享同一个续期 Promise。
- 日期字段是服务端 `LocalDateTime` 字符串（Asia/Shanghai，无时区）。展示时按字符串各字段解析，不交给浏览器按本地时区猜测。

## 9. 后端改动

只改一处：`prepdot-backend/src/main/java/com/prepdot/config/JwtAuthFilter.java`。

```java
// 浏览器 CORS 预检不携带 Authorization；预检只做跨域协商，不执行业务。
if ("OPTIONS".equalsIgnoreCase(req.getMethod())) {
    chain.doFilter(req, resp);
    return;
}
```

影响：

- 只放行 `OPTIONS`；所有业务方法的 JWT 校验不变。
- iOS 不发送 `OPTIONS`，行为不变。
- 放行后由现有 CORS 配置返回允许来源/方法/头的响应。
- 不新增接口、不改任何 DTO、不改任何响应语义。

验证：

- 部署后用 `curl -X OPTIONS` 对 `https://api.prepdot.site/api/plan/review` 验证返回 2xx 且带 `Access-Control-Allow-Origin`。
- 用无 token 的 `GET /api/decks` 验证仍返回 401。

## 10. 部署方案

### 10.1 服务器目录

```text
/opt/adeer/
  Caddyfile                         # 线上 Caddy 配置
  legal/prepdot-site/
    app/                            # Web 构建产物（新）
    app.prev/                       # 上一版，用于回滚（新）
    welcome/                        # 现有宣传页（新位置）
      index.html
      site.css
      site.js
      app-icon.png
```

宣传页文件从当前 `prepdot-site/` 根目录移动到 `welcome/`，根路径让给 Web App。

### 10.2 Caddy 配置

在现有 `prepdot.site, www.prepdot.site` 块中改为：

```caddyfile
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

- `api.prepdot.site` 保持不变。
- `api.adeer.site` 保持不变，iOS 不受影响。
- `try_files` 保证 Vue Router history 模式刷新不 404。

### 10.3 发布步骤

1. 本地 `pnpm install && pnpm build`。
2. 上传到服务器临时目录：`/opt/adeer/legal/prepdot-site/app.new/`。
3. 服务器执行：
   - `mv app app.prev`（若存在）
   - `mv app.new app`
4. 首次部署前备份 Caddyfile：`Caddyfile.backup-YYYYMMDD-HHMMSS`。
5. `docker exec adeer-caddy-1 caddy validate --config /etc/caddy/Caddyfile`
6. `docker exec adeer-caddy-1 caddy reload --config /etc/caddy/Caddyfile`
7. 验证：
   - `https://prepdot.site/` 返回 Web App；
   - `https://prepdot.site/welcome/` 返回宣传页；
   - `https://prepdot.site/api/health` 返回 200；
   - `https://api.prepdot.site/api/health` 返回 200。

发布脚本 `prepdot-web/scripts/deploy-web.sh` 封装 1–3 和 7；Caddyfile 只在首次部署手动改一次。

### 10.4 回滚

- Web：`mv app app.bad && mv app.prev app`。
- Caddy：恢复最近备份的 Caddyfile，`caddy validate` 后 `caddy reload`。
- 后端：GitHub Actions 重新部署上一个 main 提交（现有流程）。
- 回滚不影响 MySQL 数据；不做数据库迁移。

### 10.5 后端发布

- 现有 GitHub Actions 在推送到 `main` 且改动 `prepdot-backend/**` 时自动测试、rsync、重建容器。
- 本阶段后端改动只有 `JwtAuthFilter` 一行，随现有流程发布。
- 发布前先合并/确认 `feat/parser-integration` 的 3 个未上线提交，避免只上线半套改动。

## 11. 演示账号与数据

- 账号：`demo` / `PrepDot2026`。
- 数据：3 个根卡组（Java 后端面试、Spring Boot、计算机网络），共 12 个子卡组、60 张卡。
- FSRS 状态：
  - 18 张今天到期（复习页有内容）；
  - 24 张未来到期，覆盖不同难度/稳定性；
  - 18 张从未复习（难度/稳定性为空，掌握度地图不绘制）。
- 复习历史：过去 14 天每天 3–8 条 `review_record`，让个人中心的近 7 天柱状图、连续打卡、教练趋势工具有真实数据。
- 重置脚本：`/opt/prepdot/demo-seed.sql` + `/opt/prepdot/reset-demo.sh`。
  - 只删除 `user.username = 'demo'` 关联的卡组、卡片、复习记录、每日计划、Agent 运行；
  - 用固定 BCrypt 密码哈希重建 demo 用户；
  - 幂等，可重复执行；
  - cron 每日 04:17 执行。
- 真实用户数据不受影响。
- 登录页提供“体验演示账号”按钮，自动填入并登录。

## 12. 测试与验收

### 12.1 自动化

- Vitest：
  - `ApiClient` 解包成功/业务错误/401；
  - token 过期判断与续期阈值；
  - SSE 分块、多行 data、progress/result/error；
  - 卡组树构建、搜索过滤、循环父节点防护；
  - 复习队列推进与完成；
  - AI 预览 JSON 校验与多文件合并；
  - 选择题生成与计分；
  - 近 7 天补零；
  - 日期格式化（固定 Asia/Shanghai 语义）；
  - 掌握度坐标归一化与抖动确定性。
- 构建门槛：`vue-tsc --noEmit`、ESLint、`pnpm build` 全部通过。
- Playwright 冒烟（移动视口 390×844）：
  - 登录 demo；
  - 知识树加载；
  - 进入复习、翻面、评分；
  - 个人中心统计加载。
- 上传→AI 生成链路因调用外部模型，采用手动验收，不做 CI 自动化。

### 12.2 人工验收

1. 手机 4G 打开 `https://prepdot.site`：
   - 登录 demo；
   - 知识树可见；
   - 进入复习，翻面、评分、完成；
   - AI 教练提问并收到流式回答；
   - 上传一份 TXT/MD，生成并导入；
   - 刷新后新卡组仍在。
2. iOS 模拟器用同一账号登录，下拉刷新，能看到 Web 新建的卡组。
3. 桌面浏览器 1440px 检查侧边栏、双栏知识树、Modal。
4. 手机 390×844 检查底部 Tab、安全区、表单、Sheet。
5. 断网/接口失败时错误提示可读，不白屏。
6. 刷新任意子路由不 404。

## 13. 风险与约束

1. **仓库中的 DeepSeek Key**：`prepdot-backend/src/main/resources/application.yml` 有明文 `system-key`。若仓库公开，应作废并改为环境变量。本阶段不擅自修改，但会在交付说明中列为高优先级事项。
2. **公开 demo 的 AI 成本**：demo 可被任意访客使用 AI 生成；每天重置数据不会重置额度。需要监控 DeepSeek 用量。
3. **浏览器通知限制**：关闭标签页后无法保证每日提醒，页面会明确说明；系统级提醒留到 Phase 2。
4. **Token 存储**：使用 localStorage 以支持持久登录；通过禁止未净化 HTML、`markdown-it html:false`、安全响应头降低 XSS 风险。CORS 不构成服务端鉴权，JWT 仍是唯一访问控制。
5. **时间语义**：后端时间无时区，统一按 Asia/Shanghai 展示；跨时区用户看到的是服务器时间。
6. **上传限制**：单文件 20MB；多文件时逐个请求，避免超过请求上限。
7. **AI 生成耗时**：10–60 秒；提供进度与取消，避免用户误以为卡死。
8. **无 nginx**：部署沿用 Caddy；文档中明确说明，避免后续误装。

## 14. Phase 2 预留

- `adapters/desktop/` 只放空壳和映射说明，不实现。
- 桌面端 Phase 2 需要：
  - `StoragePort` → SQLite（本地缓存卡片/卡组/计划）；
  - `HttpTransport` → 在线请求 + 本地缓存读写；
  - `FilePort` → 系统文件选择器；
  - `NotificationPort` → 系统通知；
  - 冲突策略：服务端为准，本地离线写操作排队回放。
- 页面与 `core` 不重写；只替换 adapter 组装。
- Tauri 2 vs Electron 的选型在 Phase 1 验收通过后单独做对比，不在本阶段决定。

## 15. 实施顺序

1. 后端 `OPTIONS` 放行 + 测试/部署验证。
2. Web 工程脚手架、设计 Token、adapter 接口与 web 实现、ESLint 边界。
3. `core` API 客户端、会话、类型、错误处理、单测。
4. 登录页、App Shell（移动 Tab + 桌面侧栏）、路由守卫。
5. 今日复习（概览、会话、完成页、评分、笔记、问 AI）。
6. 知识树（树、搜索、卡组 CRUD、卡片 CRUD、批量删除、选择题）。
7. AI 生成、精选卡包。
8. 学习教练（SSE、历史会话、图表）。
9. 个人中心（统计、图表、提醒、注销）、掌握度地图。
10. 视觉打磨、响应式、暗色模式、无障碍。
11. 部署 Caddy + 静态资源、demo 数据、DEPLOY-WEB.md、README。
12. 手机 4G + iOS 模拟器交叉验收。

## 16. 交付物

- `prepdot-web/` 完整源码与构建产物说明。
- `DEPLOY-WEB.md`：架构图、部署步骤、Caddy 配置、演示账号、重置脚本、回滚。
- `README.md` 多端章节：iOS / Web / 桌面端路线、开发与部署入口。
- `docs/superpowers/specs/2026-10-31-prepdot-web-phase1-design.md`（本文件）。
- 后端 `JwtAuthFilter` 一处改动。
- 服务器上的 demo 重置脚本与 cron。
