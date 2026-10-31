#!/usr/bin/env bash
# 每日重置演示账号 demo 的数据。
#
# 用法:
#   ./reset-demo.sh            执行重置（会删除并重建 demo 的全部数据）
#   ./reset-demo.sh --dry-run  只打印将要执行的操作，不修改任何数据
#
# 由 cron 每天 04:17 调用:
#   17 4 * * * /opt/prepdot/demo/reset-demo.sh >> /opt/prepdot/demo-reset.log 2>&1
set -euo pipefail

API="${PREPDOT_API:-https://api.prepdot.site/api}"
DEMO_USER="demo"
DEMO_PASS="PrepDot2026"
DEMO_DIR="${PREPDOT_DEMO_DIR:-/opt/prepdot/demo}"
ENV_FILE="${PREPDOT_ENV_FILE:-/opt/prepdot/.env.production}"
MYSQL_CONTAINER="${PREPDOT_MYSQL_CONTAINER:-prepdot-mysql}"
LOCK_FILE="${PREPDOT_DEMO_LOCK:-/tmp/prepdot-demo-reset.lock}"

DRY_RUN=0

die() {
  echo "重置失败：$*" >&2
  exit 1
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
  PREPDOT_DEMO_LOCK         互斥锁文件，默认 /tmp/prepdot-demo-reset.lock
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$arg（可用 --help 查看用法）" ;;
  esac
done

command -v docker >/dev/null 2>&1 || die "本机没有 docker 命令"
command -v curl >/dev/null 2>&1 || die "本机没有 curl 命令"

[ -r "$ENV_FILE" ] || die "无法读取环境变量文件：$ENV_FILE"
[ -d "$DEMO_DIR/decks" ] || die "找不到演示数据目录：$DEMO_DIR/decks"
[ -r "$DEMO_DIR/demo-backdate.sql" ] || die "找不到回填 SQL：$DEMO_DIR/demo-backdate.sql"

shopt -s nullglob
DEMO_FILES=("$DEMO_DIR"/decks/*.json)
shopt -u nullglob
[ "${#DEMO_FILES[@]}" -gt 0 ] || die "找不到卡组文件：$DEMO_DIR/decks/*.json"

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

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] API: $API"
  echo "[dry-run] 数据库: ${MYSQL_DATABASE}（容器 $MYSQL_CONTAINER）"
  echo "[dry-run] 将按外键安全顺序删除 demo 的数据："
  echo "[dry-run]   agent_step → agent_run → daily_plan → review_record → deck（级联 flashcard）→ user"
  echo "[dry-run] 将重新注册并登录用户：$DEMO_USER"
  for file in "${DEMO_FILES[@]}"; do
    echo "[dry-run] 将导入：$file（$(grep -c '"question"' "$file") 张卡片）"
  done
  echo "[dry-run] 将执行回填 SQL：$DEMO_DIR/demo-backdate.sql"
  echo "[dry-run] 未做任何修改。"
  exit 0
fi

# 防止 cron 重叠执行：拿不到锁说明上一轮还没结束。
command -v flock >/dev/null 2>&1 || die "缺少 flock 命令（util-linux）"
exec 9>"$LOCK_FILE" || die "无法创建锁文件：$LOCK_FILE"
if ! flock -n 9; then
  die "已有另一个重置任务正在运行（锁：$LOCK_FILE）"
fi

echo "==> 健康检查：$API/health"
HEALTH="$(curl -fsS --max-time 15 "$API/health")" \
  || die "API 健康检查请求失败，未删除任何数据：$API/health"
printf '%s' "$HEALTH" | grep -Eq '"code"[[:space:]]*:[[:space:]]*200' \
  || die "API 健康检查未返回成功，未删除任何数据：$HEALTH"

echo "==> 删除 demo 旧数据"
mysql_exec <<'SQL'
SET @demo_id = (SELECT id FROM user WHERE username = 'demo');

DELETE FROM agent_step WHERE run_id IN (SELECT id FROM agent_run WHERE user_id = @demo_id);
DELETE FROM agent_run WHERE user_id = @demo_id;
DELETE FROM daily_plan WHERE user_id = @demo_id;
DELETE FROM review_record WHERE user_id = @demo_id;
DELETE FROM deck WHERE user_id = @demo_id;
DELETE FROM user WHERE id = @demo_id;
SQL

echo "==> 重新注册 demo"
REGISTER_RESP="$(curl -fsS -X POST "$API/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\",\"nickname\":\"演示用户\"}")" \
  || die "注册 demo 失败：请求 $API/auth/register 出错"
printf '%s' "$REGISTER_RESP" | grep -Eq '"code"[[:space:]]*:[[:space:]]*200' \
  || die "注册 demo 失败：$REGISTER_RESP"

echo "==> 登录 demo"
LOGIN_RESP="$(curl -fsS -X POST "$API/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$DEMO_USER\",\"password\":\"$DEMO_PASS\"}")" \
  || die "登录 demo 失败：请求 $API/auth/login 出错"
TOKEN="$(printf '%s' "$LOGIN_RESP" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
[ -n "$TOKEN" ] || die "登录 demo 失败（未返回 token）：$LOGIN_RESP"

echo "==> 导入演示卡组"
for file in "${DEMO_FILES[@]}"; do
  name="$(basename "$file")"
  IMPORT_RESP="$(curl -fsS -X POST "$API/ai/import" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$file")" \
    || die "导入 $name 失败：请求 $API/ai/import 出错"
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

echo "demo 数据已重置：$(date '+%F %T')"
echo "  卡组 $DECK_COUNT 个 / 卡片 $CARD_COUNT 张 / 今日到期 $DUE_COUNT 张 / 复习记录 $RECORD_COUNT 条"
