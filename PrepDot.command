#!/bin/zsh

APP_DIR="$(cd "$(dirname "$0")/app" && pwd)"
PORT=5173
URL="http://127.0.0.1:${PORT}/"
LOG_FILE="${APP_DIR}/.prepdot-server.log"

if ! lsof -ti tcp:${PORT} >/dev/null 2>&1; then
  cd "${APP_DIR}" || exit 1
  nohup python3 -m http.server "${PORT}" --bind 127.0.0.1 > "${LOG_FILE}" 2>&1 &
  sleep 1
fi

open "${URL}"
