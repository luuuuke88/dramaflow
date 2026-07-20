# 塑角造景对照：资产参考图与音频绑定

状态：2026-07-21 源码对照 + Flutter 引擎/widget 验证。本页只核对当前注册的
`/cornerScape` 页面；它承接角色、场景、道具三类顶层资产的批量提示词、参考图和
音频绑定，不把素材中心或项目手册的相邻能力重复计入。

## 结论先行

Flutter 已具备完整的资产筛选、可见范围选择、提示词批量生成、图片任务入队、取消、
图片预览、历史图选回、单项提示词编辑/润色/重生成、手动绑定/解绑音频和试听流程。
桌面左侧设置栏与 390dp 单列滚动布局均有直接 widget 证据；所有生成测试都使用本地
fake gateway，未提交、轮询、下载或渲染真实视频。

批量 AI 音频匹配现已闭合原版的可观察状态链：提交时仅对项目内所选角色、场景、道具
父资产写 `audioBindState=生成中`；成功写“已完成”，LLM、候选池或重启恢复失败均写
“生成失败”。卡片在音频匹配中优先显示加载态，失败时保留资产可操作性并显示失败标签。
Flutter 由同一个本地队列事件刷新页面，不额外引入 HTTP 轮询或第二套状态机。

原版仅持久化三种状态，并**不**保存音频绑定失败原因；DramaFlow 因此同样只显示失败状态，
不伪造一个无法与原版对照的错误字段。

## 用户动作对照

| 用户动作 | ToonFlow 当前行为 | DramaFlow 当前行为 | 判定 |
| --- | --- | --- | --- |
| 浏览角色、场景、道具资产 | 仅列项目内三类顶层资产，显示选中图、历史图、提示词、模型/分辨率和关联音频 | `cornerScapeAssets` 只读取三类父资产与全量图片历史；卡片显示选中图、提示词、模型/分辨率与一个已绑定音频 | 已验证等价 |
| 类型筛选与快捷选择 | 角色/场景/道具多选；全选、提示词为空、未生成、已完成、失败、反选、清空 | 同一组类型筛选与快捷选择；选择集合会随可见集合收敛 | 已验证等价 |
| 批量提示词 | 选中资产后以补充要求发起批量润色，并显示生成中 | 同样以 `asset_prompt_polish` 队列入队、受花费确认保护；任务状态与提示词结果由本地队列驱动 | 已验证等价 |
| 批量参考图 | 选择模型/1K-4K/补充词，缺提示词阻断，提交后可取消并预览 | 同一参数、提示词校验、花费确认、任务取消与图片预览；只写本地队列，真实供应商由用户验收 | 已验证等价 |
| 详情与历史图 | 打开抽屉，可选历史完成图、失焦保存提示词、润色与单图重生成 | 自适应详情弹层实现相同流程；历史失败图不可选，避免将失败产物设为当前图 | 已验证等价 |
| 手动绑定/解绑和试听 | 单选音频，绑定覆盖旧值；可移除关联 | 项目内父音频下拉、单值覆盖/解绑、可用本地文件试听 | 已验证等价 |
| 批量 AI 音频匹配的进行中/失败反馈 | 所选资产写 `audioBindState=生成中`，卡片加载态，轮询后进入“已完成”或“生成失败” | 入队同步写“生成中”；同一队列的成功、异常和冷启动恢复分别写终态；卡片显示“音频匹配中”或“音频匹配失败” | 已验证等价 |

## 证据与边界

| 范围 | ToonFlow | DramaFlow |
| --- | --- | --- |
| 实际页面 | `Toonflow-web/src/router/index.ts:30-33` → `views/cornerScape/index.vue` | `app/lib/src/screens/cornerscape/corner_scape_screen.dart` |
| 资产数据 | `cornerScape/getAllAssets.ts:16-66` | `assets.dart:240-262` |
| 图片任务 | `cornerScape/index.vue:523-740` 调共享资产生成路由 | `corner_scape_screen.dart:128-264`、`assets.dart` 的 `asset_image_generation` 队列 |
| 音频匹配状态 | `cornerScape/index.vue:664-685,838-953` 和 `batchBindAudio.ts` | `audio_bind.dart` 的入队、执行、异常与冷启动恢复状态写入；`assets.dart` 暴露字段；`corner_scape_screen.dart` 消费状态并由队列事件刷新 |

## 自动化验证

本次闭环验证：

```sh
cd app
flutter test --concurrency=1 \
  test/widgets/corner_scape_screen_test.dart \
  test/engine/assets_test.dart \
  test/engine/audio_bind_test.dart
```

这些测试只使用内存数据库、临时本地媒体和 fake gateway；不会调用文本、图片、TTS 或
视频供应商。`audio_bind_test.dart` 直接验证目标筛选、入队“生成中”、成功、失败和冷启动
恢复的终态；`corner_scape_screen_test.dart` 同时验证桌面提交会即时刷新状态、页面在没有
外层 Shell 的独立挂载下仍会随队列终态刷新，以及 390dp 滚动到资产卡后可见“音频匹配中/
失败”、失败卡仍可打开详情。

## 实现边界

`audioBindState` 是唯一的资产级可见状态，`audio_bind` 队列是其唯一写入者；页面只读状态
并响应既有队列事件。不得为这条链加独立轮询、页面本地状态机或“失败原因”列。验证只覆盖
本地任务状态与 fake gateway 协议，不发起真实文本、图片、TTS 或视频请求。

关联总清单：`W6-CORNERSCAPE-001`、`W6-CORNERSCAPE-002`、
`W7E-CORNERSCAPE-AUDIO-001`、`W7E-CORNERSCAPE-ASSETS-001`。
