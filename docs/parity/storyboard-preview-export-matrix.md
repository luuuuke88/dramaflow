# 分镜整体预览与导出对照

更新时间：2026-07-21

本记录只核对制作画布分镜节点的“预览全部”和“导出全部”。它不把逐镜查看、图片流编辑或工作台快速预览混进来，避免“能看到全部图片”被误判为原版的联系表功能。

## 结论

**已验证等价。** DramaFlow 现在会把有效首帧按原版规则合成为一张带连续 `S01…` 标签的联系表：预览使用缩略 JPEG，导出使用原尺寸 PNG。文件读取、解码和合成都在后台 isolate 内执行，画布线程只等待最终字节结果。

对应总清单条目：

- `W6B-NODE-STORYBOARD-002`：制作画布的预览/下载入口。
- `W7B-SB-EXPORT-001`：网格合成、预览和单文件导出。

## 行为逐项对照

| 行为 | ToonFlow 1.1.8 | DramaFlow | 验证 |
| --- | --- | --- | --- |
| 取图与顺序 | 前端按当前分镜顺序取有图 ID；后端依提交顺序重建路径并跳过无文件、不可读或无尺寸图片。 | `StoryboardCanvasNode` 按当前分镜顺序传绝对路径；后台合成器跳过不存在、不可读和不能解码的文件。 | 纯合成器覆盖坏字节过滤；widget 以两张有效图加一张未生成图验证只合成有效图。 |
| 布局 | 最多五列；每列取最大宽、每行取最大高；白底，原图从格子左上角贴入，不裁切、不拉伸。 | `storyboard_contact_sheet.dart` 使用相同五列、列宽/行高规则和白底 `compositeImage`。 | 不同画幅的六张夹具锁定 5 列换行、跨行最大列宽与最大行高。 |
| 标签 | 有效图从 `S01` 连续编号，左上角半透明黑底白字；背景尺寸由 `fontSize=max(14,min(width,height)*.06)` 与 `padding=round(fontSize*.4)` 得出。 | 合成器按过滤后的有效图连续编号，绘制圆角半透明标签，并按同一公式计算背景矩形。 | PNG/JPEG 均经解码验证；编号由同一渲染循环生成，100×100px 夹具像素回归锁定原版标签背景高度。 |
| 页内预览 | 单图最大宽 512px 后合成 JPEG data URL；查看器缩放范围 0.1–10，并提供下载操作。 | 单图宽度超过 512px 时先等比缩小，再生成 JPEG；全屏联系表使用同范围 `InteractiveViewer`，顶部提供下载图标。 | 纯函数锁定 1024px 宽图变为 512px 与 JPEG 输出；widget 锁定 `0.1–10` 和预览内下载按钮，桌面和 390dp 均回归。 |
| 下载 | 保留原尺寸合成，下载一张 `storyboardImagePreview-<timestamp>.png`。 | 系统保存面板以同名格式建议保存，写出一张可解码 PNG。 | widget 假保存面板断言 PNG 类型、时间戳文件名、单文件落盘及可解码内容；390dp 从预览内下载也覆盖。 |
| 无图 | 警告提示，不打开查看器或下载。 | 同样显示本地化提示，且不会调用保存面板。 | widget 回归覆盖。 |

## 实现边界

- 合成工具是纯 Dart 模块 [`storyboard_contact_sheet.dart`](../../app/lib/src/util/storyboard_contact_sheet.dart)，不依赖数据库、页面状态或供应商。
- `compute` 在后台 isolate 执行读文件、解码与合成，避免大图 I/O 占用画布交互线程。
- 本项只处理已存在的本地首帧，不入队、不调用文本、图像、语音或视频供应商；真实视频生成仍留给最终人工验收。

## 可重复验证

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/util/storyboard_contact_sheet_test.dart \
  test/widgets/storyboard_canvas_node_test.dart
flutter analyze
```

测试覆盖完整 PNG、缩略 JPEG、五列换行、坏图过滤、后台 isolate 传递、无图提示、原版缩放范围、预览内下载、桌面保存面板实际写盘，以及 390dp 移动壳的预览和下载入口。所有夹具为本地临时图片；没有真实模型或视频请求。
