# DramaFlow API 契约 v1

Base: `http://127.0.0.1:8620/api`（端口 8620，避开 azt/ima2/ToonFlow 常用端口）
认证: `Authorization: Bearer <token>`（默认 `local-dev`）；媒体文件支持 `?token=`。

所有响应统一信封：
```json
{ "ok": true, "data": ... }          // 成功
{ "ok": false, "error": "人类可读的中文错误" }  // 失败，HTTP 4xx/5xx
```

时间一律 ISO8601 字符串。id 一律字符串（nanoid）。

## 健康
- `GET /health` → `{ ok, data: { version, uptime, providers: { text: "ok"|"error:...", image: "ok"|..., video: "unconfigured"|"configured" } } }`（providers 状态来自最近一次实际调用缓存，不主动探测）

## 项目
- `GET /projects` → `[{ id, name, artStyle, createdAt, updatedAt, stats: { episodes, assets, assetsDone, shots, shotsImageDone, shotsVideoDone, hasNovel } }]`
- `POST /projects` body `{ name, artStyle? }` → project
- `GET /projects/:id` → project + stats
- `PATCH /projects/:id` body `{ name?, artStyle? }` → project
- `DELETE /projects/:id` → `{}`

## 小说
- `GET /projects/:id/novel` → `{ id, title, content } | null`
- `PUT /projects/:id/novel` body `{ title, content }` → novel（覆盖式保存）

## 剧本（分集）
- `POST /projects/:id/generate-script` body `{ episodeCount?: number }`（默认 3）→ `{ jobId }`
  - 前置：必须已有 novel，否则 400 "请先导入小说"
- `GET /projects/:id/episodes` → `[{ id, idx, title, synopsis, status, error, sceneCount }]`
- `GET /episodes/:id` → `{ id, idx, title, synopsis, status, error, scenes: [{ idx, location, timeOfDay, action, dialogues: [{ speaker, line }] }] }`
- `PUT /episodes/:id` body `{ title?, synopsis?, scenes? }` → episode（人工修订）

## 素材（角色/场景）
- `POST /projects/:id/extract-assets` → `{ jobId }`（前置：至少一集剧本 done）
- `GET /projects/:id/assets` → `[{ id, kind, name, description, imagePrompt, imageUrl, status, error }]`
  - `imageUrl` 为 `/media/...` 相对路径或 null；status: `draft|queued|running|done|failed`
- `PATCH /assets/:id` body `{ name?, description?, imagePrompt? }` → asset
- `POST /assets/:id/generate-image` → `{ jobId }`（已 queued/running 则 409）
- `POST /projects/:id/generate-all-asset-images` → `{ jobIds: [...] }`（跳过已 done/queued/running 的）

## 分镜（镜头）
- `POST /episodes/:id/generate-storyboard` → `{ jobId }`（前置：该集剧本 done；素材已提取则注入素材上下文）
- `GET /episodes/:id/shots` → `[{ id, idx, description, dialogue, camera, assetNames, imagePrompt, imageUrl, imageStatus, imageError, videoPrompt, videoUrl, videoStatus, videoError }]`
- `PATCH /shots/:id` body `{ description?, dialogue?, camera?, imagePrompt?, videoPrompt? }` → shot
- `POST /shots/:id/generate-image` → `{ jobId }`
- `POST /episodes/:id/generate-all-shot-images` → `{ jobIds }`
- `POST /shots/:id/generate-video` → `{ jobId }`（前置：镜头图 done，否则 400 "请先生成镜头图"）

## 任务
- `GET /jobs/active` → `[{ id, projectId, kind, targetId, targetLabel, state, attempt, createdAt, startedAt }]`（queued+running，全项目）
- `GET /projects/:id/jobs?limit=50` → 最近任务（含 done/failed，desc）`[{ ..., error, finishedAt, durationMs }]`
- `POST /jobs/:id/retry` → `{ jobId }`（新 job，沿用原 payload；仅 failed 可重试）
- `POST /jobs/:id/cancel` → `{}`（queued 直接取消；running 标记取消并尽力中断）

## 设置
- `GET /settings` → `{ textBaseUrl, textApiKey, textModel, imageBaseUrl, imageApiKey, imageModel, videoProvider, videoApiKey(打码), videoModel, apiToken(打码), concurrency: {...} }`
- `PUT /settings` body 同上任意子集 → 更新后的 settings（打码字段传空字符串=不修改）

## 媒体
- `GET /media/<path>?token=` → 图片/视频文件（Content-Type 自动）

## job.kind 枚举
`script_gen | asset_extract | asset_image | storyboard_gen | shot_image | shot_video`

## 轮询约定（客户端行为）
- 有活跃 job：每 2s 轮询 `/jobs/active`；某 job 从列表消失 → 刷新对应实体列表
- 无活跃 job：停止轮询
