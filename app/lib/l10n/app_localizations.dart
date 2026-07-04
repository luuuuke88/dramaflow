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

  /// No description provided for @errPlatformComposer.
  ///
  /// In zh, this message translates to:
  /// **'平台视频合成失败'**
  String get errPlatformComposer;

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

  /// No description provided for @promptGlobalTemplates.
  ///
  /// In zh, this message translates to:
  /// **'全局模板'**
  String get promptGlobalTemplates;

  /// No description provided for @promptModelTemplates.
  ///
  /// In zh, this message translates to:
  /// **'模型专属模板'**
  String get promptModelTemplates;

  /// No description provided for @promptModelTemplatesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无模型专属模板。导入配置或模型模板后会显示在这里。'**
  String get promptModelTemplatesEmpty;

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

  /// No description provided for @projectStatChapters.
  ///
  /// In zh, this message translates to:
  /// **'章节 {count}'**
  String projectStatChapters(int count);

  /// No description provided for @projectStatScripts.
  ///
  /// In zh, this message translates to:
  /// **'剧本 {count}'**
  String projectStatScripts(int count);

  /// No description provided for @projectStatAssets.
  ///
  /// In zh, this message translates to:
  /// **'素材 {count}'**
  String projectStatAssets(int count);

  /// No description provided for @projectStatStoryboards.
  ///
  /// In zh, this message translates to:
  /// **'分镜 {count}'**
  String projectStatStoryboards(int count);

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

  /// No description provided for @scriptSearchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'搜索剧本名称...'**
  String get scriptSearchPlaceholder;

  /// No description provided for @scriptSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get scriptSearch;

  /// No description provided for @scriptAddScript.
  ///
  /// In zh, this message translates to:
  /// **'新建剧本'**
  String get scriptAddScript;

  /// No description provided for @scriptCancelSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get scriptCancelSelectAll;

  /// No description provided for @scriptSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get scriptSelectAll;

  /// No description provided for @scriptExportScript.
  ///
  /// In zh, this message translates to:
  /// **'导出剧本'**
  String get scriptExportScript;

  /// No description provided for @scriptMsgExtracting.
  ///
  /// In zh, this message translates to:
  /// **'资产提取中'**
  String get scriptMsgExtracting;

  /// No description provided for @scriptMsgExtractFailed.
  ///
  /// In zh, this message translates to:
  /// **'资产提取失败'**
  String get scriptMsgExtractFailed;

  /// No description provided for @scriptMsgExtractingInProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在提取中'**
  String get scriptMsgExtractingInProgress;

  /// No description provided for @scriptMsgProjectNotFound.
  ///
  /// In zh, this message translates to:
  /// **'项目未找到'**
  String get scriptMsgProjectNotFound;

  /// No description provided for @scriptMsgSelectExport.
  ///
  /// In zh, this message translates to:
  /// **'请选择导出剧本'**
  String get scriptMsgSelectExport;

  /// No description provided for @scriptMsgDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get scriptMsgDeleteHeader;

  /// No description provided for @scriptMsgDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确认要删除这个剧本吗？次操作无法复原'**
  String get scriptMsgDeleteBody;

  /// No description provided for @scriptMsgDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get scriptMsgDeleteConfirm;

  /// No description provided for @scriptMsgCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get scriptMsgCancel;

  /// No description provided for @scriptMsgDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'删除成功'**
  String get scriptMsgDeleteSuccess;

  /// No description provided for @scriptMsgDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败'**
  String get scriptMsgDeleteFailed;

  /// No description provided for @scriptMsgSelectDelScript.
  ///
  /// In zh, this message translates to:
  /// **'请选择删除剧本'**
  String get scriptMsgSelectDelScript;

  /// No description provided for @scriptMsgBatchDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get scriptMsgBatchDeleteHeader;

  /// No description provided for @scriptMsgBatchDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中的{count}个剧本吗？此操作无法复原'**
  String scriptMsgBatchDeleteBody(String count);

  /// No description provided for @scriptMsgBatchDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'批量删除成功'**
  String get scriptMsgBatchDeleteSuccess;

  /// No description provided for @scriptMsgSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索剧本失败'**
  String get scriptMsgSearchFailed;

  /// No description provided for @scriptMsgSelectsExport.
  ///
  /// In zh, this message translates to:
  /// **'请选择导出剧本'**
  String get scriptMsgSelectsExport;

  /// No description provided for @scriptAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增剧本'**
  String get scriptAddTitle;

  /// No description provided for @scriptAddScriptName.
  ///
  /// In zh, this message translates to:
  /// **'剧本名称'**
  String get scriptAddScriptName;

  /// No description provided for @scriptAddScriptNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本名称'**
  String get scriptAddScriptNamePh;

  /// No description provided for @scriptAddUploadFile.
  ///
  /// In zh, this message translates to:
  /// **'上传文件'**
  String get scriptAddUploadFile;

  /// No description provided for @scriptAddDragUpload.
  ///
  /// In zh, this message translates to:
  /// **'拖拽剧本文件到此处或点击上传'**
  String get scriptAddDragUpload;

  /// No description provided for @scriptAddUploadHint.
  ///
  /// In zh, this message translates to:
  /// **'支持 .txt, .docx 格式，建议文件大小不超过 10MB'**
  String get scriptAddUploadHint;

  /// No description provided for @scriptAddScriptContent.
  ///
  /// In zh, this message translates to:
  /// **'剧本内容'**
  String get scriptAddScriptContent;

  /// No description provided for @scriptAddScriptContentPh.
  ///
  /// In zh, this message translates to:
  /// **'请上传或输入剧本内容...'**
  String get scriptAddScriptContentPh;

  /// No description provided for @scriptAddRelatedAssets.
  ///
  /// In zh, this message translates to:
  /// **'关联资产'**
  String get scriptAddRelatedAssets;

  /// No description provided for @scriptAddSelectAssets.
  ///
  /// In zh, this message translates to:
  /// **'选择资产'**
  String get scriptAddSelectAssets;

  /// No description provided for @scriptAddNoAssets.
  ///
  /// In zh, this message translates to:
  /// **'暂未关联资产'**
  String get scriptAddNoAssets;

  /// No description provided for @scriptAddCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get scriptAddCancel;

  /// No description provided for @scriptAddConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get scriptAddConfirm;

  /// No description provided for @scriptAddMsgFileReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件读取失败'**
  String get scriptAddMsgFileReadFailed;

  /// No description provided for @scriptAddMsgDocNotSupported.
  ///
  /// In zh, this message translates to:
  /// **'.doc文件不支持解析,请转换为.txt或.docx文件'**
  String get scriptAddMsgDocNotSupported;

  /// No description provided for @scriptAddMsgUnsupportedType.
  ///
  /// In zh, this message translates to:
  /// **'不支持的文件类型'**
  String get scriptAddMsgUnsupportedType;

  /// No description provided for @scriptAddMsgFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件大小超过10MB，请上传更小的文件'**
  String get scriptAddMsgFileTooLarge;

  /// No description provided for @scriptAddMsgParsing.
  ///
  /// In zh, this message translates to:
  /// **'文件解析中...'**
  String get scriptAddMsgParsing;

  /// No description provided for @scriptAddMsgParseFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件解析失败，请重新上传'**
  String get scriptAddMsgParseFailed;

  /// No description provided for @scriptAddMsgSelectAssetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择关联资产'**
  String get scriptAddMsgSelectAssetsTitle;

  /// No description provided for @scriptAddMsgEnterContent.
  ///
  /// In zh, this message translates to:
  /// **'请上传或输入剧本内容'**
  String get scriptAddMsgEnterContent;

  /// No description provided for @scriptAddMsgEnterName.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本名称'**
  String get scriptAddMsgEnterName;

  /// No description provided for @scriptAddMsgAddSuccess.
  ///
  /// In zh, this message translates to:
  /// **'剧本添加成功'**
  String get scriptAddMsgAddSuccess;

  /// No description provided for @scriptAddMsgAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加剧本失败，请稍后再试'**
  String get scriptAddMsgAddFailed;

  /// No description provided for @scriptEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本详情'**
  String get scriptEditTitle;

  /// No description provided for @scriptEditScriptName.
  ///
  /// In zh, this message translates to:
  /// **'剧本名称'**
  String get scriptEditScriptName;

  /// No description provided for @scriptEditScriptNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本名称'**
  String get scriptEditScriptNamePh;

  /// No description provided for @scriptEditScriptContent.
  ///
  /// In zh, this message translates to:
  /// **'剧本内容'**
  String get scriptEditScriptContent;

  /// No description provided for @scriptEditScriptContentPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本内容...'**
  String get scriptEditScriptContentPh;

  /// No description provided for @scriptEditRelatedAssets.
  ///
  /// In zh, this message translates to:
  /// **'关联资产'**
  String get scriptEditRelatedAssets;

  /// No description provided for @scriptEditSelectAssets.
  ///
  /// In zh, this message translates to:
  /// **'选择资产'**
  String get scriptEditSelectAssets;

  /// No description provided for @scriptEditNoAssets.
  ///
  /// In zh, this message translates to:
  /// **'暂未关联资产'**
  String get scriptEditNoAssets;

  /// No description provided for @scriptEditMsgSelectAssetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择关联资产'**
  String get scriptEditMsgSelectAssetsTitle;

  /// No description provided for @scriptEditMsgUpdateSuccess.
  ///
  /// In zh, this message translates to:
  /// **'剧本更新成功'**
  String get scriptEditMsgUpdateSuccess;

  /// No description provided for @scriptEditMsgUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新剧本失败，请稍后再试'**
  String get scriptEditMsgUpdateFailed;

  /// No description provided for @scriptMarkdownBold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get scriptMarkdownBold;

  /// No description provided for @scriptMarkdownItalic.
  ///
  /// In zh, this message translates to:
  /// **'斜体'**
  String get scriptMarkdownItalic;

  /// No description provided for @scriptMarkdownHeading.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get scriptMarkdownHeading;

  /// No description provided for @scriptMarkdownDialogue.
  ///
  /// In zh, this message translates to:
  /// **'台词'**
  String get scriptMarkdownDialogue;

  /// No description provided for @scriptMarkdownEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get scriptMarkdownEdit;

  /// No description provided for @scriptMarkdownPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get scriptMarkdownPreview;

  /// No description provided for @scriptMarkdownPreviewEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无内容'**
  String get scriptMarkdownPreviewEmpty;

  /// No description provided for @scriptMarkdownBoldPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'重点'**
  String get scriptMarkdownBoldPlaceholder;

  /// No description provided for @scriptMarkdownItalicPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'强调'**
  String get scriptMarkdownItalicPlaceholder;

  /// No description provided for @scriptMarkdownDialogueSnippet.
  ///
  /// In zh, this message translates to:
  /// **'角色：台词'**
  String get scriptMarkdownDialogueSnippet;

  /// No description provided for @scriptDeleteScript.
  ///
  /// In zh, this message translates to:
  /// **'批量删除剧本'**
  String get scriptDeleteScript;

  /// No description provided for @scriptExtractAssets.
  ///
  /// In zh, this message translates to:
  /// **'提取资产'**
  String get scriptExtractAssets;

  /// No description provided for @scriptImportGetAiRegex.
  ///
  /// In zh, this message translates to:
  /// **'AI解析正则'**
  String get scriptImportGetAiRegex;

  /// No description provided for @scriptImportEpisodeRegexPh.
  ///
  /// In zh, this message translates to:
  /// **'自定义剧本拆分正则'**
  String get scriptImportEpisodeRegexPh;

  /// No description provided for @scriptBatchAdd.
  ///
  /// In zh, this message translates to:
  /// **'批量添加'**
  String get scriptBatchAdd;

  /// No description provided for @scriptGenerateFromEvents.
  ///
  /// In zh, this message translates to:
  /// **'事件生成剧本'**
  String get scriptGenerateFromEvents;

  /// No description provided for @scriptGenerateFromEventsTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择事件生成剧本'**
  String get scriptGenerateFromEventsTitle;

  /// No description provided for @scriptGenerateFromEventsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用事件，请先在章节页生成事件'**
  String get scriptGenerateFromEventsEmpty;

  /// No description provided for @scriptGenerateFromEventsConfirm.
  ///
  /// In zh, this message translates to:
  /// **'生成剧本'**
  String get scriptGenerateFromEventsConfirm;

  /// No description provided for @scriptGenerateFromEventsSelectHint.
  ///
  /// In zh, this message translates to:
  /// **'请选择要生成剧本的事件'**
  String get scriptGenerateFromEventsSelectHint;

  /// No description provided for @scriptGenerateFromEventsSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'剧本生成已提交'**
  String get scriptGenerateFromEventsSubmitted;

  /// No description provided for @scriptStateWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待提取...'**
  String get scriptStateWaiting;

  /// No description provided for @scriptStateExtracting.
  ///
  /// In zh, this message translates to:
  /// **'提取中...'**
  String get scriptStateExtracting;

  /// No description provided for @scriptStateFailed.
  ///
  /// In zh, this message translates to:
  /// **'提取失败'**
  String get scriptStateFailed;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @localeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get localeSystem;

  /// No description provided for @assetsTabRole.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get assetsTabRole;

  /// No description provided for @assetsTabTool.
  ///
  /// In zh, this message translates to:
  /// **'道具'**
  String get assetsTabTool;

  /// No description provided for @assetsTabScene.
  ///
  /// In zh, this message translates to:
  /// **'场景'**
  String get assetsTabScene;

  /// No description provided for @assetsTabClip.
  ///
  /// In zh, this message translates to:
  /// **'素材'**
  String get assetsTabClip;

  /// No description provided for @assetsTabAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get assetsTabAudio;

  /// No description provided for @assetsAddPrefix.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get assetsAddPrefix;

  /// No description provided for @assetsGeneratePrompt.
  ///
  /// In zh, this message translates to:
  /// **'生成提示词'**
  String get assetsGeneratePrompt;

  /// No description provided for @assetsGenerateImage.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get assetsGenerateImage;

  /// No description provided for @assetsBatchDelete.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get assetsBatchDelete;

  /// No description provided for @assetsSearchPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'搜索资产名称...'**
  String get assetsSearchPlaceholder;

  /// No description provided for @assetsColPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get assetsColPreview;

  /// No description provided for @assetsColName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get assetsColName;

  /// No description provided for @assetsColPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get assetsColPrompt;

  /// No description provided for @assetsColDescribe.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get assetsColDescribe;

  /// No description provided for @assetsColRemark.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get assetsColRemark;

  /// No description provided for @assetsColCreateTime.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get assetsColCreateTime;

  /// No description provided for @assetsColOperation.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get assetsColOperation;

  /// No description provided for @assetsGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get assetsGenerate;

  /// No description provided for @assetsEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get assetsEdit;

  /// No description provided for @assetsDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get assetsDelete;

  /// No description provided for @assetsGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get assetsGenerating;

  /// No description provided for @assetsConfirmDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'确认删除'**
  String get assetsConfirmDeleteHeader;

  /// No description provided for @assetsConfirmDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该资产吗？其图片版本与子资产将一并删除'**
  String get assetsConfirmDeleteBody;

  /// No description provided for @assetsConfirmBatchDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中的 {count} 个资产吗？'**
  String assetsConfirmBatchDeleteBody(String count);

  /// No description provided for @assetsDeleteSuccess.
  ///
  /// In zh, this message translates to:
  /// **'删除成功'**
  String get assetsDeleteSuccess;

  /// No description provided for @assetsSex.
  ///
  /// In zh, this message translates to:
  /// **'性别'**
  String get assetsSex;

  /// No description provided for @assetsAudioName.
  ///
  /// In zh, this message translates to:
  /// **'音色'**
  String get assetsAudioName;

  /// No description provided for @assetsAudioText.
  ///
  /// In zh, this message translates to:
  /// **'音频文本'**
  String get assetsAudioText;

  /// No description provided for @assetsPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get assetsPlay;

  /// No description provided for @assetsAddName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get assetsAddName;

  /// No description provided for @assetsAddNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入资产名称'**
  String get assetsAddNamePh;

  /// No description provided for @assetsAddNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入资产名称'**
  String get assetsAddNameRequired;

  /// No description provided for @assetsAddDescribe.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get assetsAddDescribe;

  /// No description provided for @assetsAddDescribePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入资产描述'**
  String get assetsAddDescribePh;

  /// No description provided for @assetsAddDescribeRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入资产描述'**
  String get assetsAddDescribeRequired;

  /// No description provided for @assetsAddRemark.
  ///
  /// In zh, this message translates to:
  /// **'备注'**
  String get assetsAddRemark;

  /// No description provided for @assetsAddRemarkPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入备注'**
  String get assetsAddRemarkPh;

  /// No description provided for @assetsAddPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get assetsAddPrompt;

  /// No description provided for @assetsAddPromptPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入生成提示词'**
  String get assetsAddPromptPh;

  /// No description provided for @assetsAddAddSuccess.
  ///
  /// In zh, this message translates to:
  /// **'新增资产成功'**
  String get assetsAddAddSuccess;

  /// No description provided for @assetsAddUpdateSuccess.
  ///
  /// In zh, this message translates to:
  /// **'更新资产成功'**
  String get assetsAddUpdateSuccess;

  /// No description provided for @assetsAddAudioNamePh.
  ///
  /// In zh, this message translates to:
  /// **'请输入音色名称'**
  String get assetsAddAudioNamePh;

  /// No description provided for @assetsAddSexPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入性别'**
  String get assetsAddSexPh;

  /// No description provided for @assetsAddAudioFile.
  ///
  /// In zh, this message translates to:
  /// **'音频文件'**
  String get assetsAddAudioFile;

  /// No description provided for @assetsAddAudioTextPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入该音频对应的文本内容'**
  String get assetsAddAudioTextPh;

  /// No description provided for @assetsAddAudioDescPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入该音频的描述'**
  String get assetsAddAudioDescPh;

  /// No description provided for @assetsAddAudioItem.
  ///
  /// In zh, this message translates to:
  /// **'添加音频'**
  String get assetsAddAudioItem;

  /// No description provided for @assetsAddPleaseUploadAudio.
  ///
  /// In zh, this message translates to:
  /// **'请上传音频文件'**
  String get assetsAddPleaseUploadAudio;

  /// No description provided for @assetsGenerateSpeech.
  ///
  /// In zh, this message translates to:
  /// **'文本配音'**
  String get assetsGenerateSpeech;

  /// No description provided for @assetsTtsGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成配音'**
  String get assetsTtsGenerate;

  /// No description provided for @assetsTtsText.
  ///
  /// In zh, this message translates to:
  /// **'配音文本'**
  String get assetsTtsText;

  /// No description provided for @assetsTtsTextPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入要合成的台词或旁白'**
  String get assetsTtsTextPh;

  /// No description provided for @assetsTtsVoice.
  ///
  /// In zh, this message translates to:
  /// **'Voice ID'**
  String get assetsTtsVoice;

  /// No description provided for @assetsTtsVoicePh.
  ///
  /// In zh, this message translates to:
  /// **'alloy / 自定义 voice id'**
  String get assetsTtsVoicePh;

  /// No description provided for @assetsTtsTextRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入配音文本'**
  String get assetsTtsTextRequired;

  /// No description provided for @assetsGenHeader.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get assetsGenHeader;

  /// No description provided for @assetsGenUploadRef.
  ///
  /// In zh, this message translates to:
  /// **'参考图'**
  String get assetsGenUploadRef;

  /// No description provided for @assetsGenOptional.
  ///
  /// In zh, this message translates to:
  /// **'可选'**
  String get assetsGenOptional;

  /// No description provided for @assetsGenPromptLabel.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get assetsGenPromptLabel;

  /// No description provided for @assetsGenSmartGenerate.
  ///
  /// In zh, this message translates to:
  /// **'智能生成'**
  String get assetsGenSmartGenerate;

  /// No description provided for @assetsGenSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get assetsGenSelectModel;

  /// No description provided for @assetsGenSelectResolution.
  ///
  /// In zh, this message translates to:
  /// **'选择分辨率'**
  String get assetsGenSelectResolution;

  /// No description provided for @assetsGenGenerateBtn.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get assetsGenGenerateBtn;

  /// No description provided for @assetsGenFillPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请填写提示词'**
  String get assetsGenFillPrompt;

  /// No description provided for @assetsGenPickModel.
  ///
  /// In zh, this message translates to:
  /// **'请选择模型'**
  String get assetsGenPickModel;

  /// No description provided for @assetsGenGeneratedCount.
  ///
  /// In zh, this message translates to:
  /// **'已生成 {count} 张'**
  String assetsGenGeneratedCount(String count);

  /// No description provided for @assetsGenGeneratingLabel.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get assetsGenGeneratingLabel;

  /// No description provided for @assetsGenGenFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败'**
  String get assetsGenGenFailed;

  /// No description provided for @assetsGenImageSaved.
  ///
  /// In zh, this message translates to:
  /// **'图片已保存'**
  String get assetsGenImageSaved;

  /// No description provided for @assetsGenAssetGenSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已提交生成'**
  String get assetsGenAssetGenSuccess;

  /// No description provided for @assetsGenPromptSuccess.
  ///
  /// In zh, this message translates to:
  /// **'提示词生成成功'**
  String get assetsGenPromptSuccess;

  /// No description provided for @assetsGenConfirmSelect.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一张图片'**
  String get assetsGenConfirmSelect;

  /// No description provided for @assetsGenResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成结果'**
  String get assetsGenResultTitle;

  /// No description provided for @assetsBatchHeader.
  ///
  /// In zh, this message translates to:
  /// **'批量生成'**
  String get assetsBatchHeader;

  /// No description provided for @assetsBatchSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 项'**
  String assetsBatchSelected(String count);

  /// No description provided for @assetsBatchSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get assetsBatchSelectAll;

  /// No description provided for @assetsBatchClearSelection.
  ///
  /// In zh, this message translates to:
  /// **'清空选择'**
  String get assetsBatchClearSelection;

  /// No description provided for @assetsBatchColPreviewImg.
  ///
  /// In zh, this message translates to:
  /// **'预览图'**
  String get assetsBatchColPreviewImg;

  /// No description provided for @assetsBatchInputPh.
  ///
  /// In zh, this message translates to:
  /// **'请输入提示词'**
  String get assetsBatchInputPh;

  /// No description provided for @assetsBatchSaveSelected.
  ///
  /// In zh, this message translates to:
  /// **'保存已选({count})'**
  String assetsBatchSaveSelected(String count);

  /// No description provided for @assetsBatchMissingPrompts.
  ///
  /// In zh, this message translates to:
  /// **'请先为所选资产生成提示词'**
  String get assetsBatchMissingPrompts;

  /// No description provided for @assetsBatchPromptDone.
  ///
  /// In zh, this message translates to:
  /// **'提示词批量生成已提交'**
  String get assetsBatchPromptDone;

  /// No description provided for @assetsBatchImageDone.
  ///
  /// In zh, this message translates to:
  /// **'图片批量生成已提交'**
  String get assetsBatchImageDone;

  /// No description provided for @assetsBatchSaveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'保存成功'**
  String get assetsBatchSaveSuccess;

  /// No description provided for @assetsCancelBtn.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get assetsCancelBtn;

  /// No description provided for @assetsSelectAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一项'**
  String get assetsSelectAtLeastOne;

  /// No description provided for @productionEditImageInvalidConnection.
  ///
  /// In zh, this message translates to:
  /// **'无法连接：仅可连到生成节点且不可重复'**
  String get productionEditImageInvalidConnection;

  /// No description provided for @productionEditImageUploadImage.
  ///
  /// In zh, this message translates to:
  /// **'上传图片'**
  String get productionEditImageUploadImage;

  /// No description provided for @productionEditImageImageGeneration.
  ///
  /// In zh, this message translates to:
  /// **'图片生成'**
  String get productionEditImageImageGeneration;

  /// No description provided for @productionEditImageGenerating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get productionEditImageGenerating;

  /// No description provided for @productionEditImagePromptPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'描述生成需求'**
  String get productionEditImagePromptPlaceholder;

  /// No description provided for @productionEditImageGenerateBtn.
  ///
  /// In zh, this message translates to:
  /// **'生成'**
  String get productionEditImageGenerateBtn;

  /// No description provided for @productionEditImageUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传节点'**
  String get productionEditImageUpload;

  /// No description provided for @productionEditImageGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成节点'**
  String get productionEditImageGenerate;

  /// No description provided for @productionNodeScriptTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本'**
  String get productionNodeScriptTitle;

  /// No description provided for @productionNodeScriptPlanTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本规划'**
  String get productionNodeScriptPlanTitle;

  /// No description provided for @productionNodeAssetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'资产'**
  String get productionNodeAssetsTitle;

  /// No description provided for @productionNodeStoryboardTableTitle.
  ///
  /// In zh, this message translates to:
  /// **'分镜表'**
  String get productionNodeStoryboardTableTitle;

  /// No description provided for @productionNodeStoryboardTitle.
  ///
  /// In zh, this message translates to:
  /// **'分镜'**
  String get productionNodeStoryboardTitle;

  /// No description provided for @productionNodeWorkbenchTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作台'**
  String get productionNodeWorkbenchTitle;

  /// No description provided for @productionMobileNodeInspector.
  ///
  /// In zh, this message translates to:
  /// **'节点检查器'**
  String get productionMobileNodeInspector;

  /// No description provided for @productionMobileCurrentNode.
  ///
  /// In zh, this message translates to:
  /// **'当前节点'**
  String get productionMobileCurrentNode;

  /// No description provided for @productionSelectEpisode.
  ///
  /// In zh, this message translates to:
  /// **'选择剧集'**
  String get productionSelectEpisode;

  /// No description provided for @productionNoScripts.
  ///
  /// In zh, this message translates to:
  /// **'暂无剧本，请先在「剧本管理」创建'**
  String get productionNoScripts;

  /// No description provided for @productionGoToScripts.
  ///
  /// In zh, this message translates to:
  /// **'去创建剧本'**
  String get productionGoToScripts;

  /// No description provided for @productionStoryboardGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成分镜'**
  String get productionStoryboardGenerate;

  /// No description provided for @productionStoryboardGenerating.
  ///
  /// In zh, this message translates to:
  /// **'分镜生成中...'**
  String get productionStoryboardGenerating;

  /// No description provided for @productionStoryboardSelectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 个'**
  String productionStoryboardSelectedCount(String count);

  /// No description provided for @productionStoryboardSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get productionStoryboardSelectAll;

  /// No description provided for @productionStoryboardClearSelection.
  ///
  /// In zh, this message translates to:
  /// **'清空选择'**
  String get productionStoryboardClearSelection;

  /// No description provided for @productionStoryboardBatchGenerateImage.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get productionStoryboardBatchGenerateImage;

  /// No description provided for @productionStoryboardDeleteNode.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get productionStoryboardDeleteNode;

  /// No description provided for @productionStoryboardEditNode.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get productionStoryboardEditNode;

  /// No description provided for @productionStoryboardScaleRatio.
  ///
  /// In zh, this message translates to:
  /// **'缩放'**
  String get productionStoryboardScaleRatio;

  /// No description provided for @productionStoryboardNotGenerated.
  ///
  /// In zh, this message translates to:
  /// **'未生成'**
  String get productionStoryboardNotGenerated;

  /// No description provided for @productionStoryboardVideoDesc.
  ///
  /// In zh, this message translates to:
  /// **'画面描述'**
  String get productionStoryboardVideoDesc;

  /// No description provided for @productionStoryboardVideoDescPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入画面描述'**
  String get productionStoryboardVideoDescPlaceholder;

  /// No description provided for @productionStoryboardPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get productionStoryboardPrompt;

  /// No description provided for @productionStoryboardPromptPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入分镜提示词'**
  String get productionStoryboardPromptPlaceholder;

  /// No description provided for @productionStoryboardConfirmDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除该分镜吗？'**
  String get productionStoryboardConfirmDeleteBody;

  /// No description provided for @productionStoryboardConfirmBatchDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除选中的 {count} 个分镜吗？'**
  String productionStoryboardConfirmBatchDeleteBody(String count);

  /// No description provided for @productionStoryboardInsertHint.
  ///
  /// In zh, this message translates to:
  /// **'插入分镜'**
  String get productionStoryboardInsertHint;

  /// No description provided for @productionStoryboardEditImageEntry.
  ///
  /// In zh, this message translates to:
  /// **'节点编辑器'**
  String get productionStoryboardEditImageEntry;

  /// No description provided for @productionChatDisabledHint.
  ///
  /// In zh, this message translates to:
  /// **'Agent 对话在后续批次开放'**
  String get productionChatDisabledHint;

  /// No description provided for @productionEmptyProject.
  ///
  /// In zh, this message translates to:
  /// **'请先选择项目'**
  String get productionEmptyProject;

  /// No description provided for @workbenchTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作台'**
  String get workbenchTitle;

  /// No description provided for @workbenchOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开工作台'**
  String get workbenchOpen;

  /// No description provided for @workbenchGenerateVideo.
  ///
  /// In zh, this message translates to:
  /// **'生成视频'**
  String get workbenchGenerateVideo;

  /// No description provided for @workbenchGenerateAll.
  ///
  /// In zh, this message translates to:
  /// **'全部生成视频'**
  String get workbenchGenerateAll;

  /// No description provided for @workbenchGenerateAllPrompts.
  ///
  /// In zh, this message translates to:
  /// **'全部生成运镜提示词'**
  String get workbenchGenerateAllPrompts;

  /// No description provided for @workbenchClearSelectedTracks.
  ///
  /// In zh, this message translates to:
  /// **'清空已选轨道'**
  String get workbenchClearSelectedTracks;

  /// No description provided for @workbenchClearSelectedTracksConfirm.
  ///
  /// In zh, this message translates to:
  /// **'将清空已勾选镜头的视频轨道与候选视频，分镜本身会保留。'**
  String get workbenchClearSelectedTracksConfirm;

  /// No description provided for @workbenchClearTracksAction.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get workbenchClearTracksAction;

  /// No description provided for @workbenchClearSelectedTracksDone.
  ///
  /// In zh, this message translates to:
  /// **'已清空已选轨道'**
  String get workbenchClearSelectedTracksDone;

  /// No description provided for @workbenchCompose.
  ///
  /// In zh, this message translates to:
  /// **'合成本集'**
  String get workbenchCompose;

  /// No description provided for @workbenchComposing.
  ///
  /// In zh, this message translates to:
  /// **'合成中...'**
  String get workbenchComposing;

  /// No description provided for @workbenchComposeSuccess.
  ///
  /// In zh, this message translates to:
  /// **'合成成功'**
  String get workbenchComposeSuccess;

  /// No description provided for @workbenchComposeMissing.
  ///
  /// In zh, this message translates to:
  /// **'还有 {count} 个镜头未选定视频'**
  String workbenchComposeMissing(String count);

  /// No description provided for @workbenchNoShots.
  ///
  /// In zh, this message translates to:
  /// **'暂无分镜，请先在「制作」的分镜节点生成'**
  String get workbenchNoShots;

  /// No description provided for @workbenchCandidateNotGenerated.
  ///
  /// In zh, this message translates to:
  /// **'未生成'**
  String get workbenchCandidateNotGenerated;

  /// No description provided for @workbenchSelectCandidate.
  ///
  /// In zh, this message translates to:
  /// **'选为正片'**
  String get workbenchSelectCandidate;

  /// No description provided for @workbenchSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选'**
  String get workbenchSelected;

  /// No description provided for @workbenchGeneratePrompt.
  ///
  /// In zh, this message translates to:
  /// **'生成运镜提示词'**
  String get workbenchGeneratePrompt;

  /// No description provided for @workbenchPickClip.
  ///
  /// In zh, this message translates to:
  /// **'素材库'**
  String get workbenchPickClip;

  /// No description provided for @workbenchPickClipTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择素材视频'**
  String get workbenchPickClipTitle;

  /// No description provided for @workbenchNoClipAssets.
  ///
  /// In zh, this message translates to:
  /// **'素材库暂无视频素材'**
  String get workbenchNoClipAssets;

  /// No description provided for @workbenchSaveCandidateToAssets.
  ///
  /// In zh, this message translates to:
  /// **'保存到素材库'**
  String get workbenchSaveCandidateToAssets;

  /// No description provided for @workbenchCandidateClipName.
  ///
  /// In zh, this message translates to:
  /// **'镜头候选 #{videoId}'**
  String workbenchCandidateClipName(int videoId);

  /// No description provided for @workbenchShotAudioLabel.
  ///
  /// In zh, this message translates to:
  /// **'镜头配音'**
  String get workbenchShotAudioLabel;

  /// No description provided for @workbenchShotAudioNone.
  ///
  /// In zh, this message translates to:
  /// **'无配音'**
  String get workbenchShotAudioNone;

  /// No description provided for @workbenchEditPrompt.
  ///
  /// In zh, this message translates to:
  /// **'编辑运镜提示词'**
  String get workbenchEditPrompt;

  /// No description provided for @workbenchOutputPath.
  ///
  /// In zh, this message translates to:
  /// **'输出路径'**
  String get workbenchOutputPath;

  /// No description provided for @workbenchDuration.
  ///
  /// In zh, this message translates to:
  /// **'时长'**
  String get workbenchDuration;

  /// No description provided for @workbenchSavedToAssets.
  ///
  /// In zh, this message translates to:
  /// **'已保存到素材库（素材 #{assetId}）'**
  String workbenchSavedToAssets(int assetId);

  /// No description provided for @workbenchTimelineOverview.
  ///
  /// In zh, this message translates to:
  /// **'时间线总览'**
  String get workbenchTimelineOverview;

  /// No description provided for @workbenchTimelineVideoTrack.
  ///
  /// In zh, this message translates to:
  /// **'视频轨'**
  String get workbenchTimelineVideoTrack;

  /// No description provided for @workbenchTimelineAudioTrack.
  ///
  /// In zh, this message translates to:
  /// **'音频轨'**
  String get workbenchTimelineAudioTrack;

  /// No description provided for @workbenchTimelineOverlayTrack.
  ///
  /// In zh, this message translates to:
  /// **'素材层'**
  String get workbenchTimelineOverlayTrack;

  /// No description provided for @workbenchTimelineMediaLibrary.
  ///
  /// In zh, this message translates to:
  /// **'媒体库'**
  String get workbenchTimelineMediaLibrary;

  /// No description provided for @workbenchTimelineMediaLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'时间线媒体库'**
  String get workbenchTimelineMediaLibraryTitle;

  /// No description provided for @workbenchTimelineAddAtPlayhead.
  ///
  /// In zh, this message translates to:
  /// **'添加到播放头'**
  String get workbenchTimelineAddAtPlayhead;

  /// No description provided for @workbenchTimelineMediaBin.
  ///
  /// In zh, this message translates to:
  /// **'可拖素材'**
  String get workbenchTimelineMediaBin;

  /// No description provided for @workbenchTimelineDraggableClipName.
  ///
  /// In zh, this message translates to:
  /// **'拖放：{name}'**
  String workbenchTimelineDraggableClipName(String name);

  /// No description provided for @workbenchTimelineAddClip.
  ///
  /// In zh, this message translates to:
  /// **'添加素材层'**
  String get workbenchTimelineAddClip;

  /// No description provided for @workbenchTimelineAddClipTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加素材层'**
  String get workbenchTimelineAddClipTitle;

  /// No description provided for @workbenchTimelineAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get workbenchTimelineAdd;

  /// No description provided for @workbenchTimelineAutoLayerAdd.
  ///
  /// In zh, this message translates to:
  /// **'自动层级添加'**
  String get workbenchTimelineAutoLayerAdd;

  /// No description provided for @workbenchTimelineRippleInsert.
  ///
  /// In zh, this message translates to:
  /// **'波纹插入'**
  String get workbenchTimelineRippleInsert;

  /// No description provided for @workbenchTimelineLayer.
  ///
  /// In zh, this message translates to:
  /// **'层级'**
  String get workbenchTimelineLayer;

  /// No description provided for @workbenchTimelineStartMs.
  ///
  /// In zh, this message translates to:
  /// **'起点(ms)'**
  String get workbenchTimelineStartMs;

  /// No description provided for @workbenchTimelineDurationMs.
  ///
  /// In zh, this message translates to:
  /// **'时长(ms)'**
  String get workbenchTimelineDurationMs;

  /// No description provided for @workbenchTimelineClipAdded.
  ///
  /// In zh, this message translates to:
  /// **'素材层已添加'**
  String get workbenchTimelineClipAdded;

  /// No description provided for @workbenchTimelineSplitMidpoint.
  ///
  /// In zh, this message translates to:
  /// **'中点切分'**
  String get workbenchTimelineSplitMidpoint;

  /// No description provided for @workbenchTimelineDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'复制素材层'**
  String get workbenchTimelineDuplicate;

  /// No description provided for @workbenchTimelineRippleDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'波纹复制'**
  String get workbenchTimelineRippleDuplicate;

  /// No description provided for @workbenchTimelineRippleMove.
  ///
  /// In zh, this message translates to:
  /// **'波纹移动'**
  String get workbenchTimelineRippleMove;

  /// No description provided for @workbenchTimelineMoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'移动素材层'**
  String get workbenchTimelineMoveTitle;

  /// No description provided for @workbenchTimelineLaneTitle.
  ///
  /// In zh, this message translates to:
  /// **'移动素材层轨道'**
  String get workbenchTimelineLaneTitle;

  /// No description provided for @workbenchTimelineRippleMoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'波纹移动素材层'**
  String get workbenchTimelineRippleMoveTitle;

  /// No description provided for @workbenchTimelineLane.
  ///
  /// In zh, this message translates to:
  /// **'轨道'**
  String get workbenchTimelineLane;

  /// No description provided for @workbenchTimelineSplitAt.
  ///
  /// In zh, this message translates to:
  /// **'按播放头切分'**
  String get workbenchTimelineSplitAt;

  /// No description provided for @workbenchTimelineSplitAtTitle.
  ///
  /// In zh, this message translates to:
  /// **'按播放头切分素材层'**
  String get workbenchTimelineSplitAtTitle;

  /// No description provided for @workbenchTimelineSplitAtMs.
  ///
  /// In zh, this message translates to:
  /// **'播放头(ms)'**
  String get workbenchTimelineSplitAtMs;

  /// No description provided for @workbenchTimelineSplit.
  ///
  /// In zh, this message translates to:
  /// **'切分'**
  String get workbenchTimelineSplit;

  /// No description provided for @workbenchTimelineRippleTrimEnd.
  ///
  /// In zh, this message translates to:
  /// **'波纹裁剪尾部'**
  String get workbenchTimelineRippleTrimEnd;

  /// No description provided for @workbenchTimelineRippleTrimTitle.
  ///
  /// In zh, this message translates to:
  /// **'波纹裁剪素材层尾部'**
  String get workbenchTimelineRippleTrimTitle;

  /// No description provided for @workbenchTimelineEditClip.
  ///
  /// In zh, this message translates to:
  /// **'编辑素材层属性'**
  String get workbenchTimelineEditClip;

  /// No description provided for @workbenchTimelineEditClipTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑素材层属性'**
  String get workbenchTimelineEditClipTitle;

  /// No description provided for @workbenchTimelineClipActions.
  ///
  /// In zh, this message translates to:
  /// **'素材层操作'**
  String get workbenchTimelineClipActions;

  /// No description provided for @workbenchTimelineDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get workbenchTimelineDelete;

  /// No description provided for @workbenchTimelineRippleDelete.
  ///
  /// In zh, this message translates to:
  /// **'波纹删除'**
  String get workbenchTimelineRippleDelete;

  /// No description provided for @workbenchTimelineSelectedClips.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个素材层'**
  String workbenchTimelineSelectedClips(int count);

  /// No description provided for @workbenchTimelineSplitSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量切分'**
  String get workbenchTimelineSplitSelected;

  /// No description provided for @workbenchTimelineDuplicateSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量复制'**
  String get workbenchTimelineDuplicateSelected;

  /// No description provided for @workbenchTimelineCopyToPlayheadSelected.
  ///
  /// In zh, this message translates to:
  /// **'复制到播放头'**
  String get workbenchTimelineCopyToPlayheadSelected;

  /// No description provided for @workbenchTimelineAlignToPlayheadSelected.
  ///
  /// In zh, this message translates to:
  /// **'对齐播放头'**
  String get workbenchTimelineAlignToPlayheadSelected;

  /// No description provided for @workbenchTimelineRippleDuplicateSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量波纹复制'**
  String get workbenchTimelineRippleDuplicateSelected;

  /// No description provided for @workbenchTimelineMoveSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量移动'**
  String get workbenchTimelineMoveSelected;

  /// No description provided for @workbenchTimelineLaneSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量改轨'**
  String get workbenchTimelineLaneSelected;

  /// No description provided for @workbenchTimelineRippleMoveSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量波纹移动'**
  String get workbenchTimelineRippleMoveSelected;

  /// No description provided for @workbenchTimelineTrimSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量裁剪'**
  String get workbenchTimelineTrimSelected;

  /// No description provided for @workbenchTimelineTrimTitle.
  ///
  /// In zh, this message translates to:
  /// **'裁剪素材层尾部'**
  String get workbenchTimelineTrimTitle;

  /// No description provided for @workbenchTimelineRippleTrimSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量波纹裁剪'**
  String get workbenchTimelineRippleTrimSelected;

  /// No description provided for @workbenchTimelineDeleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get workbenchTimelineDeleteSelected;

  /// No description provided for @workbenchTimelineRippleDeleteSelected.
  ///
  /// In zh, this message translates to:
  /// **'批量波纹删除'**
  String get workbenchTimelineRippleDeleteSelected;

  /// No description provided for @workbenchTimelineUnselected.
  ///
  /// In zh, this message translates to:
  /// **'未选视频'**
  String get workbenchTimelineUnselected;

  /// No description provided for @workbenchTimelineNoAudio.
  ///
  /// In zh, this message translates to:
  /// **'未绑定配音'**
  String get workbenchTimelineNoAudio;

  /// No description provided for @workbenchReorderShot.
  ///
  /// In zh, this message translates to:
  /// **'拖拽调整顺序'**
  String get workbenchReorderShot;

  /// No description provided for @cornerScapeTitle.
  ///
  /// In zh, this message translates to:
  /// **'配音'**
  String get cornerScapeTitle;

  /// No description provided for @cornerScapeAutoMatch.
  ///
  /// In zh, this message translates to:
  /// **'AI 自动匹配'**
  String get cornerScapeAutoMatch;

  /// No description provided for @cornerScapeAutoMatching.
  ///
  /// In zh, this message translates to:
  /// **'匹配中...'**
  String get cornerScapeAutoMatching;

  /// No description provided for @cornerScapeSelectAudio.
  ///
  /// In zh, this message translates to:
  /// **'选择音频'**
  String get cornerScapeSelectAudio;

  /// No description provided for @cornerScapeNoAudio.
  ///
  /// In zh, this message translates to:
  /// **'未绑定'**
  String get cornerScapeNoAudio;

  /// No description provided for @cornerScapeNoAudioPool.
  ///
  /// In zh, this message translates to:
  /// **'暂无音频素材，请先在「资产中心」上传音频'**
  String get cornerScapeNoAudioPool;

  /// No description provided for @cornerScapeNoRoles.
  ///
  /// In zh, this message translates to:
  /// **'暂无角色资产，请先在「资产中心」创建角色'**
  String get cornerScapeNoRoles;

  /// No description provided for @cornerScapeSelectAtLeastOne.
  ///
  /// In zh, this message translates to:
  /// **'请至少选择一个角色'**
  String get cornerScapeSelectAtLeastOne;

  /// No description provided for @cornerScapeBindSuccess.
  ///
  /// In zh, this message translates to:
  /// **'绑定成功'**
  String get cornerScapeBindSuccess;

  /// No description provided for @cornerScapeUnbind.
  ///
  /// In zh, this message translates to:
  /// **'解除绑定'**
  String get cornerScapeUnbind;

  /// No description provided for @promptStoryboardGenTitle.
  ///
  /// In zh, this message translates to:
  /// **'分镜生成'**
  String get promptStoryboardGenTitle;

  /// No description provided for @promptStoryboardGenDescription.
  ///
  /// In zh, this message translates to:
  /// **'将剧本拆解为分镜镜头列表的提示词'**
  String get promptStoryboardGenDescription;

  /// No description provided for @promptVideoPromptGenTitle.
  ///
  /// In zh, this message translates to:
  /// **'运镜提示词生成'**
  String get promptVideoPromptGenTitle;

  /// No description provided for @promptVideoPromptGenDescription.
  ///
  /// In zh, this message translates to:
  /// **'将分镜画面转换为图生视频运镜提示词'**
  String get promptVideoPromptGenDescription;

  /// No description provided for @promptAudioBindTitle.
  ///
  /// In zh, this message translates to:
  /// **'配音匹配'**
  String get promptAudioBindTitle;

  /// No description provided for @promptAudioBindDescription.
  ///
  /// In zh, this message translates to:
  /// **'按角色描述匹配最合适音色的提示词'**
  String get promptAudioBindDescription;

  /// No description provided for @promptEventAnalysisTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件分析'**
  String get promptEventAnalysisTitle;

  /// No description provided for @promptEventAnalysisDescription.
  ///
  /// In zh, this message translates to:
  /// **'分析章节事件改编价值的提示词'**
  String get promptEventAnalysisDescription;

  /// No description provided for @stageEventExtractTitle.
  ///
  /// In zh, this message translates to:
  /// **'事件提取'**
  String get stageEventExtractTitle;

  /// No description provided for @stageEventExtractDescription.
  ///
  /// In zh, this message translates to:
  /// **'从章节内容提取结构化事件摘要'**
  String get stageEventExtractDescription;

  /// No description provided for @stageVideoPromptGenTitle.
  ///
  /// In zh, this message translates to:
  /// **'运镜提示词生成'**
  String get stageVideoPromptGenTitle;

  /// No description provided for @stageVideoPromptGenDescription.
  ///
  /// In zh, this message translates to:
  /// **'将分镜描述转换为图生视频提示词'**
  String get stageVideoPromptGenDescription;

  /// No description provided for @stageScriptGenTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本生成'**
  String get stageScriptGenTitle;

  /// No description provided for @stageScriptGenDescription.
  ///
  /// In zh, this message translates to:
  /// **'把小说改编为短剧剧本'**
  String get stageScriptGenDescription;

  /// No description provided for @stageAssetExtractTitle.
  ///
  /// In zh, this message translates to:
  /// **'素材提取'**
  String get stageAssetExtractTitle;

  /// No description provided for @stageAssetExtractDescription.
  ///
  /// In zh, this message translates to:
  /// **'从剧本提取角色、场景和道具'**
  String get stageAssetExtractDescription;

  /// No description provided for @stageStoryboardGenTitle.
  ///
  /// In zh, this message translates to:
  /// **'分镜生成'**
  String get stageStoryboardGenTitle;

  /// No description provided for @stageStoryboardGenDescription.
  ///
  /// In zh, this message translates to:
  /// **'按集拆解镜头与镜头提示词'**
  String get stageStoryboardGenDescription;

  /// No description provided for @stageAssetImageTitle.
  ///
  /// In zh, this message translates to:
  /// **'素材图生成'**
  String get stageAssetImageTitle;

  /// No description provided for @stageAssetImageDescription.
  ///
  /// In zh, this message translates to:
  /// **'生成角色、场景、道具资产图'**
  String get stageAssetImageDescription;

  /// No description provided for @stageShotImageTitle.
  ///
  /// In zh, this message translates to:
  /// **'镜头图生成'**
  String get stageShotImageTitle;

  /// No description provided for @stageShotImageDescription.
  ///
  /// In zh, this message translates to:
  /// **'生成每个镜头的静帧画面'**
  String get stageShotImageDescription;

  /// No description provided for @stageShotVideoTitle.
  ///
  /// In zh, this message translates to:
  /// **'镜头视频生成'**
  String get stageShotVideoTitle;

  /// No description provided for @stageShotVideoDescription.
  ///
  /// In zh, this message translates to:
  /// **'从镜头图生成短视频片段'**
  String get stageShotVideoDescription;

  /// No description provided for @stageTtsTitle.
  ///
  /// In zh, this message translates to:
  /// **'配音生成'**
  String get stageTtsTitle;

  /// No description provided for @stageTtsDescription.
  ///
  /// In zh, this message translates to:
  /// **'为镜头台词生成语音'**
  String get stageTtsDescription;

  /// No description provided for @stageBindingUpdated.
  ///
  /// In zh, this message translates to:
  /// **'{title}绑定已更新'**
  String stageBindingUpdated(String title);

  /// No description provided for @stageBindingMissing.
  ///
  /// In zh, this message translates to:
  /// **'未绑定可用模型'**
  String get stageBindingMissing;

  /// No description provided for @agentChatTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本 Agent'**
  String get agentChatTitle;

  /// No description provided for @agentChatInputPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'告诉我你想推进哪一步，或直接问\"现在进度如何\"'**
  String get agentChatInputPlaceholder;

  /// No description provided for @agentChatSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get agentChatSend;

  /// No description provided for @agentChatThinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中...'**
  String get agentChatThinking;

  /// No description provided for @agentChatAutoMode.
  ///
  /// In zh, this message translates to:
  /// **'自动连跑'**
  String get agentChatAutoMode;

  /// No description provided for @agentChatManualMode.
  ///
  /// In zh, this message translates to:
  /// **'手动确认'**
  String get agentChatManualMode;

  /// No description provided for @agentChatClearMemory.
  ///
  /// In zh, this message translates to:
  /// **'清空记忆'**
  String get agentChatClearMemory;

  /// No description provided for @agentChatConfirmClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空记忆'**
  String get agentChatConfirmClearTitle;

  /// No description provided for @agentChatConfirmClearBody.
  ///
  /// In zh, this message translates to:
  /// **'确定清空全部对话记录吗？此操作无法撤销。'**
  String get agentChatConfirmClearBody;

  /// No description provided for @agentChatMemoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'记忆已清空'**
  String get agentChatMemoryCleared;

  /// No description provided for @agentChatWelcome.
  ///
  /// In zh, this message translates to:
  /// **'你好，我是剧本 Agent。我可以帮你推进事件提取、资产提取、分镜生成、首帧图、视频生成、配音绑定和最终合成。直接告诉我你想做什么，或者问我\"现在进度如何\"。'**
  String get agentChatWelcome;

  /// No description provided for @agentChatToolExecuted.
  ///
  /// In zh, this message translates to:
  /// **'已执行：{tool}'**
  String agentChatToolExecuted(String tool);

  /// No description provided for @agentChatModeHint.
  ///
  /// In zh, this message translates to:
  /// **'手动模式每次只执行一步并等待你确认；自动模式会连续执行工具链（安全上限内）。'**
  String get agentChatModeHint;

  /// No description provided for @agentChatSkillsInfo.
  ///
  /// In zh, this message translates to:
  /// **'内置能力'**
  String get agentChatSkillsInfo;

  /// No description provided for @agentChatSkillsBody.
  ///
  /// In zh, this message translates to:
  /// **'我可以调用的能力包括已有流水线真实动作，也可以调用本地自定义技能。流水线动作会在「任务中心」留下可查看、可重试的任务记录；自定义技能目前支持 v1 JS return 模板。'**
  String get agentChatSkillsBody;

  /// No description provided for @agentTabChat.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get agentTabChat;

  /// No description provided for @agentTabDeploy.
  ///
  /// In zh, this message translates to:
  /// **'部署'**
  String get agentTabDeploy;

  /// No description provided for @agentTabSkills.
  ///
  /// In zh, this message translates to:
  /// **'技能'**
  String get agentTabSkills;

  /// No description provided for @agentTabMemory.
  ///
  /// In zh, this message translates to:
  /// **'记忆'**
  String get agentTabMemory;

  /// No description provided for @agentDeployExecutionMode.
  ///
  /// In zh, this message translates to:
  /// **'执行模式'**
  String get agentDeployExecutionMode;

  /// No description provided for @agentDeployModeSaved.
  ///
  /// In zh, this message translates to:
  /// **'此设置会保存为项目内 Agent 默认执行方式'**
  String get agentDeployModeSaved;

  /// No description provided for @agentDeployStagesTitle.
  ///
  /// In zh, this message translates to:
  /// **'阶段部署'**
  String get agentDeployStagesTitle;

  /// No description provided for @agentDeployStagesHint.
  ///
  /// In zh, this message translates to:
  /// **'为 Agent 各阶段指定文本模型与调用参数；启用后优先覆盖普通模型绑定。'**
  String get agentDeployStagesHint;

  /// No description provided for @agentDeployModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get agentDeployModel;

  /// No description provided for @agentDeployMaxTokens.
  ///
  /// In zh, this message translates to:
  /// **'最大输出'**
  String get agentDeployMaxTokens;

  /// No description provided for @agentDeployTemperature.
  ///
  /// In zh, this message translates to:
  /// **'温度 x100'**
  String get agentDeployTemperature;

  /// No description provided for @agentDeploySaved.
  ///
  /// In zh, this message translates to:
  /// **'Agent 部署已保存'**
  String get agentDeploySaved;

  /// No description provided for @agentSkillsBuiltinTitle.
  ///
  /// In zh, this message translates to:
  /// **'内置技能'**
  String get agentSkillsBuiltinTitle;

  /// No description provided for @agentSkillsEditableHint.
  ///
  /// In zh, this message translates to:
  /// **'技能定义保存在本地 o_skillList，可编辑说明与启停状态；工具名保持固定，确保任务中心可追踪、可重试。'**
  String get agentSkillsEditableHint;

  /// No description provided for @agentSkillEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑技能'**
  String get agentSkillEditTitle;

  /// No description provided for @agentSkillDescription.
  ///
  /// In zh, this message translates to:
  /// **'技能说明'**
  String get agentSkillDescription;

  /// No description provided for @agentSkillEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用技能'**
  String get agentSkillEnabled;

  /// No description provided for @agentSkillEnabledTag.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get agentSkillEnabledTag;

  /// No description provided for @agentSkillDisabledTag.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get agentSkillDisabledTag;

  /// No description provided for @agentCustomSkillAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增自定义技能'**
  String get agentCustomSkillAdd;

  /// No description provided for @agentCustomSkillCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增自定义技能'**
  String get agentCustomSkillCreateTitle;

  /// No description provided for @agentCustomSkillEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑自定义技能'**
  String get agentCustomSkillEditTitle;

  /// No description provided for @agentCustomSkillId.
  ///
  /// In zh, this message translates to:
  /// **'工具 ID'**
  String get agentCustomSkillId;

  /// No description provided for @agentCustomSkillName.
  ///
  /// In zh, this message translates to:
  /// **'技能名称'**
  String get agentCustomSkillName;

  /// No description provided for @agentCustomSkillSchema.
  ///
  /// In zh, this message translates to:
  /// **'参数 Schema JSON'**
  String get agentCustomSkillSchema;

  /// No description provided for @agentCustomSkillScript.
  ///
  /// In zh, this message translates to:
  /// **'脚本'**
  String get agentCustomSkillScript;

  /// No description provided for @agentCustomSkillScriptHint.
  ///
  /// In zh, this message translates to:
  /// **'v1 支持 return 字符串、args.xxx、projectId、JSON.stringify(args) 与模板字符串。'**
  String get agentCustomSkillScriptHint;

  /// No description provided for @agentCustomSkillInvalidSchema.
  ///
  /// In zh, this message translates to:
  /// **'Schema 必须是 JSON 对象'**
  String get agentCustomSkillInvalidSchema;

  /// No description provided for @agentCustomSkillSaved.
  ///
  /// In zh, this message translates to:
  /// **'自定义技能已保存'**
  String get agentCustomSkillSaved;

  /// No description provided for @agentCustomSkillTag.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get agentCustomSkillTag;

  /// No description provided for @agentMemoryCount.
  ///
  /// In zh, this message translates to:
  /// **'记忆条目 {count}'**
  String agentMemoryCount(int count);

  /// No description provided for @agentMemoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无记忆。发送消息后会在这里显示可检查的上下文记录。'**
  String get agentMemoryEmpty;

  /// No description provided for @agentLongTermMemoryCount.
  ///
  /// In zh, this message translates to:
  /// **'长期记忆 {count}'**
  String agentLongTermMemoryCount(int count);

  /// No description provided for @agentLongTermMemoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无长期记忆。可以把角色设定、禁忌写法、世界观规则保存到这里。'**
  String get agentLongTermMemoryEmpty;

  /// No description provided for @agentMemoryAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增记忆'**
  String get agentMemoryAdd;

  /// No description provided for @agentMemoryCreateTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增长期记忆'**
  String get agentMemoryCreateTitle;

  /// No description provided for @agentMemoryEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑长期记忆'**
  String get agentMemoryEditTitle;

  /// No description provided for @agentMemoryName.
  ///
  /// In zh, this message translates to:
  /// **'记忆名称'**
  String get agentMemoryName;

  /// No description provided for @agentMemoryContent.
  ///
  /// In zh, this message translates to:
  /// **'记忆内容'**
  String get agentMemoryContent;

  /// No description provided for @agentMemorySaved.
  ///
  /// In zh, this message translates to:
  /// **'长期记忆已保存'**
  String get agentMemorySaved;

  /// No description provided for @agentMemoryUpdated.
  ///
  /// In zh, this message translates to:
  /// **'长期记忆已更新'**
  String get agentMemoryUpdated;

  /// No description provided for @agentMemoryDeleted.
  ///
  /// In zh, this message translates to:
  /// **'长期记忆已删除'**
  String get agentMemoryDeleted;

  /// No description provided for @cornerScapeSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索角色名称'**
  String get cornerScapeSearchHint;

  /// No description provided for @cornerScapeFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get cornerScapeFilterAll;

  /// No description provided for @cornerScapeFilterBound.
  ///
  /// In zh, this message translates to:
  /// **'已绑定'**
  String get cornerScapeFilterBound;

  /// No description provided for @cornerScapeFilterUnbound.
  ///
  /// In zh, this message translates to:
  /// **'未绑定'**
  String get cornerScapeFilterUnbound;

  /// No description provided for @cornerScapeSelectAllUnbound.
  ///
  /// In zh, this message translates to:
  /// **'全选未绑定'**
  String get cornerScapeSelectAllUnbound;

  /// No description provided for @cornerScapeBoundSummary.
  ///
  /// In zh, this message translates to:
  /// **'已绑定 {bound}/{total}'**
  String cornerScapeBoundSummary(int bound, int total);

  /// No description provided for @cornerScapeNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有符合筛选条件的角色'**
  String get cornerScapeNoMatch;

  /// No description provided for @storyboardPreviewAll.
  ///
  /// In zh, this message translates to:
  /// **'预览全部'**
  String get storyboardPreviewAll;

  /// No description provided for @storyboardPreviewEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无分镜可预览'**
  String get storyboardPreviewEmpty;

  /// No description provided for @storyboardPreviewImageMissing.
  ///
  /// In zh, this message translates to:
  /// **'图片加载失败'**
  String get storyboardPreviewImageMissing;

  /// No description provided for @storyboardPreviewCounter.
  ///
  /// In zh, this message translates to:
  /// **'{shot}（{current}/{total}）'**
  String storyboardPreviewCounter(String shot, String current, String total);

  /// No description provided for @storyboardPreviewShotPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'{shot} 尚未生成首帧图'**
  String storyboardPreviewShotPlaceholder(String shot);

  /// No description provided for @storyboardExportAll.
  ///
  /// In zh, this message translates to:
  /// **'导出全部'**
  String get storyboardExportAll;

  /// No description provided for @storyboardExportNoImages.
  ///
  /// In zh, this message translates to:
  /// **'还没有可导出的首帧图'**
  String get storyboardExportNoImages;

  /// No description provided for @storyboardExportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {count} 张首帧图'**
  String storyboardExportSuccess(String count);

  /// No description provided for @storyboardExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{reason}'**
  String storyboardExportFailed(String reason);

  /// No description provided for @scriptPlanEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有剧本规划，点此撰写整体思路、节奏与要点。'**
  String get scriptPlanEmpty;

  /// No description provided for @scriptPlanWrite.
  ///
  /// In zh, this message translates to:
  /// **'撰写规划'**
  String get scriptPlanWrite;

  /// No description provided for @scriptPlanEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑剧本规划'**
  String get scriptPlanEditTitle;

  /// No description provided for @scriptPlanEditHint.
  ///
  /// In zh, this message translates to:
  /// **'用 Markdown 记录本项目的整体规划：主线、人物弧光、分集节奏、风格基调……'**
  String get scriptPlanEditHint;

  /// No description provided for @scriptPlanSaved.
  ///
  /// In zh, this message translates to:
  /// **'剧本规划已保存'**
  String get scriptPlanSaved;

  /// No description provided for @canvasChatTitle.
  ///
  /// In zh, this message translates to:
  /// **'剧本 Agent'**
  String get canvasChatTitle;

  /// No description provided for @canvasChatOpen.
  ///
  /// In zh, this message translates to:
  /// **'Agent 对话'**
  String get canvasChatOpen;

  /// No description provided for @canvasChatClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get canvasChatClose;

  /// No description provided for @imageEditorModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get imageEditorModel;

  /// No description provided for @imageEditorRatio.
  ///
  /// In zh, this message translates to:
  /// **'比例'**
  String get imageEditorRatio;

  /// No description provided for @imageEditorQuality.
  ///
  /// In zh, this message translates to:
  /// **'质量'**
  String get imageEditorQuality;

  /// No description provided for @imageEditorSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'请先选择模型'**
  String get imageEditorSelectModel;

  /// No description provided for @imageEditorSelectQuality.
  ///
  /// In zh, this message translates to:
  /// **'请选择画质'**
  String get imageEditorSelectQuality;

  /// No description provided for @imageEditorSelectRatio.
  ///
  /// In zh, this message translates to:
  /// **'请选择比例'**
  String get imageEditorSelectRatio;

  /// No description provided for @imageEditorNoImageModel.
  ///
  /// In zh, this message translates to:
  /// **'暂无可用图片模型'**
  String get imageEditorNoImageModel;

  /// No description provided for @novelGenerateSelectedEvents.
  ///
  /// In zh, this message translates to:
  /// **'生成事件'**
  String get novelGenerateSelectedEvents;

  /// No description provided for @scriptBatchAddMsgOverLimit.
  ///
  /// In zh, this message translates to:
  /// **'存在超出单集字数上限（{limit}）的分集，请取消勾选或缩短内容'**
  String scriptBatchAddMsgOverLimit(String limit);

  /// No description provided for @artStyleLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'画风库'**
  String get artStyleLibraryTitle;

  /// No description provided for @artStyleManage.
  ///
  /// In zh, this message translates to:
  /// **'管理画风库'**
  String get artStyleManage;

  /// No description provided for @artStyleAddTitle.
  ///
  /// In zh, this message translates to:
  /// **'新增画风'**
  String get artStyleAddTitle;

  /// No description provided for @artStyleEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑画风'**
  String get artStyleEditTitle;

  /// No description provided for @artStyleName.
  ///
  /// In zh, this message translates to:
  /// **'画风名称'**
  String get artStyleName;

  /// No description provided for @artStyleNamePh.
  ///
  /// In zh, this message translates to:
  /// **'如：2D 动漫、照片写实、3D 国创'**
  String get artStyleNamePh;

  /// No description provided for @artStylePrompt.
  ///
  /// In zh, this message translates to:
  /// **'画风提示词'**
  String get artStylePrompt;

  /// No description provided for @artStylePromptPh.
  ///
  /// In zh, this message translates to:
  /// **'如：(画风：2D动漫风格,2d animation style)'**
  String get artStylePromptPh;

  /// No description provided for @artStyleCover.
  ///
  /// In zh, this message translates to:
  /// **'封面图'**
  String get artStyleCover;

  /// No description provided for @artStyleUploadCover.
  ///
  /// In zh, this message translates to:
  /// **'上传封面'**
  String get artStyleUploadCover;

  /// No description provided for @artStyleNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写画风名称'**
  String get artStyleNameRequired;

  /// No description provided for @artStyleAddSuccess.
  ///
  /// In zh, this message translates to:
  /// **'画风添加成功'**
  String get artStyleAddSuccess;

  /// No description provided for @artStyleEditSuccess.
  ///
  /// In zh, this message translates to:
  /// **'画风编辑成功'**
  String get artStyleEditSuccess;

  /// No description provided for @artStyleDeleted.
  ///
  /// In zh, this message translates to:
  /// **'画风已删除'**
  String get artStyleDeleted;

  /// No description provided for @artStyleDeleteHeader.
  ///
  /// In zh, this message translates to:
  /// **'删除画风'**
  String get artStyleDeleteHeader;

  /// No description provided for @artStyleDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除画风「{name}」吗？'**
  String artStyleDeleteBody(String name);

  /// No description provided for @artStyleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有画风，点击上方新增。'**
  String get artStyleEmpty;

  /// No description provided for @artStyleClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get artStyleClose;

  /// No description provided for @clipUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传素材'**
  String get clipUpload;

  /// No description provided for @clipUploadTitle.
  ///
  /// In zh, this message translates to:
  /// **'上传素材文件'**
  String get clipUploadTitle;

  /// No description provided for @clipPickFile.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get clipPickFile;

  /// No description provided for @clipNoFile.
  ///
  /// In zh, this message translates to:
  /// **'尚未选择文件'**
  String get clipNoFile;

  /// No description provided for @clipName.
  ///
  /// In zh, this message translates to:
  /// **'素材名称'**
  String get clipName;

  /// No description provided for @clipNamePh.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用文件名'**
  String get clipNamePh;

  /// No description provided for @clipUploadSuccess.
  ///
  /// In zh, this message translates to:
  /// **'素材上传成功'**
  String get clipUploadSuccess;

  /// No description provided for @clipUploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'素材上传失败'**
  String get clipUploadFailed;

  /// No description provided for @assetBatchModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get assetBatchModel;

  /// No description provided for @assetBatchResolution.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get assetBatchResolution;

  /// No description provided for @assetBatchConcurrency.
  ///
  /// In zh, this message translates to:
  /// **'并发数'**
  String get assetBatchConcurrency;

  /// No description provided for @assetBatchConcurrencyPh.
  ///
  /// In zh, this message translates to:
  /// **'1-8'**
  String get assetBatchConcurrencyPh;

  /// No description provided for @assetBatchOtherPrompt.
  ///
  /// In zh, this message translates to:
  /// **'补充提示词'**
  String get assetBatchOtherPrompt;

  /// No description provided for @assetBatchOtherPromptPh.
  ///
  /// In zh, this message translates to:
  /// **'追加到润色系统提示词（可选）'**
  String get assetBatchOtherPromptPh;

  /// No description provided for @assetBatchPickModel.
  ///
  /// In zh, this message translates to:
  /// **'使用阶段默认'**
  String get assetBatchPickModel;

  /// No description provided for @manualImportFile.
  ///
  /// In zh, this message translates to:
  /// **'导入文件'**
  String get manualImportFile;

  /// No description provided for @manualImportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'文件已导入到当前标签'**
  String get manualImportSuccess;

  /// No description provided for @manualImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件导入失败'**
  String get manualImportFailed;

  /// No description provided for @storyboardTableEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有分镜表，点此撰写镜头拆解、时长与画面要点。'**
  String get storyboardTableEmpty;

  /// No description provided for @storyboardTableWrite.
  ///
  /// In zh, this message translates to:
  /// **'撰写分镜表'**
  String get storyboardTableWrite;

  /// No description provided for @storyboardTableEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑分镜表'**
  String get storyboardTableEditTitle;

  /// No description provided for @storyboardTableEditHint.
  ///
  /// In zh, this message translates to:
  /// **'用 Markdown 记录本集的分镜拆解：镜头序号、画面、运镜、时长……'**
  String get storyboardTableEditHint;

  /// No description provided for @storyboardTableSaved.
  ///
  /// In zh, this message translates to:
  /// **'分镜表已保存'**
  String get storyboardTableSaved;

  /// No description provided for @scriptNodeEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑剧本'**
  String get scriptNodeEditTitle;

  /// No description provided for @scriptNodeName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get scriptNodeName;

  /// No description provided for @scriptNodeNamePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本名称'**
  String get scriptNodeNamePlaceholder;

  /// No description provided for @scriptNodeContent.
  ///
  /// In zh, this message translates to:
  /// **'正文'**
  String get scriptNodeContent;

  /// No description provided for @scriptNodeContentPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本正文'**
  String get scriptNodeContentPlaceholder;

  /// No description provided for @scriptNodeNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入剧本名称'**
  String get scriptNodeNameRequired;

  /// No description provided for @scriptNodeSaved.
  ///
  /// In zh, this message translates to:
  /// **'剧本已保存'**
  String get scriptNodeSaved;

  /// No description provided for @productionStoryboardInsertBefore.
  ///
  /// In zh, this message translates to:
  /// **'在前面插入分镜'**
  String get productionStoryboardInsertBefore;

  /// No description provided for @imageEditorPickFromAssets.
  ///
  /// In zh, this message translates to:
  /// **'从素材库选择'**
  String get imageEditorPickFromAssets;

  /// No description provided for @imageEditorPickFromStoryboard.
  ///
  /// In zh, this message translates to:
  /// **'从分镜选择'**
  String get imageEditorPickFromStoryboard;

  /// No description provided for @imageEditorPickImageTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择参考图'**
  String get imageEditorPickImageTitle;

  /// No description provided for @imageEditorPickImageSource.
  ///
  /// In zh, this message translates to:
  /// **'选择图片来源'**
  String get imageEditorPickImageSource;

  /// No description provided for @imageEditorPickLocalFile.
  ///
  /// In zh, this message translates to:
  /// **'本地文件'**
  String get imageEditorPickLocalFile;

  /// No description provided for @imageEditorNoAssetsImages.
  ///
  /// In zh, this message translates to:
  /// **'素材库暂无已生成图片'**
  String get imageEditorNoAssetsImages;

  /// No description provided for @imageEditorNoStoryboardImages.
  ///
  /// In zh, this message translates to:
  /// **'分镜暂无已生成首帧图'**
  String get imageEditorNoStoryboardImages;

  /// No description provided for @imageEditorRemoveEdge.
  ///
  /// In zh, this message translates to:
  /// **'删除该连线'**
  String get imageEditorRemoveEdge;

  /// No description provided for @imageEditorEdgeRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已删除连线'**
  String get imageEditorEdgeRemoved;

  /// No description provided for @workbenchPlayVideo.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get workbenchPlayVideo;

  /// No description provided for @workbenchVideoLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'视频加载失败'**
  String get workbenchVideoLoadFailed;

  /// No description provided for @workbenchDeleteCandidate.
  ///
  /// In zh, this message translates to:
  /// **'删除候选'**
  String get workbenchDeleteCandidate;

  /// No description provided for @workbenchDeleteCandidateConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除该候选视频？'**
  String get workbenchDeleteCandidateConfirm;

  /// No description provided for @workbenchSelectAsMain.
  ///
  /// In zh, this message translates to:
  /// **'选为正片'**
  String get workbenchSelectAsMain;

  /// No description provided for @workbenchDurationSection.
  ///
  /// In zh, this message translates to:
  /// **'本镜时长'**
  String get workbenchDurationSection;

  /// No description provided for @workbenchDurationUnset.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get workbenchDurationUnset;

  /// No description provided for @workbenchDurationSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String workbenchDurationSeconds(int seconds);

  /// No description provided for @workbenchEditDurationTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑本镜时长'**
  String get workbenchEditDurationTitle;

  /// No description provided for @workbenchDurationFieldLabel.
  ///
  /// In zh, this message translates to:
  /// **'时长（秒）'**
  String get workbenchDurationFieldLabel;

  /// No description provided for @workbenchEditPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑运镜提示词'**
  String get workbenchEditPromptTitle;

  /// No description provided for @workbenchPromptFieldHint.
  ///
  /// In zh, this message translates to:
  /// **'描述这一镜的运镜与动作'**
  String get workbenchPromptFieldHint;

  /// No description provided for @workbenchPromptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无运镜提示词，点击生成或编辑'**
  String get workbenchPromptEmpty;

  /// No description provided for @workbenchTransitionNone.
  ///
  /// In zh, this message translates to:
  /// **'无转场'**
  String get workbenchTransitionNone;

  /// No description provided for @workbenchTransitionFade.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出'**
  String get workbenchTransitionFade;

  /// No description provided for @workbenchTransitionDissolve.
  ///
  /// In zh, this message translates to:
  /// **'叠化'**
  String get workbenchTransitionDissolve;

  /// No description provided for @workbenchTransitionWhipPan.
  ///
  /// In zh, this message translates to:
  /// **'甩镜'**
  String get workbenchTransitionWhipPan;

  /// No description provided for @workbenchFilterNone.
  ///
  /// In zh, this message translates to:
  /// **'无滤镜'**
  String get workbenchFilterNone;

  /// No description provided for @workbenchFilterCinematic.
  ///
  /// In zh, this message translates to:
  /// **'电影感'**
  String get workbenchFilterCinematic;

  /// No description provided for @workbenchFilterWarm.
  ///
  /// In zh, this message translates to:
  /// **'暖色'**
  String get workbenchFilterWarm;

  /// No description provided for @workbenchFilterCool.
  ///
  /// In zh, this message translates to:
  /// **'冷色'**
  String get workbenchFilterCool;

  /// No description provided for @workbenchFilterVintage.
  ///
  /// In zh, this message translates to:
  /// **'复古'**
  String get workbenchFilterVintage;

  /// No description provided for @cornerScapeAudition.
  ///
  /// In zh, this message translates to:
  /// **'试听'**
  String get cornerScapeAudition;

  /// No description provided for @cornerScapeStopAudition.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get cornerScapeStopAudition;

  /// No description provided for @cornerScapeAudioMissing.
  ///
  /// In zh, this message translates to:
  /// **'音频文件缺失'**
  String get cornerScapeAudioMissing;

  /// No description provided for @cornerScapeAuditionFailed.
  ///
  /// In zh, this message translates to:
  /// **'音频播放失败'**
  String get cornerScapeAuditionFailed;

  /// No description provided for @settingsOtherSection.
  ///
  /// In zh, this message translates to:
  /// **'其他设置'**
  String get settingsOtherSection;

  /// No description provided for @settingsOtherTitle.
  ///
  /// In zh, this message translates to:
  /// **'其他设置'**
  String get settingsOtherTitle;

  /// No description provided for @settingsOtherChapterReg.
  ///
  /// In zh, this message translates to:
  /// **'章节切分正则'**
  String get settingsOtherChapterReg;

  /// No description provided for @settingsOtherChapterRegHint.
  ///
  /// In zh, this message translates to:
  /// **'留空则使用内置默认章节正则'**
  String get settingsOtherChapterRegHint;

  /// No description provided for @settingsOtherChapterRegRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认'**
  String get settingsOtherChapterRegRestore;

  /// No description provided for @settingsOtherEpisodeLength.
  ///
  /// In zh, this message translates to:
  /// **'单集字数上限'**
  String get settingsOtherEpisodeLength;

  /// No description provided for @settingsOtherBatchSize.
  ///
  /// In zh, this message translates to:
  /// **'批量生成数量'**
  String get settingsOtherBatchSize;

  /// No description provided for @settingsOtherSaved.
  ///
  /// In zh, this message translates to:
  /// **'其他设置已保存'**
  String get settingsOtherSaved;

  /// No description provided for @settingsOtherInvalidNumber.
  ///
  /// In zh, this message translates to:
  /// **'请输入大于 0 的整数'**
  String get settingsOtherInvalidNumber;

  /// No description provided for @settingsStorageOpenFolder.
  ///
  /// In zh, this message translates to:
  /// **'打开数据目录'**
  String get settingsStorageOpenFolder;

  /// No description provided for @settingsStorageOpenFolderFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开数据目录：{reason}'**
  String settingsStorageOpenFolderFailed(String reason);

  /// No description provided for @settingsStorageDbInfo.
  ///
  /// In zh, this message translates to:
  /// **'数据库信息'**
  String get settingsStorageDbInfo;

  /// No description provided for @settingsStorageDbInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'数据库信息'**
  String get settingsStorageDbInfoTitle;

  /// No description provided for @settingsStorageTableColumn.
  ///
  /// In zh, this message translates to:
  /// **'数据表'**
  String get settingsStorageTableColumn;

  /// No description provided for @settingsStorageRowsColumn.
  ///
  /// In zh, this message translates to:
  /// **'行数'**
  String get settingsStorageRowsColumn;

  /// No description provided for @settingsStorageClear.
  ///
  /// In zh, this message translates to:
  /// **'清空数据'**
  String get settingsStorageClear;

  /// No description provided for @settingsStorageClearConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清空所有数据'**
  String get settingsStorageClearConfirmTitle;

  /// No description provided for @settingsStorageClearConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'此操作会删除全部项目、章节、剧本、资产、任务与媒体文件，且不可恢复。确定继续吗？'**
  String get settingsStorageClearConfirmBody;

  /// No description provided for @settingsStorageClearDone.
  ///
  /// In zh, this message translates to:
  /// **'数据已清空'**
  String get settingsStorageClearDone;

  /// No description provided for @settingsAboutSection.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAboutSection;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In zh, this message translates to:
  /// **'关于 DramaFlow'**
  String get settingsAboutTitle;

  /// No description provided for @settingsAboutAppName.
  ///
  /// In zh, this message translates to:
  /// **'应用名称'**
  String get settingsAboutAppName;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get settingsAboutVersion;

  /// No description provided for @settingsAboutEngine.
  ///
  /// In zh, this message translates to:
  /// **'引擎版本'**
  String get settingsAboutEngine;

  /// No description provided for @settingsAboutDescription.
  ///
  /// In zh, this message translates to:
  /// **'DramaFlow 是本机运行的 AI 短剧创作工作台，数据与媒体全部保存在本机。'**
  String get settingsAboutDescription;

  /// No description provided for @settingsProviderTestKind.
  ///
  /// In zh, this message translates to:
  /// **'模态'**
  String get settingsProviderTestKind;

  /// No description provided for @settingsProviderTestNoModel.
  ///
  /// In zh, this message translates to:
  /// **'请先启用至少一个可测试的模型'**
  String get settingsProviderTestNoModel;

  /// No description provided for @taskFilterClass.
  ///
  /// In zh, this message translates to:
  /// **'任务类型'**
  String get taskFilterClass;

  /// No description provided for @taskFilterState.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get taskFilterState;

  /// No description provided for @taskFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get taskFilterAll;

  /// No description provided for @taskDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务详情'**
  String get taskDetailTitle;

  /// No description provided for @taskDetailClass.
  ///
  /// In zh, this message translates to:
  /// **'任务类型'**
  String get taskDetailClass;

  /// No description provided for @taskDetailState.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get taskDetailState;

  /// No description provided for @taskDetailDescribe.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get taskDetailDescribe;

  /// No description provided for @taskDetailModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get taskDetailModel;

  /// No description provided for @taskDetailRelated.
  ///
  /// In zh, this message translates to:
  /// **'关联对象'**
  String get taskDetailRelated;

  /// No description provided for @taskDetailReason.
  ///
  /// In zh, this message translates to:
  /// **'失败原因'**
  String get taskDetailReason;

  /// No description provided for @taskDetailTiming.
  ///
  /// In zh, this message translates to:
  /// **'开始时间'**
  String get taskDetailTiming;

  /// No description provided for @taskDetailNone.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get taskDetailNone;

  /// No description provided for @taskStatePending.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get taskStatePending;

  /// No description provided for @taskStateProcessing.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get taskStateProcessing;

  /// No description provided for @taskStateSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get taskStateSuccess;

  /// No description provided for @taskStateFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get taskStateFailed;

  /// No description provided for @taskStateCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get taskStateCanceled;

  /// No description provided for @commonClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get commonClear;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonTest.
  ///
  /// In zh, this message translates to:
  /// **'测试'**
  String get commonTest;

  /// No description provided for @commonRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get commonRefresh;

  /// No description provided for @commonEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get commonEnabled;

  /// No description provided for @commonActions.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get commonActions;

  /// No description provided for @commonName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get commonName;

  /// No description provided for @commonType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get commonType;

  /// No description provided for @commonModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get commonModel;

  /// No description provided for @commonUnset.
  ///
  /// In zh, this message translates to:
  /// **'未设置'**
  String get commonUnset;

  /// No description provided for @statusQueued.
  ///
  /// In zh, this message translates to:
  /// **'排队中'**
  String get statusQueued;

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'等待中'**
  String get statusPending;

  /// No description provided for @statusRunning.
  ///
  /// In zh, this message translates to:
  /// **'生成中'**
  String get statusRunning;

  /// No description provided for @statusDone.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get statusDone;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get statusFailed;

  /// No description provided for @statusCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get statusCanceled;

  /// No description provided for @statusDraft.
  ///
  /// In zh, this message translates to:
  /// **'待生成'**
  String get statusDraft;

  /// No description provided for @statusNotGenerated.
  ///
  /// In zh, this message translates to:
  /// **'未生成'**
  String get statusNotGenerated;

  /// No description provided for @statusSuccessShort.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get statusSuccessShort;

  /// No description provided for @statusPendingShort.
  ///
  /// In zh, this message translates to:
  /// **'待处理'**
  String get statusPendingShort;

  /// No description provided for @dataTableTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 条'**
  String dataTableTotal(int total);

  /// No description provided for @dataTablePrevPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get dataTablePrevPage;

  /// No description provided for @dataTableNextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get dataTableNextPage;

  /// No description provided for @imageVersionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'图片版本'**
  String get imageVersionsTitle;

  /// No description provided for @imageVersionsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无图片版本'**
  String get imageVersionsEmpty;

  /// No description provided for @imageVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'版本 {index}'**
  String imageVersionLabel(int index);

  /// No description provided for @repaintImageTitle.
  ///
  /// In zh, this message translates to:
  /// **'重绘图片'**
  String get repaintImageTitle;

  /// No description provided for @repaintImageHint.
  ///
  /// In zh, this message translates to:
  /// **'如：把衣服改成红色'**
  String get repaintImageHint;

  /// No description provided for @repaintInstructionRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入修改意见'**
  String get repaintInstructionRequired;

  /// No description provided for @repaintAction.
  ///
  /// In zh, this message translates to:
  /// **'重绘'**
  String get repaintAction;

  /// No description provided for @inpaintAction.
  ///
  /// In zh, this message translates to:
  /// **'局部重绘'**
  String get inpaintAction;

  /// No description provided for @inpaintTitle.
  ///
  /// In zh, this message translates to:
  /// **'局部重绘'**
  String get inpaintTitle;

  /// No description provided for @inpaintHint.
  ///
  /// In zh, this message translates to:
  /// **'涂抹要重绘的区域，并描述修改意见'**
  String get inpaintHint;

  /// No description provided for @inpaintMaskRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先涂抹要重绘的区域'**
  String get inpaintMaskRequired;

  /// No description provided for @inpaintMaskCreateFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成局部重绘蒙版失败'**
  String get inpaintMaskCreateFailed;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsProvidersSection.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get settingsProvidersSection;

  /// No description provided for @settingsBindingsSection.
  ///
  /// In zh, this message translates to:
  /// **'模型绑定'**
  String get settingsBindingsSection;

  /// No description provided for @settingsPromptsSection.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get settingsPromptsSection;

  /// No description provided for @settingsStorageSection.
  ///
  /// In zh, this message translates to:
  /// **'存储与引擎'**
  String get settingsStorageSection;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeUpdated.
  ///
  /// In zh, this message translates to:
  /// **'外观已更新'**
  String get settingsThemeUpdated;

  /// No description provided for @localeChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get localeChinese;

  /// No description provided for @localeJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日本語'**
  String get localeJapanese;

  /// No description provided for @modelKindText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get modelKindText;

  /// No description provided for @modelKindImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get modelKindImage;

  /// No description provided for @modelKindVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get modelKindVideo;

  /// No description provided for @modelKindTts.
  ///
  /// In zh, this message translates to:
  /// **'配音'**
  String get modelKindTts;

  /// No description provided for @providerProtocolVolcengine.
  ///
  /// In zh, this message translates to:
  /// **'火山引擎'**
  String get providerProtocolVolcengine;

  /// No description provided for @providerProtocolOpenAiCompatible.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI兼容'**
  String get providerProtocolOpenAiCompatible;

  /// No description provided for @settingsAddProvider.
  ///
  /// In zh, this message translates to:
  /// **'添加供应商'**
  String get settingsAddProvider;

  /// No description provided for @settingsProviderEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有供应商'**
  String get settingsProviderEmptyTitle;

  /// No description provided for @settingsProviderEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'添加 OpenAI 兼容或火山引擎供应商后，再配置模型和环节绑定'**
  String get settingsProviderEmptySubtitle;

  /// No description provided for @settingsProviderAdded.
  ///
  /// In zh, this message translates to:
  /// **'供应商已添加'**
  String get settingsProviderAdded;

  /// No description provided for @settingsProviderUpdated.
  ///
  /// In zh, this message translates to:
  /// **'供应商已更新'**
  String get settingsProviderUpdated;

  /// No description provided for @settingsProviderConfigMissing.
  ///
  /// In zh, this message translates to:
  /// **'配置数据缺少供应商列表'**
  String get settingsProviderConfigMissing;

  /// No description provided for @settingsProviderMissing.
  ///
  /// In zh, this message translates to:
  /// **'供应商不存在'**
  String get settingsProviderMissing;

  /// No description provided for @settingsProviderEnabled.
  ///
  /// In zh, this message translates to:
  /// **'供应商已启用'**
  String get settingsProviderEnabled;

  /// No description provided for @settingsProviderDisabled.
  ///
  /// In zh, this message translates to:
  /// **'供应商已停用'**
  String get settingsProviderDisabled;

  /// No description provided for @settingsProviderTestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'连通成功：{elapsedMs} ms'**
  String settingsProviderTestSuccess(int elapsedMs);

  /// No description provided for @settingsProviderTestTitle.
  ///
  /// In zh, this message translates to:
  /// **'测试连通 · {name}'**
  String settingsProviderTestTitle(String name);

  /// No description provided for @settingsDeleteProviderTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除供应商'**
  String get settingsDeleteProviderTitle;

  /// No description provided for @settingsDeleteProviderMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定删除“{name}”吗？如果供应商已被环节绑定，引擎会拒绝删除。'**
  String settingsDeleteProviderMessage(String name);

  /// No description provided for @settingsProviderDeleted.
  ///
  /// In zh, this message translates to:
  /// **'供应商已删除'**
  String get settingsProviderDeleted;

  /// No description provided for @settingsModelCount.
  ///
  /// In zh, this message translates to:
  /// **'模型数'**
  String get settingsModelCount;

  /// No description provided for @settingsManageModels.
  ///
  /// In zh, this message translates to:
  /// **'模型管理'**
  String get settingsManageModels;

  /// No description provided for @settingsTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连通'**
  String get settingsTestConnection;

  /// No description provided for @settingsEditProvider.
  ///
  /// In zh, this message translates to:
  /// **'编辑供应商'**
  String get settingsEditProvider;

  /// No description provided for @settingsProviderName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get settingsProviderName;

  /// No description provided for @settingsProviderNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：azt'**
  String get settingsProviderNameHint;

  /// No description provided for @settingsKeepEmptyUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'留空不修改'**
  String get settingsKeepEmptyUnchanged;

  /// No description provided for @settingsExportConfig.
  ///
  /// In zh, this message translates to:
  /// **'导出配置'**
  String get settingsExportConfig;

  /// No description provided for @settingsImportConfig.
  ///
  /// In zh, this message translates to:
  /// **'导入配置'**
  String get settingsImportConfig;

  /// No description provided for @settingsConfigPlaintextWarning.
  ///
  /// In zh, this message translates to:
  /// **'配置 JSON 包含明文密钥，请妥善保管。'**
  String get settingsConfigPlaintextWarning;

  /// No description provided for @settingsEmbeddedEngineNote.
  ///
  /// In zh, this message translates to:
  /// **'引擎内嵌运行，数据与媒体全部保存在本机，无需任何后台服务'**
  String get settingsEmbeddedEngineNote;

  /// No description provided for @settingsEngineStatus.
  ///
  /// In zh, this message translates to:
  /// **'引擎状态'**
  String get settingsEngineStatus;

  /// No description provided for @settingsExportPanelFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开保存面板：{reason}'**
  String settingsExportPanelFailed(String reason);

  /// No description provided for @settingsExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出配置失败：{reason}'**
  String settingsExportFailed(String reason);

  /// No description provided for @settingsConfigExported.
  ///
  /// In zh, this message translates to:
  /// **'配置已导出'**
  String get settingsConfigExported;

  /// No description provided for @settingsOpenFileFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件选择器：{reason}'**
  String settingsOpenFileFailed(String reason);

  /// No description provided for @settingsImportConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入配置'**
  String get settingsImportConfigTitle;

  /// No description provided for @settingsImportConfigMessage.
  ///
  /// In zh, this message translates to:
  /// **'导入会覆盖同名供应商、模型、绑定和提示词。确定继续吗？'**
  String get settingsImportConfigMessage;

  /// No description provided for @settingsConfigInvalidFormat.
  ///
  /// In zh, this message translates to:
  /// **'配置文件格式无效'**
  String get settingsConfigInvalidFormat;

  /// No description provided for @settingsConfigInvalidJson.
  ///
  /// In zh, this message translates to:
  /// **'配置文件不是有效 JSON'**
  String get settingsConfigInvalidJson;

  /// No description provided for @settingsImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入配置失败：{reason}'**
  String settingsImportFailed(String reason);

  /// No description provided for @settingsConfigImported.
  ///
  /// In zh, this message translates to:
  /// **'配置已导入'**
  String get settingsConfigImported;

  /// No description provided for @settingsEngineChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检查引擎…'**
  String get settingsEngineChecking;

  /// No description provided for @settingsEngineOk.
  ///
  /// In zh, this message translates to:
  /// **'引擎正常 · v{version}'**
  String settingsEngineOk(String version);

  /// No description provided for @settingsEngineUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get settingsEngineUnknown;

  /// No description provided for @settingsProviderColumnProtocol.
  ///
  /// In zh, this message translates to:
  /// **'协议'**
  String get settingsProviderColumnProtocol;

  /// No description provided for @settingsProviderColumnBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'Base URL'**
  String get settingsProviderColumnBaseUrl;

  /// No description provided for @settingsModelManagementTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型管理 · {name}'**
  String settingsModelManagementTitle(String name);

  /// No description provided for @settingsAddModel.
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get settingsAddModel;

  /// No description provided for @settingsSaveModels.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get settingsSaveModels;

  /// No description provided for @settingsModelsEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有模型'**
  String get settingsModelsEmptyTitle;

  /// No description provided for @settingsModelsEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'添加至少一个文本、图片、视频或配音模型'**
  String get settingsModelsEmptySubtitle;

  /// No description provided for @settingsModelIdRequired.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID 不能为空'**
  String get settingsModelIdRequired;

  /// No description provided for @settingsModelsSaved.
  ///
  /// In zh, this message translates to:
  /// **'模型已保存'**
  String get settingsModelsSaved;

  /// No description provided for @settingsDeleteModel.
  ///
  /// In zh, this message translates to:
  /// **'删除模型'**
  String get settingsDeleteModel;

  /// No description provided for @settingsBindingModel.
  ///
  /// In zh, this message translates to:
  /// **'绑定模型'**
  String get settingsBindingModel;

  /// No description provided for @settingsSelectEnabledModel.
  ///
  /// In zh, this message translates to:
  /// **'请选择启用模型'**
  String get settingsSelectEnabledModel;

  /// No description provided for @settingsSelectModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get settingsSelectModel;

  /// No description provided for @settingsPromptContent.
  ///
  /// In zh, this message translates to:
  /// **'提示词内容'**
  String get settingsPromptContent;

  /// No description provided for @taskCenterTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务中心'**
  String get taskCenterTitle;

  /// No description provided for @taskActiveTitle.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get taskActiveTitle;

  /// No description provided for @taskActiveEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前没有进行中的任务'**
  String get taskActiveEmpty;

  /// No description provided for @taskHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'历史'**
  String get taskHistoryTitle;

  /// No description provided for @taskNoProjects.
  ///
  /// In zh, this message translates to:
  /// **'暂无项目'**
  String get taskNoProjects;

  /// No description provided for @taskHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'该项目暂无历史任务'**
  String get taskHistoryEmpty;

  /// No description provided for @taskFilterEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有符合筛选条件的任务'**
  String get taskFilterEmpty;

  /// No description provided for @taskEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无任务'**
  String get taskEmpty;

  /// No description provided for @taskProjectLabel.
  ///
  /// In zh, this message translates to:
  /// **'项目 #{id}'**
  String taskProjectLabel(int id);

  /// No description provided for @taskCancelTooltip.
  ///
  /// In zh, this message translates to:
  /// **'取消任务'**
  String get taskCancelTooltip;

  /// No description provided for @taskCanceledMessage.
  ///
  /// In zh, this message translates to:
  /// **'任务已取消'**
  String get taskCanceledMessage;

  /// No description provided for @taskRetryQueued.
  ///
  /// In zh, this message translates to:
  /// **'已重新排队'**
  String get taskRetryQueued;

  /// No description provided for @taskClassEventGeneration.
  ///
  /// In zh, this message translates to:
  /// **'事件生成'**
  String get taskClassEventGeneration;

  /// No description provided for @taskClassScriptGeneration.
  ///
  /// In zh, this message translates to:
  /// **'剧本生成'**
  String get taskClassScriptGeneration;

  /// No description provided for @taskClassAssetExtraction.
  ///
  /// In zh, this message translates to:
  /// **'素材提取'**
  String get taskClassAssetExtraction;

  /// No description provided for @taskClassAssetPromptPolish.
  ///
  /// In zh, this message translates to:
  /// **'素材提示词润色'**
  String get taskClassAssetPromptPolish;

  /// No description provided for @taskClassAssetImageGeneration.
  ///
  /// In zh, this message translates to:
  /// **'素材生图'**
  String get taskClassAssetImageGeneration;

  /// No description provided for @taskClassStoryboardGenerate.
  ///
  /// In zh, this message translates to:
  /// **'分镜生成'**
  String get taskClassStoryboardGenerate;

  /// No description provided for @taskClassStoryboardImageGeneration.
  ///
  /// In zh, this message translates to:
  /// **'首帧图生成'**
  String get taskClassStoryboardImageGeneration;

  /// No description provided for @taskClassVideoGeneration.
  ///
  /// In zh, this message translates to:
  /// **'视频生成'**
  String get taskClassVideoGeneration;

  /// No description provided for @taskClassAudioBind.
  ///
  /// In zh, this message translates to:
  /// **'配音匹配'**
  String get taskClassAudioBind;

  /// No description provided for @taskClassGeneric.
  ///
  /// In zh, this message translates to:
  /// **'任务'**
  String get taskClassGeneric;

  /// No description provided for @webPreviewBuildableTitle.
  ///
  /// In zh, this message translates to:
  /// **'Web 预览入口已可构建。'**
  String get webPreviewBuildableTitle;

  /// No description provided for @webPreviewMessage.
  ///
  /// In zh, this message translates to:
  /// **'完整本地引擎仍在移植中：浏览器版还需要 Web 数据库、浏览器文件存储、WebCodecs/Mediabunny 合成器，以及媒体预览的 Web 适配。当前 macOS、iOS、Android 客户端仍是完整功能主线。'**
  String get webPreviewMessage;

  /// No description provided for @webPreviewMacClient.
  ///
  /// In zh, this message translates to:
  /// **'macOS 完整客户端'**
  String get webPreviewMacClient;

  /// No description provided for @webPreviewIosClient.
  ///
  /// In zh, this message translates to:
  /// **'iOS 完整客户端'**
  String get webPreviewIosClient;

  /// No description provided for @webPreviewAndroidClient.
  ///
  /// In zh, this message translates to:
  /// **'Android APK 可构建'**
  String get webPreviewAndroidClient;

  /// No description provided for @webPreviewEnginePending.
  ///
  /// In zh, this message translates to:
  /// **'Web 引擎待移植'**
  String get webPreviewEnginePending;
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
