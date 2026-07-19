# 供应商预设人工验收清单（需真实 Key，不进默认 CI）

规则（spec §4 + 评审 P2）：
- 开发和 CI 不发起任何真实上游调用；视频一律只做 fake gateway 的协议/状态机验证，真实视频生成只由用户在最终验收时自行发起。设置页不会列出视频“测试连通”，而 `Engine.testProvider` 也会在调用网关前拒绝 video 模型，防止任何绕过入口。
- 用户自愿提供某一家真实 Key 后，才可按该家**已实现的协议路径**验证：①普通文本；②该路径支持时的工具调用/结构化 JSON；③仅该路径已实现时的图片生成或编辑；④`GET /models`。对原生 Agent 工具协议，首轮 `tool_use` 成功不算闭环，必须额外验证“保留 assistant `tool_use`（含 id）→ user `tool_result` → 下一轮响应”。不能因为画廊里有预设，就假定四项全都适用。
- ①②任一已宣称能力失败 = 该家不可置 `acceptanceVerified: true`；③失败 = 移除该家图片模型；④失败 = preset 备注"不支持 /models"。缺少原生协议适配的家，只能保留为“兼容模式/未验证”配置入口，不能用通用成功冒充原生适配成功。Anthropic 是例外：已实现原生 Messages API，但本地假网关合同回归不能替代真实 Key 验收。
- **`provider_presets.dart` 里把某家 `acceptanceVerified` 翻 true 的唯一合法途径：本表该行填入日期+模型+证据路径。**画廊"未验证"角标随字段自动消失。
- 记录格式：日期 / 所测模型 / 证据（日志路径、测试名或截图路径）。

## 离线回归证据

当前 `develop` 已在不接触任何真实密钥或上游服务的条件下复跑下列范围：

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/config_test.dart test/engine/providers_test.dart \
  test/engine/provider_presets_test.dart test/engine/provider_preset_create_test.dart \
  test/engine/remote_model_candidates_test.dart test/engine/model_prompt_library_test.dart \
  test/engine/prompt_resolver_test.dart test/widgets/provider_preset_gallery_test.dart \
  test/widgets/provider_preset_form_test.dart test/widgets/settings_screen_test.dart
```

结果为 124 条通过。测试以 `NoopGateway`、Dio 假 HTTP 适配器或记录型网关替代网络；视频模型的连通测试在网关分派前被拒绝。它证明的是预设目录、表单、模型模板和本地策略，绝不替代下表所要求的真实供应商验收。

| preset | ①文本 | ②工具/JSON | ③图片 | ④/models | 证据 |
|---|---|---|---|---|---|
| azt | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | ✅ 2026-07-18 | `gpt-5.6-luna` 文本+工具链路：Mac/iOS golden-path e2e（建项目→剧本→分镜表均真实调用，见 `.superpowers/sdd/progress.md` 的 P0 Task 4 与“早晨总结”）；`gpt-image-2` 图片产物：`/Users/luke/Documents/aivideo/azt-gpt-image2-test.png`，PNG 864×1821，SHA-256 `7297abdb556540f7425889ce4189f76617c70a701568050aeac45ed6dcf8f576`。请求的 1024×1024 未被 OAuth 路径严格遵守，尺寸/质量控制仍按 `vendor-protocol-matrix.md` 的 azt 缺口继续追踪；`/v1/models` 当日实测返回 gpt-5.6 系列。 |
| volcengine | 待验 | 待验 | 待验 | 待验 | 今晚视频生成被明确搁置，无真实调用证据 → acceptanceVerified=false，画廊显示"未验证" |
| openai | 待验 | 待验 | 待验(gpt-image-2) | 待验 | |
| anthropic（原生 Messages API） | 待验 | 待验 | 无图片 | 待验 | 2026-07-19 本地假网关合同回归覆盖文本、强制工具 JSON、**Agent 首轮 `tool_use` 序列化**、视觉输入、`/models` 鉴权和文本连通测试：`app/test/engine/anthropic_gateway_test.dart`（6 项）。尚未保留 `tool_use_id` 并回传原生 `tool_result`，故多轮 Agent 工具闭环缺失；未发起真实上游调用，仍 `acceptanceVerified=false`。 |
| gemini（兼容模式） | 待验 | 待验 | 无图片(协议后补) | 待验 | |
| xai（兼容模式） | 待验 | 待验 | 无图片 | 待验 | |
| openrouter | 待验 | 待验 | 无图片 | 待验 | |
| siliconflow | 待验 | 待验 | 待验(Kolors) | 待验 | |
| deepseek | 待验 | 待验 | 无图片 | 待验 | |
| moonshot | 待验 | 待验 | 无图片 | 待验 | |
| zhipu | 待验 | 待验 | 待验(cogview-4) | 待验 | |
| dashscope | 待验 | 待验 | 图片过兼容层待验证，不通则不预置 | 待验 | |
| ima2（双端点本地 OAuth） | 待验 | 待验 | 待验 | 文本端点待验；图片端点不走标准 `/models` | 协议、创建/编辑、图片请求与下载仅有 fake-gateway 回归：`app/test/engine/ima2_gateway_test.dart`、`app/test/engine/provider_preset_create_test.dart`、`app/test/widgets/provider_preset_form_test.dart`。未发起新的真实文本或图片请求，保持 `acceptanceVerified=false`。 |

本表的 Anthropic 本地合同证据只证明 DramaFlow 对首轮 `POST /v1/messages` 的序列化、鉴权与响应解析路径存在；它不证明原生多轮工具往返、任一 Claude 型号、账户权限或供应商网络可用。真实验收前，画廊必须继续显示“未验证”。
