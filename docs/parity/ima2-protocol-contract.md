# ima2 / Codex OAuth 协议对照

更新时间：2026-07-19
状态：部分实现。协议与跨端配置已完成 fake-gateway/widget 验证；没有发起真实图片或视频请求，
因此不计入真实上游验收完成数。

## 结论先行

`ima2` 不是 OpenAI 单端点配置的别名。它把文本与图片拆到两个本地服务：
文本走 OpenAI 兼容 Chat Completions，图片走 ima2 自己的 JSON 接口。因此，
把它填进通用 OpenAI 供应商会让图片请求落到错误的 `/images/*` 路径，不能算复刻。

Flutter 以一个小而独立的 `ima2` 协议适配器承接它：文本继续复用经过验证的
OpenAI 兼容编码器，但以 `chatBaseUrl` 为真实端点；图片只在该协议下发送 ima2
的 `POST /api/generate` 负载。不会恢复 Electron 的可执行 TypeScript 插件运行时。

## 原版可观察契约

证据来源：`Toonflow-app/data/vendor/ima2.ts`。

| 范围 | ToonFlow 行为 | Flutter 对应目标 | 验证方式 |
| --- | --- | --- | --- |
| 供应商输入 | `apiKey`、`chatBaseUrl`、`imageBaseUrl`、`imageQuality`、`imageSize`、`imageTimeoutMs`，均可在设置页编辑 | 同名配置字段；密钥继续只进系统凭证仓，其余字段保存到供应商配置 | `provider_preset_create_test.dart` 读写往返；桌面/移动 widget 表单 |
| 文本 | `chatBaseUrl` 上的 OpenAI 兼容 chat model | 复用 OpenAI 文本、视觉、工具 JSON 编码器，解析时强制使用 `chatBaseUrl` | `ima2_gateway_test.dart`：旧 `baseUrl` 与 `chatBaseUrl` 不一致时仍命中后者 |
| 图片模型 | 三个 `gpt-image-2-gpt-5.*` 显示模型；请求前去掉 `gpt-image-2-` 前缀 | 保留显示模型 ID；请求时传对应的 OAuth 模型后缀 | `ima2_gateway_test.dart` 断言模型转换 |
| 图片请求 | `POST {imageBaseUrl}/api/generate`，JSON 含 `provider=oauth`、`mode=direct`、`format=png`、`moderation=low`、`n=1`、`references` | 同字段与相同默认值；参考图转 data URI，不走 `/images/edits` | `ima2_gateway_test.dart` 完整 JSON 与多参考断言 |
| 图片参数 | 质量只允许 low/medium/high，尺寸为空时按 16:9、9:16、其他比例推导；超时下限 60 秒，默认 960 秒 | 相同归一化规则；项目侧画幅传给尺寸推导 | `ima2_gateway_test.dart` 覆盖合法值、非法质量、空尺寸与过短超时 |
| 图片响应 | 依次接受 `image`、`images[]` 项、`url`；URL 需下载为本地媒体 | 解析同样的直接、嵌套和 URL 形态，并落到本地媒体库 | fake JSON + fake bytes 覆盖 `image`、`images[].image`、`images[].url`、顶层 `url` |
| 视频/TTS | 没有视频模型；`videoRequest` 明确报错；TTS 不提供模型 | 不在 ima2 配置视频或 TTS；视频保持 Seedance/其它专用协议 | 配置边界测试，**不调用真实视频** |

## 跨端策略

原版运行在 Electron，默认地址是 `127.0.0.1`。Flutter 不能把这个默认值直接当成
移动端可用服务：手机的 loopback 指向手机自身，而不是 Mac。

- **macOS**：预填原版的两个 loopback 地址，可作为桌面本地 ima2 配置直接启用。
- **iOS/Android**：同一张 ima2 配置卡可见，但不预填 loopback；用户可输入局域网或
  HTTPS 反向代理地址。未配置端点时不能启用或绑定模型。
- **所有平台**：已经保存的远程 ima2 配置使用同一套引擎、队列和媒体路径；不增加伴随
  进程，也不要求移动端运行 Node。

这比“在手机隐藏 ima2”更符合跨端可用性要求，也不会把不可达地址伪装成可用配置。

## 最小实现边界

1. 已在供应商目录中声明 `ima2`、双端点输入元数据和原版六个模型。
2. 已由供应商读写 API 保留非敏感扩展输入；创建与编辑表单按元数据渲染这些字段。
3. `ResolvedModel` 仅携带所需的非敏感输入快照；`ima2` 图片适配器从该快照读取图片端点和参数。
4. `HttpProviderGateway` 在图片生成与图片连通测试两条路径都分派到 ima2；文本、视觉和工具调用复用现有 OpenAI 兼容实现。
5. 已有 fake-Dio、引擎、390dp 及桌面 widget 回归；本次没有真实图片或视频调用。

## 不等价项与完成门

`vendor-protocol-matrix.md` 的 ima2 行现为“部分实现”。必须保持这一状态，直到
用户以自己的环境验收图片质量/尺寸的真实上游遵从行为；原版整体供应商插件编辑器
也不因这个固定协议适配器而变成等价。

本次协议完成门不是“卡片出现”：双端点字段持久化、文本路径、图片完整负载、多参考、
四种响应形态、超时归一化、移动端空端点保护和桌面/390dp UI 回归均已有自动化证据。
真实图片质量、实际尺寸与 OAuth 服务的时延/额度仍是用户手动验收项；视频不测试。
