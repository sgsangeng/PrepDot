#!/bin/bash
# PrepDot 一键启动脚本
# 用法：./start.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PrepDot 启动中..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ① 检查并启动 MySQL
echo ""
echo "【1/3】检查 MySQL..."
if brew services list | grep mysql | grep -q "started"; then
    echo "  ✅ MySQL 已在运行"
else
    echo "  🔄 启动 MySQL..."
    brew services start mysql
    sleep 2
    echo "  ✅ MySQL 启动完成"
fi

# ② 释放 8080 端口
echo ""
echo "【2/3】释放 8080 端口..."
PID=$(lsof -ti:8080)
if [ -n "$PID" ]; then
    kill -9 $PID
    echo "  ✅ 已关闭旧进程 (PID: $PID)"
else
    echo "  ✅ 端口空闲，无需处理"
fi

# ③ 启动 Spring Boot 后端（同时托管前端页面）
echo ""
echo "【3/3】启动后端..."
echo ""
echo "  后端 API  → http://localhost:8080/api"
echo "  网页预览  → http://localhost:8080"
echo "  API 文档  → http://localhost:8080/doc.html"
echo ""
echo "  提示：Ctrl+C 可停止服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$(dirname "$0")"
JAVA_HOME=/Users/tangzishan/Library/Java/JavaVirtualMachines/ms-17.0.18/Contents/Home \
mvn spring-boot:run
