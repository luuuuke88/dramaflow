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
}
