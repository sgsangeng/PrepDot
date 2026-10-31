#!/usr/bin/env bash
# 序岛 Web 前端发布脚本：本地安装/检查/构建 → 上传 → 原子切换 → 线上健康检查。
# 首次部署请先阅读仓库根目录的 DEPLOY-WEB.md。
set -euo pipefail

HOST="${PREPDOT_SSH_HOST:-ubuntu@62.234.146.153}"
KEY="${PREPDOT_SSH_KEY:-$HOME/.ssh/id_ed25519}"
ROOT="/opt/adeer/legal/prepdot-site"
SITE_URL="${PREPDOT_SITE_URL:-https://prepdot.site}"
SSH_OPTS=(-i "$KEY" -o ConnectTimeout=10)

# 0 = 远端目录还没切换，1 = 已经切换（失败时要提示回滚）
SWAPPED=0
CANCELLED=0

usage() {
  cat <<'EOF'
用法: ./scripts/deploy-web.sh [选项]

在本地安装依赖、执行 lint 与构建，然后把 dist/ 发布到生产服务器，
并自动完成目录切换与线上健康检查。

环境变量:
  PREPDOT_SSH_HOST   服务器地址，默认 ubuntu@62.234.146.153
  PREPDOT_SSH_KEY    SSH 私钥路径，默认 ~/.ssh/id_ed25519
  YES=1              跳过发布前的人工确认（适合重复发布/自动化）

选项:
  -h, --help         显示本帮助
  -y, --yes          等同于 YES=1

脚本可在仓库根目录或 prepdot-web/ 下执行。
首次部署、回滚步骤与常见问题见仓库根目录 DEPLOY-WEB.md。
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -y|--yes) YES=1 ;;
  '') ;;
  *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WEB_DIR"

[ -f package.json ] || { echo "找不到 $WEB_DIR/package.json，请勿移动本脚本。" >&2; exit 1; }
[ -f "$KEY" ] || { echo "找不到 SSH 私钥: $KEY（可用 PREPDOT_SSH_KEY 指定）" >&2; exit 1; }
command -v pnpm >/dev/null 2>&1 || { echo "本机未安装 pnpm，请先执行: npm install -g pnpm" >&2; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo "本机未安装 rsync，无法上传构建产物。" >&2; exit 1; }

rollback_cmd() {
  echo "ssh -i \"$KEY\" $HOST \"cd $ROOT && if [ ! -d app.prev ]; then echo '没有 app.prev，无需回滚'; exit 0; fi; rm -rf app.failed && mv app app.failed && mv app.prev app\""
}

on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ "$CANCELLED" -eq 0 ]; then
    echo "" >&2
    echo "发布失败（退出码 $status）。" >&2
    if [ "$SWAPPED" -eq 1 ]; then
      echo "线上目录已切换为本次构建且检查未通过，请回滚到上一版：" >&2
      echo "  $(rollback_cmd)" >&2
    else
      echo "远端目录尚未切换，线上仍是旧版本，不必回滚。" >&2
    fi
  fi
}
trap on_exit EXIT

echo "==> 安装依赖"
pnpm install --frozen-lockfile

echo "==> 代码检查"
pnpm lint

echo "==> 构建"
pnpm build
[ -f dist/index.html ] || { echo "构建产物 dist/index.html 不存在。" >&2; exit 1; }

if [[ "${YES:-0}" != "1" ]]; then
  # EOF（如 Ctrl+D / 无 stdin）时视为取消，而不是让 set -e 抛错。
  read -r -p "发布到 ${HOST}? [y/N] " answer || answer=""
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    CANCELLED=1
    echo "已取消。"
    exit 1
  fi
fi

echo "==> 检查服务器连接与 rsync"
if ! ssh "${SSH_OPTS[@]}" "$HOST" "command -v rsync >/dev/null 2>&1"; then
  echo "SSH 连接失败，或服务器缺少 rsync。" >&2
  echo "若 SSH 能登录，请在服务器执行: sudo apt install -y rsync" >&2
  exit 1
fi

echo "==> 准备远端目录"
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$ROOT/app.new' '$ROOT/welcome'"

# 首次部署：把旧的宣传/法律落地页移动到 welcome/，让它继续在 /welcome/ 可访问。
echo "==> 首次部署检查：旧落地页移入 /welcome/"
ssh "${SSH_OPTS[@]}" "$HOST" "
  cd '$ROOT'
  if [ ! -f welcome/index.html ] && [ -f index.html ]; then
    for f in index.html site.css site.js app-icon.png; do
      if [ -f \"\$f\" ]; then mv \"\$f\" welcome/; fi
    done
  fi
"

echo "==> 上传构建产物到 app.new/"
if ! rsync -az --delete -e "ssh -i '$KEY' -o ConnectTimeout=10" dist/ "$HOST:$ROOT/app.new/"; then
  echo "rsync 上传失败。若提示 rsync 不存在，请到服务器执行: sudo apt install -y rsync" >&2
  exit 1
fi

echo "==> 切换版本（app → app.prev，app.new → app）"
ssh "${SSH_OPTS[@]}" "$HOST" "
  set -e
  cd '$ROOT'
  rm -rf app.prev
  if [ -d app ]; then mv app app.prev; fi
  if ! mv app.new app; then
    # 第二次 mv 失败时把旧版本放回去，避免站点目录缺失。
    if [ -d app.prev ]; then mv app.prev app; fi
    exit 1
  fi
"
SWAPPED=1

echo "==> 线上健康检查"
check() {
  local desc="$1" url="$2"
  if curl -fsS --max-time 15 -o /dev/null "$url"; then
    echo "  ✓ $desc"
  else
    echo "  ✗ $desc（$url）" >&2
    return 1
  fi
}
check "后端健康检查 /api/health" "$SITE_URL/api/health"
check "Web 首页" "$SITE_URL/"
check "宣传/落地页 /welcome/" "$SITE_URL/welcome/"

echo ""
echo "发布完成：$SITE_URL"
echo "如需回滚到上一版："
echo "  $(rollback_cmd)"
