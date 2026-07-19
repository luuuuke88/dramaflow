# DramaFlow 工程规范（执行代理必读）

单体多端 Flutter App：AI 短剧流水线（小说→剧本→素材→分镜→镜头图→视频）。引擎内嵌（Dart），无后台服务。`server/` 目录已弃用，仅作移植参照，禁止修改。

## 结构

- `app/lib/src/engine/` — 内嵌引擎（sqlite3 直用 + dio + 事件广播队列）。**改动引擎必须同步补测试**（`app/test/engine/`）
- `app/lib/src/screens|widgets|state/` — 界面层（Riverpod 3 + go_router）
- `app/lib/src/api/models.dart` — 数据模型（手写 fromJson，无代码生成）
- 设计文档：`docs/superpowers/specs/2026-07-02-v0.2-providers-and-pipeline-close-design.md`

## 硬性规则

1. 完成任何任务前必须通过：`cd app && flutter analyze`（零 issue）+ `flutter test`（全绿）
2. 引擎层是纯 Dart：禁止在 `engine/` 引入 Flutter 依赖（`main.dart` 注入路径除外）
3. 错误信息一律中文、人类可读；一切生成失败必须落库带原因、可重试
4. UI 文案中文；状态显示统一走 `StatusChip`；变更操作统一走 `runAction`（错误 SnackBar + poke 轮询）
5. Riverpod 3 语法（Notifier/NotifierProvider；AsyncValue.value 而非 valueOrNull；StateProvider 需 legacy import——尽量避免）
6. 数据库 schema 变更需改 `engine/db.dart` 的 `initSchema` 并 bump `PRAGMA user_version` + 写迁移；禁止 ad-hoc ALTER
7. 提交信息用 conventional commits；不要提交 build 产物
8. 禁止运行 `server/` 下任何东西；禁止调用外部网络 API 做测试（测试用 fake/mock）

## 供应商密钥策略

- 供应商 API Key 固定经 `app/lib/src/engine/credentials.dart` 的
  `DbCredentialStore` 存入本地 SQLite `o_secret` 表。这样不会触发 macOS
  钥匙串授权，且 macOS/iOS/Android/Windows/Linux 行为一致。
- **禁止**在未获 Luke 明确同意时恢复 `flutter_secure_storage`、系统钥匙串、
  或自动迁移旧钥匙串密钥。
- `o_secret` 不得进入配置导出、日志、测试快照或 git 提交；`clearAllData`
  保留它以与供应商配置保持一致。
- 此策略由 `71c844d` 落地并已验证。后续涉及供应商设置、凭证迁移或安全
  加固的改动，必须保持上述本地 SQLite 行为，不能以“更安全”为由擅自改回
  macOS 钥匙串授权流程。

## 批量剧本导入契约

- 批量剧本导入默认按“第 N 集”拆分；小说导入才按“第 N 章”拆分。
- 进入第二步时默认**不勾选**任何分集，用户自行选择后才可保存。这是 ToonFlow
  对齐行为，测试和界面改动不得擅自恢复为默认全选（见 `8ecc8f6`）。

## 常用命令

```bash
cd app
flutter analyze          # 静态检查（必须零 issue）
flutter test             # 引擎单测（当前 58 个）
flutter build macos --debug
```
