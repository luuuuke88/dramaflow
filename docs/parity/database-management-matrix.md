# 存储与数据库管理对照

更新时间：2026-07-21

本记录只处理 ToonFlow 1.1.8 设置中的 `dbConfig.vue`。它把相似但语义不同的四类
操作拆开记录，避免把“能清一些数据”误判成完整数据库管理能力。

## 行为结论

| 能力 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 查看表信息 | 从 `sqlite_master` 取得非系统表，逐表 `COUNT(*)`，在弹窗表格显示表名和行数。 | `Engine.dbInfo()` 以相同方式读取非 `sqlite_` 表；设置页可打开表名/行数弹窗。 | 已验证等价 |
| 清空指定表 | 选择任意数据库表，后端先校验它存在，再仅执行该表的 `DELETE`；其余表和结构不受影响。 | `Engine.clearableDbTables()` 只列内容表，`clearTable()` 在事务内删除用户选中的一表并通知观察者；设置页先显示表名/行数，再以明确表名二次确认。`o_secret`、供应商、模型绑定、提示词、画风与其他设置不显示也不能被 API 清空。 | 部分实现 |
| 整库导出/导入 | 导出所有表 JSON；导入时重建库并恢复表数据。导入有二次确认和输入关键词。 | 只导入/导出供应商元数据、模型绑定、提示词和模型提示词模板，刻意不包含项目、章节、剧本、素材、任务或媒体。 | 部分实现 |
| 恢复出厂/清空整库 | `clearData` 删除全部表后重播默认数据，连供应商、密钥、Agent 绑定与提示词覆写也会清掉。 | `clearAllData()` 只清业务数据与媒体，保留供应商、`o_secret` 密钥、模型绑定、提示词、画风和外观设置。 | 部分实现 |

## 源码对照

### ToonFlow

- [`dbConfig.vue`](../../../Toonflow-web/src/components/setting/components/dbConfig.vue)
  的 `loadDbInfo`、`clearTable`、`exportData`、`handleSecondConfirm` 分别承接上述四个
  用户操作。单表清空没有沿用整库操作的输入关键词确认，只要求用户在普通危险确认弹窗中
  确认。
- [`clearTable.ts`](../../../Toonflow-app/src/routes/setting/dbConfig/clearTable.ts) 先以参数化
  查询确认表名确实存在，再把表名包在双引号中执行 `DELETE`。因此实现时不能把用户输入直接
  拼进 SQL，也不能允许清空 SQLite 内部表。
- `clearData.ts`、`exportData.ts` 与 `importData.ts` 是整库恢复、备份和还原的实际后端
  路径；它们不等同于 `clearTable.ts`。

### DramaFlow

- [`db_admin.dart`](../../app/lib/src/engine/db_admin.dart) 的 `dbInfo()` 已有同等的表信息
  查询；`clearableDbTables()`/`clearTable()` 承接单表内容清理，`clearAllData()` 则是有意保留
  用户配置的“清业务数据”动作。三者共用同一份配置保护集，避免清空全量业务数据时遗漏模型
  绑定、提示词模板或画风。
- [`settings_screen.dart`](../../app/lib/src/screens/settings_screen.dart) 的“存储与引擎”区
  有配置导入/导出、打开数据目录、表信息、单表选择器和清空业务数据。窄屏时单表选择器使用
  全屏可滚动列表；桌面使用紧凑对话框，二者都必须选表后再进入危险确认。
- [`credentials.dart`](../../app/lib/src/engine/credentials.dart) 将 API Key 存在本地 SQLite
  的 `o_secret`。这符合 DramaFlow 的无钥匙串产品决策，但也意味着未来“恢复出厂”必须在
  UI 上清楚区分“保留密钥的清项目数据”和“删除所有本地数据及密钥”。

## 现有自动化证据

```bash
cd /Users/luke/Documents/aivideo/dramaflow/app
flutter test --concurrency=1 \
  test/engine/db_admin_test.dart \
  test/widgets/settings_screen_test.dart
```

- `db_admin_test.dart` 直接断言表信息中的行数、单表清空只影响选中的内容表、任意 SQL/配置/
  密钥表名会被拒绝，以及清业务数据后媒体被删除、供应商/绑定/密钥/模型提示词/画风仍保留。
- `settings_screen_test.dart` 驱动 390dp 全屏选择器与 1280dp 桌面对话框完成“选内容表 → 明确
  表名确认 → 删除”；两个用例都断言 `o_secret` 不在候选中。
- 这些测试**没有**证明整库 JSON 备份/还原或恢复出厂已经存在；单表清空也刻意不复刻原版
  “任意表均可清”的配置破坏能力，因此不能标为完全等价。

## 后续实现边界

1. “清项目数据”和“恢复出厂”必须保留为两个命令，不能为了复刻而暗中改变当前清项目数据
   的保留密钥语义。整库备份/还原、恢复出厂与单表清空各自独立验收。

相关总清单：`W6D-DB-001`、`W7A-DB-INFO-001`、`W7A-DB-RESET-001`、
`W7A-DB-CLEARTABLE-001`、`W7F-DATA-CLEAR-001`。
