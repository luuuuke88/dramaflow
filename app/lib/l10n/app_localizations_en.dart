// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get menuMyProject => 'My Projects';

  @override
  String get menuTaskCenter => 'Task Center';

  @override
  String get menuNovel => 'Novel Text';

  @override
  String get menuScriptAgent => 'Script Agent';

  @override
  String get menuScriptManage => 'Script Management';

  @override
  String get menuCornerScape => 'Characters & Scenes';

  @override
  String get menuProduction => 'Video Production';

  @override
  String get menuAssetCenter => 'Asset Center';

  @override
  String get menuSettings => 'Settings';

  @override
  String get menuJumpGithub => 'Jump to Github';

  @override
  String get menuFeedbackQuestions => 'Feedback question';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonNextStep => 'Next';

  @override
  String get commonPrevStep => 'Previous';

  @override
  String get projectListTitle => 'Projects';

  @override
  String get projectListSubtitle =>
      'Temporary project list; T9 will rebuild this screen';

  @override
  String get projectNew => 'New Project';

  @override
  String get projectName => 'Project Name';

  @override
  String get projectCreate => 'Create';

  @override
  String get projectCreated => 'Project created';

  @override
  String get projectEmpty => 'No projects yet';

  @override
  String get projectUntitled => 'Untitled project';

  @override
  String get errProviderMissing => 'Provider is missing or disabled';

  @override
  String get errModelMissing => 'Model is missing or not bound';

  @override
  String get errPromptMissing => 'Prompt is missing';

  @override
  String get errConfigVersion => 'Config file version is incompatible';

  @override
  String get errNetwork => 'Network request failed';

  @override
  String get errLlmFormat => 'Model output format is invalid';

  @override
  String get errCanceled => 'Task canceled';

  @override
  String get errAppRestart => 'App restarted; task interrupted';

  @override
  String get errFileTooLarge => 'File is too large';

  @override
  String get errFileType => 'File type is not supported';

  @override
  String get errRegexInvalid => 'Regular expression is invalid';

  @override
  String get errNoChapters => 'No chapters found';

  @override
  String get promptPanelTitle => 'Prompts';

  @override
  String get promptEventExtractionTitle => 'Event extraction';

  @override
  String get promptEventExtractionDescription =>
      'Prompt for extracting structured events from novel chapters';

  @override
  String get promptScriptAssetExtractionTitle => 'Script asset extraction';

  @override
  String get promptScriptAssetExtractionDescription =>
      'Prompt for extracting characters, scenes, and props from scripts';

  @override
  String get promptImageSizeDirectiveTitle => 'Image size directive';

  @override
  String get promptImageSizeDirectiveDescription =>
      'Size constraint injected into image generation requests';

  @override
  String get promptUnset => 'Not set';

  @override
  String get promptOverridden => 'Modified';

  @override
  String promptCharacterCount(int count) {
    return '$count characters';
  }

  @override
  String promptEditTitle(Object title) {
    return 'Edit prompt · $title';
  }

  @override
  String get promptSaved => 'Prompt saved';

  @override
  String get promptRestoreDefault => 'Restore default';

  @override
  String get promptRestoreDefaultTitle => 'Restore default';

  @override
  String promptRestoreDefaultMessage(Object title) {
    return 'Restore “$title” to the built-in default?';
  }

  @override
  String get promptRestoreDefaultConfirm => 'Restore';

  @override
  String get promptRestored => 'Prompt restored to default';
}
