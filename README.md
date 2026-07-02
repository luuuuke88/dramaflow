# DramaFlow

AI 短剧流水线：小说 → 剧本 → 角色/场景素材 → 分镜 → 镜头图 → 视频。

与 ToonFlow 的核心差异：**显式可控流水线**。没有对话式 Agent——每一步都是你明确点击的动作，产生持久化任务，状态/失败原因全部落库可见、可重试。

## 架构

```
┌─────────────────────────────┐      ┌──────────────────────────┐
│ Flutter App (app/)          │ REST │ 后端 server/ :8620       │
│ macOS/Win/Android/iOS/Web   │─────▶│ Hono + SQLite 任务队列   │
│ 响应式 UI，2s 轮询任务状态  │      │ 显式流水线，串行车道     │
└─────────────────────────────┘      └───────────┬──────────────┘
                                            ┌────┴─────┬─────────────┐
                                       azt :8787   azt :8787   volcengine
                                       gpt-5.5     gpt-image-2  seedance-2.0-mini
                                       (剧本/素材/分镜) (素材图/镜头图)  (视频，待实测)
```

## 快速开始

```bash
./start.sh          # 启动 azt 网关 + 后端
cd app && flutter run -d macos    # 运行桌面 App（或 -d chrome 网页版）
```

后端默认 `http://127.0.0.1:8620`，token `local-dev`（App 设置页可改）。

## 使用流程（App 内）

1. **项目** → 新建项目（可填美术风格，如"国风动漫，厚涂插画风"）
2. **小说** → 粘贴正文 → 保存
3. 流水线页 → **生成剧本**（选集数，gpt-5.5 约 1-3 分钟）
4. **提取素材** → 素材库 → **批量生成图片**（gpt-image-2 每张约 2-5 分钟，串行排队）
5. 进入某一集 → **生成分镜** → 分镜页 → 逐镜/批量生成镜头图
6. 镜头图完成后 → **生成视频**（⚠️ Seedance 通道已接好未实测，首次使用先到设置页确认视频配置）

任一步失败：任务中心/对应卡片会显示**具体失败原因**，点重试即可。

## 已测试 / 未测试

| 环节 | 状态 |
|---|---|
| 剧本生成（azt gpt-5.5） | ✅ 已实测 |
| 素材提取（azt gpt-5.5） | ✅ 已实测 |
| 素材图/镜头图（azt gpt-image-2） | ✅ 已实测 |
| 分镜生成（azt gpt-5.5） | ✅ 已实测 |
| 视频生成（volcengine seedance-2.0-mini） | ⏸ 通道按 ToonFlow 同款参数移植，**未实测**，留给用户验证 |

## 已知行为（来自 azt/Codex OAuth 路径实测）

- 图片接口响应头等到生成完才返回（2-6 分钟），不要在中间层加短超时
- `size`/`quality` 参数是建议性的；构图靠 prompt 内注入的尺寸指令（设置页 `imageSizeDirective` 可调）
- OAuth 路径脆弱，图片/文本车道各自串行（并发=1），宁慢勿炸
- 服务重启时，进行中的任务会标记为"失败：服务重启，任务中断"，手动重试即可

## 开发

```bash
cd server && npm run dev     # 后端热重载
cd server && npm run lint    # tsc --noEmit
cd app && flutter analyze
cd app && flutter build macos --release
```

数据与生成的媒体在 `server/data/`（已 gitignore）。API 契约见 [docs/API.md](docs/API.md)，设计文档见 [docs/DESIGN.md](docs/DESIGN.md)。
