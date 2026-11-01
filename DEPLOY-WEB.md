# Web 端生产部署指南

本文面向不熟悉运维的同学，从零解释 Web 端（`prepdot-web/`）如何上线、如何发布、出问题怎么回滚。
照着做即可；每条命令都可以直接复制。

- Web 应用地址：<https://prepdot.site>
- 旧的宣传/法律落地页：<https://prepdot.site/welcome/>
- 后端 API（iOS 也用它）：<https://api.prepdot.site>
- 反代：Caddy 容器 `adeer-caddy-1`，宿主机配置 `/opt/adeer/Caddyfile`

> 本文只处理 Web 静态站点与 Caddy 配置。**不改 iOS 代码，也不改变后端接口契约**：
> 本分支在后端 `JwtAuthFilter` 中放行了浏览器 CORS 预检的 `OPTIONS` 请求，并新增
> 「账号注销后旧 token 失效」校验；接口路径、请求体与响应结构均未变化。

---

## 1. 整体架构

```text
                    ┌──────────────────────────────────────────────┐
                    │          Caddy（容器 adeer-caddy-1）          │
  iOS App ─────────►│  api.prepdot.site ──► /api/*                  │
                    │                                              │
  浏览器（Web）────►│  prepdot.site ─────► /api/* ──┐               │
                    │            └──────► /app 静态文件              │
                    │            └──────► /welcome/ 宣传页          │
                    │                                              │
  桌面端 ──────────►│  Phase 2（规划中，方案未定）                   │
  macOS / Windows   │  后续接入同一套 /api                          │
                    └───────────────────────────────┬──────────────┘
                                                    │ HTTP（同一 Docker 网络 prepdot_proxy）
                                                    ▼
                                        ┌───────────────────────┐
                                        │ Spring Boot 容器       │
                                        │ prepdot-backend:8080   │
                                        └───────────┬───────────┘
                                                    │
                                                    ▼
                                        ┌───────────────────────┐
                                        │ MySQL 容器             │
                                        │ prepdot-mysql:3306     │
                                        └───────────────────────┘
```

关键点：

- **同一个域名、同一个来源**：Web 端的接口请求走相对路径 `/api/...`，最终由 Caddy 转发给
  `prepdot-backend:8080`。因此生产环境**没有跨域问题**，也不需要额外的 CORS 响应头；
  后端 `JwtAuthFilter` 会直接放行浏览器预检的 `OPTIONS` 请求（便于本地开发等跨域场景），
  实际业务请求仍然要求 `Authorization`。
- **静态站点**：`prepdot.site/` 的所有非 `/api/*`、非 `/welcome/*` 请求都指向
  `/srv/legal/prepdot-site/app`，由 Caddy 的 `file_server` 提供文件。
- **客户端路由**：Vue Router 使用 history 模式，像 `/decks/123` 这样的地址并不存在于磁盘上。
  Caddy 用 `try_files {path} /index.html` 兜底：找不到文件就返回 `index.html`，交给前端路由处理。
- **目录映射**：Caddy 容器里的 `/srv/legal/prepdot-site` 对应宿主机上的
  `/opt/adeer/legal/prepdot-site`（发布脚本操作的是宿主机路径）。
- **规范域名是 `prepdot.site`**：`www.prepdot.site` 会 301 到 apex。JWT 存在 localStorage，
  按 origin 隔离，如果允许用户在 www 登录，切到 `prepdot.site` 后会变成未登录状态，
  所以统一收敛到一个域名。

---

## 2. 为什么用 Caddy，而不是 nginx

1. **自动 HTTPS**：Caddy 会自动向 Let's Encrypt 申请并续期证书，不需要手写 certbot 定时任务。
   新加一个域名，基本只要写好站点块。
2. **配置短、可读**：上面的整份配置只有几十行，`try_files`、反代、跳转一眼能看懂。
3. **项目已经用它**：`api.prepdot.site` 一直由同一个 Caddy 容器提供服务，再加 Web 站点不需要
   引入第二套反代，也不用迁移现有配置。
4. **内置压缩**：`encode zstd gzip` 一行就开启压缩。

nginx 当然也能做到，但对本项目的规模来说，Caddy 需要维护的东西更少。

---

## 3. 首次部署（只做一次）

首次部署会改变 `prepdot.site` 根路径的提供内容：从"宣传/法律落地页"切换为"Web 应用"，
同时把落地页移动到 `/welcome/`。

> ⚠️ 404 窗口：从 §3.3 把落地页文件移入 `welcome/` 开始，到 §3.6 第一次发布完成之间，
> `prepdot.site` 根路径会暂时 404。建议在访问量低的时段操作，整个过程通常几分钟。

### 3.1 前置条件检查

在**本地**仓库根目录确认：

```bash
# 本地需要 pnpm、rsync
pnpm -v
rsync --version | head -n 1

# 确认能免密登录服务器
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 'echo ok'
```

如果上一条要你输密码，说明密钥没有配好，先解决 SSH 登录，再继续。

到**服务器**上确认 Caddy 容器存在，并查看宿主机目录是怎么挂进容器的：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker ps --filter name=adeer-caddy-1 --format '{{.Names}} {{.Status}}'"

ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker inspect adeer-caddy-1 --format '{{range .Mounts}}{{println .Source \" -> \" .Destination}}{{end}}'"
```

输出里应当能找到两件事（路径以实际输出为准）：

- `/opt/adeer/Caddyfile` 被挂载进容器（常见位置是 `/etc/caddy/Caddyfile`）；
- `/opt/adeer/legal` 被挂载到容器的 `/srv/legal`（站点文件由此暴露）。

如果第二条不存在，需要先给容器补上挂载，否则 Caddy 找不到站点文件。本文后续命令假设
容器内配置路径是 `/etc/caddy/Caddyfile`；**如果你的输出不同，请把命令里的路径换成实际值。**

再确认 Caddy 容器和 backend 在同一个 Docker 网络（否则 `prepdot-backend:8080` 解析不到）：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker inspect adeer-caddy-1 --format '{{range \$k,\$v := .NetworkSettings.Networks}}{{println \$k}}{{end}}'"
```

输出里应有 `prepdot_proxy`。

### 3.2 备份现有 Caddyfile

**任何修改之前先备份。** 备份文件名带时间戳，方便回滚时辨认：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo cp /opt/adeer/Caddyfile /opt/adeer/Caddyfile.bak.\$(date +%Y%m%d-%H%M%S) && ls -l /opt/adeer/Caddyfile*"
```

记下输出里备份文件的名字（例如 `/opt/adeer/Caddyfile.bak.20261101-120000`）。

### 3.3 创建目录并迁移落地页

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "mkdir -p /opt/adeer/legal/prepdot-site/app /opt/adeer/legal/prepdot-site/welcome"

ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "cd /opt/adeer/legal/prepdot-site && \
   for f in index.html site.css site.js app-icon.png; do \
     [ -f \"\$f\" ] && mv \"\$f\" welcome/ || true; \
   done && ls -l . welcome"
```

如果提示 `Permission denied`，先用 `ls -ld /opt/adeer/legal/prepdot-site` 看目录属主，
把当前用户加进去或调整属主（例如 `sudo chown -R ubuntu:ubuntu /opt/adeer/legal/prepdot-site`），
再重试。发布脚本本身不使用 `sudo`，因此当前 SSH 用户必须对站点目录有写权限。

> 发布脚本也会自动做一次同样的迁移（仅当 `welcome/index.html` 不存在且根目录还有
> `index.html` 时），这里先手动做是为了让 Caddy 切换后 `/welcome/` 立刻可访问。

### 3.4 合并新的 Caddyfile（只能手动合并）

仓库里的 `deploy/Caddyfile.prepdot` **只包含 prepdot 自己的站点块，不是服务器上
`/opt/adeer/Caddyfile` 的完整镜像**。线上文件同时还承载其它站点（至少包含
`{$SITE_ADDRESS}`、`adeer.site`、`sssangeng.online` 等），整份覆盖会让它们在下一次
reload 后一起消失。**不存在「线上只有 prepdot 配置就整体覆盖」的选项，必须手动合并。**

先把新文件传到服务器，并检查线上文件的实际内容：

```bash
scp -i ~/.ssh/id_ed25519 deploy/Caddyfile.prepdot ubuntu@62.234.146.153:/tmp/Caddyfile.prepdot

# 如果 3.2 已经备份过，这步可跳过；否则再备份一次
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo cp /opt/adeer/Caddyfile /opt/adeer/Caddyfile.bak.\$(date +%Y%m%d-%H%M%S)"

# 查看线上配置，确认一共有哪些站点块
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo cat -n /opt/adeer/Caddyfile"
```

用编辑器手动合并，**不要整份复制覆盖**：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo nano /opt/adeer/Caddyfile"    # 或用 sudo vim
```

只做两件事：

- 删掉旧的 `prepdot.site { ... }` / `www.prepdot.site { ... }` 块（如果存在，
  否则同域名重复定义会报错）；
- 把仓库文件里的 `www.prepdot.site { ... }`、`prepdot.site { ... }` 两个块
  追加到文件末尾；`api.prepdot.site` 已存在且内容一致时保持原样，不要重复添加。

`{$SITE_ADDRESS}`、`adeer.site`、`sssangeng.online` 等其它站点块必须原样保留。
保存后再次 `sudo cat -n /opt/adeer/Caddyfile`，确认其它站点块仍在。

新配置对应的最终形态（三份站点块）：

- `api.prepdot.site`：原样转发到 `prepdot-backend:8080`。
- `www.prepdot.site`：301 到 `https://prepdot.site{uri}`（规范域名见第 1 节说明）。
- `prepdot.site`：
  - `/api/*` → 后端（这也是 Web 端同源调用 API 的原因）；
  - `/welcome` → 301 到 `/welcome/`；`/welcome/*` 从站点根目录找文件，即宣传页；
  - 其余所有路径 → `app/` 目录，找不到文件回落 `index.html`（客户端路由）；
  - 统一加 `X-Content-Type-Options`、`Referrer-Policy`、`X-Frame-Options` 安全头。

### 3.5 校验、对比并重载 Caddy

**不要跳过校验。** 配置写错时 `reload` 会失败；先 `validate` 能看到具体错误行。

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker exec adeer-caddy-1 caddy validate --config /etc/caddy/Caddyfile"
```

看到 `Valid configuration` 后，再把合并结果与 3.2 的备份做一次 diff，确认只改动了
预期的 prepdot 块、其它站点原样保留：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo diff -u /opt/adeer/Caddyfile.bak.20261101-120000 /opt/adeer/Caddyfile || true"
```

把文件名换成实际备份。diff 里只应出现 `prepdot.site` / `www.prepdot.site` 的增删；
如果出现 `{$SITE_ADDRESS}`、`adeer.site`、`sssangeng.online` 等其它块的变化，
先不要 reload，回到编辑器修正。

确认无误后再重载：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker exec adeer-caddy-1 caddy reload --config /etc/caddy/Caddyfile"
```

若 `validate` 报错，把报错行对照 `deploy/Caddyfile.prepdot` 检查；不要重载，先修好文件。
如果 `reload` 后站点异常，回到 [3.2](#32-备份现有-caddyfile) 用备份文件覆盖回来再 reload。

> 注意：旧配置通常从站点根目录提供落地页，而 §3.3 已经把落地页移进了 `welcome/`。
> 只恢复旧 Caddyfile 的话，根路径会因为没有 `index.html` 而 404。恢复旧配置后，
> 还要把落地页文件移回根目录（见 [5.2](#52-回滚-caddy-配置)），再 reload。

> 本仓库开发机上没有安装 `caddy`，所以 `deploy/Caddyfile.prepdot` 没有在本地校验过。
> **每次改动后都必须在服务器上执行上面的 `caddy validate`，通过后再 reload。**

### 3.6 第一次发布 Web 应用

在本地仓库根目录执行：

```bash
prepdot-web/scripts/deploy-web.sh
```

或在 `prepdot-web/` 目录下执行：

```bash
cd prepdot-web
./scripts/deploy-web.sh
```

脚本会依次：安装依赖 → `lint` → 构建 → 询问确认 → 检查服务器 rsync →
上传到 `app.new/` → 切换目录 → 做线上健康检查。第一次执行时它还会顺手完成
"旧落地页移入 `welcome/`"的兜底操作。

### 3.7 验证首次部署

```bash
curl -fsS https://prepdot.site/api/health
curl -fsSI https://prepdot.site/
curl -fsSI https://prepdot.site/welcome/
curl -fsSI https://prepdot.site/review
curl -sI https://prepdot.site/welcome | head -n 1          # 状态行应为 301
curl -sI https://www.prepdot.site/ | head -n 1            # 状态行应为 301
```

期望：

- `/api/health` 返回 `{"code":200,...}` 之类的成功 JSON（具体字段以接口为准）；
- `/` 和 `/review` 返回 `200`，`Content-Type: text/html`（后者验证刷新深链不 404）；
- `/welcome/` 返回 `200`，内容仍是原来的宣传/法律页；
- `/welcome`（不带斜杠）返回 **301**，`Location: /welcome/`；
- `https://www.prepdot.site/` 返回 **301**，`Location: https://prepdot.site/`。
  不要用 `curl -f` 判断跳转以外的内容，先看状态行和 `Location` 头即可：
  `curl -sI https://www.prepdot.site/ | grep -i '^location'`。

再用浏览器打开 <https://prepdot.site>，能正常登录并看到复习页即完成。

---

## 4. 日常发布

改了 `prepdot-web/` 的代码后，在本地执行：

```bash
cd prepdot-web
./scripts/deploy-web.sh
```

或在仓库根目录：

```bash
prepdot-web/scripts/deploy-web.sh
```

脚本会先跑 `pnpm install --frozen-lockfile`、`pnpm lint`、`pnpm build`，**构建失败就不会上传**。
确认提示输入 `y` 后开始发布。

需要跳过确认（例如自动化）时：

```bash
YES=1 ./scripts/deploy-web.sh
# 或
./scripts/deploy-web.sh --yes
```

可用的环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PREPDOT_SSH_HOST` | `ubuntu@62.234.146.153` | 目标服务器 |
| `PREPDOT_SSH_KEY` | `~/.ssh/id_ed25519` | SSH 私钥路径 |
| `YES` | 未设置 | `1` 时跳过确认 |

脚本的发布过程是"近似原子"的：

1. 上传到 `app.new/`，此时线上仍读旧的 `app/`；
2. 把旧的 `app/` 改名为 `app.prev/`，再把 `app.new/` 改名为 `app/`（两次 `mv`，间隔极短）；
3. 执行线上健康检查。

如果第 2 步之后检查失败，脚本会打印回滚命令。目录结构：

```text
/opt/adeer/legal/prepdot-site/
├── app/       当前线上版本（每次发布被整体替换）
├── app.prev/  上一版，用于回滚（下一次发布会覆盖它）
├── app.new/   上传暂存区（发布过程中存在）
└── welcome/   宣传/法律落地页，长期保留
```

---

## 5. 回滚

### 5.1 回滚 Web 前端（最常见）

发布后发现问题，把 `app.prev/` 换回来即可，**不需要重新构建**：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "cd /opt/adeer/legal/prepdot-site && \
   ls -ld app app.prev && \
   rm -rf app.failed && \
   mv app app.failed && \
   mv app.prev app && \
   ls -ld app app.failed"
```

执行后刷新 <https://prepdot.site> 即可看到上一版。`app.failed/` 是这次出问题的版本，
确认不需要排查后可以删除：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "rm -rf /opt/adeer/legal/prepdot-site/app.failed"
```

注意：`app.prev/` 只保留**上一版**。如果连续发布了两次，第一次的版本已经不存在了。

如果健康检查失败、脚本已打印回滚命令，直接复制执行即可（脚本输出里的命令与上面等价）。

### 5.2 回滚 Caddy 配置

如果问题出在反向代理配置（例如改了 Caddyfile 后站点打不开）：

```bash
# 1. 看一眼备份文件名
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "ls -l /opt/adeer/Caddyfile*"

# 2. 用备份覆盖（把文件名换成实际备份）
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "sudo cp /opt/adeer/Caddyfile.bak.20261101-120000 /opt/adeer/Caddyfile"

# 3. 如果备份是"从站点根目录提供落地页"的旧配置，把落地页文件从 welcome/ 移回根目录
#    （否则根路径会因为没有 index.html 而 404；文件不存在时跳过）
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "cd /opt/adeer/legal/prepdot-site && \
   for f in index.html site.css site.js app-icon.png; do \
     if [ -f \"welcome/\$f\" ] && [ ! -f \"\$f\" ]; then mv \"welcome/\$f\" ./; fi; \
   done && ls -l . welcome"

# 4. 校验 + 重载
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker exec adeer-caddy-1 caddy validate --config /etc/caddy/Caddyfile"
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "docker exec adeer-caddy-1 caddy reload --config /etc/caddy/Caddyfile"
```

重载后验证：

```bash
curl -fsS https://api.prepdot.site/api/health
curl -sI https://prepdot.site/ | head -n 1   # 应为 200
curl -fsSI https://prepdot.site/ | grep -i content-type
```

如果回滚后的旧配置只提供落地页、没有 `/api` 反代，那么 `prepdot.site` 的 200 页面是
宣传页而不是 Web 应用，这是符合预期的——此时 Web 端本身也随之下线，直到重新应用新配置。

> 注意：只恢复 Caddyfile、不把落地页文件移回根目录时，旧配置找不到 `index.html`，
> 根路径会一直是 404。要么按上面第 3 步移回文件，要么重新应用新配置并保持文件在
> `welcome/` 下。

---

## 6. 演示账号与每日重置（已启用）

生产环境提供一个公开的演示账号，方便访客直接体验。为了避免访客把演示数据改乱，
服务器上有一个重置脚本，由 cron 每天凌晨自动恢复初始状态。

> **当前状态（2026-11-01）**：卡组数据、回填 SQL 与 `reset-demo.sh` 已同步到
> `/opt/prepdot/demo/`；cron 已安装并完成首次重置。发布 Web 站点时会自动同步这些文件，
> 但会排除 `.reset-demo.lock` 与 `.demo-user-id`。

| 项目 | 值 |
|---|---|
| 状态 | 已安装 cron，已完成首次重置 |
| 脚本路径 | `/opt/prepdot/demo/reset-demo.sh` |
| 执行时间 | 每天 04:17（服务器本地时区，Asia/Shanghai） |
| cron 表达式 | `17 4 * * *` |
| cron 命令 | `timeout 900 /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1` |
| 互斥锁 | `/opt/prepdot/demo/.reset-demo.lock`（防止 cron 重叠执行） |
| 标记文件 | `/opt/prepdot/demo/.demo-user-id`（记录 demo 用户数据库 id，用于识别被改名的账号） |
| 作用 | 把演示账号的数据恢复到干净的初始状态，清除访客新增或修改的内容 |

`timeout 900` 保证请求卡死时进程会在 15 分钟后被终止并释放锁；脚本内部对
健康检查、注册/登录和导入分别设置了更短的 curl 超时。

### 6.1 安装 cron 并首次执行

1. 在服务器安装 cron（会替换同名旧条目，保留其它任务）：

   ```bash
   ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
     (crontab -l 2>/dev/null | grep -v "/opt/prepdot/demo/reset-demo.sh"; \
      echo "17 4 * * * timeout 900 /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1") | crontab -
     crontab -l | grep reset-demo
   '
   ```

   输出里应能看到带 `timeout 900` 的完整命令。

2. 安装后先手动完整执行一次，确认注册、导入和回填都成功（不要用 `sudo`）：

   ```bash
   ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
     "chmod +x /opt/prepdot/demo/reset-demo.sh && timeout 900 /opt/prepdot/demo/reset-demo.sh"
   ```

   成功时最后几行应包含 `demo 数据已重置：...` 以及
   `卡组 ... 个 / 卡片 60 张 / 今日到期 ... 张 / 复习记录 ... 条`。

3. 检查标记文件与日志：

   ```bash
   ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
     "ls -l /opt/prepdot/demo/.demo-user-id && tail -n 30 /opt/prepdot/demo-reset.log"
   ```

   `.demo-user-id` 应只有一行数字（权限 `-rw-------`）。手动执行时输出在终端；
   `demo-reset.log` 会在下一次 cron 运行后写入，首次安装后第二天再检查一次。

4. 失败观察：建议每天花一分钟看日志：

   ```bash
   ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
     "tail -n 30 /opt/prepdot/demo-reset.log; grep -n '重置失败' /opt/prepdot/demo-reset.log || true"
   ```

   脚本失败时会以非零退出码结束，并打印 `重置失败：<原因>`。如果日志里超过一天没有新的
   `demo 数据已重置`，先检查 `crontab -l`、`docker ps` 中的 MySQL/后端容器，以及
   `/opt/prepdot/.env.production` 的读取权限。

### 6.2 重置标记与账号被改名的恢复

演示密码是公开的，访客登录后可以通过 `PUT /api/auth/profile` 修改 demo 账号的昵称。
脚本用 `/opt/prepdot/demo/.demo-user-id` 记录上次成功重置时的用户数据库 id：

- 昵称仍是「演示用户」→ 正常继续；
- 昵称被改、但当前 id 与标记一致 → 打印警告后继续重置（重新注册会把昵称恢复成「演示用户」）；
- 昵称和 id 都对不上，或标记不存在 → 中止，提示设置 `FORCE_DEMO_REPLACE=1`。

**残余限制**：拿到公开 demo 密码的人也可以先删除账号，再用同名但昵称不是「演示用户」
的账号重新注册。此时数据库 id 会变化且昵称不匹配，夜间重置会中止而不再自动恢复。
如果重新注册时昵称仍是「演示用户」，昵称检查会直接放行（即使 id 变化），重置继续。
发现日志里的「重置失败」并确认没有真实用户受影响后，用下面命令人工恢复一次
（脚本会删除并重建 demo 数据，随后写入新 id）：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  "cd /opt/prepdot/demo && FORCE_DEMO_REPLACE=1 timeout 900 ./reset-demo.sh"
```

标记文件与 `.reset-demo.lock` 都不会被发布脚本的 `rsync --delete` 删除。

演示账号由重置脚本固定为 `demo`，密码写在脚本中；请勿用该账号存放任何真实数据。
手动执行前可先加 `--dry-run` 查看将要执行的操作（`--dry-run` 不需要 docker/curl，
也不会读写标记文件）。脚本应以 cron 的 `ubuntu` 用户运行，不要用 `sudo`：root 创建的
锁文件会让之后的 cron 任务一直拿不到锁。

---

## 7. 验证命令速查

```bash
# 后端健康（同源，走 prepdot.site 的 Caddy 转发）
curl -fsS https://prepdot.site/api/health

# 独立 API 域名（iOS 使用）
curl -fsS https://api.prepdot.site/api/health

# 首页 / 前端深链（应返回 200 text/html）
curl -fsSI https://prepdot.site/
curl -fsSI https://prepdot.site/review

# 宣传/法律页
curl -fsSI https://prepdot.site/welcome/
curl -sI https://prepdot.site/welcome | head -n 1   # 应为 301，Location: /welcome/
curl -sI https://prepdot.site/welcome | grep -i '^location'

# 规范域名：www 应 301 到 apex
curl -sI https://www.prepdot.site/ | head -n 1     # 应为 301
curl -sI https://www.prepdot.site/ | grep -i '^location'

# 首页 Content-Type（应为 text/html）
curl -fsSI https://prepdot.site/ | grep -i content-type
```

---

## 8. 常见问题

### 刷新页面 404

浏览器里点导航正常，但直接打开或刷新 `/review`、`/decks/1` 变成 404。

- 原因：Caddy 没有用 `try_files {path} /index.html` 兜底，或新 Caddyfile 没有 reload。
- 处理：确认服务器上 Caddyfile 的 `prepdot.site` 块与仓库里 `deploy/Caddyfile.prepdot` 一致
  （线上可能还有其它站点块，**不要整份覆盖**，只对照 prepdot 相关块），再
  `caddy validate` + `caddy reload`；用 `curl -fsSI https://prepdot.site/review` 验证返回 200。

### API 返回 401

- 通常是 token 过期或浏览器清了 localStorage：退出重新登录即可。
- 如果**所有人**突然都 401：检查后端 `JWT_SECRET` 是否在最近一次后端发布中被换掉
  （换 secret 会让全部旧 token 失效），确认后让用户重新登录。

### 跨域（CORS）报错

生产环境的 Web 端与 API 同源（都在 `prepdot.site` 下），**正常情况不会有跨域问题**。

- 检查构建时是否误设置了 `VITE_API_BASE_URL`（它会把请求指向别的域名）；
  生产构建应保持默认的 `/api`。必要时清掉该变量后重新发布。
- Web 端不要直接调用 `https://api.prepdot.site`——那是给 iOS 用的独立域名。

### 上传文件超限

上传上限由后端 Spring 配置决定（`spring.servlet.multipart.max-file-size` /
`max-request-size`，当前为 20MB），不是 Caddy 的限制。

- 超限时后端返回错误，前端提示失败。需要调大时修改
  `prepdot-backend/src/main/resources/application-production.yml`，走后端既有 CI 重新部署。
- 注意：这与前端无关，也不需要改 Caddy。

### AI 生成超时

卡片生成走 Agent 流水线，最长可能需要约 **180 秒**。

- 期间保持页面打开，不要反复刷新或重复点击；SSE 连接断开后重试即可。
- 不要在 Caddy 上加很短的 `response_header_timeout` 之类限制（当前配置没有设，保持默认）。
- 如果以后在站点前再加 CDN/防火墙，需要确认其超时时间大于 180 秒。

### HTTPS 证书问题

证书由 Caddy 自动申请与续期。

- 确认 `prepdot.site`、`www.prepdot.site` 的 DNS 都解析到 `62.234.146.153`；
- 确认服务器 80、443 端口可从公网访问（Let's Encrypt 校验要用 80 端口）；
- 查看 Caddy 日志：`docker logs --tail 100 adeer-caddy-1`；
- 证书有效期内会自动续期，不需要手动操作。

### API 502 / 连不上后端

- `docker ps` 看 `prepdot-backend` 是否在运行；
- `docker logs --tail 100 prepdot-backend` 看启动报错；
- 确认 Caddy 容器在 `prepdot_proxy` 网络中（见 3.1）。

---

## 9. 安全说明

以下都是**明确的取舍**，上线前请知悉：

1. **JWT 存在 localStorage**：Web 端登录凭证保存在浏览器 localStorage，没有使用
   `HttpOnly` Cookie。好处是实现简单、与会话刷新逻辑一致；代价是如果页面发生 XSS，
   脚本可以读取 token。项目因此不加载第三方统计/广告脚本，Markdown 渲染也做了限制。
   这是当前阶段的已知取舍，后续若要做更严格的安全模型，需要改为 HttpOnly Cookie + CSRF 防护。
2. **AI Key 为明文环境变量**：后端读取 `AI_DEEPSEEK_SYSTEM_KEY`，它来自服务器上的
   `.env.production`，以明文形式存在并由 Docker 注入容器。不要把它提交进仓库；
   服务器被入侵时该 key 会泄露，届时应在供应商后台吊销并轮换。
   环境变量文件应只对运行用户可读，确认权限为 `-rw-------`：

   ```bash
   ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
     "sudo chmod 600 /opt/prepdot/.env.production && ls -l /opt/prepdot/.env.production"
   ```
3. **演示账号没有独立 AI 配额**：后端没有按账号限制 AI 调用量，而演示密码是公开的，
   任何访客登录后都能消耗真实的 AI 额度；每日重置只恢复数据，不会限制调用次数。
   若发现被滥用，应在后端或网关增加限流，必要时临时停用演示账号。
4. **不要在前端写入任何密钥**：`prepdot-web/` 构建产物是公开可下载的，任何注入到
   `VITE_*` 变量的内容都会出现在浏览器里。
5. **发布脚本不含密钥**：`deploy-web.sh` 只使用本机 SSH 私钥路径与目标地址，
   不包含密码或 token。

---

## 10. 发布记录（2026-11-01）

| 项目 | 结果 |
|---|---|
| 合并提交 | `12a9b94`（`feat/web-multiplatform` → `main`，`--no-ff`） |
| 后端 | `JwtAuthFilter` 放行 `OPTIONS`；生产容器重建后健康检查通过 |
| 数据库备份 | `/opt/prepdot/backups/prepdot-db-20261101-104043.sql.gz`（`gzip -t` 通过，含 10 张表） |
| 后端镜像备份 | `prepdot-backend:prev-20261101-104031` |
| Caddy 配置备份 | `/opt/adeer/Caddyfile.backup-20261101-104349` |
| Web 静态目录 | `/opt/adeer/legal/prepdot-site/app`（旧版在 `app.prev`） |
| 落地页 | `/opt/adeer/legal/prepdot-site/welcome/` |
| demo 首次重置 | 2026-11-01 10:44:46，14 个卡组 / 60 张卡 / 18 张今日到期 / 336 条复习记录 |
| demo 验收后重置 | 2026-11-01 10:53:17，数据量同上 |
| cron | `17 4 * * * timeout 900 /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1` |

### 10.1 后端发布说明（重要）

本次 `git push origin main` 触发的 GitHub Actions 运行
[`41265974860`](https://github.com/sgsangeng/PrepDot/actions/runs/41265974860)
在 “Upload source” 步骤失败：仓库尚未配置 `PREPDOT_DEPLOY_HOST`、
`PREPDOT_DEPLOY_USER`、`PREPDOT_DEPLOY_SSH_KEY`、`PREPDOT_KNOWN_HOSTS` 这四个 Secrets，
`DEPLOY_HOST`/`DEPLOY_USER` 为空，`rsync` 无法解析主机名。

本次后端改为在本地用与 workflow 相同的步骤手动发布：

```bash
rsync -az --delete --exclude 'src/main/resources/application.yml' --exclude 'target/' \
  -e "ssh -i ~/.ssh/id_ed25519" prepdot-backend/ \
  ubuntu@62.234.146.153:/opt/prepdot/prepdot-backend/
rsync -az -e "ssh -i ~/.ssh/id_ed25519" docker-compose.production.yml \
  ubuntu@62.234.146.153:/opt/prepdot/docker-compose.production.yml
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  cd /opt/prepdot
  docker compose --project-name prepdot --env-file .env.production \
    -f docker-compose.production.yml up -d --build --remove-orphans
'
```

发布后 `prepdot-backend` 在约 30 秒内变为 `healthy`。**后续若要让 push 自动部署**，
需要在 GitHub 仓库 `Settings → Secrets and variables → Actions` 中补齐上述四个 Secrets
（SSH 私钥内容、`known_hosts` 内容、主机 `62.234.146.153`、用户 `ubuntu`），
然后手动重跑一次 workflow 验证。未配置前，后端改动仍需按上面的命令手动发布。

### 10.2 验证结果

| 检查 | 结果 |
|---|---|
| `https://prepdot.site/` | 200 |
| `https://prepdot.site/welcome/` | 200（`/welcome` 为 301） |
| `https://prepdot.site/api/health` | 200，`{"code":200,...}` |
| `https://api.prepdot.site/api/health` | 200 |
| `https://www.prepdot.site/` | 301 → `https://prepdot.site/` |
| CORS 预检 `OPTIONS /api/plan/review` | 200，含 `Access-Control-Allow-Origin: https://prepdot.site` |
| 前端深链 `/review`、`/decks` 刷新 | 200 `text/html`（SPA 兜底） |
| `pnpm e2e`（本地 dev + 生产环境各 2 例） | 4/4 通过 |
| AI 生成（上传测试资料） | 200，约 3 秒，生成 5 个子卡组 / 7 张卡，导入后可见，测试卡组已删除 |
| AI 教练 SSE | 200，收到 `progress` + `result` 事件，约 2.3 秒 |
| 复习提交 | 200，今日计划 `completedCount` 从 0 变 1，随后重置恢复为 0 |
| iOS 构建与启动 | `BUILD SUCCEEDED`；模拟器登录 demo 后显示 18 张待复习 |

> 说明：本机 Xcode 安装不带独立 `Simulator.app`，模拟器只能无头运行，
> 无法用鼠标点击「知识树」标签，因此 **iOS 端点开卡组列表的人工交叉验收未完成**。
> 已确认 iOS 与 Web 使用同一账号、同一后端，且 iOS 能读取生产 demo 计划（18 张）。
> 有图形界面的 Xcode/真机环境下，登录 demo 后下拉刷新知识树即可完成这一步。

### 10.3 回滚

```bash
# Web 前端
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  'cd /opt/adeer/legal/prepdot-site && rm -rf app.failed && mv app app.failed && mv app.prev app'

# Caddy（本次备份文件名）
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 \
  'cd /opt/adeer && cp Caddyfile.backup-20261101-104349 Caddyfile && \
   docker exec adeer-caddy-1 caddy validate --config /etc/caddy/Caddyfile && \
   docker exec adeer-caddy-1 caddy reload --config /etc/caddy/Caddyfile'
```

若旧 Caddy 配置从站点根目录提供落地页，回滚后还需要把 `welcome/` 里的
`index.html`、`site.css`、`site.js`、`app-icon.png` 移回根目录，否则 `/` 会 404。

后端回滚：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  cd /opt/prepdot
  docker tag prepdot-backend:prev-20261101-104031 prepdot-backend:latest
  docker compose --project-name prepdot --env-file .env.production \
    -f docker-compose.production.yml up -d --no-build --force-recreate backend
'
```

数据库回滚（仅在确认需要时执行，会覆盖当前数据）：

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@62.234.146.153 '
  cd /opt/prepdot
  set -a; . ./.env.production; set +a
  gunzip -c backups/prepdot-db-20261101-104043.sql.gz | \
    docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" prepdot-mysql \
      mysql -u"$MYSQL_USER" "$MYSQL_DATABASE"
'
```

---

## 11. 边界

- **不改 iOS**：`prepdot-ios/` 与 `api.prepdot.site` 的行为保持不变。
- **不改后端接口契约**：本阶段 Web 端复用现有 `/api`，Caddy 只做路径转发。分支里的后端
  改动只在 `JwtAuthFilter`：放行浏览器 `OPTIONS` 预检（预检不携带 Authorization，否则会被
  401 拦截），并在账号注销后拒绝旧 token；接口路径、请求体与响应结构未变。
- **桌面端（Phase 2）尚未开始**：后续才会确定 Tauri/Electron 方案与部署方式。
