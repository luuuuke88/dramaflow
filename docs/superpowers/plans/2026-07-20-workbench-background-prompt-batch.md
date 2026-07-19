# 工作台后台批量运镜提示词实施记录

目标：对齐 ToonFlow `batchGeneratePrompt/checkVideoPrompt` 的可观察行为。用户选择镜头后立即返回，镜头分别展示生成中、已完成或生成失败，任务可在后台继续执行。

边界：不提交或轮询真实视频；不修改 `o_secret` 本地 SQLite 密钥策略；不改变既有视频候选 `state` 语义。测试只使用内存 SQLite、临时目录与 fake gateway。

## 完成项

- [x] 在 `o_videoTrack` 增加独立的 `promptState` 与 `promptErrorReason`，避免提示词工作流覆盖视频候选状态。
- [x] 新增 `video_prompt_generation` 文本车道任务；入队即标记生成中，后台按受限并发逐镜生成，允许部分成功。
- [x] 每轨以 `promptTaskId` 记录当前任务归属；取消、冷启动恢复、手动编辑、单镜替代、单镜失败和清轨都会使旧任务失效，迟到结果不能覆写较新的内容或复活已删轨道；失败任务重试会原子认领新的任务 ID。
- [x] 引擎拒绝把已有活跃提示词任务的同一轨道再次入队，避免重复收费。
- [x] 工作台批量入口经过费用确认策略、即时入队并提示已开始；每个镜头展示状态；任务中心显示“视频提示词生成”。
- [x] 中文、英文、日文补齐批量开始反馈和任务类别文案，并执行 `flutter gen-l10n`。
- [x] 更新主清单 `W7B-WB-PROMPT-BATCH-001`、工作台矩阵和执行总览；其他工作台缺口维持原判定。

## 验证门

- [x] `flutter test --concurrency=1 --reporter compact` 全量离线测试通过（890 条）。
- [x] `flutter analyze` 零 issue。
- [x] `flutter build macos --debug` 构建成功。
- [x] `node tool/parity/check_no_orphans.js`（538/538）和 `git diff --check` 通过。

真实文本、图像、音频和视频供应商调用不属于本次验证；上述离线门全部通过后，才将清单项标记为“已验证等价”。
