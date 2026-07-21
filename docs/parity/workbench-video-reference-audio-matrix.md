# 工作台视频参考音频对照

## 结论

ToonFlow 在装配工作台数据时，会把分镜关联角色、场景或道具的 `o_assetsRole2Audio` 绑定音频放入该镜头的媒体参考。DramaFlow 现已在同一可观察位置恢复此行为：打开视频参数，在多参考模式选择音频，保存后以 `reference_audio` 提交给视频供应商适配层。

## 对照

| 环节 | ToonFlow 1.1.8 | DramaFlow | 结论 |
| --- | --- | --- | --- |
| 关联范围 | `getGenerateData.ts` 从分镜关联资产及其父资产读取 `o_assetsRole2Audio` | `videoReferenceCandidates` 对同一两级资产关系读取绑定 | 等价 |
| 音频文件定位 | `o_assets`/`o_image` 解析 OSS 文件 URL | 音频父资产自身优先，回退首个有文件的子样本；只接受媒体根目录内的本地普通文件 | 等价 |
| 模型限制 | 读取 `audioReference:N` 后截取音频 | `VideoModelCapabilities.referenceLimits['audio']` 限制参数弹窗的可勾选数量 | 等价 |
| 草稿和请求 | 媒体项标为 `fileType: audio`，随后由生成请求消费 | 草稿存 `sourceType: audio`、`role: reference_audio`；最终解析为相对本地路径 | 等价 |

## 验证证据

- `app/test/engine/video_track_test.dart`：关联角色的已绑定音色子样本进入候选；不相关音色不会进入。
- `app/test/widgets/workbench_screen_test.dart`：390dp 宽度下打开视频参数、选择音频参考、保存草稿，再由引擎成功构建 `reference_audio` 请求。
- 测试夹具只写本地临时文件，不调用文本、图片、音频或视频供应商。
