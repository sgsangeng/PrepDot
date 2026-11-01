#!/usr/bin/env bash
# 每日重置演示账号 demo 的数据。
#
# 用法:
#   ./reset-demo.sh            执行重置（会删除并重建 demo 的全部数据）
#   ./reset-demo.sh --dry-run  只打印将要执行的操作，不修改任何数据
#
# 由 cron 每天 04:17 调用（外层 timeout 防止卡死进程长期占用互斥锁）:
#   17 4 * * * timeout 900 /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1
set -euo pipefail

API="${PREPDOT_API:-https://api.prepdot.site/api}"
DEMO_USER="demo"
DEMO_PASS="PrepDot2026"
DEMO_NICKNAME="演示用户"
DEMO_DIR="${PREPDOT_DEMO_DIR:-/opt/prepdot/demo}"
ENV_FILE="${PREPDOT_ENV_FILE:-/opt/prepdot/.env.production}"
MYSQL_CONTAINER="${PREPDOT_MYSQL_CONTAINER:-prepdot-mysql}"
LOCK_FILE="${PREPDOT_DEMO_LOCK:-$DEMO_DIR/.reset-demo.lock}"
MARKER_FILE="${PREPDOT_DEMO_MARKER:-$DEMO_DIR/.demo-user-id}"
FORCE_DEMO_REPLACE="${FORCE_DEMO_REPLACE:-0}"

DRY_RUN=0

die() {
  echo "重置失败：$*" >&2
  exit 1
}

warn() {
  echo "警告：$*" >&2
}

usage() {
  cat <<'EOF'
用法: ./reset-demo.sh [--dry-run]

  --dry-run  仅打印计划执行的操作，不删除、不导入、不执行 SQL
  -h, --help 显示本帮助

可通过环境变量覆盖:
  PREPDOT_API               API 根地址，默认 https://api.prepdot.site/api
  PREPDOT_DEMO_DIR          演示数据目录，默认 /opt/prepdot/demo
  PREPDOT_ENV_FILE          生产环境变量文件，默认 /opt/prepdot/.env.production
  PREPDOT_MYSQL_CONTAINER   MySQL 容器名，默认 prepdot-mysql
  PREPDOT_DEMO_LOCK         互斥锁文件，默认 $PREPDOT_DEMO_DIR/.reset-demo.lock
  PREPDOT_DEMO_MARKER       记录 demo 用户数据库 id 的标记，默认 $PREPDOT_DEMO_DIR/.demo-user-id
  FORCE_DEMO_REPLACE=1      允许覆盖无法通过昵称或标记确认归属的同名账号（危险）

注意：不要用 sudo 运行本脚本。root 创建的锁文件会归 root 所有，
之后 cron 以 ubuntu 用户运行时将永远拿不到锁。
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$arg（可用 --help 查看用法）" ;;
  esac
done

[ -d "$DEMO_DIR/decks" ] || die "找不到演示数据目录：$DEMO_DIR/decks"
[ -r "$DEMO_DIR/demo-backdate.sql" ] || die "找不到回填 SQL：$DEMO_DIR/demo-backdate.sql"

shopt -s nullglob
DEMO_FILES=("$DEMO_DIR"/decks/*.json)
shopt -u nullglob
[ "${#DEMO_FILES[@]}" -gt 0 ] || die "找不到卡组文件：$DEMO_DIR/decks/*.json"

# --dry-run 只需要查看本地文件，因此放在 docker/curl/env 检查之前，
# 方便在没有生产环境的机器上预览计划。
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] API: $API"
  echo "[dry-run] 环境变量文件：$ENV_FILE（MySQL 容器 $MYSQL_CONTAINER）"
  echo "[dry-run] 将检查 demo 账号昵称与 $MARKER_FILE 中的用户 id；昵称被改但 id 一致时继续，否则中止（除非 FORCE_DEMO_REPLACE=1）"
  echo "[dry-run] 将解除外部用户指向 demo 卡组的 parent_id，再按外键安全顺序删除："
  echo "[dry-run]   agent_step → agent_run → daily_plan → review_record → deck（级联 flashcard）→ user"
  echo "[dry-run] 将重新注册并登录用户：$DEMO_USER"
  for file in "${DEMO_FILES[@]}"; do
    echo "[dry-run] 将导入：$file（$(grep -c '"question"' "$file") 张卡片）"
  done
  echo "[dry-run] 将执行回填 SQL：$DEMO_DIR/demo-backdate.sql"
  echo "[dry-run] 未做任何修改。"
  exit 0
fi

command -v docker >/dev/null 2>&1 || die "本机没有 docker 命令"
command -v curl >/dev/null 2>&1 || die "本机没有 curl 命令"
command -v flock >/dev/null 2>&1 || die "缺少 flock 命令（util-linux）"

[ -r "$ENV_FILE" ] || die "无法读取环境变量文件：$ENV_FILE"

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

: "${MYSQL_USER:?环境变量文件缺少 MYSQL_USER}"
: "${MYSQL_PASSWORD:?环境变量文件缺少 MYSQL_PASSWORD}"
: "${MYSQL_DATABASE:?环境变量文件缺少 MYSQL_DATABASE}"

# 容器内已注入 MYSQL_USER / MYSQL_PASSWORD / MYSQL_DATABASE，
# 因此用 sh -c 单引号让变量在容器内展开；-i 保证 heredoc / 重定向能进入 mysql。
mysql_exec() {
  docker exec -i "$MYSQL_CONTAINER" sh -c \
    'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql -u"$MYSQL_USER" "$MYSQL_DATABASE" --default-character-set=utf8mb4 --batch --skip-column-names'
}

# 防止 cron 重叠执行：拿不到锁说明上一轮还没结束。
exec 9>"$LOCK_FILE" || die "无法创建锁文件：$LOCK_FILE"
if ! flock -n 9; then
  die "已有另一个重置任务正在运行（锁：$LOCK_FILE）"
fi

echo "==> 健康检查：$API/health"
HEALTH="$(curl -fsS --connect-timeout 10 --max-time 15 "$API/health")" \
  || die "API 健康检查请求失败，未删除任何数据：$API/health"
printf '%s' "$HEALTH" | grep -Eq '"code"[[:space:]]*:[[:space:]]*200' \
  || die "API 健康检查未返回成功，未删除任何数据：$HEALTH"

# 用户名唯一索引不区分大小写（utf8mb4_0900_ai_ci），因此 'demo'、'Demo'
# 会命中同一个账号。首次执行前确认它不是真实用户，避免误删。
#
# 演示密码是公开的，访客可以登录后把 demo 改名。为了不因此永久停掉夜间重置：
# - 昵称仍是「演示用户」→ 直接继续；
# - 昵称被改、但数据库 id 与上次成功重置写入的标记一致 → 说明仍是脚本管理的账号，
#   记录警告后继续（重新注册会恢复昵称）；
# - 两者都对不上（或没有标记）→ 中止，要求人工确认 FORCE_DEMO_REPLACE=1。
MARKER_ID=""
if [ -r "$MARKER_FILE" ]; then
  MARKER_ID="$(tr -d '[:space:]' < "$MARKER_FILE" || true)"
  case "$MARKER_ID" in
    ''|*[!0-9]*) MARKER_ID="" ;;
  esac
fi

EXISTING_ID=""
EXISTING_NICK=""
EXISTING_ROW="$(mysql_exec <<'SQL'
SELECT id, IFNULL(nickname, '') FROM user WHERE username = 'demo' LIMIT 1;
SQL
)"
if [ -n "$EXISTING_ROW" ]; then
  IFS=$'\t' read -r EXISTING_ID EXISTING_NICK <<< "$EXISTING_ROW"
fi

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_NICK" != "$DEMO_NICKNAME" ]; then
  if [ "$FORCE_DEMO_REPLACE" = "1" ]; then
    warn "demo 账号昵称为「$EXISTING_NICK」（不是「$DEMO_NICKNAME」）；已按 FORCE_DEMO_REPLACE=1 覆盖。"
  elif [ -n "$MARKER_ID" ] && [ "$EXISTING_ID" = "$MARKER_ID" ]; then
    warn "demo 账号昵称已被改为「$EXISTING_NICK」，但 id=$EXISTING_ID 与标记 $MARKER_FILE 一致；继续重置并恢复昵称。"
  else
    die "已存在用户名 demo 的账号，但昵称是「$EXISTING_NICK」而不是「$DEMO_NICKNAME」，且无法确认它由重置脚本管理（标记 id=${MARKER_ID:-缺失}，实际 id=$EXISTING_ID）。为避免误删真实用户已中止；确认要覆盖请设置 FORCE_DEMO_REPLACE=1 后重试。"
  fi
fi

echo "==> 删除 demo 旧数据"
mysql_exec <<'SQL'
SET @demo_id = (SELECT id FROM user WHERE username = 'demo');

-- deck.parent_id 是 ON DELETE CASCADE：先把外部用户（或公共卡组）挂到
-- demo 卡组下的子节点摘下来，避免删除 demo 卡组时连带删除别人的数据。
UPDATE deck c JOIN deck p ON c.parent_id = p.id
SET c.parent_id = NULL
WHERE p.user_id = @demo_id AND (c.user_id IS NULL OR c.user_id <> @demo_id);

DELETE FROM agent_step WHERE run_id IN (SELECT id FROM agent_run WHERE user_id = @demo_id);
DELETE FROM agent_run WHERE user_id = @demo_id;
DELETE FROM daily_plan WHERE user_id = @demo_id;
DELETE FROM review_record WHERE user_id = @demo_id;
DELETE FROM deck WHERE user_id = @demo_id;
DELETE FROM user WHERE id = @demo_id;
SQL

echo "==> 重新注册 demo"
REGISTER_RESP="$(curl -fsS --connect-timeout 10 --max-time 60 -X POST "$API/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\",\"nickname\":\"$DEMO_NICKNAME\"}")" \
  || die "注册 demo 失败：请求 $API/auth/register 出错或超时"
printf '%s' "$REGISTER_RESP" | grep -Eq '"code"[[:space:]]*:[[:space:]]*200' \
  || die "注册 demo 失败：$REGISTER_RESP"

echo "==> 登录 demo"
LOGIN_RESP="$(curl -fsS --connect-timeout 10 --max-time 60 -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\"}")" \
  || die "登录 demo 失败：请求 $API/auth/login 出错或超时"
TOKEN="$(printf '%s' "$LOGIN_RESP" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$TOKEN" ] || die "登录 demo 失败（未返回 token）：$LOGIN_RESP"

echo "==> 导入演示卡组"
for file in "${DEMO_FILES[@]}"; do
  name="$(basename "$file")"
  IMPORT_RESP="$(curl -fsS --connect-timeout 10 --max-time 180 -X POST "$API/ai/import" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$file")" \
    || die "导入 $name 失败：请求 $API/ai/import 出错或超时"
  printf '%s' "$IMPORT_RESP" | grep -Eq '"code"[[:space:]]*:[[:space:]]*200' \
    || die "导入 $name 失败：$IMPORT_RESP"
  echo "  ✓ $name"
done

echo "==> 回填复习进度"
mysql_exec < "$DEMO_DIR/demo-backdate.sql"

echo "==> 汇总"
SUMMARY="$(mysql_exec <<'SQL'
SELECT COUNT(*) FROM deck WHERE user_id = (SELECT id FROM user WHERE username = 'demo');
SELECT COUNT(*) FROM flashcard f JOIN deck d ON f.deck_id = d.id
  WHERE d.user_id = (SELECT id FROM user WHERE username = 'demo');
SELECT COUNT(*) FROM flashcard f JOIN deck d ON f.deck_id = d.id
  WHERE d.user_id = (SELECT id FROM user WHERE username = 'demo') AND f.next_review_at <= NOW();
SELECT COUNT(*) FROM review_record WHERE user_id = (SELECT id FROM user WHERE username = 'demo');
SQL
)"
DECK_COUNT="$(printf '%s\n' "$SUMMARY" | sed -n '1p')"
CARD_COUNT="$(printf '%s\n' "$SUMMARY" | sed -n '2p')"
DUE_COUNT="$(printf '%s\n' "$SUMMARY" | sed -n '3p')"
RECORD_COUNT="$(printf '%s\n' "$SUMMARY" | sed -n '4p')"

# 卡片数必须精确为 60：导入被截断时这里会失败，cron 日志能立刻发现。
[ "$CARD_COUNT" = "60" ] \
  || die "导入后 demo 卡片数为 $CARD_COUNT，预期 60（可能导入被截断），请检查日志。"
# 今日到期数受自增 id 分布影响，只告警不失败。
[ "$DUE_COUNT" = "18" ] \
  || warn "今日到期卡片数为 $DUE_COUNT，预期约 18（自增 id 不连续时会偏移）。"

# 记录本次成功重置后的 demo 用户 id，供下次运行确认账号仍由脚本管理。
DEMO_ID="$(mysql_exec <<'SQL'
SELECT id FROM user WHERE username = 'demo' LIMIT 1;
SQL
)"
[ -n "$DEMO_ID" ] || die "重置后找不到 demo 账号，无法写入用户 id 标记：$MARKER_FILE"
if printf '%s\n' "$DEMO_ID" > "$MARKER_FILE" 2>/dev/null; then
  chmod 600 "$MARKER_FILE" 2>/dev/null || true
else
  warn "无法写入 $MARKER_FILE；下次运行只能凭昵称识别 demo 账号。"
fi

echo "demo 数据已重置：$(date '+%F %T')"
echo "  卡组 $DECK_COUNT 个 / 卡片 $CARD_COUNT 张 / 今日到期 $DUE_COUNT 张 / 复习记录 $RECORD_COUNT 条"
