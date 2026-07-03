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
  String promptEditTitle(String title);

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
  String promptRestoreDefaultMessage(String title);

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
