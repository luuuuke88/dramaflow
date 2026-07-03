// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get menuMyProject => '我的项目';

  @override
  String get menuTaskCenter => '任务中心';

  @override
  String get menuNovel => '小说原文';

  @override
  String get menuScriptAgent => '剧本Agent';

  @override
  String get menuScriptManage => '剧本管理';

  @override
  String get menuCornerScape => '塑角造景';

  @override
  String get menuProduction => '视频生产';

  @override
  String get menuAssetCenter => '资产中心';

  @override
  String get menuSettings => '设置';

  @override
  String get menuJumpGithub => '跳转Github';

  @override
  String get menuFeedbackQuestions => '反馈问题';

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonDelete => '删除';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonNextStep => '下一步';

  @override
  String get commonPrevStep => '上一步';

  @override
  String get projectListTitle => '项目';

  @override
  String get projectListSubtitle => '临时项目列表，T9 将全量重写';

  @override
  String get projectNew => '新建项目';

  @override
  String get projectName => '项目名称';

  @override
  String get projectCreate => '创建';

  @override
  String get projectCreated => '项目已创建';

  @override
  String get projectEmpty => '暂无项目';

  @override
  String get projectUntitled => '未命名项目';

  @override
  String get errProviderMissing => '供应商缺失或已停用';

  @override
  String get errModelMissing => '模型缺失或未绑定';

  @override
  String get errPromptMissing => '提示词不存在';

  @override
  String get errConfigVersion => '配置文件版本不兼容';

  @override
  String get errNetwork => '网络请求失败';

  @override
  String get errLlmFormat => '模型输出格式无效';

  @override
  String get errCanceled => '任务已取消';

  @override
  String get errAppRestart => '应用重启，任务中断';

  @override
  String get errFileTooLarge => '文件过大';

  @override
  String get errFileType => '文件类型不支持';

  @override
  String get errRegexInvalid => '正则表达式无效';

  @override
  String get errNoChapters => '未找到章节';

  @override
  String get promptPanelTitle => '提示词';

  @override
  String get promptEventExtractionTitle => '事件提取';

  @override
  String get promptEventExtractionDescription => '小说章节结构化事件提取提示词';

  @override
  String get promptScriptAssetExtractionTitle => '剧本资产提取';

  @override
  String get promptScriptAssetExtractionDescription => '从剧本提取角色、场景、道具的提示词';

  @override
  String get promptImageSizeDirectiveTitle => '图片尺寸指令';

  @override
  String get promptImageSizeDirectiveDescription => '注入图片生成请求的尺寸约束';

  @override
  String get promptUnset => '未设置';

  @override
  String get promptOverridden => '已修改';

  @override
  String promptCharacterCount(int count) {
    return '$count 字符';
  }

  @override
  String promptEditTitle(Object title) {
    return '编辑提示词 · $title';
  }

  @override
  String get promptSaved => '提示词已保存';

  @override
  String get promptRestoreDefault => '恢复默认';

  @override
  String get promptRestoreDefaultTitle => '恢复默认';

  @override
  String promptRestoreDefaultMessage(Object title) {
    return '确定将“$title”恢复为内置默认内容吗？';
  }

  @override
  String get promptRestoreDefaultConfirm => '恢复';

  @override
  String get promptRestored => '提示词已恢复默认';

  @override
  String get errTaskUnsupported => '不支持的任务类型';

  @override
  String get shellSelectProject => '请选择项目';

  @override
  String shellComingSoon(String batch) {
    return '本区域随 $batch 批次交付';
  }

  @override
  String shellComingSoonBadge(String batch) {
    return '$batch';
  }
}
