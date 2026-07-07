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
  String get errPlatformComposer => '平台视频合成失败';

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
  String get promptGlobalTemplates => '全局模板';

  @override
  String get promptModelTemplates => '模型专属模板';

  @override
  String get promptModelTemplatesEmpty => '暂无模型专属模板。导入配置或模型模板后会显示在这里。';

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
  String get projectTitle => '我的项目';

  @override
  String get projectSubtitle => '管理您的所有短剧项目';

  @override
  String get projectNewProject => '新建项目';

  @override
  String projectStatChapters(int count) {
    return '章节 $count';
  }

  @override
  String projectStatScripts(int count) {
    return '剧本 $count';
  }

  @override
  String projectStatAssets(int count) {
    return '素材 $count';
  }

  @override
  String projectStatStoryboards(int count) {
    return '分镜 $count';
  }

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

  @override
  String get novelImportText => '导入原文';

  @override
  String get novelBatchDelete => '批量删除';

  @override
  String get novelEventAnalysis => '事件分析';

  @override
  String get novelSearchPlaceholder => '搜索原文名称...';

  @override
  String get novelSearch => '搜索';

  @override
  String get novelGenerating => '生成中...';

  @override
  String get novelGenFailed => '生成失败';

  @override
  String get novelViewDetail => '查看详情';

  @override
  String get novelNone => '无';

  @override
  String get novelEdit => '编辑';

  @override
  String get novelDelete => '删除';

  @override
  String get novelColId => '序号';

  @override
  String get novelColReel => '卷';

  @override
  String get novelColChapter => '章节名称';

  @override
  String get novelColChapterData => '章节内容';

  @override
  String get novelColEvent => '事件';

  @override
  String get novelColOperation => '操作';

  @override
  String get novelMsgBatchDeleteHeader => '批量删除';

  @override
  String novelMsgBatchDeleteBody(String count) {
    return '确定要删除选中的 $count 条数据吗?';
  }

  @override
  String get novelMsgBatchDeleteSuccess => '批量删除成功';

  @override
  String get novelMsgDeleteHeader => '删除确认';

  @override
  String novelMsgDeleteBody(String name) {
    return '确定要删除章节名称为「$name」的数据吗?';
  }

  @override
  String get novelMsgDeleteSuccess => '删除成功';

  @override
  String get novelMsgEventAnalysisHeader => '事件分析';

  @override
  String novelMsgEventAnalysisBody(String count) {
    return '确定要对选中的 $count 条数据进行事件分析吗?';
  }

  @override
  String get novelImportTitle => '上传小说原文';

  @override
  String get novelImportStep1 => '第一步';

  @override
  String get novelImportStep2 => '第二步';

  @override
  String get novelImportStep3 => '第三步';

  @override
  String get novelImportDragUpload => '拖拽小说原文文件到此处或点击上传';

  @override
  String get novelImportUploadHint => '支持 .txt, .docx 格式，建议文件大小不超过 10MB';

  @override
  String get novelImportOr => '或';

  @override
  String get novelImportPasteLabel => '直接粘贴小说原文内容';

  @override
  String get novelImportPastePlaceholder => '请输入小说原文内容';

  @override
  String get novelImportChars => '字符';

  @override
  String get novelImportTooShort => '内容过短，建议至少100字符';

  @override
  String novelImportParsedChapters(String count) {
    return '已解析 $count 章节';
  }

  @override
  String get novelImportNextStep => '下一步';

  @override
  String get novelImportPrevStep => '上一步';

  @override
  String novelImportSelectedInfo(String count) {
    return '已勾选：$count字';
  }

  @override
  String get novelImportEventAnalysis => '事件分析';

  @override
  String get novelImportSaveAndAnalyze => '保存原文并分析事件';

  @override
  String get novelImportColChapter => '章';

  @override
  String get novelImportColReel => '卷';

  @override
  String get novelImportColChapterName => '章节名称';

  @override
  String get novelImportColChapterData => '章节内容';

  @override
  String get novelImportMsgParseFailed => '文件解析失败，请重新上传';

  @override
  String get novelImportMsgSelectFile => '选择文件';

  @override
  String get novelImportMsgDocNotSupported => '.doc文件不支持解析，请转换为.ts文件';

  @override
  String get novelImportMsgUnsupportedType => '不支持的文件类型';

  @override
  String get novelImportMsgFileTooLarge => '文件大小超过10MB，请上传更小的文件';

  @override
  String get novelImportMsgSelectChapters => '请先勾选章节';

  @override
  String get novelImportMsgSaveSuccess => '小说原文保存成功';

  @override
  String get novelImportImportAdd => '拖拽文件到此处或点击上传';

  @override
  String get novelImportLimit => '支持 .ts格式';

  @override
  String get novelEditDialogTitle => '编辑小说原文';

  @override
  String get novelEditDialogChapterName => '章节名称';

  @override
  String get novelEditDialogChapterNamePh => '请输入章节名称';

  @override
  String get novelEditDialogEventContent => '事件内容';

  @override
  String get novelEditDialogEventContentPh => '输入事件内容';

  @override
  String get novelEditDialogChapterContent => '章节内容';

  @override
  String get novelEditDialogChapterContentPh => '请输入章节内容';

  @override
  String get novelEditDialogCancel => '取消';

  @override
  String get novelEditDialogSave => '保存';

  @override
  String get novelEditDialogMsgUpdateSuccess => '小说原文更新成功';

  @override
  String get novelEventRegenerate => '重新生成事件';

  @override
  String get novelEventBatchDelete => '批量删除';

  @override
  String get novelEventNoData => '暂无事件数据，点击开始生成';

  @override
  String get novelEventGenerate => '生成事件';

  @override
  String get novelEventGeneratingHint => '事件生成中，请稍候...';

  @override
  String get novelEventLoading => '加载中...';

  @override
  String get novelEventDelete => '删除';

  @override
  String get novelEventColId => '事件ID';

  @override
  String get novelEventColEventName => '事件名称';

  @override
  String get novelEventColChapters => '来源章节';

  @override
  String get novelEventColDetail => '事件过程';

  @override
  String get novelEventColCreateTime => '创建时间';

  @override
  String get novelEventColOperation => '操作';

  @override
  String get novelEventMsgDeleteHeader => '删除事件';

  @override
  String get novelEventMsgDeleteBody => '确定要删除这个事件吗？';

  @override
  String get novelEventMsgDeleteSuccess => '删除成功';

  @override
  String get novelEventMsgGenerateSuccess => '事件生成成功';

  @override
  String get novelEventMsgBatchDeleteHeader => '批量删除';

  @override
  String novelEventMsgBatchDeleteBody(String count) {
    return '确定要删除选中的 $count 条数据吗?';
  }

  @override
  String get novelEventMsgBatchDeleteSuccess => '批量删除成功';

  @override
  String get novelAnalysisAnalyzeFirst => '请先分析事件';

  @override
  String get novelAnalysisStartAnalysis => '开始分析';

  @override
  String novelAnalysisChapterHeader(String index, String name) {
    return '第$index章 - $name';
  }

  @override
  String get novelAnalysisAnalyzing => '事件分析中';

  @override
  String get scriptSearchPlaceholder => '搜索剧本名称...';

  @override
  String get scriptSearch => '搜索';

  @override
  String get scriptAddScript => '新建剧本';

  @override
  String get scriptCancelSelectAll => '取消全选';

  @override
  String get scriptSelectAll => '全选';

  @override
  String get scriptExportScript => '导出剧本';

  @override
  String get scriptMsgExtracting => '资产提取中';

  @override
  String get scriptMsgExtractFailed => '资产提取失败';

  @override
  String get scriptMsgExtractingInProgress => '正在提取中';

  @override
  String get scriptMsgProjectNotFound => '项目未找到';

  @override
  String get scriptMsgSelectExport => '请选择导出剧本';

  @override
  String get scriptMsgDeleteHeader => '确认删除';

  @override
  String get scriptMsgDeleteBody => '确认要删除这个剧本吗？次操作无法复原';

  @override
  String get scriptMsgDeleteConfirm => '删除';

  @override
  String get scriptMsgCancel => '取消';

  @override
  String get scriptMsgDeleteSuccess => '删除成功';

  @override
  String get scriptMsgDeleteFailed => '删除失败';

  @override
  String get scriptMsgSelectDelScript => '请选择删除剧本';

  @override
  String get scriptMsgBatchDeleteHeader => '批量删除';

  @override
  String scriptMsgBatchDeleteBody(String count) {
    return '确定要删除选中的$count个剧本吗？此操作无法复原';
  }

  @override
  String get scriptMsgBatchDeleteSuccess => '批量删除成功';

  @override
  String get scriptMsgSearchFailed => '搜索剧本失败';

  @override
  String get scriptMsgSelectsExport => '请选择导出剧本';

  @override
  String get scriptAddTitle => '新增剧本';

  @override
  String get scriptAddScriptName => '剧本名称';

  @override
  String get scriptAddScriptNamePh => '请输入剧本名称';

  @override
  String get scriptAddUploadFile => '上传文件';

  @override
  String get scriptAddDragUpload => '拖拽剧本文件到此处或点击上传';

  @override
  String get scriptAddUploadHint => '支持 .txt, .docx 格式，建议文件大小不超过 10MB';

  @override
  String get scriptAddScriptContent => '剧本内容';

  @override
  String get scriptAddScriptContentPh => '请上传或输入剧本内容...';

  @override
  String get scriptAddRelatedAssets => '关联资产';

  @override
  String get scriptAddSelectAssets => '选择资产';

  @override
  String get scriptAddNoAssets => '暂未关联资产';

  @override
  String get scriptAddCancel => '取消';

  @override
  String get scriptAddConfirm => '确认';

  @override
  String get scriptAddMsgFileReadFailed => '文件读取失败';

  @override
  String get scriptAddMsgDocNotSupported => '.doc文件不支持解析,请转换为.txt或.docx文件';

  @override
  String get scriptAddMsgUnsupportedType => '不支持的文件类型';

  @override
  String get scriptAddMsgFileTooLarge => '文件大小超过10MB，请上传更小的文件';

  @override
  String get scriptAddMsgParsing => '文件解析中...';

  @override
  String get scriptAddMsgParseFailed => '文件解析失败，请重新上传';

  @override
  String get scriptAddMsgSelectAssetsTitle => '选择关联资产';

  @override
  String get scriptAddMsgEnterContent => '请上传或输入剧本内容';

  @override
  String get scriptAddMsgEnterName => '请输入剧本名称';

  @override
  String get scriptAddMsgAddSuccess => '剧本添加成功';

  @override
  String get scriptAddMsgAddFailed => '添加剧本失败，请稍后再试';

  @override
  String get scriptEditTitle => '剧本详情';

  @override
  String get scriptEditScriptName => '剧本名称';

  @override
  String get scriptEditScriptNamePh => '请输入剧本名称';

  @override
  String get scriptEditScriptContent => '剧本内容';

  @override
  String get scriptEditScriptContentPh => '请输入剧本内容...';

  @override
  String get scriptEditRelatedAssets => '关联资产';

  @override
  String get scriptEditSelectAssets => '选择资产';

  @override
  String get scriptEditNoAssets => '暂未关联资产';

  @override
  String get scriptEditMsgSelectAssetsTitle => '选择关联资产';

  @override
  String get scriptEditMsgUpdateSuccess => '剧本更新成功';

  @override
  String get scriptEditMsgUpdateFailed => '更新剧本失败，请稍后再试';

  @override
  String get scriptMarkdownBold => '加粗';

  @override
  String get scriptMarkdownItalic => '斜体';

  @override
  String get scriptMarkdownHeading => '标题';

  @override
  String get scriptMarkdownDialogue => '台词';

  @override
  String get scriptMarkdownEdit => '编辑';

  @override
  String get scriptMarkdownPreview => '预览';

  @override
  String get scriptMarkdownPreviewEmpty => '暂无内容';

  @override
  String get scriptMarkdownBoldPlaceholder => '重点';

  @override
  String get scriptMarkdownItalicPlaceholder => '强调';

  @override
  String get scriptMarkdownDialogueSnippet => '角色：台词';

  @override
  String get scriptDeleteScript => '批量删除剧本';

  @override
  String get scriptExtractAssets => '提取资产';

  @override
  String get scriptImportGetAiRegex => 'AI解析正则';

  @override
  String get scriptImportEpisodeRegexPh => '自定义剧本拆分正则';

  @override
  String get scriptBatchAdd => '批量添加';

  @override
  String get scriptGenerateFromEvents => '事件生成剧本';

  @override
  String get scriptGenerateFromEventsTitle => '选择事件生成剧本';

  @override
  String get scriptGenerateFromEventsEmpty => '暂无可用事件，请先在章节页生成事件';

  @override
  String get scriptGenerateFromEventsConfirm => '生成剧本';

  @override
  String get scriptGenerateFromEventsSelectHint => '请选择要生成剧本的事件';

  @override
  String get scriptGenerateFromEventsSubmitted => '剧本生成已提交';

  @override
  String get scriptStateWaiting => '等待提取...';

  @override
  String get scriptStateExtracting => '提取中...';

  @override
  String get scriptStateFailed => '提取失败';

  @override
  String get settingsLanguage => '语言';

  @override
  String get localeSystem => '跟随系统';

  @override
  String get assetsTabRole => '角色';

  @override
  String get assetsTabTool => '道具';

  @override
  String get assetsTabScene => '场景';

  @override
  String get assetsTabClip => '素材';

  @override
  String get assetsTabAudio => '音频';

  @override
  String get assetsAddPrefix => '新增';

  @override
  String get assetsGeneratePrompt => '生成提示词';

  @override
  String get assetsGenerateImage => '生成图片';

  @override
  String get assetsBatchDelete => '批量删除';

  @override
  String get assetsSearchPlaceholder => '搜索资产名称...';

  @override
  String get assetsColPreview => '预览';

  @override
  String get assetsColName => '名称';

  @override
  String get assetsColPrompt => '提示词';

  @override
  String get assetsColDescribe => '描述';

  @override
  String get assetsColRemark => '备注';

  @override
  String get assetsColCreateTime => '创建时间';

  @override
  String get assetsColOperation => '操作';

  @override
  String get assetsGenerate => '生成';

  @override
  String get assetsEdit => '编辑';

  @override
  String get assetsDelete => '删除';

  @override
  String get assetsGenerating => '生成中...';

  @override
  String get assetsConfirmDeleteHeader => '确认删除';

  @override
  String get assetsConfirmDeleteBody => '确定要删除该资产吗？其图片版本与子资产将一并删除';

  @override
  String assetsConfirmBatchDeleteBody(String count) {
    return '确定要删除选中的 $count 个资产吗？';
  }

  @override
  String get assetsDeleteSuccess => '删除成功';

  @override
  String get assetsSex => '性别';

  @override
  String get assetsAudioName => '音色';

  @override
  String get assetsAudioText => '音频文本';

  @override
  String get assetsPlay => '播放';

  @override
  String get assetsAddName => '名称';

  @override
  String get assetsAddNamePh => '请输入资产名称';

  @override
  String get assetsAddNameRequired => '请输入资产名称';

  @override
  String get assetsAddDescribe => '描述';

  @override
  String get assetsAddDescribePh => '请输入资产描述';

  @override
  String get assetsAddDescribeRequired => '请输入资产描述';

  @override
  String get assetsAddRemark => '备注';

  @override
  String get assetsAddRemarkPh => '请输入备注';

  @override
  String get assetsAddPrompt => '提示词';

  @override
  String get assetsAddPromptPh => '请输入生成提示词';

  @override
  String get assetsAddAddSuccess => '新增资产成功';

  @override
  String get assetsAddUpdateSuccess => '更新资产成功';

  @override
  String get assetsAddAudioNamePh => '请输入音色名称';

  @override
  String get assetsAddSexPh => '请输入性别';

  @override
  String get assetsAddAudioFile => '音频文件';

  @override
  String get assetsAddAudioTextPh => '请输入该音频对应的文本内容';

  @override
  String get assetsAddAudioDescPh => '请输入该音频的描述';

  @override
  String get assetsAddAudioItem => '添加音频';

  @override
  String get assetsAddPleaseUploadAudio => '请上传音频文件';

  @override
  String get assetsGenerateSpeech => '文本配音';

  @override
  String get assetsTtsGenerate => '生成配音';

  @override
  String get assetsTtsText => '配音文本';

  @override
  String get assetsTtsTextPh => '请输入要合成的台词或旁白';

  @override
  String get assetsTtsVoice => 'Voice ID';

  @override
  String get assetsTtsVoicePh => 'alloy / 自定义 voice id';

  @override
  String get assetsTtsTextRequired => '请输入配音文本';

  @override
  String get assetsGenHeader => '生成图片';

  @override
  String get assetsGenUploadRef => '参考图';

  @override
  String get assetsGenOptional => '可选';

  @override
  String get assetsGenPromptLabel => '提示词';

  @override
  String get assetsGenSmartGenerate => '智能生成';

  @override
  String get assetsGenSelectModel => '选择模型';

  @override
  String get assetsGenSelectResolution => '选择分辨率';

  @override
  String get assetsGenGenerateBtn => '生成';

  @override
  String get assetsGenFillPrompt => '请填写提示词';

  @override
  String get assetsGenPickModel => '请选择模型';

  @override
  String assetsGenGeneratedCount(String count) {
    return '已生成 $count 张';
  }

  @override
  String get assetsGenGeneratingLabel => '生成中...';

  @override
  String get assetsGenGenFailed => '生成失败';

  @override
  String get assetsGenImageSaved => '图片已保存';

  @override
  String get assetsGenAssetGenSuccess => '已提交生成';

  @override
  String get assetsGenPromptSuccess => '提示词生成成功';

  @override
  String get assetsGenConfirmSelect => '请先选择一张图片';

  @override
  String get assetsGenResultTitle => '生成结果';

  @override
  String get assetsBatchHeader => '批量生成';

  @override
  String assetsBatchSelected(String count) {
    return '已选 $count 项';
  }

  @override
  String get assetsBatchSelectAll => '全选';

  @override
  String get assetsBatchClearSelection => '清空选择';

  @override
  String get assetsBatchColPreviewImg => '预览图';

  @override
  String get assetsBatchInputPh => '请输入提示词';

  @override
  String assetsBatchSaveSelected(String count) {
    return '保存已选($count)';
  }

  @override
  String get assetsBatchMissingPrompts => '请先为所选资产生成提示词';

  @override
  String get assetsBatchPromptDone => '提示词批量生成已提交';

  @override
  String get assetsBatchImageDone => '图片批量生成已提交';

  @override
  String get assetsBatchSaveSuccess => '保存成功';

  @override
  String get assetsCancelBtn => '取消';

  @override
  String get assetsSelectAtLeastOne => '请至少选择一项';

  @override
  String get productionEditImageInvalidConnection => '无法连接：仅可连到生成节点且不可重复';

  @override
  String get productionEditImageUploadImage => '上传图片';

  @override
  String get productionEditImageImageGeneration => '图片生成';

  @override
  String get productionEditImageGenerating => '生成中...';

  @override
  String get productionEditImagePromptPlaceholder => '描述生成需求';

  @override
  String get productionEditImageGenerateBtn => '生成';

  @override
  String get productionEditImageUpload => '上传节点';

  @override
  String get productionEditImageGenerate => '生成节点';

  @override
  String get productionNodeScriptTitle => '剧本';

  @override
  String get productionNodeScriptPlanTitle => '剧本规划';

  @override
  String get productionNodeAssetsTitle => '资产';

  @override
  String get productionNodeStoryboardTableTitle => '分镜表';

  @override
  String get productionNodeStoryboardTitle => '分镜';

  @override
  String get productionNodeWorkbenchTitle => '工作台';

  @override
  String get productionMobileNodeInspector => '节点检查器';

  @override
  String get productionMobileCurrentNode => '当前节点';

  @override
  String get productionSelectEpisode => '选择剧集';

  @override
  String get productionNoScripts => '暂无剧本，请先在「剧本管理」创建';

  @override
  String get productionGoToScripts => '去创建剧本';

  @override
  String get productionStoryboardGenerate => '生成分镜';

  @override
  String get productionStoryboardGenerating => '分镜生成中...';

  @override
  String productionStoryboardSelectedCount(String count) {
    return '已选择 $count 个';
  }

  @override
  String get productionStoryboardSelectAll => '全选';

  @override
  String get productionStoryboardClearSelection => '清空选择';

  @override
  String get productionStoryboardBatchGenerateImage => '生成图片';

  @override
  String get productionStoryboardDeleteNode => '删除';

  @override
  String get productionStoryboardEditNode => '编辑';

  @override
  String get productionStoryboardScaleRatio => '缩放';

  @override
  String get productionStoryboardNotGenerated => '未生成';

  @override
  String get productionStoryboardVideoDesc => '画面描述';

  @override
  String get productionStoryboardVideoDescPlaceholder => '请输入画面描述';

  @override
  String get productionStoryboardPrompt => '提示词';

  @override
  String get productionStoryboardPromptPlaceholder => '请输入分镜提示词';

  @override
  String get productionStoryboardConfirmDeleteBody => '确定要删除该分镜吗？';

  @override
  String productionStoryboardConfirmBatchDeleteBody(String count) {
    return '确定要删除选中的 $count 个分镜吗？';
  }

  @override
  String get productionStoryboardInsertHint => '插入分镜';

  @override
  String get productionStoryboardEditImageEntry => '节点编辑器';

  @override
  String get productionChatDisabledHint => 'Agent 对话在后续批次开放';

  @override
  String get productionEmptyProject => '请先选择项目';

  @override
  String get workbenchTitle => '工作台';

  @override
  String get workbenchOpen => '打开工作台';

  @override
  String get workbenchGenerateVideo => '生成视频';

  @override
  String get workbenchGenerateAll => '全部生成视频';

  @override
  String get workbenchGenerateAllPrompts => '全部生成运镜提示词';

  @override
  String get workbenchClearSelectedTracks => '清空已选轨道';

  @override
  String get workbenchClearSelectedTracksConfirm =>
      '将清空已勾选镜头的视频轨道与候选视频，分镜本身会保留。';

  @override
  String get workbenchClearTracksAction => '清空';

  @override
  String get workbenchClearSelectedTracksDone => '已清空已选轨道';

  @override
  String get workbenchCompose => '合成本集';

  @override
  String get workbenchComposing => '合成中...';

  @override
  String get workbenchComposeSuccess => '合成成功';

  @override
  String workbenchComposeMissing(String count) {
    return '还有 $count 个镜头未选定视频';
  }

  @override
  String get workbenchNoShots => '暂无分镜，请先在「制作」的分镜节点生成';

  @override
  String get workbenchCandidateNotGenerated => '未生成';

  @override
  String get workbenchSelectCandidate => '选为正片';

  @override
  String get workbenchSelected => '已选';

  @override
  String get workbenchGeneratePrompt => '生成运镜提示词';

  @override
  String get workbenchPickClip => '素材库';

  @override
  String get workbenchPickClipTitle => '选择素材视频';

  @override
  String get workbenchNoClipAssets => '素材库暂无视频素材';

  @override
  String get workbenchSaveCandidateToAssets => '保存到素材库';

  @override
  String workbenchCandidateClipName(int videoId) {
    return '镜头候选 #$videoId';
  }

  @override
  String get workbenchShotAudioLabel => '镜头配音';

  @override
  String get workbenchShotAudioNone => '无配音';

  @override
  String get workbenchEditPrompt => '编辑运镜提示词';

  @override
  String get workbenchOutputPath => '输出路径';

  @override
  String get workbenchDuration => '时长';

  @override
  String workbenchSavedToAssets(int assetId) {
    return '已保存到素材库（素材 #$assetId）';
  }

  @override
  String get workbenchTimelineOverview => '时间线总览';

  @override
  String get workbenchTimelineVideoTrack => '视频轨';

  @override
  String get workbenchTimelineAudioTrack => '音频轨';

  @override
  String get workbenchTimelineOverlayTrack => '素材层';

  @override
  String get workbenchTimelineMediaLibrary => '媒体库';

  @override
  String get workbenchTimelineMediaLibraryTitle => '时间线媒体库';

  @override
  String get workbenchTimelineAddAtPlayhead => '添加到播放头';

  @override
  String get workbenchTimelineMediaBin => '可拖素材';

  @override
  String workbenchTimelineDraggableClipName(String name) {
    return '拖放：$name';
  }

  @override
  String get workbenchTimelineAddClip => '添加素材层';

  @override
  String get workbenchTimelineAddClipTitle => '添加素材层';

  @override
  String get workbenchTimelineAdd => '添加';

  @override
  String get workbenchTimelineAutoLayerAdd => '自动层级添加';

  @override
  String get workbenchTimelineRippleInsert => '波纹插入';

  @override
  String get workbenchTimelineLayer => '层级';

  @override
  String get workbenchTimelineStartMs => '起点(ms)';

  @override
  String get workbenchTimelineDurationMs => '时长(ms)';

  @override
  String get workbenchTimelineOpacity => '透明度(%)';

  @override
  String get workbenchTimelineClipAdded => '素材层已添加';

  @override
  String get workbenchTimelineSplitMidpoint => '中点切分';

  @override
  String get workbenchTimelineDuplicate => '复制素材层';

  @override
  String get workbenchTimelineRippleDuplicate => '波纹复制';

  @override
  String get workbenchTimelineRippleMove => '波纹移动';

  @override
  String get workbenchTimelineMoveTitle => '移动素材层';

  @override
  String get workbenchTimelineLaneTitle => '移动素材层轨道';

  @override
  String get workbenchTimelineRippleMoveTitle => '波纹移动素材层';

  @override
  String get workbenchTimelineLane => '轨道';

  @override
  String get workbenchTimelineSplitAt => '按播放头切分';

  @override
  String get workbenchTimelineSplitAtTitle => '按播放头切分素材层';

  @override
  String get workbenchTimelineSplitAtMs => '播放头(ms)';

  @override
  String get workbenchTimelineSplit => '切分';

  @override
  String get workbenchTimelineRippleTrimEnd => '波纹裁剪尾部';

  @override
  String get workbenchTimelineRippleTrimTitle => '波纹裁剪素材层尾部';

  @override
  String get workbenchTimelineEditClip => '编辑素材层属性';

  @override
  String get workbenchTimelineEditClipTitle => '编辑素材层属性';

  @override
  String get workbenchTimelineClipActions => '素材层操作';

  @override
  String get workbenchTimelineDelete => '删除';

  @override
  String get workbenchTimelineRippleDelete => '波纹删除';

  @override
  String workbenchTimelineSelectedClips(int count) {
    return '已选 $count 个素材层';
  }

  @override
  String get workbenchTimelineSplitSelected => '批量切分';

  @override
  String get workbenchTimelineDuplicateSelected => '批量复制';

  @override
  String get workbenchTimelineCopyToPlayheadSelected => '复制到播放头';

  @override
  String get workbenchTimelineAlignToPlayheadSelected => '对齐播放头';

  @override
  String get workbenchTimelineAlignEndToPlayheadSelected => '尾部对齐播放头';

  @override
  String get workbenchTimelineAlignCenterToPlayheadSelected => '中心对齐播放头';

  @override
  String get workbenchTimelineRippleDuplicateSelected => '批量波纹复制';

  @override
  String get workbenchTimelineMoveSelected => '批量移动';

  @override
  String get workbenchTimelineLaneSelected => '批量改轨';

  @override
  String get workbenchTimelineRippleMoveSelected => '批量波纹移动';

  @override
  String get workbenchTimelineTrimSelected => '批量裁剪';

  @override
  String get workbenchTimelineTrimToPlayheadSelected => '裁到播放头';

  @override
  String get workbenchTimelineTrimStartToPlayheadSelected => '裁开头到播放头';

  @override
  String get workbenchTimelineTrimTitle => '裁剪素材层尾部';

  @override
  String get workbenchTimelineRippleTrimSelected => '批量波纹裁剪';

  @override
  String get workbenchTimelineDeleteSelected => '批量删除';

  @override
  String get workbenchTimelineRippleDeleteSelected => '批量波纹删除';

  @override
  String get workbenchTimelineUnselected => '未选视频';

  @override
  String get workbenchTimelineNoAudio => '未绑定配音';

  @override
  String get workbenchReorderShot => '拖拽调整顺序';

  @override
  String get cornerScapeTitle => '配音';

  @override
  String get cornerScapeAutoMatch => 'AI 自动匹配';

  @override
  String get cornerScapeAutoMatching => '匹配中...';

  @override
  String get cornerScapeSelectAudio => '选择音频';

  @override
  String get cornerScapeNoAudio => '未绑定';

  @override
  String get cornerScapeNoAudioPool => '暂无音频素材，请先在「资产中心」上传音频';

  @override
  String get cornerScapeNoRoles => '暂无角色资产，请先在「资产中心」创建角色';

  @override
  String get cornerScapeSelectAtLeastOne => '请至少选择一个角色';

  @override
  String get cornerScapeBindSuccess => '绑定成功';

  @override
  String get cornerScapeUnbind => '解除绑定';

  @override
  String get promptStoryboardGenTitle => '分镜生成';

  @override
  String get promptStoryboardGenDescription => '将剧本拆解为分镜镜头列表的提示词';

  @override
  String get promptVideoPromptGenTitle => '运镜提示词生成';

  @override
  String get promptVideoPromptGenDescription => '将分镜画面转换为图生视频运镜提示词';

  @override
  String get promptAudioBindTitle => '配音匹配';

  @override
  String get promptAudioBindDescription => '按角色描述匹配最合适音色的提示词';

  @override
  String get promptEventAnalysisTitle => '事件分析';

  @override
  String get promptEventAnalysisDescription => '分析章节事件改编价值的提示词';

  @override
  String get stageEventExtractTitle => '事件提取';

  @override
  String get stageEventExtractDescription => '从章节内容提取结构化事件摘要';

  @override
  String get stageVideoPromptGenTitle => '运镜提示词生成';

  @override
  String get stageVideoPromptGenDescription => '将分镜描述转换为图生视频提示词';

  @override
  String get stageScriptGenTitle => '剧本生成';

  @override
  String get stageScriptGenDescription => '把小说改编为短剧剧本';

  @override
  String get stageAssetExtractTitle => '素材提取';

  @override
  String get stageAssetExtractDescription => '从剧本提取角色、场景和道具';

  @override
  String get stageStoryboardGenTitle => '分镜生成';

  @override
  String get stageStoryboardGenDescription => '按集拆解镜头与镜头提示词';

  @override
  String get stageAgentEmbeddingTitle => 'Agent 向量召回';

  @override
  String get stageAgentEmbeddingDescription => '为 Agent 记忆生成语义向量并进行召回';

  @override
  String get stageAgentVisionTitle => 'Agent 视觉理解';

  @override
  String get stageAgentVisionDescription => '分析参考图并提炼画风、角色和场景特征';

  @override
  String get stageAssetImageTitle => '素材图生成';

  @override
  String get stageAssetImageDescription => '生成角色、场景、道具资产图';

  @override
  String get stageShotImageTitle => '镜头图生成';

  @override
  String get stageShotImageDescription => '生成每个镜头的静帧画面';

  @override
  String get stageShotVideoTitle => '镜头视频生成';

  @override
  String get stageShotVideoDescription => '从镜头图生成短视频片段';

  @override
  String get stageTtsTitle => '配音生成';

  @override
  String get stageTtsDescription => '为镜头台词生成语音';

  @override
  String stageBindingUpdated(String title) {
    return '$title绑定已更新';
  }

  @override
  String get stageBindingMissing => '未绑定可用模型';

  @override
  String get agentChatTitle => '剧本 Agent';

  @override
  String get agentChatInputPlaceholder => '告诉我你想推进哪一步，或直接问\"现在进度如何\"';

  @override
  String get agentChatSend => '发送';

  @override
  String get agentChatThinking => '思考中...';

  @override
  String get agentChatAutoMode => '自动连跑';

  @override
  String get agentChatManualMode => '手动确认';

  @override
  String get agentChatClearMemory => '清空记忆';

  @override
  String get agentChatConfirmClearTitle => '清空记忆';

  @override
  String get agentChatConfirmClearBody => '确定清空全部对话记录吗？此操作无法撤销。';

  @override
  String get agentChatMemoryCleared => '记忆已清空';

  @override
  String get agentChatWelcome =>
      '你好，我是剧本 Agent。我可以帮你推进事件提取、资产提取、分镜生成、首帧图、视频生成、配音绑定和最终合成。直接告诉我你想做什么，或者问我\"现在进度如何\"。';

  @override
  String agentChatToolExecuted(String tool) {
    return '已执行：$tool';
  }

  @override
  String get agentChatModeHint => '手动模式每次只执行一步并等待你确认；自动模式会连续执行工具链（安全上限内）。';

  @override
  String get agentChatSkillsInfo => '内置能力';

  @override
  String get agentChatSkillsBody =>
      '我可以调用的能力包括已有流水线真实动作，也可以调用本地自定义技能。流水线动作会在「任务中心」留下可查看、可重试的任务记录；自定义技能目前支持 v1 JS return 模板。';

  @override
  String get agentTabChat => '对话';

  @override
  String get agentTabDeploy => '部署';

  @override
  String get agentTabSkills => '技能';

  @override
  String get agentTabMemory => '记忆';

  @override
  String get agentDeployExecutionMode => '执行模式';

  @override
  String get agentDeployModeSaved => '此设置会保存为项目内 Agent 默认执行方式';

  @override
  String get agentDeployStagesTitle => '阶段部署';

  @override
  String get agentDeployStagesHint => '为 Agent 各阶段指定文本模型与调用参数；启用后优先覆盖普通模型绑定。';

  @override
  String get agentDeployModel => '模型';

  @override
  String get agentDeployMaxTokens => '最大输出';

  @override
  String get agentDeployTemperature => '温度 x100';

  @override
  String get agentDeploySaved => 'Agent 部署已保存';

  @override
  String get agentDeployGroupScriptAgent => '剧本 Agent';

  @override
  String get agentDeployGroupProductionAgent => '制作 Agent';

  @override
  String get agentDeployGroupPipeline => '流水线';

  @override
  String get agentSkillsBuiltinTitle => '内置技能';

  @override
  String get agentSkillsEditableHint =>
      '技能定义保存在本地 o_skillList，可编辑说明与启停状态；工具名保持固定，确保任务中心可追踪、可重试。';

  @override
  String get agentSkillAttributionFilter => '技能归属';

  @override
  String get agentSkillAttributionAll => '全部技能';

  @override
  String get agentSkillAttributionScriptDecision => '剧本决策';

  @override
  String get agentSkillAttributionScriptExecution => '剧本执行';

  @override
  String get agentSkillAttributionScriptSupervision => '剧本监督';

  @override
  String get agentSkillAttributionProductionDecision => '制作决策';

  @override
  String get agentSkillAttributionProductionExecution => '制作执行';

  @override
  String get agentSkillAttributionProductionSupervision => '制作监督';

  @override
  String get agentSkillEditTitle => '编辑技能';

  @override
  String get agentSkillDescription => '技能说明';

  @override
  String get agentSkillEnabled => '启用技能';

  @override
  String get agentSkillEnabledTag => '已启用';

  @override
  String get agentSkillDisabledTag => '已停用';

  @override
  String get agentCustomSkillAdd => '新增自定义技能';

  @override
  String get agentCustomSkillCreateTitle => '新增自定义技能';

  @override
  String get agentCustomSkillEditTitle => '编辑自定义技能';

  @override
  String get agentCustomSkillId => '工具 ID';

  @override
  String get agentCustomSkillName => '技能名称';

  @override
  String get agentCustomSkillSchema => '参数 Schema JSON';

  @override
  String get agentCustomSkillScript => '脚本';

  @override
  String get agentCustomSkillScriptHint =>
      'v1 支持 return 字符串、args.xxx、projectId、JSON.stringify(args) 与模板字符串。';

  @override
  String get agentCustomSkillInvalidSchema => 'Schema 必须是 JSON 对象';

  @override
  String get agentCustomSkillSaved => '自定义技能已保存';

  @override
  String get agentCustomSkillTag => '自定义';

  @override
  String agentMemoryCount(int count) {
    return '记忆条目 $count';
  }

  @override
  String get agentMemoryEmpty => '暂无记忆。发送消息后会在这里显示可检查的上下文记录。';

  @override
  String agentLongTermMemoryCount(int count) {
    return '长期记忆 $count';
  }

  @override
  String get agentLongTermMemoryEmpty => '暂无长期记忆。可以把角色设定、禁忌写法、世界观规则保存到这里。';

  @override
  String agentMemorySummaryCount(int count) {
    return '历史摘要 $count';
  }

  @override
  String get agentMemorySummaryEmpty => '暂无历史摘要。对话达到摘要触发消息数后会自动生成。';

  @override
  String agentMemoryRelatedMessagesCount(int count) {
    return '关联原文 $count';
  }

  @override
  String get agentMemoryAdd => '新增记忆';

  @override
  String get agentMemoryCreateTitle => '新增长期记忆';

  @override
  String get agentMemoryEditTitle => '编辑长期记忆';

  @override
  String get agentMemoryName => '记忆名称';

  @override
  String get agentMemoryContent => '记忆内容';

  @override
  String get agentMemorySaved => '长期记忆已保存';

  @override
  String get agentMemoryUpdated => '长期记忆已更新';

  @override
  String get agentMemoryDeleted => '长期记忆已删除';

  @override
  String get agentMemorySettingsTitle => 'Agent 记忆设置';

  @override
  String get agentMemorySettingsHelp =>
      '控制短期上下文、摘要压缩、长期记忆搜索和 deepRetrieve 深度召回。';

  @override
  String get agentMemoryMessagesPerSummary => '摘要触发消息数';

  @override
  String get agentMemorySummaryMaxLength => '摘要最大字数';

  @override
  String get agentMemoryShortTermLimit => '短期上下文条数';

  @override
  String get agentMemorySummaryLimit => '历史摘要条数';

  @override
  String get agentMemoryDeepRetrieveSummaryLimit => '深度召回摘要数';

  @override
  String get agentMemoryMinScore => '最低召回分数';

  @override
  String get agentMemoryModelOnnxFile => '本地向量模型文件';

  @override
  String get agentMemoryModelDtype => '向量模型 dtype';

  @override
  String get agentMemoryRerankEnabled => '模型重排 RAG';

  @override
  String get agentMemoryRerankHelp => '开启后会让模型从本地候选记忆中再筛选真正相关的原文。';

  @override
  String get agentMemorySettingsSaved => 'Agent 记忆设置已保存';

  @override
  String get agentMemorySettingsInvalid => '请输入有效的整数配置';

  @override
  String get agentMemoryClearSummary => '清理摘要';

  @override
  String get agentMemoryClearNote => '清空长期记忆';

  @override
  String get agentRagLimitTitle => '搜索记忆条数';

  @override
  String get agentRagLimitHelp =>
      'Agent 每次回复前从长期记忆中检索并注入的最大条数，对齐 ToonFlow 的 ragLimit。';

  @override
  String get agentRagLimitSaved => '搜索记忆条数已保存';

  @override
  String get agentRagLimitInvalid => '请输入 0-50 之间的整数';

  @override
  String get agentSupervisionTitle => '监督模式';

  @override
  String get agentSupervisionHelp =>
      '开启后，决策 Agent 的工具调用会先交给对应监督 Agent 复核；监督拒绝时不会提交任务。';

  @override
  String get agentSupervisionOn => '开启';

  @override
  String get agentSupervisionOff => '关闭';

  @override
  String get agentSupervisionSaved => '监督模式已保存';

  @override
  String get cornerScapeSearchHint => '搜索角色名称';

  @override
  String get cornerScapeFilterAll => '全部';

  @override
  String get cornerScapeFilterBound => '已绑定';

  @override
  String get cornerScapeFilterUnbound => '未绑定';

  @override
  String get cornerScapeSelectAllUnbound => '全选未绑定';

  @override
  String cornerScapeBoundSummary(int bound, int total) {
    return '已绑定 $bound/$total';
  }

  @override
  String get cornerScapeNoMatch => '没有符合筛选条件的角色';

  @override
  String get storyboardPreviewAll => '预览全部';

  @override
  String get storyboardPreviewEmpty => '暂无分镜可预览';

  @override
  String get storyboardPreviewImageMissing => '图片加载失败';

  @override
  String storyboardPreviewCounter(String shot, String current, String total) {
    return '$shot（$current/$total）';
  }

  @override
  String storyboardPreviewShotPlaceholder(String shot) {
    return '$shot 尚未生成首帧图';
  }

  @override
  String get storyboardExportAll => '导出全部';

  @override
  String get storyboardExportNoImages => '还没有可导出的首帧图';

  @override
  String storyboardExportSuccess(String count) {
    return '已导出 $count 张首帧图';
  }

  @override
  String storyboardExportFailed(String reason) {
    return '导出失败：$reason';
  }

  @override
  String get scriptPlanEmpty => '还没有剧本规划，点此撰写整体思路、节奏与要点。';

  @override
  String get scriptPlanWrite => '撰写规划';

  @override
  String get scriptPlanEditTitle => '编辑剧本规划';

  @override
  String get scriptPlanEditHint => '用 Markdown 记录本项目的整体规划：主线、人物弧光、分集节奏、风格基调……';

  @override
  String get scriptPlanSaved => '剧本规划已保存';

  @override
  String get canvasChatTitle => '制作 Agent';

  @override
  String get canvasChatWelcome =>
      '你好，我是制作 Agent。我可以帮你推进导演计划、分镜面板、首帧图、视频生成、配音绑定和最终合成。直接告诉我你想处理哪一集或哪一步。';

  @override
  String get canvasChatOpen => 'Agent 对话';

  @override
  String get canvasChatClose => '关闭';

  @override
  String get imageEditorModel => '模型';

  @override
  String get imageEditorRatio => '比例';

  @override
  String get imageEditorQuality => '质量';

  @override
  String get imageEditorSelectModel => '请先选择模型';

  @override
  String get imageEditorSelectQuality => '请选择画质';

  @override
  String get imageEditorSelectRatio => '请选择比例';

  @override
  String get imageEditorNoImageModel => '暂无可用图片模型';

  @override
  String get novelGenerateSelectedEvents => '生成事件';

  @override
  String scriptBatchAddMsgOverLimit(String limit) {
    return '存在超出单集字数上限（$limit）的分集，请取消勾选或缩短内容';
  }

  @override
  String get artStyleLibraryTitle => '画风库';

  @override
  String get artStyleManage => '管理画风库';

  @override
  String get artStyleAddTitle => '新增画风';

  @override
  String get artStyleEditTitle => '编辑画风';

  @override
  String get artStyleName => '画风名称';

  @override
  String get artStyleNamePh => '如：2D 动漫、照片写实、3D 国创';

  @override
  String get artStylePrompt => '画风提示词';

  @override
  String get artStylePromptPh => '如：(画风：2D动漫风格,2d animation style)';

  @override
  String get artStyleCover => '封面图';

  @override
  String get artStyleUploadCover => '上传封面';

  @override
  String get artStyleNameRequired => '请填写画风名称';

  @override
  String get artStyleAddSuccess => '画风添加成功';

  @override
  String get artStyleEditSuccess => '画风编辑成功';

  @override
  String get artStyleDeleted => '画风已删除';

  @override
  String get artStyleDeleteHeader => '删除画风';

  @override
  String artStyleDeleteBody(String name) {
    return '确定删除画风「$name」吗？';
  }

  @override
  String get artStyleEmpty => '还没有画风，点击上方新增。';

  @override
  String get artStyleClose => '关闭';

  @override
  String get clipUpload => '上传素材';

  @override
  String get clipUploadTitle => '上传素材文件';

  @override
  String get clipPickFile => '选择文件';

  @override
  String get clipNoFile => '尚未选择文件';

  @override
  String get clipName => '素材名称';

  @override
  String get clipNamePh => '留空则使用文件名';

  @override
  String get clipUploadSuccess => '素材上传成功';

  @override
  String get clipUploadFailed => '素材上传失败';

  @override
  String get assetBatchModel => '模型';

  @override
  String get assetBatchResolution => '分辨率';

  @override
  String get assetBatchConcurrency => '并发数';

  @override
  String get assetBatchConcurrencyPh => '1-8';

  @override
  String get assetBatchOtherPrompt => '补充提示词';

  @override
  String get assetBatchOtherPromptPh => '追加到润色系统提示词（可选）';

  @override
  String get assetBatchPickModel => '使用阶段默认';

  @override
  String get manualImportFile => '导入文件';

  @override
  String get manualImportSuccess => '文件已导入到当前标签';

  @override
  String get manualImportFailed => '文件导入失败';

  @override
  String get storyboardTableEmpty => '还没有分镜表，点此撰写镜头拆解、时长与画面要点。';

  @override
  String get storyboardTableWrite => '撰写分镜表';

  @override
  String get storyboardTableEditTitle => '编辑分镜表';

  @override
  String get storyboardTableEditHint => '用 Markdown 记录本集的分镜拆解：镜头序号、画面、运镜、时长……';

  @override
  String get storyboardTableSaved => '分镜表已保存';

  @override
  String get scriptNodeEditTitle => '编辑剧本';

  @override
  String get scriptNodeName => '名称';

  @override
  String get scriptNodeNamePlaceholder => '请输入剧本名称';

  @override
  String get scriptNodeContent => '正文';

  @override
  String get scriptNodeContentPlaceholder => '请输入剧本正文';

  @override
  String get scriptNodeNameRequired => '请输入剧本名称';

  @override
  String get scriptNodeSaved => '剧本已保存';

  @override
  String get productionStoryboardInsertBefore => '在前面插入分镜';

  @override
  String get imageEditorPickFromAssets => '从素材库选择';

  @override
  String get imageEditorPickFromStoryboard => '从分镜选择';

  @override
  String get imageEditorPickImageTitle => '选择参考图';

  @override
  String get imageEditorPickImageSource => '选择图片来源';

  @override
  String get imageEditorPickLocalFile => '本地文件';

  @override
  String get imageEditorNoAssetsImages => '素材库暂无已生成图片';

  @override
  String get imageEditorNoStoryboardImages => '分镜暂无已生成首帧图';

  @override
  String get imageEditorRemoveEdge => '删除该连线';

  @override
  String get imageEditorEdgeRemoved => '已删除连线';

  @override
  String get workbenchPlayVideo => '播放';

  @override
  String get workbenchVideoLoadFailed => '视频加载失败';

  @override
  String get workbenchDeleteCandidate => '删除候选';

  @override
  String get workbenchDeleteCandidateConfirm => '确定删除该候选视频？';

  @override
  String get workbenchSelectAsMain => '选为正片';

  @override
  String get workbenchDurationSection => '本镜时长';

  @override
  String get workbenchDurationUnset => '未设置';

  @override
  String workbenchDurationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get workbenchEditDurationTitle => '编辑本镜时长';

  @override
  String get workbenchDurationFieldLabel => '时长（秒）';

  @override
  String get workbenchEditPromptTitle => '编辑运镜提示词';

  @override
  String get workbenchPromptFieldHint => '描述这一镜的运镜与动作';

  @override
  String get workbenchPromptEmpty => '暂无运镜提示词，点击生成或编辑';

  @override
  String get workbenchTransitionNone => '无转场';

  @override
  String get workbenchTransitionFade => '淡入淡出';

  @override
  String get workbenchTransitionDissolve => '叠化';

  @override
  String get workbenchTransitionWhipPan => '甩镜';

  @override
  String get workbenchFilterNone => '无滤镜';

  @override
  String get workbenchFilterCinematic => '电影感';

  @override
  String get workbenchFilterWarm => '暖色';

  @override
  String get workbenchFilterCool => '冷色';

  @override
  String get workbenchFilterVintage => '复古';

  @override
  String get cornerScapeAudition => '试听';

  @override
  String get cornerScapeStopAudition => '停止';

  @override
  String get cornerScapeAudioMissing => '音频文件缺失';

  @override
  String get cornerScapeAuditionFailed => '音频播放失败';

  @override
  String get settingsOtherSection => '其他设置';

  @override
  String get settingsOtherTitle => '其他设置';

  @override
  String get settingsOtherChapterReg => '章节切分正则';

  @override
  String get settingsOtherChapterRegHint => '留空则使用内置默认章节正则';

  @override
  String get settingsOtherChapterRegRestore => '恢复默认';

  @override
  String get settingsOtherEpisodeLength => '单集字数上限';

  @override
  String get settingsOtherBatchSize => '批量生成数量';

  @override
  String get settingsOtherSaved => '其他设置已保存';

  @override
  String get settingsOtherInvalidNumber => '请输入大于 0 的整数';

  @override
  String get settingsStorageOpenFolder => '打开数据目录';

  @override
  String settingsStorageOpenFolderFailed(String reason) {
    return '无法打开数据目录：$reason';
  }

  @override
  String get settingsStorageDbInfo => '数据库信息';

  @override
  String get settingsStorageDbInfoTitle => '数据库信息';

  @override
  String get settingsStorageTableColumn => '数据表';

  @override
  String get settingsStorageRowsColumn => '行数';

  @override
  String get settingsStorageClear => '清空数据';

  @override
  String get settingsStorageClearConfirmTitle => '清空所有数据';

  @override
  String get settingsStorageClearConfirmBody =>
      '此操作会删除全部项目、章节、剧本、资产、任务与媒体文件，且不可恢复。确定继续吗？';

  @override
  String get settingsStorageClearDone => '数据已清空';

  @override
  String get settingsAboutSection => '关于';

  @override
  String get settingsAboutTitle => '关于 DramaFlow';

  @override
  String get settingsAboutAppName => '应用名称';

  @override
  String get settingsAboutVersion => '版本';

  @override
  String get settingsAboutEngine => '引擎版本';

  @override
  String get settingsAboutDescription =>
      'DramaFlow 是本机运行的 AI 短剧创作工作台，数据与媒体全部保存在本机。';

  @override
  String get settingsProviderTestKind => '模态';

  @override
  String get settingsProviderTestNoModel => '请先启用至少一个可测试的模型';

  @override
  String get taskFilterClass => '任务类型';

  @override
  String get taskFilterState => '状态';

  @override
  String get taskFilterAll => '全部';

  @override
  String get taskDetailTitle => '任务详情';

  @override
  String get taskDetailClass => '任务类型';

  @override
  String get taskDetailState => '状态';

  @override
  String get taskDetailDescribe => '描述';

  @override
  String get taskDetailModel => '模型';

  @override
  String get taskDetailRelated => '关联对象';

  @override
  String get taskDetailReason => '失败原因';

  @override
  String get taskDetailTiming => '开始时间';

  @override
  String get taskDetailNone => '无';

  @override
  String get taskStatePending => '等待中';

  @override
  String get taskStateProcessing => '进行中';

  @override
  String get taskStateSuccess => '已完成';

  @override
  String get taskStateFailed => '失败';

  @override
  String get taskStateCanceled => '已取消';

  @override
  String get commonClear => '清除';

  @override
  String get commonClose => '关闭';

  @override
  String get commonRetry => '重试';

  @override
  String get commonTest => '测试';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonEnabled => '启用';

  @override
  String get commonActions => '操作';

  @override
  String get commonName => '名称';

  @override
  String get commonType => '类型';

  @override
  String get commonModel => '模型';

  @override
  String get commonUnset => '未设置';

  @override
  String get statusQueued => '排队中';

  @override
  String get statusPending => '等待中';

  @override
  String get statusRunning => '生成中';

  @override
  String get statusDone => '已完成';

  @override
  String get statusFailed => '失败';

  @override
  String get statusCanceled => '已取消';

  @override
  String get statusDraft => '待生成';

  @override
  String get statusNotGenerated => '未生成';

  @override
  String get statusSuccessShort => '成功';

  @override
  String get statusPendingShort => '待处理';

  @override
  String dataTableTotal(int total) {
    return '共 $total 条';
  }

  @override
  String get dataTablePrevPage => '上一页';

  @override
  String get dataTableNextPage => '下一页';

  @override
  String get imageVersionsTitle => '图片版本';

  @override
  String get imageVersionsEmpty => '暂无图片版本';

  @override
  String imageVersionLabel(int index) {
    return '版本 $index';
  }

  @override
  String get repaintImageTitle => '重绘图片';

  @override
  String get repaintImageHint => '如：把衣服改成红色';

  @override
  String get repaintInstructionRequired => '请输入修改意见';

  @override
  String get repaintAction => '重绘';

  @override
  String get inpaintAction => '局部重绘';

  @override
  String get inpaintTitle => '局部重绘';

  @override
  String get inpaintHint => '涂抹要重绘的区域，并描述修改意见';

  @override
  String get inpaintMaskRequired => '请先涂抹要重绘的区域';

  @override
  String get inpaintMaskCreateFailed => '生成局部重绘蒙版失败';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearanceSection => '外观';

  @override
  String get settingsProvidersSection => '供应商';

  @override
  String get settingsBindingsSection => '模型绑定';

  @override
  String get settingsPromptsSection => '提示词';

  @override
  String get settingsStorageSection => '存储与引擎';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeUpdated => '外观已更新';

  @override
  String get localeChinese => '中文';

  @override
  String get localeJapanese => '日本語';

  @override
  String get modelKindText => '文本';

  @override
  String get modelKindImage => '图片';

  @override
  String get modelKindVideo => '视频';

  @override
  String get modelKindTts => '配音';

  @override
  String get modelKindEmbedding => '向量';

  @override
  String get providerProtocolVolcengine => '火山引擎';

  @override
  String get providerProtocolOpenAiCompatible => 'OpenAI兼容';

  @override
  String get settingsAddProvider => '添加供应商';

  @override
  String get settingsProviderEmptyTitle => '还没有供应商';

  @override
  String get settingsProviderEmptySubtitle =>
      '添加 OpenAI 兼容或火山引擎供应商后，再配置模型和环节绑定';

  @override
  String get settingsProviderAdded => '供应商已添加';

  @override
  String get settingsProviderUpdated => '供应商已更新';

  @override
  String get settingsProviderConfigMissing => '配置数据缺少供应商列表';

  @override
  String get settingsProviderMissing => '供应商不存在';

  @override
  String get settingsProviderEnabled => '供应商已启用';

  @override
  String get settingsProviderDisabled => '供应商已停用';

  @override
  String settingsProviderTestSuccess(int elapsedMs) {
    return '连通成功：$elapsedMs ms';
  }

  @override
  String settingsProviderTestTitle(String name) {
    return '测试连通 · $name';
  }

  @override
  String get settingsDeleteProviderTitle => '删除供应商';

  @override
  String settingsDeleteProviderMessage(String name) {
    return '确定删除“$name”吗？如果供应商已被环节绑定，引擎会拒绝删除。';
  }

  @override
  String get settingsProviderDeleted => '供应商已删除';

  @override
  String get settingsModelCount => '模型数';

  @override
  String get settingsManageModels => '模型管理';

  @override
  String get settingsTestConnection => '测试连通';

  @override
  String get settingsEditProvider => '编辑供应商';

  @override
  String get settingsProviderName => '名称';

  @override
  String get settingsProviderNameHint => '例如：azt';

  @override
  String get settingsKeepEmptyUnchanged => '留空不修改';

  @override
  String get settingsExportConfig => '导出配置';

  @override
  String get settingsImportConfig => '导入配置';

  @override
  String get settingsConfigPlaintextWarning => '配置 JSON 包含明文密钥，请妥善保管。';

  @override
  String get settingsEmbeddedEngineNote => '引擎内嵌运行，数据与媒体全部保存在本机，无需任何后台服务';

  @override
  String get settingsEngineStatus => '引擎状态';

  @override
  String settingsExportPanelFailed(String reason) {
    return '无法打开保存面板：$reason';
  }

  @override
  String settingsExportFailed(String reason) {
    return '导出配置失败：$reason';
  }

  @override
  String get settingsConfigExported => '配置已导出';

  @override
  String settingsOpenFileFailed(String reason) {
    return '无法打开文件选择器：$reason';
  }

  @override
  String get settingsImportConfigTitle => '导入配置';

  @override
  String get settingsImportConfigMessage => '导入会覆盖同名供应商、模型、绑定和提示词。确定继续吗？';

  @override
  String get settingsConfigInvalidFormat => '配置文件格式无效';

  @override
  String get settingsConfigInvalidJson => '配置文件不是有效 JSON';

  @override
  String settingsImportFailed(String reason) {
    return '导入配置失败：$reason';
  }

  @override
  String get settingsConfigImported => '配置已导入';

  @override
  String get settingsEngineChecking => '正在检查引擎…';

  @override
  String settingsEngineOk(String version) {
    return '引擎正常 · v$version';
  }

  @override
  String get settingsEngineUnknown => '未知';

  @override
  String get settingsProviderColumnProtocol => '协议';

  @override
  String get settingsProviderColumnBaseUrl => 'Base URL';

  @override
  String settingsModelManagementTitle(String name) {
    return '模型管理 · $name';
  }

  @override
  String get settingsAddModel => '添加模型';

  @override
  String get settingsSaveModels => '保存';

  @override
  String get settingsModelsEmptyTitle => '还没有模型';

  @override
  String get settingsModelsEmptySubtitle => '添加至少一个文本、图片、视频或配音模型';

  @override
  String get settingsModelIdRequired => '模型 ID 不能为空';

  @override
  String get settingsModelsSaved => '模型已保存';

  @override
  String get settingsDeleteModel => '删除模型';

  @override
  String get settingsBindingModel => '绑定模型';

  @override
  String get settingsSelectEnabledModel => '请选择启用模型';

  @override
  String get settingsSelectModel => '选择模型';

  @override
  String get settingsPromptContent => '提示词内容';

  @override
  String get taskCenterTitle => '任务中心';

  @override
  String get taskActiveTitle => '进行中';

  @override
  String get taskActiveEmpty => '当前没有进行中的任务';

  @override
  String get taskHistoryTitle => '历史';

  @override
  String get taskNoProjects => '暂无项目';

  @override
  String get taskHistoryEmpty => '该项目暂无历史任务';

  @override
  String get taskFilterEmpty => '没有符合筛选条件的任务';

  @override
  String get taskEmpty => '暂无任务';

  @override
  String taskProjectLabel(int id) {
    return '项目 #$id';
  }

  @override
  String get taskCancelTooltip => '取消任务';

  @override
  String get taskCanceledMessage => '任务已取消';

  @override
  String get taskRetryQueued => '已重新排队';

  @override
  String get taskClassEventGeneration => '事件生成';

  @override
  String get taskClassScriptGeneration => '剧本生成';

  @override
  String get taskClassAssetExtraction => '素材提取';

  @override
  String get taskClassAssetPromptPolish => '素材提示词润色';

  @override
  String get taskClassAssetImageGeneration => '素材生图';

  @override
  String get taskClassStoryboardGenerate => '分镜生成';

  @override
  String get taskClassStoryboardImageGeneration => '首帧图生成';

  @override
  String get taskClassVideoGeneration => '视频生成';

  @override
  String get taskClassAudioBind => '配音匹配';

  @override
  String get taskClassGeneric => '任务';

  @override
  String get webPreviewBuildableTitle => 'Web 预览入口已可构建。';

  @override
  String get webPreviewMessage =>
      '完整本地引擎仍在移植中：浏览器版还需要 Web 数据库、浏览器文件存储、WebCodecs/Mediabunny 合成器，以及媒体预览的 Web 适配。当前 macOS、iOS、Android 客户端仍是完整功能主线。';

  @override
  String get webPreviewMacClient => 'macOS 完整客户端';

  @override
  String get webPreviewIosClient => 'iOS 完整客户端';

  @override
  String get webPreviewAndroidClient => 'Android APK 可构建';

  @override
  String get webPreviewEnginePending => 'Web 引擎待移植';

  @override
  String get policyConfirmMoneyTitle => '花费确认';

  @override
  String policyConfirmMoneyBody(String description, int units) {
    return '$description：本次将调用 $units 次付费生成，确认继续？';
  }

  @override
  String get policyConfirmDestructiveTitle => '危险操作确认';

  @override
  String policyConfirmDestructiveBody(String description) {
    return '$description：该操作不可撤销，确认继续？';
  }

  @override
  String get settingsPolicyConfirmMoney => '花钱操作需确认';

  @override
  String get settingsPolicyConfirmDestructive => '破坏性操作需确认（含 auto 模式）';
}
