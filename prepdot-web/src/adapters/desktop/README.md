# Desktop Adapters（Phase 2 预留）

Phase 1 只提供 web adapter；桌面端（Tauri / Electron）将在 Phase 2 实现，届时只替换
`createWebAdapters()` 的组装，`src/core` 与 `src/ui` 不需要改动。

映射关系：

- `storage` → SQLite：本地缓存卡片、卡组与学习计划。
- `file` → 系统文件选择对话框：返回同样的 `PickedFile` 结构。
- `notification` → 系统通知：支持应用关闭后的每日提醒。

冲突策略：以服务端为准，本地离线写操作排队回放。

当前目录下的 `storage.ts`、`file.ts`、`notification.ts` 只是空壳，调用时抛出
`new Error('desktop adapter 将在 Phase 2 实现')`。
