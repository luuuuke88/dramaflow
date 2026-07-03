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
  String promptCharacterCount(int count) {
    return '$count 文字';
  }

  @override
  String promptEditTitle(Object title) {
    return 'プロンプトを編集 · $title';
  }

  @override
  String get promptSaved => 'プロンプトを保存しました';

  @override
  String get promptRestoreDefault => 'デフォルトに戻す';

  @override
  String get promptRestoreDefaultTitle => 'デフォルトに戻す';

  @override
  String promptRestoreDefaultMessage(Object title) {
    return '「$title」を組み込みのデフォルト内容に戻しますか？';
  }

  @override
  String get promptRestoreDefaultConfirm => '戻す';

  @override
  String get promptRestored => 'プロンプトをデフォルトに戻しました';

  @override
  String get errTaskUnsupported => '未対応のタスク種別';

  @override
  String get shellSelectProject => 'プロジェクトを選択';

  @override
  String shellComingSoon(String batch) {
    return 'このエリアは $batch バッチで提供予定';
  }

  @override
  String shellComingSoonBadge(String batch) {
    return '$batch';
  }

  @override
  String get projectTitle => 'マイプロジェクト';

  @override
  String get projectSubtitle => 'すべてのショートドラマプロジェクトを管理します';

  @override
  String get projectNewProject => '新規プロジェクト';

  @override
  String get projectDialogEditTitle => 'プロジェクトの編集';

  @override
  String get projectDialogAddTitle => '新規プロジェクト';

  @override
  String get projectDialogSave => '保存';

  @override
  String get projectDialogOk => '確定';

  @override
  String get projectDialogCancel => 'キャンセル';

  @override
  String get projectDialogProjectType => 'プロジェクトタイプ';

  @override
  String get projectDialogSelectType => 'プロジェクトタイプを選択';

  @override
  String get projectDialogBasedOnNovel => '小説の原文に基づく';

  @override
  String get projectDialogProjectName => 'プロジェクト名';

  @override
  String get projectDialogProjectNamePh => 'プロジェクト名を入力してください';

  @override
  String get projectDialogNovelType => '小説のジャンル';

  @override
  String get projectDialogNovelTypePh => '例：ファンタジー、SF、恋愛';

  @override
  String get projectDialogArtStyle => 'ビジュアルマニュアル';

  @override
  String get projectDialogSelected => '選択済み：';

  @override
  String get projectDialogSelectArtStyle => 'ビジュアルマニュアルを選択してください';

  @override
  String get projectDialogNewArtStyle => '新しいビジュアルマニュアル';

  @override
  String get projectDialogLoading => '読み込み中...';

  @override
  String get projectDialogVideoRatio => '画面アスペクト比';

  @override
  String get projectDialogNovelIntro => '小説のあらすじ';

  @override
  String get projectDialogNovelIntroPh => 'あらすじを入力してください';

  @override
  String get projectDialogEditArtStyleTitle => 'ビジュアルマニュアルの編集';

  @override
  String get projectDialogNewArtStyleTitle => '新しいビジュアルマニュアル';

  @override
  String get projectDialogArtStyleName => 'ビジュアルマニュアル名';

  @override
  String get projectDialogArtStyleNamePh => 'ビジュアルマニュアル名を入力してください';

  @override
  String get projectDialogArtStyleImage => 'ビジュアルマニュアルカバー';

  @override
  String get projectDialogRemove => '削除';

  @override
  String get projectDialogUploadCover => 'カバーをアップロード';

  @override
  String get projectDialogArtStylePrompt => 'ビジュアルマニュアルのプロンプトワード';

  @override
  String get projectDialogAiExtract => 'AI プロンプト抽出';

  @override
  String get projectDialogPromptPlaceholder =>
      '画像生成時にビジュアルマニュアルを指定するために使用されるビジュアルマニュアルプロンプトワードについて説明します。';

  @override
  String get projectDialogVisualManual => 'ビジュアルマニュアル';

  @override
  String get projectDialogNewVisualManual => '新しいビジュアルマニュアル';

  @override
  String get projectDialogEditVisualManualTitle => 'ビジュアルマニュアルの編集';

  @override
  String get projectDialogNewVisualManualTitle => '新しいビジュアルマニュアル';

  @override
  String get projectDialogVisualManualName => 'ビジュアルマニュアル名';

  @override
  String get projectDialogVisualManualNamePh => 'ビジュアルマニュアル名を入力してください';

  @override
  String get projectDialogVisualManualCover => 'ビジュアルマニュアルカバー';

  @override
  String get projectDialogVisualManualPrompt => 'ビジュアルマニュアルのプロンプト';

  @override
  String get projectDialogModelData => '画像モデルの選択';

  @override
  String get projectDialogVideoModelData => 'ビデオモデルを選択してください';

  @override
  String get projectDialogPromptSaveSuccess => '更新に成功しました';

  @override
  String get projectDialogPromptTitle => '即効性のある言葉';

  @override
  String get projectDialogBasedOnScript => '脚本に基づいて';

  @override
  String get projectDialogMdFile => 'ビジュアルマニュアルファイル';

  @override
  String get projectDialogDirectorManual => 'ディレクターズハンドブック';

  @override
  String get projectDialogAddDirectorManual => '新しいディレクターマニュアル';

  @override
  String get projectDialogEditingDirectorManual => 'ディレクターズマニュアルを編集する';

  @override
  String get projectDialogNewDirecorManualTitle => '新しいディレクターマニュアル';

  @override
  String get projectDialogDirectorManualPrompt => 'ディレクターズマニュアル プロンプトワード';

  @override
  String get projectDialogDirectorManualName => 'ディレクターズマニュアル名';

  @override
  String get projectDialogDirectorManualNamePh => 'ディレクターズマニュアル名を入力してください';

  @override
  String get projectDialogDirectorFile => 'ディレクターズマニュアル文書';

  @override
  String get projectDialogDirectorManualCover => 'ディレクターズマニュアルの表紙';

  @override
  String get projectMsgFetchFailed => 'プロジェクトリストの取得に失敗しました';

  @override
  String get projectMsgNotFound => 'プロジェクトが見つかりません！';

  @override
  String get projectMsgEditSuccess => 'プロジェクトを編集しました';

  @override
  String get projectMsgEditFailed => 'プロジェクトの編集に失敗しました';

  @override
  String get projectMsgAddSuccess => 'プロジェクトを新規作成しました';

  @override
  String get projectMsgAddFailed => 'プロジェクトの作成に失敗しました';

  @override
  String get projectMsgDeleteHeader => 'プロジェクトの削除';

  @override
  String get projectMsgDeleteBody => '本当にこのプロジェクトを削除しますか？';

  @override
  String get projectMsgDeleteConfirm => '削除';

  @override
  String get projectMsgDeleteCancel => 'キャンセル';

  @override
  String get projectMsgDeleteSuccess => 'プロジェクトを削除しました';

  @override
  String get projectMsgDeleteFailed => 'プロジェクトの削除に失敗しました';

  @override
  String get projectMsgExtractSuccess => 'プロンプトの抽出に成功しました';

  @override
  String get projectMsgExtractFailed => '抽出に失敗しました';

  @override
  String get projectMsgEnterArtStyleName => 'ビジュアルマニュアル名を入力してください';

  @override
  String get projectMsgArtStyleUpdated => 'ビジュアルマニュアルを更新しました';

  @override
  String get projectMsgArtStyleAdded => 'ビジュアルマニュアルを追加しました';

  @override
  String get projectMsgOperationFailed => '操作に失敗しました';

  @override
  String get projectMsgEnterVisualManualName => 'ビジュアルマニュアル名を入力してください';

  @override
  String get projectMsgEnterVisualManualImage =>
      'ビジュアルマニュアルのカバー画像をアップロードしてください';

  @override
  String get projectMsgEnterVisualManualTabData => 'プロンプトは空にできません';

  @override
  String get projectMsgVisualManualUpdated => 'ビジュアルマニュアルを更新しました';

  @override
  String get projectMsgVisualManualAdded => 'ビジュアルマニュアルを追加しました';

  @override
  String get projectMsgDeleteVisualManualHeader => 'ビジュアルマニュアルを削除';

  @override
  String projectMsgDeleteVisualManualBody(String name) {
    return 'ビジュアルマニュアル「$name」を削除してよろしいですか？';
  }

  @override
  String get projectMsgDeleteVisualManualConfirm => '削除';

  @override
  String get projectMsgDeleteVisualManualCancel => 'キャンセル';

  @override
  String get projectMsgEnterProjectName => 'プロジェクト名を入力してください';

  @override
  String get projectMsgEnterProjectIntro => '小説の紹介文を入力してください';

  @override
  String get projectMsgEnterProjectType => 'プロジェクトのタイプを入力してください';

  @override
  String get projectMsgEnterArtStyle => 'プロジェクトのビジュアルパンフレットを選択してください';

  @override
  String get projectMsgEnterVideoRatio => 'ビデオ比率を選択してください';

  @override
  String get projectMsgEnterImageModel => '画像モデルを選択してください';

  @override
  String get projectMsgEnterVideoModel => 'ビデオモデルを選択してください';

  @override
  String get projectMsgVisualManualDeleted => '正常に削除されました';

  @override
  String get projectMsgSelectMode => 'モードを選択してください';

  @override
  String get projectMsgDeleteDirectorManualHeader => 'ディレクターズマニュアルの削除';

  @override
  String projectMsgDeleteDirectorManualBody(String name) {
    return 'ディレクターズマニュアル「$name」を削除してもよろしいですか?';
  }

  @override
  String get projectMsgDirectorManualUpdated => 'ディレクターズマニュアルを更新しました';

  @override
  String get projectMsgDirectorManualAdded => 'ディレクターズマニュアルを追加しました';

  @override
  String get projectMsgDirectorManual => 'プロジェクトディレクターズマニュアルを選択してください';

  @override
  String get projectMsgModelProviderDisabled =>
      'ビデオ モデルまたは画像モデルのサプライヤーが有効になっていない、またはモデル サプライヤーがありません。最初に設定してください。';

  @override
  String get projectTypeNovel => '原作小説に基づいて';

  @override
  String get projectTypeScript => '小説の脚本に基づく';

  @override
  String get commonEdit => '編集';

  @override
  String get manualTabReadme => 'README';

  @override
  String get manualTabPrefix => 'プレフィックス';

  @override
  String get manualTabCharacter => 'キャラクター';

  @override
  String get manualTabCharacterDerivative => 'キャラクター派生';

  @override
  String get manualTabProp => '小道具';

  @override
  String get manualTabPropDerivative => '小道具派生';

  @override
  String get manualTabScene => 'シーン';

  @override
  String get manualTabSceneDerivative => 'シーン派生';

  @override
  String get manualTabStoryboard => '絵コンテ';

  @override
  String get manualTabStoryboardVideo => '絵コンテ動画';

  @override
  String get manualTabDirectorPlanning => '技法・監督プランニング';

  @override
  String get manualTabStoryboardTable => '技法・絵コンテ表';

  @override
  String get manualTabNarrativePlanning => '監督プランニング';

  @override
  String get manualTabNarrativeTable => '絵コンテ表';

  @override
  String get errManualInvalid => 'マニュアルデータが無効です';

  @override
  String get novelImportText => '原文をインポート';

  @override
  String get novelBatchDelete => '一括削除';

  @override
  String get novelEventAnalysis => 'イベント分析';

  @override
  String get novelSearchPlaceholder => '原文の名前を検索...';

  @override
  String get novelSearch => '検索';

  @override
  String get novelGenerating => '生成中...';

  @override
  String get novelGenFailed => '生成失敗';

  @override
  String get novelViewDetail => '查看详情';

  @override
  String get novelNone => 'なし';

  @override
  String get novelEdit => '編集';

  @override
  String get novelDelete => '削除';

  @override
  String get novelColId => 'No.';

  @override
  String get novelColReel => '巻';

  @override
  String get novelColChapter => '章名';

  @override
  String get novelColChapterData => '章の内容';

  @override
  String get novelColEvent => 'イベント';

  @override
  String get novelColOperation => '操作';

  @override
  String get novelMsgBatchDeleteHeader => '一括削除';

  @override
  String novelMsgBatchDeleteBody(String count) {
    return '選択した $count 件のデータを削除してもよろしいですか？';
  }

  @override
  String get novelMsgBatchDeleteSuccess => '一括削除に成功しました';

  @override
  String get novelMsgDeleteHeader => '削除の確認';

  @override
  String novelMsgDeleteBody(String name) {
    return '章名「$name」のデータを削除してもよろしいですか？';
  }

  @override
  String get novelMsgDeleteSuccess => '削除に成功しました';

  @override
  String get novelMsgEventAnalysisHeader => 'イベント分析';

  @override
  String novelMsgEventAnalysisBody(String count) {
    return '選択した $count 件のデータのイベント分析を実行してもよろしいですか？';
  }

  @override
  String get novelImportTitle => '小説の原文をアップロード';

  @override
  String get novelImportStep1 => 'ステップ 1';

  @override
  String get novelImportStep2 => 'ステップ 2';

  @override
  String get novelImportStep3 => 'ステップ 3';

  @override
  String get novelImportDragUpload => 'ここに小説ファイルをドラッグ＆ドロップするか、クリックしてアップロード';

  @override
  String get novelImportUploadHint => '対応形式: .txt, .docx。ファイルサイズは10MB以下を推奨します';

  @override
  String get novelImportOr => 'または';

  @override
  String get novelImportPasteLabel => '小説の原文を直接貼り付け';

  @override
  String get novelImportPastePlaceholder => '小説の原文を入力してください';

  @override
  String get novelImportChars => '文字';

  @override
  String get novelImportTooShort => '内容が短すぎます。100文字以上を推奨します';

  @override
  String novelImportParsedChapters(String count) {
    return '$count 章を解析しました';
  }

  @override
  String get novelImportNextStep => '次へ';

  @override
  String get novelImportPrevStep => '戻る';

  @override
  String novelImportSelectedInfo(String count) {
    return '選択済み：$count 文字 (200,000文字以内)';
  }

  @override
  String get novelImportEventAnalysis => 'イベント分析';

  @override
  String get novelImportSaveAndAnalyze => '原文を保存してイベントを分析';

  @override
  String get novelImportColChapter => '章';

  @override
  String get novelImportColReel => '巻';

  @override
  String get novelImportColChapterName => '章名';

  @override
  String get novelImportColChapterData => '章の内容';

  @override
  String get novelImportMsgParseFailed => 'ファイルの解析に失敗しました。再アップロードしてください';

  @override
  String get novelImportMsgSelectFile => 'ファイルを選択';

  @override
  String get novelImportMsgDocNotSupported =>
      '.doc ファイルは解析をサポートしていません。.ts ファイルに変換してください。';

  @override
  String get novelImportMsgUnsupportedType => '未対応のファイル形式です';

  @override
  String get novelImportMsgFileTooLarge =>
      'ファイルサイズが10MBを超えています。より小さなファイルをアップロードしてください';

  @override
  String get novelImportMsgSelectChapters => '先に章を選択してください';

  @override
  String get novelImportMsgSaveSuccess => '小説の原文を保存しました';

  @override
  String get novelImportImportAdd => 'ここにファイルをドラッグ アンド ドロップするか、クリックしてアップロードします';

  @override
  String get novelImportLimit => '.ts形式をサポート';

  @override
  String get novelEditDialogTitle => '小説の原文を編集';

  @override
  String get novelEditDialogChapterName => '章名';

  @override
  String get novelEditDialogChapterNamePh => '章名を入力してください';

  @override
  String get novelEditDialogEventContent => 'イベント内容';

  @override
  String get novelEditDialogEventContentPh => 'イベント内容を入力してください';

  @override
  String get novelEditDialogChapterContent => '章の内容';

  @override
  String get novelEditDialogChapterContentPh => '章の内容を入力してください';

  @override
  String get novelEditDialogCancel => 'キャンセル';

  @override
  String get novelEditDialogSave => '保存';

  @override
  String get novelEditDialogMsgUpdateSuccess => '小説の原文を更新しました';

  @override
  String get novelEventRegenerate => 'イベントを再生成';

  @override
  String get novelEventBatchDelete => '一括削除';

  @override
  String get novelEventNoData => 'イベントデータがありません。生成を開始してください';

  @override
  String get novelEventGenerate => 'イベントを生成';

  @override
  String get novelEventGeneratingHint => 'イベント生成中。しばらくお待ちください...';

  @override
  String get novelEventLoading => '読み込み中...';

  @override
  String get novelEventDelete => '削除';

  @override
  String get novelEventColId => 'イベントID';

  @override
  String get novelEventColEventName => 'イベント名';

  @override
  String get novelEventColChapters => '元の章';

  @override
  String get novelEventColDetail => 'イベントのプロセス';

  @override
  String get novelEventColCreateTime => '作成時間';

  @override
  String get novelEventColOperation => '操作';

  @override
  String get novelEventMsgDeleteHeader => 'イベントの削除';

  @override
  String get novelEventMsgDeleteBody => 'このイベントを削除してもよろしいですか？';

  @override
  String get novelEventMsgDeleteSuccess => '削除に成功しました';

  @override
  String get novelEventMsgGenerateSuccess => 'イベントの生成に成功しました';

  @override
  String get novelEventMsgBatchDeleteHeader => '一括削除';

  @override
  String novelEventMsgBatchDeleteBody(String count) {
    return '選択した $count 件のデータを削除してもよろしいですか？';
  }

  @override
  String get novelEventMsgBatchDeleteSuccess => '一括削除に成功しました';

  @override
  String get novelAnalysisAnalyzeFirst => '先にイベントを分析してください';

  @override
  String get novelAnalysisStartAnalysis => '分析を開始';

  @override
  String novelAnalysisChapterHeader(String index, String name) {
    return '第$index章 - $name';
  }

  @override
  String get novelAnalysisAnalyzing => 'イベント分析中';
}
