# 序岛（PrepDot）

以知识树组织内容、以 FSRS 安排复习的 AI 记忆卡应用。

上传学习资料（TXT / Markdown / PDF / DOCX / PPTX），AI 拆解成"根卡组 → 子卡组 → 卡片"的层级结构；知识树展示各分支的卡片数量、到期数量和聚合掌握度；FSRS-4.5 根据真实复习表现安排下一次复习；AI 学习教练基于记忆状态数据做诊断并生成针对性补充卡片。

产品需求见 [PRD.md](PRD.md)，技术方案见 [技术方案.md](技术方案.md)。

## 核心能力

- **FSRS-4.5 间隔重复**：手写 Java 实现（非第三方库），纯函数算法模块与 Spring/数据库解耦，以 Difficulty / Stability / Retrievability 三个连续变量对每张卡片单独建模；TDD 开发，含不变量测试与 golden master 回归测试。
- **自研 Agent 编排层**：手写 ReAct 工具循环（不依赖 LangChain / Spring AI），`AgentTool` 抽象 + 工具注册分发；Generator + Critic 自我修正流水线（生成 → 质检 → 携带意见重写）；执行轨迹落库（`agent_run` / `agent_step`）支持完整回放，SSE 流式输出。学习教练与卡片生成两个任务共用同一套基建。
- **知识树**：复用 `Deck.parent_id` 自关联（depth 0/1/2）三层结构，不新增数据模型；节点聚合卡片总数、今日到期数与基于 FSRS 实时掌握度的平均值。
- **AI 生成卡组**：多格式文本抽取（PDFBox / POI）→ 生成结构化 JSON → 客户端预览确认 → 单事务入库，AI 不直接覆盖已有内容。
- **掌握度地图**：难度 × 稳定性 × 实时记忆度散点图，定位"哪些卡片难且不稳定"，与知识树（"薄弱内容在哪个分支"）互补。

## 技术栈

| 端 | 技术 |
|---|---|
| 后端 | Java 17、Spring Boot 3.3.4、MyBatis-Plus、MySQL 8、Flyway、JWT（滑动续期）、SSE |
| 客户端 | iOS：SwiftUI（iPhone / iPad）、Charts、NavigationSplitView + OutlineGroup；Web：Vue 3、Vite、TypeScript |
| 部署 | GitHub Actions → Docker Compose（服务器本机构建）→ Caddy 反代 HTTPS；Web 静态站点由 Caddy 直接提供 |

## 项目结构

```text
prepdot-backend/    Spring Boot 后端（含 Flyway 迁移与单元测试）
prepdot-ios/        SwiftUI 客户端（PreDot/PrepDot.xcodeproj）
prepdot-web/        Web 客户端（Vue 3 + Vite + TypeScript，Phase 1）
deploy/             Caddy 反代配置（api.prepdot.site 与 Web 站点）
docs/               FSRS 设计与实现计划、简历技术要点
prepdot.sh          本地一键启动脚本
docker-compose.production.yml   生产编排（MySQL + 后端，三网络隔离）
```

## 多端架构

| 端 | 状态 | 技术 / 地址 |
|---|---|---|
| iOS | 线上运行 | SwiftUI（iPhone / iPad），API `https://api.prepdot.site` |
| Web | Phase 1 已完成 | Vue 3 + Vite + TypeScript，<https://prepdot.site> |
| 桌面端 | Phase 2 尚未开始 | macOS / Windows；Tauri 或 Electron 方案待定 |

`prepdot-web/` 常用命令（需要 Node.js 与 pnpm）：

```bash
cd prepdot-web
pnpm install    # 安装依赖
pnpm dev        # 本地开发，默认 http://localhost:5173
pnpm test       # Vitest 单元测试
pnpm build      # 类型检查并构建到 dist/
pnpm lint       # ESLint
pnpm e2e        # Playwright 端到端测试
```

开发模式下 `/api` 会被代理到 `http://127.0.0.1:8080`（可用 `VITE_DEV_API_TARGET` 覆盖）；
生产环境 Web 与 API 同源，均由 Caddy 反代。Web 端的首次部署、日常发布、回滚与常见问题见
[DEPLOY-WEB.md](DEPLOY-WEB.md)。

Web 端复用现有后端接口，不改变 iOS 端行为；桌面端（Phase 2）尚未开始。

## 本地启动

首次运行前，将 `prepdot-backend/src/main/resources/application.yml.example` 复制为
`application.yml`，并填写 MySQL、JWT 和 AI 配置。之后在项目根目录执行：

```bash
./prepdot.sh start    # 启动 MySQL、后端和 iOS App
./prepdot.sh stop     # 停止整个项目
```

脚本默认优先复用已启动的 iPhone 模拟器；没有已启动设备时使用
`iPhone 17 Pro Max`，并自动构建、安装和打开 App。停止时只退出 App，
保留模拟器运行。

后端默认地址为 <http://127.0.0.1:8080>。可通过 `BACKEND_PORT` 修改后端端口，
通过 `SIMULATOR_NAME` 或 `SIMULATOR_UDID` 指定模拟器。

## 测试与部署

```bash
cd prepdot-backend && mvn test
```

推送到 `main`（改动 `prepdot-backend/**` 或 compose 文件）会触发 GitHub Actions：
CI 内跑测试 → rsync 源码到服务器 → 服务器上 `docker compose up -d --build` →
轮询健康检查直至通过。生产密钥全部经 `.env.production` 环境变量注入，不入仓库。
