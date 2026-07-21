// 助手会话代际号（epoch）：清空聊天记录、清空已激活技能都会递增它。
// _driveAssistantLoop 等长时间运行的对话循环在每次往数据库回写之前，都会用
// 循环开始时记下的代际号与"当下"的代际号比对——如果中途发生过清空导致代际号
// 变了，说明这次回写已经过期，必须放弃并停止继续，不能让飞行中的旧请求把用户
// 已经明确清空的会话复活。
//
// 按 projectId+family 区分；进程内内存态即可——清空本身已经是最新事实来源
// （数据库行已被删除），代际号只是给旧请求一个"认出自己已经过期"的信号，不需要
// 跨进程或跨重启持久化。
final Map<String, int> _assistantSessionEpochs = <String, int>{};

String _assistantSessionEpochKey(int projectId, String family) =>
    '$projectId::$family';

/// 当前项目 + 家族的助手会话代际号（默认 0）。
int assistantSessionEpoch(int projectId, String family) =>
    _assistantSessionEpochs[_assistantSessionEpochKey(projectId, family)] ?? 0;

/// 递增并返回新的代际号；任何"清空当前会话相关持久状态"的操作都应调用它。
int bumpAssistantSessionEpoch(int projectId, String family) {
  final key = _assistantSessionEpochKey(projectId, family);
  final next = (_assistantSessionEpochs[key] ?? 0) + 1;
  _assistantSessionEpochs[key] = next;
  return next;
}
