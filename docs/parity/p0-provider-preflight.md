# P0 供应商预检记录

> **归档说明（2026-07-19）**：本文仅保留 2026-07-17 的两次真实 Seedance
> 预检事实，不是可再次执行的操作手册。用户现行决定是开发和 CI 不调用真实视频
> 供应商；`app/test/preflight/p0_live_preflight_test.dart` 已删除，并由
> `video_safety_boundary_test.dart` 锁定，后续仅保留 fake gateway 的状态机、恢复、
> 取消与重试回归。真实视频生成由用户在最终验收自行发起。

## 结论

**恰好一次真实生成未达成**——两次授权的真实提交均被火山引擎以 HTTP 400 拒绝，具体拒绝原因未能诊断（代理设计上不记录响应体，且引擎自身错误处理也只保留了 dio 的通用包装消息，未保留供应商返回的实际错误文本）。六项断言 2/6 PASS（4 项核心 + 2 项辅助）：**恰好一次提交纪律成立**（每次真实调用都确证只发出 1 次 POST、只产生 1 条候选行），**实际生成未成功**（无 upstreamTaskId、无候选文件、无 MP4）。经用户决策，视频供应商联调问题暂搁置，不在本轮继续排查。

本预检**已证明有效**的是：提交纪律（恰好一次）与 `uncertain`/`accepted` 两态对 `retryJob` 防重复付费的正确处理（后者经 Task 3 零真实调用演练验证，非本轮真实调用直接验证）。**未被证实**的是"真实生成成功"与**真实冷启动恢复路径本身**——两次真实调用均在 GATE1 止步，`RESTART` 标记从未写入，`P0_PHASE=resume`（`Engine.boot` 冷启轮询）从未被真实执行过；"恢复"在本预检中被验证的只是 `retryJob` 的决策逻辑（Task 3 演练，假上游），不是真实冷启动恢复本身。详见"覆盖范围声明"。

## 真实付费场景

### 尝试 1（原始参考图）

- 提交时间：2026-07-17T18:41Z 前后；分辨率/时长档：480p / 4s（模型声明能力中最低成本档）
- 强杀点输出：`Shell: P0_MARK submitted taskId=1 resolution=480p duration=4`
- 代理日志：`{"ts":"2026-07-17T18:41:03.102Z","method":"POST","path":"/api/v3/contents/generations/tasks","status":400,"ms":10990}`
- 结果：180 秒轮询超时，`upstreamTaskId` 从未落库（提交异常 → `submissionState='uncertain'`，符合 `video_track.dart:812` 语义）；**GATE1 未过，脚本按设计正确停手，未进入 RESTART/resume**，未发生第二次真实提交
- `o_video.errorReason`：`{"key":"errNetwork","params":{"message":"...status code of 400...RequestOptions.validateStatus was configured to throw for this status code...400: Client error - the request contains bad syntax or cannot be fulfilled..."}}`（dio 通用模板文本，不含供应商实际错误详情）

### 诊断与假设

参考图 `azt-gpt-image2-test.png` 实际尺寸 864×1821（比例 ≈0.475），与请求的 `videoRatio=9:16`（比例 0.5625）不匹配——首帧图比例与目标视频比例不符是图生视频类 API 的常见校验失败点。此假设已征得用户授权，用于第二次尝试。

### 尝试 2（比例修正后，用户已授权的唯一重试）

- 参考图裁剪为精确 864×1536（比例 0.5625，与 9:16 完全一致，原图未改动，另存新文件）
- 强杀点输出：`Shell: P0_MARK submitted taskId=1 resolution=480p duration=4`
- 代理日志：`{"ts":"2026-07-17T18:54:25.512Z","method":"POST","path":"/api/v3/contents/generations/tasks","status":400,"ms":14323}`
- 结果：**与尝试 1 相同**——180 秒超时，`upstreamTaskId` 未落库，GATE1 未过。**比例假设被证伪**，真实拒绝原因仍未知。

### p0_assert.js 完整输出（对尝试 2 最终状态）

```
PASS 真实 POST 提交次数 == 1 (posts=1)
FAIL upstreamTaskId 数量 == 1 (distinct=0)
FAIL 重启后只有轮询/下载类请求（无 POST） (afterRestart=0)
PASS o_video 候选行数 == 1（主断言） (rows=1)
FAIL 候选 filePath 文件真实存在 (file=null)
FAIL 媒体目录 MP4 数量 == 1（辅助断言） (videos=0)
exit=1
```

两次真实调用**均恰好只发出 1 次 POST**（代理日志逐次核验），证明"恰好一次"纪律在两次独立真实调用中都成立，未发生任何意外重复提交。RESTART 标记因 GATE1 未过而从未写入，故重启恢复路径（Engine.boot 冷启轮询）本身未被真实调用验证到——这也是本预检未达成的一部分（见"覆盖范围声明"）。

## 失败与重试演练（零真实调用）

按计划 Task 3 完成，与本次真实预检独立：

- 用例 A（uncertain，假上游 `fail` 模式）：`P0_DRILL_UNCERTAIN_OK`，假上游 POST 计数 == 1（`retryJob` 正确拒绝重提，防重复付费保护成立）；引擎语义见 `app/lib/src/engine/video_track.dart:812`（提交异常 → `uncertain`）与 `:1100-1114`（冷启动仅 `accepted`+非空 `upstreamTaskId` 才恢复轮询，`uncertain`/`prepared`/`submitting` 一律标 failed）
- 用例 B（accepted+终态失败，假上游 `acceptThenFail` 模式）：`P0_DRILL_ACCEPTED_FAIL_OK`，假上游 POST 计数 == 2（`retryJob` 正确允许重试）
- 两用例均零真实供应商调用；完整线束代码见 `app/test/preflight/p0_failure_drill_test.dart`（本仓库内，非外部报告文件引用）

## azt 服务冒烟

- 文本：2.2 秒返回 `OK`（`gpt-5.5`）
- 图片：26.7 秒返回 `b64_json` 长度 1,171,768（>10000 门槛，确认为真实图片数据），远快于 `AGENTS.md` 历史记录的 195–342 秒（模型/负载差异，非异常）
- 摘录见 `/tmp/p0-azt-smoke.txt`（本机路径，未纳入仓库）

## 发现的缺陷与处置

1. **现象**：真实 Seedance 提交两次均返回 HTTP 400，具体原因不可见。
   **诊断**：代理按安全设计不记录请求/响应正文；引擎 `video_track.dart` 的提交异常处理只保留 dio 通用模板消息（`errNetwork` + 泛化的状态码解释），未保留 `DioException.response?.data`（供应商实际返回的错误详情，通常不含敏感信息）。这是一个真实的**错误可观测性缺口**：任务中心和日志目前都无法向用户展示供应商拒绝的具体原因，只能看到"网络错误"。
   **处置**：记录进 W0 总对照清单（Agent/任务中心相关审计单元，待 W0 Task 8/其他单元执行时归档为具体条目）；不在 P0 期间修复（P0 修复纪律：只诊断记录，不做产品代码改动）。
2. **现象**：图片比例（864×1821 vs 请求的 9:16）不匹配的假设经真实验证被证伪。
   **诊断**：真正拒绝原因仍未知，可能候选包括但不限于：`data:` base64 内联图片的传输方式是否被该 API 支持（部分供应商要求托管 URL 而非内联 base64）、账号/模型准入状态、请求体其他字段格式问题。
   **处置**：经用户决策（本轮对话），Seedance 视频供应商联调问题**暂搁置**，留待后续专项处理；处理该问题的前提是先补上第 1 条的响应体捕获能力，否则任何后续尝试仍是盲猜。

P0 期间零产品代码改动（仅测试线束与工具脚本）。

## 凭证处置声明

key 仅在两次线束运行期间存在于进程内存（`InMemoryCredentialStore`），全程未持久化、未打印、未写盘、未进入任何 git 提交。Keychain 迁移按计划偏差声明推迟至终验收准备阶段。

## 覆盖范围声明

本预检已验证：提交路径的凭证读取（引擎/供应商协议层）、恰好一次提交纪律（两次独立真实调用均确认仅 1 次 POST）、`uncertain`/`accepted` 两种提交结果对 `retryJob` 防重复付费保护的正确处理（零真实调用演练部分）。

本预检**未验证**：Seedance 视频生成的完整成功路径（提交→轮询→下载落盘）、重启后冷启动恢复路径的真实触发（因两次尝试都未越过 GATE1，RESTART 标记从未写入）、Keychain/设置页/打包 App 凭证路径、GUI 与 macOS App 生命周期——后两项按计划设计本就推迟到终验收 12 步；前两项是本轮未达成的直接后果，需在后续专项处理 Seedance 联调问题后补齐，或在终验收 12 步中一并验证。
