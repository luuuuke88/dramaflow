# 工作台候选视频导出对照

## 范围

本表只覆盖工作台中已经落到本地媒体目录的视频候选导出。测试只构造短字节夹具；不提交视频生成任务，也不请求任何供应商。

| 动作 | ToonFlow 1.1.8 | DramaFlow | 结论 |
| --- | --- | --- | --- |
| 单个候选下载 | `video.vue` 的完成候选显示下载图标；`downloadVideo` 将远端 `src` 拉为 blob 后由浏览器下载 | 完成候选显示下载图标；`exportVideoCandidateToFile` 通过系统保存面板将安全的本地媒体文件复制到目标位置 | 等价 |
| 批量下载 | `track.vue` 按 `checkedTrackIds` 取每条轨的 `selectVideoId`，JSZip 打包后浏览器下载 | 工作台按已勾选分镜取每轨 `selectVideoId`，`exportVideoCandidatesToFile` 以 ZIP 写到系统保存位置 | 等价 |
| 非完成或缺文件候选 | 原版没有可下载的 `src` 时跳过 | 仅 `state=已完成` 且 `MediaStore.existingFilePath` 仍在媒体根目录的普通文件会进入导出 | 等价，且本地路径边界更严格 |
| 选择取消 | 原版批量下载结束后清空勾选轨道 | ZIP 写入结束后清空同一组已勾选分镜 | 等价 |

## 实现边界

- [`video_track.dart`](../../app/lib/src/engine/video_track.dart) 使用 `MediaStore.existingFilePath` 拒绝绝对路径、`..` 与符号链接逃逸；ZIP 写入放在独立 isolate，避免 UI isolate 汇集视频字节。
- [`workbench_screen.dart`](../../app/lib/src/screens/production/workbench_screen.dart) 的单候选按钮仅在完成态可见；批量按钮复用已有分镜勾选集，因此不会引入第二套候选选择状态。
- 原版网页从远端 URL 下载，Flutter 只处理此前已经由应用保存的本地文件。这是原生单体应用的数据边界差异，不会改动用户“另存/批量 ZIP”的结果。

## 离线证据

- `app/test/engine/video_track_test.dart`：已选完成候选 ZIP 的文件名和字节、缺失/生成中/越界路径的拒绝、单文件复制。
- `app/test/widgets/workbench_screen_test.dart`：完成候选请求 `.mp4` 保存；已勾选镜头请求 `.zip` 保存并导出该轨已选正片。
- 验证命令：`flutter test test/engine/video_track_test.dart`、`flutter test test/widgets/workbench_screen_test.dart`、`flutter analyze`。
