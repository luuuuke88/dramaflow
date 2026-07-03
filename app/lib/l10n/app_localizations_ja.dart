// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get menuMyProject => 'マイプロジェクト';

  @override
  String get menuTaskCenter => 'タスクセンター';

  @override
  String get menuNovel => '小説の原文';

  @override
  String get menuScriptAgent => 'シナリオ Agent';

  @override
  String get menuScriptManage => 'シナリオ管理';

  @override
  String get menuCornerScape => 'キャラ・背景制作';

  @override
  String get menuProduction => '動画制作';

  @override
  String get menuAssetCenter => 'アセットセンター';

  @override
  String get menuSettings => '設定';

  @override
  String get menuJumpGithub => 'Githubにジャンプ';

  @override
  String get menuFeedbackQuestions => 'フィードバックの質問';

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonConfirm => '確定';

  @override
  String get commonDelete => '削除';

  @override
  String get commonSearch => '検索';

  @override
  String get commonNextStep => '次へ';

  @override
  String get commonPrevStep => '前へ';

  @override
  String get projectListTitle => 'プロジェクト';

  @override
  String get projectListSubtitle => '一時的なプロジェクト一覧です。T9で全面的に作り直します';

  @override
  String get projectNew => '新規プロジェクト';

  @override
  String get projectName => 'プロジェクト名';

  @override
  String get projectCreate => '作成';

  @override
  String get projectCreated => 'プロジェクトを作成しました';

  @override
  String get projectEmpty => 'プロジェクトはまだありません';

  @override
  String get projectUntitled => '無題のプロジェクト';

  @override
  String get errProviderMissing => 'プロバイダーが見つからないか無効です';

  @override
  String get errModelMissing => 'モデルが見つからないか未設定です';

  @override
  String get errPromptMissing => 'プロンプトが見つかりません';

  @override
  String get errConfigVersion => '設定ファイルのバージョンに互換性がありません';

  @override
  String get errNetwork => 'ネットワーク要求に失敗しました';

  @override
  String get errLlmFormat => 'モデル出力形式が不正です';

  @override
  String get errCanceled => 'タスクはキャンセルされました';

  @override
  String get errAppRestart => 'アプリが再起動し、タスクが中断されました';

  @override
  String get errFileTooLarge => 'ファイルが大きすぎます';

  @override
  String get errFileType => '対応していないファイル形式です';

  @override
  String get errRegexInvalid => '正規表現が無効です';

  @override
  String get errNoChapters => '章が見つかりません';

  @override
  String get promptPanelTitle => 'プロンプト';

  @override
  String get promptEventExtractionTitle => 'イベント抽出';

  @override
  String get promptEventExtractionDescription => '小説の章から構造化イベントを抽出するプロンプト';

  @override
  String get promptScriptAssetExtractionTitle => 'シナリオ素材抽出';

  @override
  String get promptScriptAssetExtractionDescription =>
      'シナリオからキャラクター、シーン、小道具を抽出するプロンプト';

  @override
  String get promptImageSizeDirectiveTitle => '画像サイズ指示';

  @override
  String get promptImageSizeDirectiveDescription => '画像生成リクエストに挿入するサイズ制約';

  @override
  String get promptUnset => '未設定';

  @override
  String get promptOverridden => '変更済み';

  @override
  String promptCharacterCount(int count) => '$count 文字';

  @override
  String promptEditTitle(String title) => 'プロンプトを編集 · $title';

  @override
  String get promptSaved => 'プロンプトを保存しました';

  @override
  String get promptRestoreDefault => 'デフォルトに戻す';

  @override
  String get promptRestoreDefaultTitle => 'デフォルトに戻す';

  @override
  String promptRestoreDefaultMessage(String title) =>
      '「$title」を組み込みのデフォルト内容に戻しますか？';

  @override
  String get promptRestoreDefaultConfirm => '戻す';

  @override
  String get promptRestored => 'プロンプトをデフォルトに戻しました';
}
