import 'package:dramaflow/src/engine/config.dart';

class ActionPolicyMeta {
  final bool costsMoney;
  final bool destructive;
  const ActionPolicyMeta({this.costsMoney = false, this.destructive = false});
}

/// 队列 taskClass → 策略元数据（与 queue.dart laneOf 的键保持一致）
const actionPolicyByTaskClass = <String, ActionPolicyMeta>{
  'event_generation': ActionPolicyMeta(costsMoney: true),
  'script_generation': ActionPolicyMeta(costsMoney: true),
  'asset_extraction': ActionPolicyMeta(costsMoney: true),
  'asset_prompt_polish': ActionPolicyMeta(costsMoney: true),
  'director_plan_generation': ActionPolicyMeta(costsMoney: true),
  'storyboard_table_generation': ActionPolicyMeta(costsMoney: true),
  'asset_image_generation': ActionPolicyMeta(costsMoney: true),
  'storyboard_generate': ActionPolicyMeta(costsMoney: true),
  'storyboard_image_generation': ActionPolicyMeta(costsMoney: true),
  'video_generation': ActionPolicyMeta(costsMoney: true),
  'audio_bind': ActionPolicyMeta(costsMoney: true),
};

/// 非队列的破坏性动作标识（供助手与 UI 复用同一张表）
const destructiveActionKeys = <String>{
  'delete_assets',
  'delete_scripts',
  'delete_storyboards',
  'delete_video',
  'clear_tracks',
  'write_script',
  'note_delete',
  'clear_chat',
  'clear_all_data',
  'replace_storyboards',
  'cancel_generation',
};

enum PolicyVerdict { allow, confirmMoney, confirmDestructive }

PolicyVerdict checkAction(
  EngineConfig config, {
  String? taskClass,
  String? destructiveKey,
  bool autoMode = false,
}) {
  // 优先检查 taskClass（队列任务）
  if (taskClass != null && actionPolicyByTaskClass.containsKey(taskClass)) {
    final meta = actionPolicyByTaskClass[taskClass]!;
    if (meta.costsMoney &&
        config.str('policy.confirmMoney') != '0' &&
        !autoMode) {
      return PolicyVerdict.confirmMoney;
    }
    return PolicyVerdict.allow;
  }

  // 其次检查 destructiveKey（破坏动作）
  if (destructiveKey != null &&
      destructiveActionKeys.contains(destructiveKey)) {
    if (config.str('policy.confirmDestructive') != '0') {
      return PolicyVerdict.confirmDestructive;
    }
    return PolicyVerdict.allow;
  }

  // 默认允许
  return PolicyVerdict.allow;
}
