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

  @override
  String get projectTitle => '我的项目';

  @override
  String get projectSubtitle => '管理您的所有短剧项目';

  @override
  String get projectNewProject => '新建项目';

  @override
  String get projectDialogEditTitle => '编辑项目';

  @override
  String get projectDialogAddTitle => '新建项目';

  @override
  String get projectDialogSave => '保存';

  @override
  String get projectDialogOk => '确定';

  @override
  String get projectDialogCancel => '取消';

  @override
  String get projectDialogProjectType => '项目类型';

  @override
  String get projectDialogSelectType => '选择项目类型';

  @override
  String get projectDialogBasedOnNovel => '基于小说原文';

  @override
  String get projectDialogProjectName => '项目名称';

  @override
  String get projectDialogProjectNamePh => '请输入项目名称';

  @override
  String get projectDialogNovelType => '小说类型';

  @override
  String get projectDialogNovelTypePh => '例如:玄幻、科幻、言情';

  @override
  String get projectDialogArtStyle => '画风';

  @override
  String get projectDialogSelected => '已选：';

  @override
  String get projectDialogSelectArtStyle => '请选择画风';

  @override
  String get projectDialogNewArtStyle => '新建画风';

  @override
  String get projectDialogLoading => '加载中...';

  @override
  String get projectDialogVideoRatio => '影片比例';

  @override
  String get projectDialogNovelIntro => '小说简介';

  @override
  String get projectDialogNovelIntroPh => '请输入小说简介';

  @override
  String get projectDialogEditArtStyleTitle => '编辑画风';

  @override
  String get projectDialogNewArtStyleTitle => '新建画风';

  @override
  String get projectDialogArtStyleName => '画风名称';

  @override
  String get projectDialogArtStyleNamePh => '请输入画风名称';

  @override
  String get projectDialogArtStyleImage => '画风图片';

  @override
  String get projectDialogRemove => '移除';

  @override
  String get projectDialogUploadCover => '上传封面';

  @override
  String get projectDialogArtStylePrompt => '提示词';

  @override
  String get projectDialogAiExtract => 'AI提取提示词';

  @override
  String get projectDialogPromptPlaceholder => '描述提示词';

  @override
  String get projectDialogVisualManual => '视觉手册';

  @override
  String get projectDialogNewVisualManual => '新建视觉手册';

  @override
  String get projectDialogEditVisualManualTitle => '编辑视觉手册';

  @override
  String get projectDialogNewVisualManualTitle => '新建视觉手册';

  @override
  String get projectDialogVisualManualName => '视觉手册名称';

  @override
  String get projectDialogVisualManualNamePh => '请输入视觉手册名称';

  @override
  String get projectDialogVisualManualCover => '视觉手册封面';

  @override
  String get projectDialogVisualManualPrompt => '视觉手册提示词';

  @override
  String get projectDialogModelData => '选择图片模型';

  @override
  String get projectDialogVideoModelData => '选择视频模型';

  @override
  String get projectDialogPromptSaveSuccess => '更新成功';

  @override
  String get projectDialogPromptTitle => '提示词';

  @override
  String get projectDialogBasedOnScript => '基于剧本';

  @override
  String get projectDialogMdFile => '视觉手册文件';

  @override
  String get projectDialogDirectorManual => '导演手册';

  @override
  String get projectDialogAddDirectorManual => '新建导演手册';

  @override
  String get projectDialogEditingDirectorManual => '编辑导演手册';

  @override
  String get projectDialogNewDirecorManualTitle => '新建导演手册';

  @override
  String get projectDialogDirectorManualPrompt => '导演手册提示词';

  @override
  String get projectDialogDirectorManualName => '导演手册名称';

  @override
  String get projectDialogDirectorManualNamePh => '输入导演手册名称';

  @override
  String get projectDialogDirectorFile => '导演手册文件';

  @override
  String get projectDialogDirectorManualCover => '导演手册封面';

  @override
  String get projectMsgFetchFailed => '获取项目列表失败';

  @override
  String get projectMsgNotFound => '未找到该项目!';

  @override
  String get projectMsgEditSuccess => '编辑项目成功';

  @override
  String get projectMsgEditFailed => '编辑项目失败';

  @override
  String get projectMsgAddSuccess => '新增项目成功';

  @override
  String get projectMsgAddFailed => '新增项目失败';

  @override
  String get projectMsgDeleteHeader => '删除项目';

  @override
  String get projectMsgDeleteBody => '确定要删除该项目吗？';

  @override
  String get projectMsgDeleteConfirm => '删除';

  @override
  String get projectMsgDeleteCancel => '取消';

  @override
  String get projectMsgDeleteSuccess => '删除项目成功';

  @override
  String get projectMsgDeleteFailed => '删除项目失败';

  @override
  String get projectMsgExtractSuccess => '提示词提取成功';

  @override
  String get projectMsgExtractFailed => '提取失败';

  @override
  String get projectMsgEnterArtStyleName => '请输入画风名称';

  @override
  String get projectMsgArtStyleUpdated => '画风已更新';

  @override
  String get projectMsgArtStyleAdded => '画风已添加';

  @override
  String get projectMsgOperationFailed => '操作失败';

  @override
  String get projectMsgEnterVisualManualName => '请输入视觉手册名称';

  @override
  String get projectMsgEnterVisualManualImage => '请上传视觉手册封面图片';

  @override
  String get projectMsgEnterVisualManualTabData => '提示词不能为空';

  @override
  String get projectMsgVisualManualUpdated => '视觉手册已更新';

  @override
  String get projectMsgVisualManualAdded => '视觉手册已添加';

  @override
  String get projectMsgDeleteVisualManualHeader => '删除视觉手册';

  @override
  String projectMsgDeleteVisualManualBody(String name) {
    return '确定要删除视觉手册「$name」吗？';
  }

  @override
  String get projectMsgDeleteVisualManualConfirm => '删除';

  @override
  String get projectMsgDeleteVisualManualCancel => '取消';

  @override
  String get projectMsgEnterProjectName => '请输入项目名称';

  @override
  String get projectMsgEnterProjectIntro => '请输入小说简介';

  @override
  String get projectMsgEnterProjectType => '请输入小说类型';

  @override
  String get projectMsgEnterArtStyle => '请选择项目视觉手册';

  @override
  String get projectMsgEnterVideoRatio => '请选择影片比例';

  @override
  String get projectMsgEnterImageModel => '请选择图片模型';

  @override
  String get projectMsgEnterVideoModel => '请选择视频模型';

  @override
  String get projectMsgVisualManualDeleted => '删除成功';

  @override
  String get projectMsgSelectMode => '请选择模式';

  @override
  String get projectMsgDeleteDirectorManualHeader => '删除导演手册';

  @override
  String projectMsgDeleteDirectorManualBody(String name) {
    return '确定要删除导演手册「$name」吗？';
  }

  @override
  String get projectMsgDirectorManualUpdated => '导演手册已更新';

  @override
  String get projectMsgDirectorManualAdded => '导演手册已添加';

  @override
  String get projectMsgDirectorManual => '请选择项目导演手册';

  @override
  String get projectMsgModelProviderDisabled => '视频模型或图片模型供应商未启用或无模型供应商，请先配置';

  @override
  String get projectTypeNovel => '基于小说原文';

  @override
  String get projectTypeScript => '基于小说剧本';

  @override
  String get commonEdit => '编辑';

  @override
  String get manualTabReadme => 'README';

  @override
  String get manualTabPrefix => '前缀';

  @override
  String get manualTabCharacter => '角色';

  @override
  String get manualTabCharacterDerivative => '角色衍生';

  @override
  String get manualTabProp => '道具';

  @override
  String get manualTabPropDerivative => '道具衍生';

  @override
  String get manualTabScene => '场景';

  @override
  String get manualTabSceneDerivative => '场景衍生';

  @override
  String get manualTabStoryboard => '分镜';

  @override
  String get manualTabStoryboardVideo => '分镜视频';

  @override
  String get manualTabDirectorPlanning => '技法-导演规划';

  @override
  String get manualTabStoryboardTable => '技法-分镜表设计';

  @override
  String get manualTabNarrativePlanning => '导演规划';

  @override
  String get manualTabNarrativeTable => '分镜表';

  @override
  String get errManualInvalid => '手册数据无效';
}
