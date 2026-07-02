# DramaFlow

AI 短剧流水线：小说 → 剧本 → 角色/场景/道具素材 → 分镜 → 镜头图 → 视频。

**单体多端 Flutter App**：引擎内嵌（Dart），数据与媒体全部本地，无需任何后台服务。目标平台 macOS / iOS / iPad / Android（Windows 后置）。

## 架构（v0.2 M0 起）

```
┌──────────────────────────────────────────────┐
│ Flutter App（app/）                           │
│ ┌──────────────┐   ┌───────────────────────┐ │
│ │ UI (Riverpod) │──▶│ 内嵌引擎 lib/src/engine│ │
│ └──────────────┘   │ sqlite3 + 任务队列     │ │
│                    │ + 供应商适配器(dio)    │ │
│                    └───────────┬───────────┘ │
└────────────────────────────────┼─────────────┘
                     ┌───────────┴───────────┐
                openai 兼容端点          volcengine ark
                （azt / ark / 任意）      （seedance 视频）
```

- **显式流水线**：每步用户触发、任务落库、失败原因可见、可重试
- **供应商可配置**：桌面默认 azt（本机 Codex OAuth 网关），移动端默认火山 ark（填自己的 key）；M2 起界面可插拔任意 OpenAI 兼容服务
- `server/`：v0.1 的 Node 后端，**已弃用**，仅作移植参照

## 运行

```bash
cd app
flutter run -d macos      # 桌面（开发机默认走 azt，需 azt serve 在跑）
flutter run -d <android>  # 移动端（设置页填火山 ark key）
flutter test              # 引擎单测
flutter analyze
```

macOS 数据目录：`~/Library/Containers/com.dramaflow.dramaflow/Data/Documents/dramaflow/`

## 已验证（M0，2026-07-03）

- 引擎 58+ 单测全绿；macOS 真实 E2E：小说→剧本→素材提取（含道具）→生图 全链路通过（azt gpt-5.5 / gpt-image-2）
- Android APK 构建通过；冷启动恢复 / 运行中取消 / 车道串行 均有测试覆盖
- 视频链路（volcengine seedance）按 ToonFlow 同款参数移植，**待真机实测**

## 已知约束

- 移动端长任务依赖前台+屏幕常亮（生成期间自动 wakelock），锁屏可能中断——任务会标失败、可重试
- 图片经 Codex OAuth 路径实际返回约 1254×1254，尺寸靠提示词指令控制
- Web 构建仅作 UI 预览（无本地文件/ffmpeg 能力）

## 文档

- 设计：[docs/superpowers/specs/2026-07-02-v0.2-providers-and-pipeline-close-design.md](docs/superpowers/specs/2026-07-02-v0.2-providers-and-pipeline-close-design.md)
- M0 计划：[docs/superpowers/plans/2026-07-03-m0-embedded-engine.md](docs/superpowers/plans/2026-07-03-m0-embedded-engine.md)
- 路线：M1 UI重构（对标 ToonFlow）→ M2 配置后台 → M3 成片闭环 → M3.5 自动连跑 → M4 重绘 → M5 配音
