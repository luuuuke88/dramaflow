import 'package:sqlite3/sqlite3.dart';

String _placeholders(int count) => List.filled(count, '?').join(',');

List<int> imageFlowIdsForAssets(Database db, List<int> assetIds) {
  if (assetIds.isEmpty) return const [];
  return db
      .select(
        'SELECT flowId FROM o_assets WHERE id IN (${_placeholders(assetIds.length)}) '
        'AND flowId IS NOT NULL',
        assetIds,
      )
      .map((row) => row['flowId'] as int)
      .toSet()
      .toList();
}

List<int> imageFlowIdsForStoryboards(Database db, List<int> storyboardIds) {
  if (storyboardIds.isEmpty) return const [];
  return db
      .select(
        'SELECT flowId FROM o_storyboard '
        'WHERE id IN (${_placeholders(storyboardIds.length)}) '
        'AND flowId IS NOT NULL',
        storyboardIds,
      )
      .map((row) => row['flowId'] as int)
      .toSet()
      .toList();
}

/// 删除已没有资产或分镜引用的图片编辑流程。
///
/// 正常流程一对一归属，但导入的历史数据可能出现共用 flowId；此处保留仍有
/// 引用的行，避免删除一个素材时破坏另一个素材或分镜的编辑记录。
void clearUnreferencedImageFlows(Database db, Iterable<int> candidateFlowIds) {
  final flowIds = candidateFlowIds.toSet().toList();
  if (flowIds.isEmpty) return;
  final ph = _placeholders(flowIds.length);
  db.execute(
    'DELETE FROM o_imageFlow WHERE id IN ($ph) '
    'AND NOT EXISTS (SELECT 1 FROM o_assets WHERE o_assets.flowId=o_imageFlow.id) '
    'AND NOT EXISTS (SELECT 1 FROM o_storyboard WHERE o_storyboard.flowId=o_imageFlow.id)',
    flowIds,
  );
}
