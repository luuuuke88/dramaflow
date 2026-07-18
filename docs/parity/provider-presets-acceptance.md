# 供应商预设人工验收清单（需真实 Key，不进默认 CI）

规则（spec §4 + 评审 P2）：
- 开发和 CI 不发起任何真实上游调用；视频一律只做 fake gateway 的协议/状态机验证，真实视频生成只由用户在最终验收时自行发起。
- 用户自愿提供某一家真实 Key 后，才可按该家**已实现的协议路径**验证：①普通文本；②该路径支持时的工具调用/结构化 JSON；③仅该路径已实现时的图片生成或编辑；④`GET /models`。不能因为画廊里有预设，就假定四项全都适用。
- ①②任一已宣称能力失败 = 该家不可置 `acceptanceVerified: true`；③失败 = 移除该家图片模型；④失败 = preset 备注"不支持 /models"。缺少原生协议适配的家，只能保留为“兼容模式/未验证”配置入口，不能用通用成功冒充原生适配成功。
- **`provider_presets.dart` 里把某家 `acceptanceVerified` 翻 true 的唯一合法途径：本表该行填入日期+模型+证据路径。**画廊"未验证"角标随字段自动消失。
- 记录格式：日期 / 所测模型 / 证据（日志路径、测试名或截图路径）。

| preset | ①文本 | ②工具/JSON | ③图片 | ④/models | 证据 |
|---|---|---|---|---|---|
| azt | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | gpt-5.6-luna 文本+工具链路：macOS/iOS golden-path e2e 全流程（建项目→剧本→分镜表均真实调用，`.superpowers/sdd/progress.md` P0 Task 4 与"早晨总结"条目）；gpt-image-2 1024 图片 26.7s：`/tmp/p0-azt-smoke.txt`；/v1/models 当日实测返回 gpt-5.6 系列 |
| volcengine | 待验 | 待验 | 待验 | 待验 | 今晚视频生成被明确搁置，无真实调用证据 → acceptanceVerified=false，画廊显示"未验证" |
| openai | 待验 | 待验 | 待验(gpt-image-2) | 待验 | |
| anthropic（兼容模式） | 待验 | 待验 | 无图片 | 待验 | |
| gemini（兼容模式） | 待验 | 待验 | 无图片(协议后补) | 待验 | |
| xai（兼容模式） | 待验 | 待验 | 无图片 | 待验 | |
| openrouter | 待验 | 待验 | 无图片 | 待验 | |
| siliconflow | 待验 | 待验 | 待验(Kolors) | 待验 | |
| deepseek | 待验 | 待验 | 无图片 | 待验 | |
| moonshot | 待验 | 待验 | 无图片 | 待验 | |
| zhipu | 待验 | 待验 | 待验(cogview-4) | 待验 | |
| dashscope | 待验 | 待验 | 图片过兼容层待验证，不通则不预置 | 待验 | |
