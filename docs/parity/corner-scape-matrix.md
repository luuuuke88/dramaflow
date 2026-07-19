# 塑角造景对照：资产参考图与音频绑定

状态：2026-07-19 源码对照 + Flutter 引擎/widget 验证。本页只核对当前注册的
`/cornerScape` 页面；它承接角色、场景、道具三类顶层资产的批量提示词、参考图和
音频绑定，不把素材中心或项目手册的相邻能力重复计入。

## 结论先行

Flutter 已具备完整的资产筛选、可见范围选择、提示词批量生成、图片任务入队、取消、
图片预览、历史图选回、单项提示词编辑/润色/重生成、手动绑定/解绑音频和试听流程。
桌面左侧设置栏与 390dp 单列滚动布局均有直接 widget 证据；所有生成测试都使用本地
fake gateway，未提交、轮询、下载或渲染真实视频。

批量 AI 音频匹配仍有一个可观察缺口：ToonFlow 在提交后立即把所选资产标成“生成中”，
卡片显示音频匹配加载态，并轮询 `audioBindState` 至成功或失败。DramaFlow 仅写一个
`audio_bind` 队列任务；页面重建时只读取最终关联音频，既不写也不呈现资产级
`audioBindState`。因此用户在匹配运行期间无法从资产卡判断工作中或失败，相关音频绑定
结论只能是“部分实现”。

## 用户动作对照

| 用户动作 | ToonFlow 当前行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 浏览角色、场景、道具资产 | 仅列项目内三类顶层资产，显示选中图、历史图、提示词、模型/分辨率和关联音频 | `cornerScapeAssets` 只读取三类父资产与全量图片历史；卡片显示选中图、提示词、模型/分辨率与一个已绑定音频 | 已验证等价 |
| 类型筛选与快捷选择 | 角色/场景/道具多选；全选、提示词为空、未生成、已完成、失败、反选、清空 | 同一组类型筛选与快捷选择；选择集合会随可见集合收敛 | 已验证等价 |
| 批量提示词 | 选中资产后以补充要求发起批量润色，并显示生成中 | 同样以 `asset_prompt_polish` 队列入队、受花费确认保护；任务状态与提示词结果由本地队列驱动 | 已验证等价 |
| 批量参考图 | 选择模型/1K-4K/补充词，缺提示词阻断，提交后可取消并预览 | 同一参数、提示词校验、花费确认、任务取消与图片预览；只写本地队列，真实供应商由用户验收 | 已验证等价 |
| 详情与历史图 | 打开抽屉，可选历史完成图、失焦保存提示词、润色与单图重生成 | 自适应详情弹层实现相同流程；历史失败图不可选，避免将失败产物设为当前图 | 已验证等价 |
| 手动绑定/解绑和试听 | 单选音频，绑定覆盖旧值；可移除关联 | 项目内父音频下拉、单值覆盖/解绑、可用本地文件试听 | 已验证等价 |
| 批量 AI 音频匹配的进行中/失败反馈 | 所选资产写 `audioBindState=生成中`，卡片加载态，轮询后显示结果 | 只创建 `audio_bind` 任务；卡片没有运行/失败状态或原因 | 部分实现 |

## 证据与边界

| 范围 | ToonFlow | DramaFlow |
| --- | --- | --- |
| 实际页面 | `Toonflow-web/src/router/index.ts:30-33` → `views/cornerScape/index.vue` | `app/lib/src/screens/cornerscape/corner_scape_screen.dart` |
| 资产数据 | `cornerScape/getAllAssets.ts:16-66` | `assets.dart:240-262` |
| 图片任务 | `cornerScape/index.vue:523-740` 调共享资产生成路由 | `corner_scape_screen.dart:128-264`、`assets.dart` 的 `asset_image_generation` 队列 |
| 音频匹配状态 | `cornerScape/index.vue:664-685,838-953` 和 `batchBindAudio.ts` | `audio_bind.dart:182-245`；`db.dart` 有 `audioBindState` 列，但运行时没有写入/读取显示路径 |

## 自动化验证

本次收尾将复跑：

```sh
cd app
flutter test --concurrency=1 \
  test/widgets/corner_scape_screen_test.dart \
  test/engine/assets_test.dart \
  test/engine/audio_bind_test.dart
```

这些测试只使用内存数据库、临时本地媒体和 fake gateway；不会调用文本、图片、TTS 或
视频供应商。现有用例直接覆盖 390dp 单列滚动、类型和状态选择、历史图、取消的竞态
保护、提示词润色、场景/道具通用音频绑定及音频试听按钮状态。

当前 `develop` 已按上述命令复跑，结果为 60 条通过；相关三份实现文件的
`flutter analyze` 同时无诊断。验证仍只覆盖本地任务状态和假网关协议，未发起任何
真实生成请求。

## 后续实现边界

补齐音频状态时，沿用队列任务作为唯一事实来源：提交时记录选中资产，页面根据该任务的
`pending/processing/failed/done` 映射每张卡的“匹配中/失败原因/已完成”展示。不要把
独立轮询定时器或第二套状态机塞回页面。实现必须补引擎映射测试，以及桌面和 390dp 卡片
的处理中/失败态回归；不需要，也不得为此发起真实视频任务。

关联总清单：`W6-CORNERSCAPE-001`、`W6-CORNERSCAPE-002`、
`W7E-CORNERSCAPE-AUDIO-001`、`W7E-CORNERSCAPE-ASSETS-001`。
