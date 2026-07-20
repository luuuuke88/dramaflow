# 模型选择器对照

> 对照对象：ToonFlow 1.1.8 的 `modelSelect.vue` 与 `utils/providersLogo.ts`。本页只记录
> 用户可见的模型选择体验；供应商协议和真实连通性另见 `vendor-protocol-matrix.md`。

## 对照表

| 行为 | ToonFlow | DramaFlow | 结论 |
| --- | --- | --- | --- |
| 按模型类型筛选 | `text`、`image`、`video`，以及排除视频的 `all` | `ModelSelect.kind` 筛选启用供应商中的同类启用模型；额外承接 `tts` 与 `embedding` | 已承接 |
| 供应商分组 | 下拉菜单以供应商名称分段 | 弹出菜单以 `providerId` 分组，并保留本地供应商创建顺序 | 已验证 |
| 模型项信息 | 供应商头像、模型名称、类型标签 | 稳定颜色的供应商首字母头像、供应商加模型名、本地化类型标签 | 部分实现 |
| 最新模型列表 | 初次展示和下拉展开时刷新 | 初次由 Riverpod 读取本地 SQLite；每次打开前再次读取本地 Provider/Model 记录 | 已验证 |
| 无模型引导 | 空列表提供“去供应商配置” | 空列表显示设置图标和本地化“去设置”，项目向导会关闭自己后进入 `/settings?section=providers` | 已验证 |
| 选择值 | `vendorId:modelName` | `providerId:modelId`；调用端继续拿到能力表 `capabilities` | 已承接 |

## 证据与边界

[`model_select.dart`](../../app/lib/src/screens/project/model_select.dart) 先筛选本机启用供应商及
启用模型，再在用户点击字段时重新读取同一份 SQLite 数据并打开菜单。这样用户刚在设置页
新增模型后，不需要重启应用或刷新整个页面。

[`model_select_test.dart`](../../app/test/widgets/model_select_test.dart) 使用内存数据库与空网关验证：

1. 两个图片供应商在同一菜单中各自有组头，模型项显示“图片”类型标签。
2. 组件首次加载后新增第二个供应商，第一次点开菜单即可看到它。
3. 组件首次加载后停用唯一供应商，不会从旧缓存继续提供该模型。

这些测试不发送 Provider、图片或视频请求。项目入口的模型选择与空态路由仍由
[`project_page_test.dart`](../../app/test/widgets/project_page_test.dart) 覆盖。

## 不复制的视觉实现

ToonFlow 的 `providersLogo.ts` 是大批本地图标资源与按模型名猜供应商的规则。DramaFlow 的
模型记录已拥有明确 `providerId`，因此不需要猜测；为了不引入原版品牌资产，使用确定性的
颜色加首字母头像作为可辨识回退。品牌 logo、按模型名匹配图标和原始资源包均未复刻。

因此 `W6E-CMP-MODELSELECT-001` 保持**部分实现**。这不是功能缺口，而是有意保留的视觉和
资产边界；若未来加入自有或获授权的供应商品牌资源，应在不改变 `providerId:modelId` 选择值
及上述离线回归的前提下扩展头像解析器。
