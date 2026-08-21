#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${ROOT_DIR}/prepdot-backend"
IOS_DIR="${ROOT_DIR}/prepdot-ios/PreDot"
IOS_PROJECT="${IOS_DIR}/PrepDot.xcodeproj"
RUN_DIR="${ROOT_DIR}/.run"
LOG_DIR="${ROOT_DIR}/logs"
IOS_DERIVED_DATA="${RUN_DIR}/ios-build"
BACKEND_PID_FILE="${RUN_DIR}/backend.pid"
SIMULATOR_FILE="${RUN_DIR}/simulator.udid"
MYSQL_MARKER="${RUN_DIR}/mysql.started-by-prepdot"
BACKEND_LOG="${LOG_DIR}/backend.log"
XCODE_LOG="${LOG_DIR}/xcodebuild.log"
BACKEND_PORT="${BACKEND_PORT:-8080}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro Max}"
BUNDLE_ID="com.prepdot.app"

mkdir -p "${RUN_DIR}" "${LOG_DIR}"

info() { printf '\033[1;34m[PrepDot]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[完成]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[提示]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

pid_is_running() {
  local pid_file="$1" pid
  [[ -f "${pid_file}" ]] || return 1
  pid="$(cat "${pid_file}" 2>/dev/null)"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null
}

port_pid() {
  lsof -ti "tcp:$1" -sTCP:LISTEN 2>/dev/null | head -n 1
}

ensure_port_free() {
  local port="$1" name="$2" pid
  pid="$(port_pid "${port}")"
  [[ -z "${pid}" ]] || fail "${name} 端口 ${port} 已被 PID ${pid} 占用，请先处理后重试。"
}

mysql_is_running() {
  if command_exists mysqladmin && mysqladmin ping --silent >/dev/null 2>&1; then
    return 0
  fi
  command_exists brew && brew services list 2>/dev/null | awk '$1 ~ /^mysql(@.*)?$/ && $2 == "started" { found=1 } END { exit !found }'
}

start_mysql() {
  if mysql_is_running; then
    ok "MySQL 已在运行"
    return
  fi
  command_exists brew || fail "未检测到运行中的 MySQL，且找不到 Homebrew。请先启动 MySQL。"

  local formula
  formula="$(brew list --formula 2>/dev/null | awk '/^mysql(@.*)?$/ { print; exit }')"
  [[ -n "${formula}" ]] || fail "未找到 Homebrew MySQL。请先安装 MySQL，或手动启动已有实例。"
  info "启动 MySQL (${formula})..."
  brew services start "${formula}" >/dev/null || fail "MySQL 启动失败。"
  touch "${MYSQL_MARKER}"

  local i
  for i in {1..20}; do
    mysql_is_running && { ok "MySQL 已启动"; return; }
    sleep 1
  done
  fail "等待 MySQL 就绪超时，请运行 brew services list 查看状态。"
}

start_backend() {
  if pid_is_running "${BACKEND_PID_FILE}"; then
    ok "后端已在运行 (PID $(cat "${BACKEND_PID_FILE}"))"
    return
  fi
  rm -f "${BACKEND_PID_FILE}"
  ensure_port_free "${BACKEND_PORT}" "后端"
  command_exists mvn || fail "找不到 Maven (mvn)，请先安装并加入 PATH。"
  [[ -f "${BACKEND_DIR}/src/main/resources/application.yml" ]] || \
    fail "缺少 application.yml，请复制 application.yml.example 并填写数据库配置。"

  info "启动 Spring Boot 后端..."
  (
    cd "${BACKEND_DIR}" || exit 1
    nohup mvn spring-boot:run \
      -Dspring-boot.run.arguments="--server.port=${BACKEND_PORT}" \
      >"${BACKEND_LOG}" 2>&1 &
    echo "$!" >"${BACKEND_PID_FILE}"
  )

  local i
  for i in {1..60}; do
    if ! pid_is_running "${BACKEND_PID_FILE}"; then
      rm -f "${BACKEND_PID_FILE}"
      warn "后端启动失败，日志末尾如下："
      tail -n 30 "${BACKEND_LOG}" 2>/dev/null
      exit 1
    fi
    if [[ -n "$(port_pid "${BACKEND_PORT}")" ]]; then
      ok "后端已启动：http://127.0.0.1:${BACKEND_PORT}"
      return
    fi
    sleep 1
  done
  warn "后端仍在启动，请查看日志：${BACKEND_LOG}"
}

find_simulator() {
  local udid
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    printf '%s\n' "${SIMULATOR_UDID}"
    return
  fi
  udid="$(xcrun simctl list devices available | \
    awk '/-- iOS / { ios=1; next } /^-- / { ios=0 } ios && /\(Booted\)/ && /iPhone/ { if (match($0, /[0-9A-Fa-f-]{36}/)) { print substr($0, RSTART, RLENGTH); exit } }')"
  if [[ -z "${udid}" ]]; then
    udid="$(xcrun simctl list devices available | \
      awk -v name="${SIMULATOR_NAME}" 'index($0, name " (") { if (match($0, /[0-9A-Fa-f-]{36}/)) { print substr($0, RSTART, RLENGTH); exit } }')"
  fi
  if [[ -z "${udid}" ]]; then
    udid="$(xcrun simctl list devices available | \
      awk '/-- iOS / { ios=1; next } /^-- / { ios=0 } ios && /iPhone/ { if (match($0, /[0-9A-Fa-f-]{36}/)) { print substr($0, RSTART, RLENGTH); exit } }')"
  fi
  printf '%s\n' "${udid}"
}

start_ios() {
  command_exists xcrun || fail "找不到 xcrun，请先安装 Xcode。"
  command_exists xcodebuild || fail "找不到 xcodebuild，请先安装 Xcode。"
  [[ -d "${IOS_PROJECT}" ]] || fail "找不到 iOS 工程：${IOS_PROJECT}"

  local udid app_path
  udid="$(find_simulator)"
  [[ -n "${udid}" ]] || fail "没有可用的 iPhone 模拟器，请先在 Xcode 中创建一个。"
  printf '%s\n' "${udid}" >"${SIMULATOR_FILE}"

  info "启动 iOS 模拟器 (${udid})..."
  open -a Simulator
  xcrun simctl boot "${udid}" 2>/dev/null || true
  xcrun simctl bootstatus "${udid}" -b || fail "iOS 模拟器启动失败。"

  info "构建 PrepDot iOS App..."
  xcodebuild -project "${IOS_PROJECT}" -scheme PrepDot -configuration Debug \
    -destination "platform=iOS Simulator,id=${udid}" \
    -derivedDataPath "${IOS_DERIVED_DATA}" build >"${XCODE_LOG}" 2>&1 || {
      tail -n 40 "${XCODE_LOG}" >&2
      fail "iOS 构建失败，完整日志：${XCODE_LOG}"
    }
  app_path="${IOS_DERIVED_DATA}/Build/Products/Debug-iphonesimulator/PrepDot.app"
  [[ -d "${app_path}" ]] || fail "构建完成但找不到 ${app_path}。"
  xcrun simctl install "${udid}" "${app_path}" || fail "App 安装失败。"
  xcrun simctl launch "${udid}" "${BUNDLE_ID}" || fail "App 启动失败。"
  ok "PrepDot 已在 iOS 模拟器中启动"
}

stop_ios() {
  [[ -f "${SIMULATOR_FILE}" ]] || { warn "没有记录 PrepDot 使用的模拟器"; return; }
  local udid
  udid="$(cat "${SIMULATOR_FILE}")"
  xcrun simctl terminate "${udid}" "${BUNDLE_ID}" 2>/dev/null || true
  rm -f "${SIMULATOR_FILE}"
  ok "PrepDot iOS App 已停止（模拟器保持运行，方便与 aDeer 共用）"
}

stop_process() {
  local name="$1" pid_file="$2" pid child i
  if ! pid_is_running "${pid_file}"; then
    rm -f "${pid_file}"
    warn "${name}未运行"
    return
  fi
  pid="$(cat "${pid_file}")"
  info "停止${name} (PID ${pid})..."
  # Maven 会创建 Java 子进程，先温和停止整个进程树。
  while read -r child; do
    [[ -n "${child}" ]] && kill -TERM "${child}" 2>/dev/null || true
  done < <(pgrep -P "${pid}" 2>/dev/null || true)
  kill -TERM "${pid}" 2>/dev/null || true
  for i in {1..10}; do
    kill -0 "${pid}" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "${pid}" 2>/dev/null; then
    warn "${name}未及时退出，正在强制停止。"
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
  ok "${name}已停止"
}

stop_mysql_if_owned() {
  [[ -f "${MYSQL_MARKER}" ]] || { warn "MySQL 不是由本脚本启动，保持运行"; return; }
  if command_exists brew; then
    local formula
    formula="$(brew services list 2>/dev/null | awk '$1 ~ /^mysql(@.*)?$/ && $2 == "started" { print $1; exit }')"
    if [[ -n "${formula}" ]]; then
      info "停止 MySQL (${formula})..."
      brew services stop "${formula}" >/dev/null && ok "MySQL 已停止" || warn "MySQL 停止失败"
    fi
  fi
  rm -f "${MYSQL_MARKER}"
}

start_all() {
  info "启动整个项目"
  start_mysql
  start_backend
  start_ios
  printf '\niOS：  已安装并启动到模拟器\n后端： http://127.0.0.1:%s\n日志： %s\n' \
    "${BACKEND_PORT}" "${LOG_DIR}"
}

stop_all() {
  info "停止整个项目"
  stop_ios
  stop_process "后端" "${BACKEND_PID_FILE}"
  stop_mysql_if_owned
}

usage() {
  echo "用法: $0 {start|stop}"
}

case "${1:-}" in
  start) start_all ;;
  stop) stop_all ;;
  *) usage; exit 2 ;;
esac
