# 存储与数据库管理对照

更新时间：2026-07-19

本记录只处理 ToonFlow 1.1.8 设置中的 `dbConfig.vue`。它把相似但语义不同的四类
操作拆开记录，避免把“能清一些数据”误判成完整数据库管理能力。

## 行为结论

| 能力 | ToonFlow 1.1.8 | DramaFlow 当前实现 | 结论 |
| --- | --- | --- | --- |
| 查看表信息 | 从 `sqlite_master` 取得非系统表，逐表 `COUNT(*)`，在弹窗表格显示表名和行数。 | `Engine.dbInfo()` 以相同方式读取非 `sqlite_` 表；设置页可打开表名/行数弹窗。 | 已验证等价 |
| 清空指定表 | 选择任意数据库表，后端先校验它存在，再仅执行该表的 `DELETE`；其余表和结构不受影响。 | 无表选择器、无单表清空 API 或引擎方法。 | 缺失 |
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
  查询；`clearAllData()` 则是有意保留用户配置的“清业务数据”动作。
- [`settings_screen.dart`](../../app/lib/src/screens/settings_screen.dart) 的“存储与引擎”区
  有配置导入/导出、打开数据目录、表信息和清空业务数据，但没有表选择控件。
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

- `db_admin_test.dart` 直接断言表信息中的行数，以及清业务数据后媒体被删除、供应商/绑定/
  密钥仍保留。
- `settings_screen_test.dart` 驱动窄屏设置页打开数据库信息，并确认“清空数据”只清内容。
- 这些测试**没有**证明单表清空、整库 JSON 备份/还原或恢复出厂已经存在；它们正是当前
  三个缺口不能被标绿的原因。

## 后续实现边界

1. 单表清空应由受控的 `Engine.clearTable(String table)` 实现：只能接受 `dbInfo()` 枚举的
   应用表，不接受 `sqlite_`、`o_secret` 或任意手填标识符；在一个事务内删除并通知状态更新。
2. 设置页应先显示包含当前行数的选择器，再以明确表名的危险确认执行。桌面可以用紧凑的
   下拉与确认对话框，窄屏应使用可滚动选择列表和全宽确认按钮，不能把关键操作藏在 hover
   菜单里。
3. “清项目数据”和“恢复出厂”必须保留为两个命令，不能为了复刻而暗中改变当前清项目数据
   的保留密钥语义。整库备份/还原、恢复出厂与单表清空各自独立验收。

相关总清单：`W6D-DB-001`、`W7A-DB-INFO-001`、`W7A-DB-RESET-001`、
`W7A-DB-CLEARTABLE-001`、`W7F-DATA-CLEAR-001`。
