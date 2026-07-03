import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh')
  ];

  /// No description provided for @menuMyProject.
  ///
  /// In zh, this message translates to:
  /// **'我的项目'**
  String get menuMyProject;

  /// No description provided for @menuTaskCenter.
  ///
  /// In zh, this message translates to:
  /// **'任务中心'**
  String get menuTaskCenter;

  /// No description provided for @menuNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说原文'**
  String get menuNovel;

  /// No description provided for @menuScriptAgent.
  ///
  /// In zh, this message translates to:
  /// **'剧本Agent'**
  String get menuScriptAgent;

  /// No description provided for @menuScriptManage.
  ///
  /// In zh, this message translates to:
  /// **'剧本管理'**
  String get menuScriptManage;

  /// No description provided for @menuCornerScape.
  ///
  /// In zh, this message translates to:
  /// **'塑角造景'**
  String get menuCornerScape;

  /// No description provided for @menuProduction.
  ///
  /// In zh, this message translates to:
  /// **'视频生产'**
  String get menuProduction;

  /// No description provided for @menuAssetCenter.
  ///
  /// In zh, this message translates to:
  /// **'资产中心'**
  String get menuAssetCenter;

  /// No description provided for @menuSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get menuSettings;

  /// No description provided for @menuJumpGithub.
  ///
  /// In zh, this message translates to:
  /// **'跳转Github'**
  String get menuJumpGithub;

  /// No description provided for @menuFeedbackQuestions.
  ///
  /// In zh, this message translates to:
  /// **'反馈问题'**
  String get menuFeedbackQuestions;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonConfirm;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get commonSearch;

  /// No description provided for @commonNextStep.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get commonNextStep;

  /// No description provided for @commonPrevStep.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get commonPrevStep;

  /// No description provided for @projectListTitle.
  ///
  /// In zh, this message translates to:
  /// **'项目'**
  String get projectListTitle;

  /// No description provided for @projectListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'临时项目列表，T9 将全量重写'**
  String get projectListSubtitle;

  /// No description provided for @projectNew.
  ///
  /// In zh, this message translates to:
  /// **'新建项目'**
  String get projectNew;

  /// No description provided for @projectName.
  ///
  /// In zh, this message translates to:
  /// **'项目名称'**
  String get projectName;

  /// No description provided for @projectCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get projectCreate;

  /// No description provided for @projectCreated.
  ///
  /// In zh, this message translates to:
  /// **'项目已创建'**
  String get projectCreated;

  /// No description provided for @projectEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无项目'**
  String get projectEmpty;

  /// No description provided for @projectUntitled.
  ///
  /// In zh, this message translates to:
  /// **'未命名项目'**
  String get projectUntitled;

  /// No description provided for @errProviderMissing.
  ///
  /// In zh, this message translates to:
  /// **'供应商缺失或已停用'**
  String get errProviderMissing;

  /// No description provided for @errModelMissing.
  ///
  /// In zh, this message translates to:
  /// **'模型缺失或未绑定'**
  String get errModelMissing;

  /// No description provided for @errPromptMissing.
  ///
  /// In zh, this message translates to:
  /// **'提示词不存在'**
  String get errPromptMissing;

  /// No description provided for @errConfigVersion.
  ///
  /// In zh, this message translates to:
  /// **'配置文件版本不兼容'**
  String get errConfigVersion;

  /// No description provided for @errNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络请求失败'**
  String get errNetwork;

  /// No description provided for @errLlmFormat.
  ///
  /// In zh, this message translates to:
  /// **'模型输出格式无效'**
  String get errLlmFormat;

  /// No description provided for @errCanceled.
  ///
  /// In zh, this message translates to:
  /// **'任务已取消'**
  String get errCanceled;

  /// No description provided for @errAppRestart.
  ///
  /// In zh, this message translates to:
  /// **'应用重启，任务中断'**
  String get errAppRestart;

  /// No description provided for @errFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件过大'**
  String get errFileTooLarge;

  /// No description provided for @errFileType.
  ///
  /// In zh, this message translates to:
  /// **'文件类型不支持'**
  String get errFileType;

  /// No description provided for @errRegexInvalid.
  ///
  /// In zh, this message translates to:
  /// **'正则表达式无效'**
  String get errRegexInvalid;

  /// No description provided for @errNoChapters.
  ///
  /// In zh, this message translates to:
  /// **'未找到章节'**
  String get errNoChapters;

  /// No description provided for @promptPanelTitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get promptPanelTitle;

  /// No description provided for @promptEventExtractionTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件提取'**
  String get promptEventExtractionTitle;

  /// No description provided for @promptEventExtractionDescription.
  ///
  /// In zh, this message translates to:
  /// **'小说章节结构化事件提取提示词'**
  String get promptEventExtractionDescription;

  /// No description provided for @promptScriptAssetExtractionTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本资产提取'**
  String get promptScriptAssetExtractionTitle;

  /// No description provided for @promptScriptAssetExtractionDescription.
  ///
  /// In zh, this message translates to:
  /// **'从剧本提取角色、场景、道具的提示词'**
  String get promptScriptAssetExtractionDescription;

  /// No description provided for @promptImageSizeDirectiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'图片尺寸指令'**
  String get promptImageSizeDirectiveTitle;

  /// No description provided for @promptImageSizeDirectiveDescription.
  ///
  /// In zh, this message translates to:
  /// **'注入图片生成请求的尺寸约束'**
  String get promptImageSizeDirectiveDescription;

  /// No description provided for @promptUnset.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get promptUnset;

  /// No description provided for @promptOverridden.
  ///
  /// In zh, this message translates to:
  /// **'已修改'**
  String get promptOverridden;

  /// No description provided for @promptCharacterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字符'**
  String promptCharacterCount(int count);

  /// No description provided for @promptEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑提示词 · {title}'**
  String promptEditTitle(Object title);

  /// No description provided for @promptSaved.
  ///
  /// In zh, this message translates to:
  /// **'提示词已保存'**
  String get promptSaved;

  /// No description provided for @promptRestoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get promptRestoreDefault;

  /// No description provided for @promptRestoreDefaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get promptRestoreDefaultTitle;

  /// No description provided for @promptRestoreDefaultMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定将“{title}”恢复为内置默认内容吗？'**
  String promptRestoreDefaultMessage(Object title);

  /// No description provided for @promptRestoreDefaultConfirm.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get promptRestoreDefaultConfirm;

  /// No description provided for @promptRestored.
  ///
  /// In zh, this message translates to:
  /// **'提示词已恢复默认'**
  String get promptRestored;

  /// No description provided for @errTaskUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'不支持的任务类型'**
  String get errTaskUnsupported;

  /// No description provided for @shellSelectProject.
  ///
  /// In zh, this message translates to:
  /// **'请选择项目'**
  String get shellSelectProject;

  /// No description provided for @shellComingSoon.
  ///
  /// In zh, this message translates to:
  /// **'本区域随 {batch} 批次交付'**
  String shellComingSoon(String batch);

  /// No description provided for @shellComingSoonBadge.
  ///
  /// In zh, this message translates to:
  /// **'{batch}'**
  String shellComingSoonBadge(String batch);

  /// No description provided for @projectTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的项目'**
  String get projectTitle;

  /// No description provided for @projectSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理您的所有短剧项目'**
  String get projectSubtitle;

  /// No description provided for @projectNewProject.
  ///
  /// In zh, this message translates to:
  /// **'新建项目'**
  String get projectNewProject;

  /// No description provided for @projectDialogEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑项目'**
  String get projectDialogEditTitle;

  /// No description provided for @projectDialogAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建项目'**
  String get projectDialogAddTitle;

  /// No description provided for @projectDialogSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get projectDialogSave;

  /// No description provided for @projectDialogOk.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get projectDialogOk;

  /// No description provided for @projectDialogCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get projectDialogCancel;

  /// No description provided for @projectDialogProjectType.
  ///
  /// In zh, this message translates to:
  /// **'项目类型'**
  String get projectDialogProjectType;

  /// No description provided for @projectDialogSelectType.
  ///
  /// In zh, this message translates to:
  /// **'选择项目类型'**
  String get projectDialogSelectType;

  /// No description provided for @projectDialogBasedOnNovel.
  ///
  /// In zh, this message translates to:
  /// **'基于小说原文'**
  String get projectDialogBasedOnNovel;

  /// No description provided for @projectDialogProjectName.
  ///
  /// In zh, this message translates to:
  /// **'项目名称'**
  String get projectDialogProjectName;

  /// No description provided for @projectDialogProjectNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入项目名称'**
  String get projectDialogProjectNamePh;

  /// No description provided for @projectDialogNovelType.
  ///
  /// In zh, this message translates to:
  /// **'小说类型'**
  String get projectDialogNovelType;

  /// No description provided for @projectDialogNovelTypePh.
  ///
  /// In zh, this message translates to:
  /// **'例如:玄幻、科幻、言情'**
  String get projectDialogNovelTypePh;

  /// No description provided for @projectDialogArtStyle.
  ///
  /// In zh, this message translates to:
  /// **'画风'**
  String get projectDialogArtStyle;

  /// No description provided for @projectDialogSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选：'**
  String get projectDialogSelected;

  /// No description provided for @projectDialogSelectArtStyle.
  ///
  /// In zh, this message translates to:
  /// **'请选择画风'**
  String get projectDialogSelectArtStyle;

  /// No description provided for @projectDialogNewArtStyle.
  ///
  /// In zh, this message translates to:
  /// **'新建画风'**
  String get projectDialogNewArtStyle;

  /// No description provided for @projectDialogLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get projectDialogLoading;

  /// No description provided for @projectDialogVideoRatio.
  ///
  /// In zh, this message translates to:
  /// **'影片比例'**
  String get projectDialogVideoRatio;

  /// No description provided for @projectDialogNovelIntro.
  ///
  /// In zh, this message translates to:
  /// **'小说简介'**
  String get projectDialogNovelIntro;

  /// No description provided for @projectDialogNovelIntroPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入小说简介'**
  String get projectDialogNovelIntroPh;

  /// No description provided for @projectDialogEditArtStyleTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑画风'**
  String get projectDialogEditArtStyleTitle;

  /// No description provided for @projectDialogNewArtStyleTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建画风'**
  String get projectDialogNewArtStyleTitle;

  /// No description provided for @projectDialogArtStyleName.
  ///
  /// In zh, this message translates to:
  /// **'画风名称'**
  String get projectDialogArtStyleName;

  /// No description provided for @projectDialogArtStyleNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入画风名称'**
  String get projectDialogArtStyleNamePh;

  /// No description provided for @projectDialogArtStyleImage.
  ///
  /// In zh, this message translates to:
  /// **'画风图片'**
  String get projectDialogArtStyleImage;

  /// No description provided for @projectDialogRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get projectDialogRemove;

  /// No description provided for @projectDialogUploadCover.
  ///
  /// In zh, this message translates to:
  /// **'上传封面'**
  String get projectDialogUploadCover;

  /// No description provided for @projectDialogArtStylePrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get projectDialogArtStylePrompt;

  /// No description provided for @projectDialogAiExtract.
  ///
  /// In zh, this message translates to:
  /// **'AI提取提示词'**
  String get projectDialogAiExtract;

  /// No description provided for @projectDialogPromptPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'描述提示词'**
  String get projectDialogPromptPlaceholder;

  /// No description provided for @projectDialogVisualManual.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册'**
  String get projectDialogVisualManual;

  /// No description provided for @projectDialogNewVisualManual.
  ///
  /// In zh, this message translates to:
  /// **'新建视觉手册'**
  String get projectDialogNewVisualManual;

  /// No description provided for @projectDialogEditVisualManualTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑视觉手册'**
  String get projectDialogEditVisualManualTitle;

  /// No description provided for @projectDialogNewVisualManualTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建视觉手册'**
  String get projectDialogNewVisualManualTitle;

  /// No description provided for @projectDialogVisualManualName.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册名称'**
  String get projectDialogVisualManualName;

  /// No description provided for @projectDialogVisualManualNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入视觉手册名称'**
  String get projectDialogVisualManualNamePh;

  /// No description provided for @projectDialogVisualManualCover.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册封面'**
  String get projectDialogVisualManualCover;

  /// No description provided for @projectDialogVisualManualPrompt.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册提示词'**
  String get projectDialogVisualManualPrompt;

  /// No description provided for @projectDialogModelData.
  ///
  /// In zh, this message translates to:
  /// **'选择图片模型'**
  String get projectDialogModelData;

  /// No description provided for @projectDialogVideoModelData.
  ///
  /// In zh, this message translates to:
  /// **'选择视频模型'**
  String get projectDialogVideoModelData;

  /// No description provided for @projectDialogPromptSaveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'更新成功'**
  String get projectDialogPromptSaveSuccess;

  /// No description provided for @projectDialogPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get projectDialogPromptTitle;

  /// No description provided for @projectDialogBasedOnScript.
  ///
  /// In zh, this message translates to:
  /// **'基于剧本'**
  String get projectDialogBasedOnScript;

  /// No description provided for @projectDialogMdFile.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册文件'**
  String get projectDialogMdFile;

  /// No description provided for @projectDialogDirectorManual.
  ///
  /// In zh, this message translates to:
  /// **'导演手册'**
  String get projectDialogDirectorManual;

  /// No description provided for @projectDialogAddDirectorManual.
  ///
  /// In zh, this message translates to:
  /// **'新建导演手册'**
  String get projectDialogAddDirectorManual;

  /// No description provided for @projectDialogEditingDirectorManual.
  ///
  /// In zh, this message translates to:
  /// **'编辑导演手册'**
  String get projectDialogEditingDirectorManual;

  /// No description provided for @projectDialogNewDirecorManualTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建导演手册'**
  String get projectDialogNewDirecorManualTitle;

  /// No description provided for @projectDialogDirectorManualPrompt.
  ///
  /// In zh, this message translates to:
  /// **'导演手册提示词'**
  String get projectDialogDirectorManualPrompt;

  /// No description provided for @projectDialogDirectorManualName.
  ///
  /// In zh, this message translates to:
  /// **'导演手册名称'**
  String get projectDialogDirectorManualName;

  /// No description provided for @projectDialogDirectorManualNamePh.
  ///
  /// In zh, this message translates to:
  /// **'输入导演手册名称'**
  String get projectDialogDirectorManualNamePh;

  /// No description provided for @projectDialogDirectorFile.
  ///
  /// In zh, this message translates to:
  /// **'导演手册文件'**
  String get projectDialogDirectorFile;

  /// No description provided for @projectDialogDirectorManualCover.
  ///
  /// In zh, this message translates to:
  /// **'导演手册封面'**
  String get projectDialogDirectorManualCover;

  /// No description provided for @projectMsgFetchFailed.
  ///
  /// In zh, this message translates to:
  /// **'获取项目列表失败'**
  String get projectMsgFetchFailed;

  /// No description provided for @projectMsgNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到该项目!'**
  String get projectMsgNotFound;

  /// No description provided for @projectMsgEditSuccess.
  ///
  /// In zh, this message translates to:
  /// **'编辑项目成功'**
  String get projectMsgEditSuccess;

  /// No description provided for @projectMsgEditFailed.
  ///
  /// In zh, this message translates to:
  /// **'编辑项目失败'**
  String get projectMsgEditFailed;

  /// No description provided for @projectMsgAddSuccess.
  ///
  /// In zh, this message translates to:
  /// **'新增项目成功'**
  String get projectMsgAddSuccess;

  /// No description provided for @projectMsgAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'新增项目失败'**
  String get projectMsgAddFailed;

  /// No description provided for @projectMsgDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除项目'**
  String get projectMsgDeleteHeader;

  /// No description provided for @projectMsgDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该项目吗？'**
  String get projectMsgDeleteBody;

  /// No description provided for @projectMsgDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get projectMsgDeleteConfirm;

  /// No description provided for @projectMsgDeleteCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get projectMsgDeleteCancel;

  /// No description provided for @projectMsgDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'删除项目成功'**
  String get projectMsgDeleteSuccess;

  /// No description provided for @projectMsgDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除项目失败'**
  String get projectMsgDeleteFailed;

  /// No description provided for @projectMsgExtractSuccess.
  ///
  /// In zh, this message translates to:
  /// **'提示词提取成功'**
  String get projectMsgExtractSuccess;

  /// No description provided for @projectMsgExtractFailed.
  ///
  /// In zh, this message translates to:
  /// **'提取失败'**
  String get projectMsgExtractFailed;

  /// No description provided for @projectMsgEnterArtStyleName.
  ///
  /// In zh, this message translates to:
  /// **'请输入画风名称'**
  String get projectMsgEnterArtStyleName;

  /// No description provided for @projectMsgArtStyleUpdated.
  ///
  /// In zh, this message translates to:
  /// **'画风已更新'**
  String get projectMsgArtStyleUpdated;

  /// No description provided for @projectMsgArtStyleAdded.
  ///
  /// In zh, this message translates to:
  /// **'画风已添加'**
  String get projectMsgArtStyleAdded;

  /// No description provided for @projectMsgOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败'**
  String get projectMsgOperationFailed;

  /// No description provided for @projectMsgEnterVisualManualName.
  ///
  /// In zh, this message translates to:
  /// **'请输入视觉手册名称'**
  String get projectMsgEnterVisualManualName;

  /// No description provided for @projectMsgEnterVisualManualImage.
  ///
  /// In zh, this message translates to:
  /// **'请上传视觉手册封面图片'**
  String get projectMsgEnterVisualManualImage;

  /// No description provided for @projectMsgEnterVisualManualTabData.
  ///
  /// In zh, this message translates to:
  /// **'提示词不能为空'**
  String get projectMsgEnterVisualManualTabData;

  /// No description provided for @projectMsgVisualManualUpdated.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册已更新'**
  String get projectMsgVisualManualUpdated;

  /// No description provided for @projectMsgVisualManualAdded.
  ///
  /// In zh, this message translates to:
  /// **'视觉手册已添加'**
  String get projectMsgVisualManualAdded;

  /// No description provided for @projectMsgDeleteVisualManualHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除视觉手册'**
  String get projectMsgDeleteVisualManualHeader;

  /// No description provided for @projectMsgDeleteVisualManualBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除视觉手册「{name}」吗？'**
  String projectMsgDeleteVisualManualBody(String name);

  /// No description provided for @projectMsgDeleteVisualManualConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get projectMsgDeleteVisualManualConfirm;

  /// No description provided for @projectMsgDeleteVisualManualCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get projectMsgDeleteVisualManualCancel;

  /// No description provided for @projectMsgEnterProjectName.
  ///
  /// In zh, this message translates to:
  /// **'请输入项目名称'**
  String get projectMsgEnterProjectName;

  /// No description provided for @projectMsgEnterProjectIntro.
  ///
  /// In zh, this message translates to:
  /// **'请输入小说简介'**
  String get projectMsgEnterProjectIntro;

  /// No description provided for @projectMsgEnterProjectType.
  ///
  /// In zh, this message translates to:
  /// **'请输入小说类型'**
  String get projectMsgEnterProjectType;

  /// No description provided for @projectMsgEnterArtStyle.
  ///
  /// In zh, this message translates to:
  /// **'请选择项目视觉手册'**
  String get projectMsgEnterArtStyle;

  /// No description provided for @projectMsgEnterVideoRatio.
  ///
  /// In zh, this message translates to:
  /// **'请选择影片比例'**
  String get projectMsgEnterVideoRatio;

  /// No description provided for @projectMsgEnterImageModel.
  ///
  /// In zh, this message translates to:
  /// **'请选择图片模型'**
  String get projectMsgEnterImageModel;

  /// No description provided for @projectMsgEnterVideoModel.
  ///
  /// In zh, this message translates to:
  /// **'请选择视频模型'**
  String get projectMsgEnterVideoModel;

  /// No description provided for @projectMsgVisualManualDeleted.
  ///
  /// In zh, this message translates to:
  /// **'删除成功'**
  String get projectMsgVisualManualDeleted;

  /// No description provided for @projectMsgSelectMode.
  ///
  /// In zh, this message translates to:
  /// **'请选择模式'**
  String get projectMsgSelectMode;

  /// No description provided for @projectMsgDeleteDirectorManualHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除导演手册'**
  String get projectMsgDeleteDirectorManualHeader;

  /// No description provided for @projectMsgDeleteDirectorManualBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除导演手册「{name}」吗？'**
  String projectMsgDeleteDirectorManualBody(String name);

  /// No description provided for @projectMsgDirectorManualUpdated.
  ///
  /// In zh, this message translates to:
  /// **'导演手册已更新'**
  String get projectMsgDirectorManualUpdated;

  /// No description provided for @projectMsgDirectorManualAdded.
  ///
  /// In zh, this message translates to:
  /// **'导演手册已添加'**
  String get projectMsgDirectorManualAdded;

  /// No description provided for @projectMsgDirectorManual.
  ///
  /// In zh, this message translates to:
  /// **'请选择项目导演手册'**
  String get projectMsgDirectorManual;

  /// No description provided for @projectMsgModelProviderDisabled.
  ///
  /// In zh, this message translates to:
  /// **'视频模型或图片模型供应商未启用或无模型供应商，请先配置'**
  String get projectMsgModelProviderDisabled;

  /// No description provided for @projectTypeNovel.
  ///
  /// In zh, this message translates to:
  /// **'基于小说原文'**
  String get projectTypeNovel;

  /// No description provided for @projectTypeScript.
  ///
  /// In zh, this message translates to:
  /// **'基于小说剧本'**
  String get projectTypeScript;

  /// No description provided for @commonEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @manualTabReadme.
  ///
  /// In zh, this message translates to:
  /// **'README'**
  String get manualTabReadme;

  /// No description provided for @manualTabPrefix.
  ///
  /// In zh, this message translates to:
  /// **'前缀'**
  String get manualTabPrefix;

  /// No description provided for @manualTabCharacter.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get manualTabCharacter;

  /// No description provided for @manualTabCharacterDerivative.
  ///
  /// In zh, this message translates to:
  /// **'角色衍生'**
  String get manualTabCharacterDerivative;

  /// No description provided for @manualTabProp.
  ///
  /// In zh, this message translates to:
  /// **'道具'**
  String get manualTabProp;

  /// No description provided for @manualTabPropDerivative.
  ///
  /// In zh, this message translates to:
  /// **'道具衍生'**
  String get manualTabPropDerivative;

  /// No description provided for @manualTabScene.
  ///
  /// In zh, this message translates to:
  /// **'场景'**
  String get manualTabScene;

  /// No description provided for @manualTabSceneDerivative.
  ///
  /// In zh, this message translates to:
  /// **'场景衍生'**
  String get manualTabSceneDerivative;

  /// No description provided for @manualTabStoryboard.
  ///
  /// In zh, this message translates to:
  /// **'分镜'**
  String get manualTabStoryboard;

  /// No description provided for @manualTabStoryboardVideo.
  ///
  /// In zh, this message translates to:
  /// **'分镜视频'**
  String get manualTabStoryboardVideo;

  /// No description provided for @manualTabDirectorPlanning.
  ///
  /// In zh, this message translates to:
  /// **'技法-导演规划'**
  String get manualTabDirectorPlanning;

  /// No description provided for @manualTabStoryboardTable.
  ///
  /// In zh, this message translates to:
  /// **'技法-分镜表设计'**
  String get manualTabStoryboardTable;

  /// No description provided for @manualTabNarrativePlanning.
  ///
  /// In zh, this message translates to:
  /// **'导演规划'**
  String get manualTabNarrativePlanning;

  /// No description provided for @manualTabNarrativeTable.
  ///
  /// In zh, this message translates to:
  /// **'分镜表'**
  String get manualTabNarrativeTable;

  /// No description provided for @errManualInvalid.
  ///
  /// In zh, this message translates to:
  /// **'手册数据无效'**
  String get errManualInvalid;

  /// No description provided for @novelImportText.
  ///
  /// In zh, this message translates to:
  /// **'导入原文'**
  String get novelImportText;

  /// No description provided for @novelBatchDelete.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get novelBatchDelete;

  /// No description provided for @novelEventAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'事件分析'**
  String get novelEventAnalysis;

  /// No description provided for @novelSearchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'搜索原文名称...'**
  String get novelSearchPlaceholder;

  /// No description provided for @novelSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get novelSearch;

  /// No description provided for @novelGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get novelGenerating;

  /// No description provided for @novelGenFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败'**
  String get novelGenFailed;

  /// No description provided for @novelViewDetail.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get novelViewDetail;

  /// No description provided for @novelNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get novelNone;

  /// No description provided for @novelEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get novelEdit;

  /// No description provided for @novelDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get novelDelete;

  /// No description provided for @novelColId.
  ///
  /// In zh, this message translates to:
  /// **'序号'**
  String get novelColId;

  /// No description provided for @novelColReel.
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get novelColReel;

  /// No description provided for @novelColChapter.
  ///
  /// In zh, this message translates to:
  /// **'章节名称'**
  String get novelColChapter;

  /// No description provided for @novelColChapterData.
  ///
  /// In zh, this message translates to:
  /// **'章节内容'**
  String get novelColChapterData;

  /// No description provided for @novelColEvent.
  ///
  /// In zh, this message translates to:
  /// **'事件'**
  String get novelColEvent;

  /// No description provided for @novelColOperation.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get novelColOperation;

  /// No description provided for @novelMsgBatchDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get novelMsgBatchDeleteHeader;

  /// No description provided for @novelMsgBatchDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中的 {count} 条数据吗?'**
  String novelMsgBatchDeleteBody(String count);

  /// No description provided for @novelMsgBatchDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'批量删除成功'**
  String get novelMsgBatchDeleteSuccess;

  /// No description provided for @novelMsgDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除确认'**
  String get novelMsgDeleteHeader;

  /// No description provided for @novelMsgDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除章节名称为「{name}」的数据吗?'**
  String novelMsgDeleteBody(String name);

  /// No description provided for @novelMsgDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'删除成功'**
  String get novelMsgDeleteSuccess;

  /// No description provided for @novelMsgEventAnalysisHeader.
  ///
  /// In zh, this message translates to:
  /// **'事件分析'**
  String get novelMsgEventAnalysisHeader;

  /// No description provided for @novelMsgEventAnalysisBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要对选中的 {count} 条数据进行事件分析吗?'**
  String novelMsgEventAnalysisBody(String count);

  /// No description provided for @novelImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'上传小说原文'**
  String get novelImportTitle;

  /// No description provided for @novelImportStep1.
  ///
  /// In zh, this message translates to:
  /// **'第一步'**
  String get novelImportStep1;

  /// No description provided for @novelImportStep2.
  ///
  /// In zh, this message translates to:
  /// **'第二步'**
  String get novelImportStep2;

  /// No description provided for @novelImportStep3.
  ///
  /// In zh, this message translates to:
  /// **'第三步'**
  String get novelImportStep3;

  /// No description provided for @novelImportDragUpload.
  ///
  /// In zh, this message translates to:
  /// **'拖拽小说原文文件到此处或点击上传'**
  String get novelImportDragUpload;

  /// No description provided for @novelImportUploadHint.
  ///
  /// In zh, this message translates to:
  /// **'支持 .txt, .docx 格式，建议文件大小不超过 10MB'**
  String get novelImportUploadHint;

  /// No description provided for @novelImportOr.
  ///
  /// In zh, this message translates to:
  /// **'或'**
  String get novelImportOr;

  /// No description provided for @novelImportPasteLabel.
  ///
  /// In zh, this message translates to:
  /// **'直接粘贴小说原文内容'**
  String get novelImportPasteLabel;

  /// No description provided for @novelImportPastePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入小说原文内容'**
  String get novelImportPastePlaceholder;

  /// No description provided for @novelImportChars.
  ///
  /// In zh, this message translates to:
  /// **'字符'**
  String get novelImportChars;

  /// No description provided for @novelImportTooShort.
  ///
  /// In zh, this message translates to:
  /// **'内容过短，建议至少100字符'**
  String get novelImportTooShort;

  /// No description provided for @novelImportParsedChapters.
  ///
  /// In zh, this message translates to:
  /// **'已解析 {count} 章节'**
  String novelImportParsedChapters(String count);

  /// No description provided for @novelImportNextStep.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get novelImportNextStep;

  /// No description provided for @novelImportPrevStep.
  ///
  /// In zh, this message translates to:
  /// **'上一步'**
  String get novelImportPrevStep;

  /// No description provided for @novelImportSelectedInfo.
  ///
  /// In zh, this message translates to:
  /// **'已勾选：{count}字'**
  String novelImportSelectedInfo(String count);

  /// No description provided for @novelImportEventAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'事件分析'**
  String get novelImportEventAnalysis;

  /// No description provided for @novelImportSaveAndAnalyze.
  ///
  /// In zh, this message translates to:
  /// **'保存原文并分析事件'**
  String get novelImportSaveAndAnalyze;

  /// No description provided for @novelImportColChapter.
  ///
  /// In zh, this message translates to:
  /// **'章'**
  String get novelImportColChapter;

  /// No description provided for @novelImportColReel.
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get novelImportColReel;

  /// No description provided for @novelImportColChapterName.
  ///
  /// In zh, this message translates to:
  /// **'章节名称'**
  String get novelImportColChapterName;

  /// No description provided for @novelImportColChapterData.
  ///
  /// In zh, this message translates to:
  /// **'章节内容'**
  String get novelImportColChapterData;

  /// No description provided for @novelImportMsgParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件解析失败，请重新上传'**
  String get novelImportMsgParseFailed;

  /// No description provided for @novelImportMsgSelectFile.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get novelImportMsgSelectFile;

  /// No description provided for @novelImportMsgDocNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'.doc文件不支持解析，请转换为.ts文件'**
  String get novelImportMsgDocNotSupported;

  /// No description provided for @novelImportMsgUnsupportedType.
  ///
  /// In zh, this message translates to:
  /// **'不支持的文件类型'**
  String get novelImportMsgUnsupportedType;

  /// No description provided for @novelImportMsgFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件大小超过10MB，请上传更小的文件'**
  String get novelImportMsgFileTooLarge;

  /// No description provided for @novelImportMsgSelectChapters.
  ///
  /// In zh, this message translates to:
  /// **'请先勾选章节'**
  String get novelImportMsgSelectChapters;

  /// No description provided for @novelImportMsgSaveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'小说原文保存成功'**
  String get novelImportMsgSaveSuccess;

  /// No description provided for @novelImportImportAdd.
  ///
  /// In zh, this message translates to:
  /// **'拖拽文件到此处或点击上传'**
  String get novelImportImportAdd;

  /// No description provided for @novelImportLimit.
  ///
  /// In zh, this message translates to:
  /// **'支持 .ts格式'**
  String get novelImportLimit;

  /// No description provided for @novelEditDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑小说原文'**
  String get novelEditDialogTitle;

  /// No description provided for @novelEditDialogChapterName.
  ///
  /// In zh, this message translates to:
  /// **'章节名称'**
  String get novelEditDialogChapterName;

  /// No description provided for @novelEditDialogChapterNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入章节名称'**
  String get novelEditDialogChapterNamePh;

  /// No description provided for @novelEditDialogEventContent.
  ///
  /// In zh, this message translates to:
  /// **'事件内容'**
  String get novelEditDialogEventContent;

  /// No description provided for @novelEditDialogEventContentPh.
  ///
  /// In zh, this message translates to:
  /// **'输入事件内容'**
  String get novelEditDialogEventContentPh;

  /// No description provided for @novelEditDialogChapterContent.
  ///
  /// In zh, this message translates to:
  /// **'章节内容'**
  String get novelEditDialogChapterContent;

  /// No description provided for @novelEditDialogChapterContentPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入章节内容'**
  String get novelEditDialogChapterContentPh;

  /// No description provided for @novelEditDialogCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get novelEditDialogCancel;

  /// No description provided for @novelEditDialogSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get novelEditDialogSave;

  /// No description provided for @novelEditDialogMsgUpdateSuccess.
  ///
  /// In zh, this message translates to:
  /// **'小说原文更新成功'**
  String get novelEditDialogMsgUpdateSuccess;

  /// No description provided for @novelEventRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成事件'**
  String get novelEventRegenerate;

  /// No description provided for @novelEventBatchDelete.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get novelEventBatchDelete;

  /// No description provided for @novelEventNoData.
  ///
  /// In zh, this message translates to:
  /// **'暂无事件数据，点击开始生成'**
  String get novelEventNoData;

  /// No description provided for @novelEventGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成事件'**
  String get novelEventGenerate;

  /// No description provided for @novelEventGeneratingHint.
  ///
  /// In zh, this message translates to:
  /// **'事件生成中，请稍候...'**
  String get novelEventGeneratingHint;

  /// No description provided for @novelEventLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中...'**
  String get novelEventLoading;

  /// No description provided for @novelEventDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get novelEventDelete;

  /// No description provided for @novelEventColId.
  ///
  /// In zh, this message translates to:
  /// **'事件ID'**
  String get novelEventColId;

  /// No description provided for @novelEventColEventName.
  ///
  /// In zh, this message translates to:
  /// **'事件名称'**
  String get novelEventColEventName;

  /// No description provided for @novelEventColChapters.
  ///
  /// In zh, this message translates to:
  /// **'来源章节'**
  String get novelEventColChapters;

  /// No description provided for @novelEventColDetail.
  ///
  /// In zh, this message translates to:
  /// **'事件过程'**
  String get novelEventColDetail;

  /// No description provided for @novelEventColCreateTime.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get novelEventColCreateTime;

  /// No description provided for @novelEventColOperation.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get novelEventColOperation;

  /// No description provided for @novelEventMsgDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除事件'**
  String get novelEventMsgDeleteHeader;

  /// No description provided for @novelEventMsgDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除这个事件吗？'**
  String get novelEventMsgDeleteBody;

  /// No description provided for @novelEventMsgDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'删除成功'**
  String get novelEventMsgDeleteSuccess;

  /// No description provided for @novelEventMsgGenerateSuccess.
  ///
  /// In zh, this message translates to:
  /// **'事件生成成功'**
  String get novelEventMsgGenerateSuccess;

  /// No description provided for @novelEventMsgBatchDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get novelEventMsgBatchDeleteHeader;

  /// No description provided for @novelEventMsgBatchDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中的 {count} 条数据吗?'**
  String novelEventMsgBatchDeleteBody(String count);

  /// No description provided for @novelEventMsgBatchDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'批量删除成功'**
  String get novelEventMsgBatchDeleteSuccess;

  /// No description provided for @novelAnalysisAnalyzeFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先分析事件'**
  String get novelAnalysisAnalyzeFirst;

  /// No description provided for @novelAnalysisStartAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'开始分析'**
  String get novelAnalysisStartAnalysis;

  /// No description provided for @novelAnalysisChapterHeader.
  ///
  /// In zh, this message translates to:
  /// **'第{index}章 - {name}'**
  String novelAnalysisChapterHeader(String index, String name);

  /// No description provided for @novelAnalysisAnalyzing.
  ///
  /// In zh, this message translates to:
  /// **'事件分析中'**
  String get novelAnalysisAnalyzing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
