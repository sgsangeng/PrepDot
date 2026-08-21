# PrepDot
PrepDot 是一个 AI 辅助的间隔重复复习应用：用户上传学习资料（文本/PDF/Word/PPT），AI 自动拆解成结构化闪卡并组织成层级卡组，用户按每日计划复习，系统根据复习表现动态调整下次复习时间。

## 本地启动

首次运行前，将 `prepdot-backend/src/main/resources/application.yml.example` 复制为
`application.yml`，并填写 MySQL、JWT 和 AI 配置。之后在项目根目录执行：

```bash
./prepdot.sh start    # 启动 MySQL、后端和 iOS App
./prepdot.sh stop     # 停止整个项目
```

脚本默认优先复用已启动的 iPhone 模拟器；没有已启动设备时使用
`iPhone 17 Pro Max`，并自动构建、安装和打开 PrepDot。停止时只退出 PrepDot App，
保留模拟器运行，方便和 aDeer 共用同一台设备。

后端默认地址为 <http://127.0.0.1:8080>。可通过 `BACKEND_PORT` 修改后端端口，
通过 `SIMULATOR_NAME` 或 `SIMULATOR_UDID` 指定模拟器。
