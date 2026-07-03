# 2026-07-04 Codex 接手快照：ToonFlow 全量复刻进度

## 当前事实源

- 当前分支：`master`
- 本轮起点：`c4c3cf6 chore(progress): record handoff audit and localize composer errors`
- 本轮接手验证：
  - `cd app && flutter analyze`：通过，0 issues
  - `cd app && flutter test`：通过，268 tests
  - `cd app && flutter build macos --debug`：通过，产物 `build/macos/Build/Products/Debug/dramaflow.app`
  - `cd app && flutter build ios --simulator --debug`：通过，产物 `build/ios/iphonesimulator/Runner.app`
  - `cd app && flutter build apk --debug`：通过，产物 `build/app/outputs/flutter-apk/app-debug.apk`
  - `cd app && flutter build web`：通过，产物 `build/web`，但仍是预览态，不代表 Web 完整流程已完成
  - `cd app && dart run tool/e2e_local_smoke.dart`：通过，纯本地、不调用供应商，串起章节→剧本→资产→分镜→选中视频→镜头配音→合成导出
- 权威目标仍是 `docs/superpowers/specs/2026-07-03-v0.3-toonflow-parity-design.md`。旧 `docs/API.md` 和 `docs/DESIGN.md` 是 v0.1/v0.2 历史口径，不能作为当前实现目标。

## 已落地且有测试覆盖的主链能力

- 单体 Flutter/Dart 架构：`app/lib/src/engine` 内嵌 sqlite3、JobQueue、ProviderGateway、MediaStore，无运行时 JS/Node 后端依赖。
- ToonFlow v3/v4 数据模型：26 张核心表已建，旧库打开会重建但不删除媒体目录。
- 项目、小说章节、事件、剧本、素材、画风库、手册、分镜、图片流、视频轨、配音绑定、TTS、Agent 消息、任务中心、设置页均已有 engine/API 与 widget/engine 测试覆盖。
- 图片生成链已修正：分镜和节点编辑器可传多参考图，并带模型、画幅、清晰度参数。
- 视频生成链已具备：分镜首帧图 → Seedance 视频候选 → 选择候选 → 按分镜顺序合成本集。
- 工作台已补齐每镜配音绑定入口：每个分镜行可从 audio 资产池选择/清空音频，写入 `o_storyboard.audioAssetId`，合成时自动进入音频时间线。
- 新增离线主链 smoke：`app/tool/e2e_local_smoke.dart` 用本地 sqlite/media/fake composer 验证章节、剧本、资产、分镜、视频候选、镜头配音与合成导出全链，不依赖 AZT/ima2/Seedance，也不依赖 JS 后端。
- 新增 UI 级离线主链 smoke：制作页桌面画布可从完整 fake 项目打开工作台并合成；移动端可从工作台 Tab 打开同一条链路。该测试同时锁定 `DFCanvas.fitOnInit` 首帧节点非空时必须自动缩放到可见范围。
- 新增移动端剧本页 smoke：390px 宽度下工具栏不再溢出，可打开批量添加弹窗、解析两集剧本并落库显示。
- 新增移动端小说页 smoke：390px 宽度下工具栏和导入步骤头不再溢出，可粘贴两章原文、保存落库并自动入队事件生成任务。
- 新增移动端素材页 smoke：390px 宽度下素材工具栏不再溢出，音频 tab 可打开文本配音、生成音频资产并回到移动端卡片列表。
- 新增移动端配音页 smoke：390px 宽度下角色音频下拉可打开、选择音频并写入绑定关系。
- 新增机器可验证的 11 页 ToonFlow parity checklist：`docs/superpowers/progress/2026-07-04-page-parity-checklist.md` 逐页记录 Status、Desktop Evidence、Mobile Evidence、Known Gaps、Next Verification，并由 `app/test/docs/page_parity_checklist_test.dart` 防止缺页。
- 新增移动端项目新建向导 smoke：390px 宽度下可选择图片/视频模型、画质、模式、画幅、视觉手册、导演手册并保存到 `o_project`；同时修复项目对话框窄下拉在小屏下的横向溢出。
- 扩展项目列表页 smoke：桌面卡片 hover 后可编辑/删除，移动端卡片无需 hover 也可编辑/删除；卡片展示章节、剧本、素材、分镜本地统计，并由 engine `projectStats()` 单测锁定聚合逻辑。
- 新增移动端设置页 smoke：390px 宽度下可修改外观/语言、新增供应商、打开提示词编辑页，补齐全套设置页的首个移动端机器证据。
- 扩展移动端设置页 smoke：390px 宽度下可进入模型管理新增文本模型、绑定剧本生成模型、打开数据库信息、确认清空数据且保留供应商配置。
- 新增移动端任务中心 smoke：390px 宽度下可切换项目、打开任务详情、重试失败任务、取消待处理任务，并锁定任务筛选下拉不再横向溢出。
- 修复共享 `runAction` 成功提示：连续操作会替换当前 SnackBar，且任务行卸载后仍可由预先捕获的 `ScaffoldMessenger` 显示成功反馈。
- 合成导出：
  - macOS/iOS：`dramaflow/composer` Swift AVFoundation 插件，含音频轨合成。
  - Android：同一 MethodChannel，Kotlin `MediaMuxer` 实现，支持视频拼接与外部 AAC/M4A 音频轨封装。
  - macOS 音频合成已有 integration smoke test。
- i18n：zh/en/ja ARB 已生成，设置、任务、共享组件有静态硬编码检查。本轮新增 `errPlatformComposer`，让 Dart composer 封装不再抛中文裸错误。

## 仍未达到“完全复刻”的边界

- Web/H5 目前只是 buildable preview。`bootstrap_web.dart` 明确不接入 engine，仍缺 Web 数据库、浏览器文件存储、WebCodecs/Mediabunny 合成器与媒体预览适配。
- ToonFlow 的完整 WebAV 非线性剪辑器没有复刻。当前工作台是顺序分镜、候选选择、时长/运镜提示词编辑、播放预览和合成导出，不包含完整转场、滤镜、多层剪辑特效。
- Agent 体系是瘦身版单层 AgentRunner，保留可见任务与工具调用；没有复刻 ToonFlow/Claude 风格的多层 Agent + RAG 记忆大系统。
- “每页每按钮与 ToonFlow 并排验收”已有机器可验证清单骨架；项目页和任务中心已补成 Verified，但多数页面仍是 Partial，需要按清单继续补截图/真机/按钮级证据。
- 移动端已有响应式布局和 Android/iOS 合成入口，但还需要真机或模拟器完整跑一遍：从导入章节到生成分镜、视频候选、配音、合成导出。

## 接下来优先级

1. 继续补“客户端完整流程”的可验证缺口，而不是优先做 Web。Web 完整 H5 是大子项目，应单独拆 M6。
2. 沿 `docs/superpowers/progress/2026-07-04-page-parity-checklist.md` 逐项补证据，避免只看文件存在就误判完成。
3. 跑并记录 `flutter build macos --debug`、iOS simulator build、Android APK build 作为多端集成基线。
4. 继续补每页每按钮 parity checklist，优先补素材移动端 CRUD/批量参数、节点式图片编辑器移动端操作、Agent 体系页配置证据。
