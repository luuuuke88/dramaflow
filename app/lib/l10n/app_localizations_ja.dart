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
  String get novelViewDetail => '詳細を見る';

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

  @override
  String get scriptSearchPlaceholder => 'シナリオ名を検索...';

  @override
  String get scriptSearch => '検索';

  @override
  String get scriptAddScript => 'シナリオを新規作成';

  @override
  String get scriptCancelSelectAll => '全選択を解除';

  @override
  String get scriptSelectAll => 'すべて選択';

  @override
  String get scriptExportScript => 'シナリオをエクスポート';

  @override
  String get scriptMsgExtracting => 'アセットを抽出中';

  @override
  String get scriptMsgExtractFailed => 'アセットの抽出に失敗しました';

  @override
  String get scriptMsgExtractingInProgress => '抽出中';

  @override
  String get scriptMsgProjectNotFound => 'アイテムが見つかりません';

  @override
  String get scriptMsgSelectExport => '先にエクスポートするシナリオを選択してください';

  @override
  String get scriptMsgDeleteHeader => '削除の確認';

  @override
  String get scriptMsgDeleteBody => 'このシナリオを削除してもよろしいですか？この操作は取り消せません。';

  @override
  String get scriptMsgDeleteConfirm => '削除';

  @override
  String get scriptMsgCancel => 'キャンセル';

  @override
  String get scriptMsgDeleteSuccess => '削除に成功しました';

  @override
  String get scriptMsgDeleteFailed => '削除に失敗しました';

  @override
  String get scriptMsgSelectDelScript => 'スクリプトを削除することを選択してください';

  @override
  String get scriptMsgBatchDeleteHeader => '一括削除';

  @override
  String scriptMsgBatchDeleteBody(String count) {
    return '選択した $count 件のシナリオを削除してもよろしいですか？この操作は取り消せません。';
  }

  @override
  String get scriptMsgBatchDeleteSuccess => '一括削除に成功しました';

  @override
  String get scriptMsgSearchFailed => 'シナリオの検索に失敗しました';

  @override
  String get scriptMsgSelectsExport => 'スクリプトをエクスポートすることを選択してください';

  @override
  String get scriptAddTitle => 'シナリオの追加';

  @override
  String get scriptAddScriptName => 'シナリオ名';

  @override
  String get scriptAddScriptNamePh => 'シナリオ名を入力してください';

  @override
  String get scriptAddUploadFile => 'ファイルをアップロード';

  @override
  String get scriptAddDragUpload => 'ここにシナリオファイルをドラッグ＆ドロップするか、クリックしてアップロード';

  @override
  String get scriptAddUploadHint => '対応形式: .txt, .docx。ファイルサイズは10MB以下を推奨します';

  @override
  String get scriptAddScriptContent => 'シナリオ内容';

  @override
  String get scriptAddScriptContentPh => 'シナリオ内容をアップロードまたは入力してください...';

  @override
  String get scriptAddRelatedAssets => '関連アセット';

  @override
  String get scriptAddSelectAssets => 'アセットを選択';

  @override
  String get scriptAddNoAssets => '関連アセットがありません';

  @override
  String get scriptAddCancel => 'キャンセル';

  @override
  String get scriptAddConfirm => '確定';

  @override
  String get scriptAddMsgFileReadFailed => 'ファイルの読み取りに失敗しました';

  @override
  String get scriptAddMsgDocNotSupported =>
      '.docファイルの解析は未対応です。.txtまたは.docx形式に変換してください';

  @override
  String get scriptAddMsgUnsupportedType => '未対応のファイル形式です';

  @override
  String get scriptAddMsgFileTooLarge =>
      'ファイルサイズが10MBを超えています。より小さなファイルをアップロードしてください';

  @override
  String get scriptAddMsgParsing => 'ファイルを解析中...';

  @override
  String get scriptAddMsgParseFailed => 'ファイルの解析に失敗しました。再アップロードしてください';

  @override
  String get scriptAddMsgSelectAssetsTitle => '関連アセットの選択';

  @override
  String get scriptAddMsgEnterContent => 'シナリオ内容をアップロードまたは入力してください';

  @override
  String get scriptAddMsgEnterName => 'シナリオ名を入力してください';

  @override
  String get scriptAddMsgAddSuccess => 'シナリオを追加しました';

  @override
  String get scriptAddMsgAddFailed => 'シナリオの追加に失敗しました。後で再試行してください';

  @override
  String get scriptEditTitle => 'シナリオ詳細';

  @override
  String get scriptEditScriptName => 'シナリオ名';

  @override
  String get scriptEditScriptNamePh => 'シナリオ名を入力してください';

  @override
  String get scriptEditScriptContent => 'シナリオ内容';

  @override
  String get scriptEditScriptContentPh => 'シナリオ内容を入力してください...';

  @override
  String get scriptEditRelatedAssets => '関連アセット';

  @override
  String get scriptEditSelectAssets => 'アセットを選択';

  @override
  String get scriptEditNoAssets => '関連アセットがありません';

  @override
  String get scriptEditMsgSelectAssetsTitle => '関連アセットの選択';

  @override
  String get scriptEditMsgUpdateSuccess => 'シナリオの更新に成功しました';

  @override
  String get scriptEditMsgUpdateFailed => 'シナリオの更新に失敗しました。後で再試行してください';

  @override
  String get scriptDeleteScript => 'スクリプトを一括で削除する';

  @override
  String get scriptExtractAssets => 'アセットを抽出';

  @override
  String get scriptImportGetAiRegex => 'AI生成の正規表現';

  @override
  String get scriptImportEpisodeRegexPh =>
      'スクリプト分割ルールをカスタマイズします。デフォルトの分割ルールを使用するには空白のままにしてください (デフォルトはエピソード X 形式に従って分割されます)。';

  @override
  String get scriptBatchAdd => '一括追加';

  @override
  String get scriptStateWaiting => '待機中...';

  @override
  String get scriptStateExtracting => '抽出中...';

  @override
  String get scriptStateFailed => '抽出失敗';

  @override
  String get settingsLanguage => '言語';

  @override
  String get localeSystem => 'システムに従う';

  @override
  String get assetsTabRole => 'キャラクター';

  @override
  String get assetsTabTool => '小道具';

  @override
  String get assetsTabScene => 'シーン';

  @override
  String get assetsTabClip => '素材';

  @override
  String get assetsTabAudio => '音声';

  @override
  String get assetsAddPrefix => '新規';

  @override
  String get assetsGeneratePrompt => 'プロンプト生成';

  @override
  String get assetsGenerateImage => '画像生成';

  @override
  String get assetsBatchDelete => '一括削除';

  @override
  String get assetsSearchPlaceholder => 'アセット名を検索...';

  @override
  String get assetsColPreview => 'プレビュー';

  @override
  String get assetsColName => '名称';

  @override
  String get assetsColPrompt => 'プロンプト';

  @override
  String get assetsColDescribe => '説明';

  @override
  String get assetsColRemark => '備考';

  @override
  String get assetsColCreateTime => '作成日時';

  @override
  String get assetsColOperation => '操作';

  @override
  String get assetsGenerate => '生成';

  @override
  String get assetsEdit => '編集';

  @override
  String get assetsDelete => '削除';

  @override
  String get assetsGenerating => '生成中...';

  @override
  String get assetsConfirmDeleteHeader => '削除の確認';

  @override
  String get assetsConfirmDeleteBody => 'このアセットを削除しますか？画像バージョンと子アセットも削除されます';

  @override
  String assetsConfirmBatchDeleteBody(String count) {
    return '選択した $count 件のアセットを削除しますか？';
  }

  @override
  String get assetsDeleteSuccess => '削除しました';

  @override
  String get assetsSex => '性別';

  @override
  String get assetsAudioName => 'ボイス';

  @override
  String get assetsAudioText => '音声テキスト';

  @override
  String get assetsPlay => '再生';

  @override
  String get assetsAddName => '名称';

  @override
  String get assetsAddNamePh => 'アセット名を入力';

  @override
  String get assetsAddNameRequired => 'アセット名を入力してください';

  @override
  String get assetsAddDescribe => '説明';

  @override
  String get assetsAddDescribePh => '説明を入力';

  @override
  String get assetsAddDescribeRequired => '説明を入力してください';

  @override
  String get assetsAddRemark => '備考';

  @override
  String get assetsAddRemarkPh => '備考を入力';

  @override
  String get assetsAddPrompt => 'プロンプト';

  @override
  String get assetsAddPromptPh => '生成プロンプトを入力';

  @override
  String get assetsAddAddSuccess => 'アセットを追加しました';

  @override
  String get assetsAddUpdateSuccess => 'アセットを更新しました';

  @override
  String get assetsAddAudioNamePh => 'ボイス名を入力';

  @override
  String get assetsAddSexPh => '性別を入力';

  @override
  String get assetsAddAudioFile => '音声ファイル';

  @override
  String get assetsAddAudioTextPh => 'この音声のテキストを入力';

  @override
  String get assetsAddAudioDescPh => '音声の説明を入力';

  @override
  String get assetsAddAudioItem => '音声を追加';

  @override
  String get assetsAddPleaseUploadAudio => '音声ファイルをアップロードしてください';

  @override
  String get assetsGenHeader => '画像生成';

  @override
  String get assetsGenUploadRef => '参照画像';

  @override
  String get assetsGenOptional => '任意';

  @override
  String get assetsGenPromptLabel => 'プロンプト';

  @override
  String get assetsGenSmartGenerate => 'スマート生成';

  @override
  String get assetsGenSelectModel => 'モデル';

  @override
  String get assetsGenSelectResolution => '解像度';

  @override
  String get assetsGenGenerateBtn => '生成';

  @override
  String get assetsGenFillPrompt => 'プロンプトを入力してください';

  @override
  String get assetsGenPickModel => 'モデルを選択してください';

  @override
  String assetsGenGeneratedCount(String count) {
    return '$count 枚生成済み';
  }

  @override
  String get assetsGenGeneratingLabel => '生成中...';

  @override
  String get assetsGenGenFailed => '生成失敗';

  @override
  String get assetsGenImageSaved => '画像を保存しました';

  @override
  String get assetsGenAssetGenSuccess => '生成を送信しました';

  @override
  String get assetsGenPromptSuccess => 'プロンプトを生成しました';

  @override
  String get assetsGenConfirmSelect => '先に画像を選択してください';

  @override
  String get assetsGenResultTitle => '生成結果';

  @override
  String get assetsBatchHeader => '一括生成';

  @override
  String assetsBatchSelected(String count) {
    return '$count 件選択中';
  }

  @override
  String get assetsBatchSelectAll => 'すべて選択';

  @override
  String get assetsBatchClearSelection => '選択解除';

  @override
  String get assetsBatchColPreviewImg => 'プレビュー';

  @override
  String get assetsBatchInputPh => 'プロンプトを入力';

  @override
  String assetsBatchSaveSelected(String count) {
    return '選択を保存($count)';
  }

  @override
  String get assetsBatchMissingPrompts => '先に選択アセットのプロンプトを生成してください';

  @override
  String get assetsBatchPromptDone => '一括プロンプト生成を送信しました';

  @override
  String get assetsBatchImageDone => '一括画像生成を送信しました';

  @override
  String get assetsBatchSaveSuccess => '保存しました';

  @override
  String get assetsCancelBtn => 'キャンセル';

  @override
  String get assetsSelectAtLeastOne => '1 件以上選択してください';

  @override
  String get productionEditImageInvalidConnection => '接続できません：接続先は生成ノードのみ、重複不可';

  @override
  String get productionEditImageUploadImage => '画像をアップロード';

  @override
  String get productionEditImageImageGeneration => '画像生成';

  @override
  String get productionEditImageGenerating => '生成中...';

  @override
  String get productionEditImagePromptPlaceholder => '生成内容を入力';

  @override
  String get productionEditImageGenerateBtn => '生成';

  @override
  String get productionEditImageUpload => 'アップロードノード';

  @override
  String get productionEditImageGenerate => '生成ノード';

  @override
  String get productionNodeScriptTitle => '脚本';

  @override
  String get productionNodeScriptPlanTitle => '脚本プラン';

  @override
  String get productionNodeAssetsTitle => 'アセット';

  @override
  String get productionNodeStoryboardTableTitle => '絵コンテ表';

  @override
  String get productionNodeStoryboardTitle => '絵コンテ';

  @override
  String get productionNodeWorkbenchTitle => 'ワークベンチ';

  @override
  String get productionSelectEpisode => '話数を選択';

  @override
  String get productionNoScripts => '脚本がありません。脚本管理で作成してください';

  @override
  String get productionGoToScripts => '脚本を作成';

  @override
  String get productionStoryboardGenerate => '絵コンテ生成';

  @override
  String get productionStoryboardGenerating => '絵コンテ生成中...';

  @override
  String productionStoryboardSelectedCount(String count) {
    return '$count 件選択中';
  }

  @override
  String get productionStoryboardSelectAll => 'すべて選択';

  @override
  String get productionStoryboardClearSelection => '選択解除';

  @override
  String get productionStoryboardBatchGenerateImage => '画像生成';

  @override
  String get productionStoryboardDeleteNode => '削除';

  @override
  String get productionStoryboardEditNode => '編集';

  @override
  String get productionStoryboardScaleRatio => '拡大縮小';

  @override
  String get productionStoryboardNotGenerated => '未生成';

  @override
  String get productionStoryboardVideoDesc => '画面説明';

  @override
  String get productionStoryboardVideoDescPlaceholder => '画面説明を入力';

  @override
  String get productionStoryboardPrompt => 'プロンプト';

  @override
  String get productionStoryboardPromptPlaceholder => '絵コンテのプロンプトを入力';

  @override
  String get productionStoryboardConfirmDeleteBody => 'このカットを削除しますか？';

  @override
  String productionStoryboardConfirmBatchDeleteBody(String count) {
    return '選択した $count 件のカットを削除しますか？';
  }

  @override
  String get productionStoryboardInsertHint => 'カットを挿入';

  @override
  String get productionStoryboardEditImageEntry => 'ノードエディタ';

  @override
  String get productionChatDisabledHint => 'エージェントチャットは今後のバッチで提供予定';

  @override
  String get productionEmptyProject => '先にプロジェクトを選択してください';

  @override
  String get workbenchTitle => 'ワークベンチ';

  @override
  String get workbenchOpen => 'ワークベンチを開く';

  @override
  String get workbenchGenerateVideo => '動画を生成';

  @override
  String get workbenchGenerateAll => 'すべて動画生成';

  @override
  String get workbenchCompose => '話数を合成';

  @override
  String get workbenchComposing => '合成中...';

  @override
  String get workbenchComposeSuccess => '合成に成功しました';

  @override
  String workbenchComposeMissing(String count) {
    return '$count 件のカットで動画が未選択です';
  }

  @override
  String get workbenchNoShots => 'カットがありません。制作画面で絵コンテを生成してください';

  @override
  String get workbenchCandidateNotGenerated => '未生成';

  @override
  String get workbenchSelectCandidate => '採用する';

  @override
  String get workbenchSelected => '選択中';

  @override
  String get workbenchGeneratePrompt => 'カメラワークプロンプト生成';

  @override
  String get workbenchEditPrompt => 'カメラワークプロンプト編集';

  @override
  String get workbenchOutputPath => '出力パス';

  @override
  String get workbenchDuration => '再生時間';

  @override
  String get cornerScapeTitle => '配音';

  @override
  String get cornerScapeAutoMatch => 'AI自動マッチング';

  @override
  String get cornerScapeAutoMatching => 'マッチング中...';

  @override
  String get cornerScapeSelectAudio => '音声を選択';

  @override
  String get cornerScapeNoAudio => '未割り当て';

  @override
  String get cornerScapeNoAudioPool => '音声素材がありません。先にアセットでアップロードしてください';

  @override
  String get cornerScapeNoRoles => 'キャラクター資産がありません。先にアセットで作成してください';

  @override
  String get cornerScapeSelectAtLeastOne => 'キャラクターを1件以上選択してください';

  @override
  String get cornerScapeBindSuccess => '割り当てました';

  @override
  String get cornerScapeUnbind => '割り当て解除';

  @override
  String get promptStoryboardGenTitle => '絵コンテ生成';

  @override
  String get promptStoryboardGenDescription => '脚本をカットリストに分解するプロンプト';

  @override
  String get promptVideoPromptGenTitle => 'カメラワークプロンプト生成';

  @override
  String get promptVideoPromptGenDescription => 'カットを画像から動画へのプロンプトに変換';

  @override
  String get promptAudioBindTitle => '配音マッチング';

  @override
  String get promptAudioBindDescription => 'キャラクター説明から最適な音声を選ぶプロンプト';

  @override
  String get promptEventAnalysisTitle => 'イベント分析';

  @override
  String get promptEventAnalysisDescription => '章のイベントの改編価値を分析するプロンプト';

  @override
  String get stageEventExtractTitle => 'イベント抽出';

  @override
  String get stageEventExtractDescription => '章の内容から構造化イベント要約を抽出';

  @override
  String get stageVideoPromptGenTitle => 'カメラワークプロンプト生成';

  @override
  String get stageVideoPromptGenDescription => 'カット説明を画像から動画へのプロンプトに変換';

  @override
  String get stageScriptGenTitle => '脚本生成';

  @override
  String get stageScriptGenDescription => '小説を短編ドラマの脚本に改編';

  @override
  String get stageAssetExtractTitle => '素材抽出';

  @override
  String get stageAssetExtractDescription => '脚本からキャラクター・シーン・小道具を抽出';

  @override
  String get stageStoryboardGenTitle => '絵コンテ生成';

  @override
  String get stageStoryboardGenDescription => '話数をカットとプロンプトに分解';

  @override
  String get stageAssetImageTitle => '素材画像生成';

  @override
  String get stageAssetImageDescription => 'キャラクター・シーン・小道具の画像を生成';

  @override
  String get stageShotImageTitle => 'カット画像生成';

  @override
  String get stageShotImageDescription => '各カットの静止画を生成';

  @override
  String get stageShotVideoTitle => 'カット動画生成';

  @override
  String get stageShotVideoDescription => 'カット画像から短い動画を生成';

  @override
  String get stageTtsTitle => '音声生成';

  @override
  String get stageTtsDescription => 'カットのセリフの音声を生成';

  @override
  String stageBindingUpdated(String title) {
    return '$title の割り当てを更新しました';
  }

  @override
  String get stageBindingMissing => 'モデルが未割り当てです';

  @override
  String get agentChatTitle => '脚本エージェント';

  @override
  String get agentChatInputPlaceholder => '次に進める作業を教えてください。または「今の進捗は?」と聞いてください';

  @override
  String get agentChatSend => '送信';

  @override
  String get agentChatThinking => '考え中...';

  @override
  String get agentChatAutoMode => '自動連続実行';

  @override
  String get agentChatManualMode => '手動確認';

  @override
  String get agentChatClearMemory => '記憶を消去';

  @override
  String get agentChatConfirmClearTitle => '記憶を消去';

  @override
  String get agentChatConfirmClearBody => '会話履歴をすべて消去しますか？元に戻せません。';

  @override
  String get agentChatMemoryCleared => '記憶を消去しました';

  @override
  String get agentChatWelcome =>
      'こんにちは、脚本エージェントです。イベント抽出、素材抽出、絵コンテ生成、初期フレーム画像、動画生成、配音の割り当て、最終合成をお手伝いできます。何をしたいか教えてください。または「今の進捗は?」と聞いてください。';

  @override
  String agentChatToolExecuted(String tool) {
    return '実行しました：$tool';
  }

  @override
  String get agentChatModeHint => '手動モードは1ステップ実行して確認を待ちます。自動モードは安全上限内で連続実行します。';

  @override
  String get agentChatSkillsInfo => '組み込み機能';

  @override
  String get agentChatSkillsBody =>
      '私が呼び出せる機能はすべて既存パイプラインの実際の動作で、呼び出すたびにタスクセンターに確認・再試行可能な記録が残ります：イベント抽出、素材抽出、絵コンテ生成、初期フレーム画像生成、動画生成、配音マッチング、合成書き出し。カスタムスクリプト技能には対応していません。';

  @override
  String get cornerScapeSearchHint => 'キャラクター名を検索';

  @override
  String get cornerScapeFilterAll => 'すべて';

  @override
  String get cornerScapeFilterBound => '割り当て済み';

  @override
  String get cornerScapeFilterUnbound => '未割り当て';

  @override
  String get cornerScapeSelectAllUnbound => '未割り当てをすべて選択';

  @override
  String cornerScapeBoundSummary(int bound, int total) {
    return '割り当て済み $bound/$total';
  }

  @override
  String get cornerScapeNoMatch => '条件に一致するキャラクターがありません';

  @override
  String get storyboardPreviewAll => 'すべてプレビュー';

  @override
  String get storyboardPreviewEmpty => 'プレビューできる絵コンテがありません';

  @override
  String get storyboardPreviewImageMissing => '画像の読み込みに失敗しました';

  @override
  String storyboardPreviewCounter(String shot, String current, String total) {
    return '$shot（$current/$total）';
  }

  @override
  String storyboardPreviewShotPlaceholder(String shot) {
    return '$shot は初期フレーム画像が未生成です';
  }

  @override
  String get storyboardExportAll => 'すべて書き出し';

  @override
  String get storyboardExportNoImages => '書き出せる初期フレーム画像がまだありません';

  @override
  String storyboardExportSuccess(String count) {
    return '$count 枚の初期フレーム画像を書き出しました';
  }

  @override
  String storyboardExportFailed(String reason) {
    return '書き出しに失敗しました：$reason';
  }

  @override
  String get scriptPlanEmpty => '脚本プランはまだありません。全体の方向性・テンポ・要点をここに書き込みます。';

  @override
  String get scriptPlanWrite => 'プランを書く';

  @override
  String get scriptPlanEditTitle => '脚本プランを編集';

  @override
  String get scriptPlanEditHint =>
      'Markdown でプロジェクト全体の計画を記録：メインストーリー、キャラクターの成長、各話のテンポ、トーンとスタイル……';

  @override
  String get scriptPlanSaved => '脚本プランを保存しました';

  @override
  String get canvasChatTitle => '脚本エージェント';

  @override
  String get canvasChatOpen => 'エージェント対話';

  @override
  String get canvasChatClose => '閉じる';

  @override
  String get imageEditorModel => 'モデル';

  @override
  String get imageEditorRatio => 'アスペクト比';

  @override
  String get imageEditorQuality => '画質';

  @override
  String get imageEditorSelectModel => '先にモデルを選択してください';

  @override
  String get imageEditorSelectQuality => '画質を選択してください';

  @override
  String get imageEditorSelectRatio => 'アスペクト比を選択してください';

  @override
  String get imageEditorNoImageModel => '利用可能な画像モデルがありません';

  @override
  String get novelGenerateSelectedEvents => 'イベント生成';

  @override
  String scriptBatchAddMsgOverLimit(String limit) {
    return '1話あたりの文字数上限（$limit）を超えた話数があります。選択を外すか内容を短くしてください。';
  }

  @override
  String get artStyleLibraryTitle => '画風ライブラリ';

  @override
  String get artStyleManage => '画風ライブラリを管理';

  @override
  String get artStyleAddTitle => '画風を追加';

  @override
  String get artStyleEditTitle => '画風を編集';

  @override
  String get artStyleName => '画風名';

  @override
  String get artStyleNamePh => '例：2Dアニメ、写真リアル、3D CG';

  @override
  String get artStylePrompt => '画風プロンプト';

  @override
  String get artStylePromptPh => '例：(画風：2Dアニメ,2d animation style)';

  @override
  String get artStyleCover => 'カバー画像';

  @override
  String get artStyleUploadCover => 'カバーをアップロード';

  @override
  String get artStyleNameRequired => '画風名を入力してください';

  @override
  String get artStyleAddSuccess => '画風を追加しました';

  @override
  String get artStyleEditSuccess => '画風を更新しました';

  @override
  String get artStyleDeleted => '画風を削除しました';

  @override
  String get artStyleDeleteHeader => '画風を削除';

  @override
  String artStyleDeleteBody(String name) {
    return '画風「$name」を削除しますか？';
  }

  @override
  String get artStyleEmpty => '画風がまだありません。上から追加してください。';

  @override
  String get artStyleClose => '閉じる';

  @override
  String get clipUpload => '素材をアップロード';

  @override
  String get clipUploadTitle => '素材ファイルをアップロード';

  @override
  String get clipPickFile => 'ファイルを選択';

  @override
  String get clipNoFile => 'ファイル未選択';

  @override
  String get clipName => '素材名';

  @override
  String get clipNamePh => '空欄の場合はファイル名を使用';

  @override
  String get clipUploadSuccess => '素材をアップロードしました';

  @override
  String get clipUploadFailed => '素材のアップロードに失敗しました';

  @override
  String get assetBatchModel => 'モデル';

  @override
  String get assetBatchResolution => '解像度';

  @override
  String get assetBatchConcurrency => '並列数';

  @override
  String get assetBatchConcurrencyPh => '1-8';

  @override
  String get assetBatchOtherPrompt => '追加プロンプト';

  @override
  String get assetBatchOtherPromptPh => '推敲システムプロンプトに追記（任意）';

  @override
  String get assetBatchPickModel => 'ステージ既定を使用';

  @override
  String get manualImportFile => 'ファイルを取り込む';

  @override
  String get manualImportSuccess => 'ファイルを現在のタブに取り込みました';

  @override
  String get manualImportFailed => 'ファイルの取り込みに失敗しました';

  @override
  String get storyboardTableEmpty =>
      '絵コンテ表がまだありません。タップしてカット割り・尺・画面の要点を記入してください。';

  @override
  String get storyboardTableWrite => '絵コンテ表を書く';

  @override
  String get storyboardTableEditTitle => '絵コンテ表を編集';

  @override
  String get storyboardTableEditHint =>
      'Markdown でこの話数のカット割りを記録：カット番号、画面、カメラワーク、尺……';

  @override
  String get storyboardTableSaved => '絵コンテ表を保存しました';

  @override
  String get scriptNodeEditTitle => '脚本を編集';

  @override
  String get scriptNodeName => '名称';

  @override
  String get scriptNodeNamePlaceholder => '脚本名を入力してください';

  @override
  String get scriptNodeContent => '本文';

  @override
  String get scriptNodeContentPlaceholder => '脚本本文を入力してください';

  @override
  String get scriptNodeNameRequired => '脚本名を入力してください';

  @override
  String get scriptNodeSaved => '脚本を保存しました';

  @override
  String get productionStoryboardInsertBefore => '前に絵コンテを挿入';

  @override
  String get imageEditorPickFromAssets => '素材ライブラリから選択';

  @override
  String get imageEditorPickFromStoryboard => '絵コンテから選択';

  @override
  String get imageEditorPickImageTitle => '参照画像を選択';

  @override
  String get imageEditorPickImageSource => '画像ソースを選択';

  @override
  String get imageEditorPickLocalFile => 'ローカルファイル';

  @override
  String get imageEditorNoAssetsImages => '素材ライブラリに生成済み画像がありません';

  @override
  String get imageEditorNoStoryboardImages => '絵コンテに生成済みの初期フレームがありません';

  @override
  String get imageEditorRemoveEdge => 'この接続を削除';

  @override
  String get imageEditorEdgeRemoved => '接続を削除しました';

  @override
  String get workbenchPlayVideo => '再生';

  @override
  String get workbenchVideoLoadFailed => '動画の読み込みに失敗しました';

  @override
  String get workbenchDeleteCandidate => '候補を削除';

  @override
  String get workbenchDeleteCandidateConfirm => 'この候補動画を削除しますか？';

  @override
  String get workbenchSelectAsMain => '本編に採用';

  @override
  String get workbenchDurationSection => 'ショットの長さ';

  @override
  String get workbenchDurationUnset => '未設定';

  @override
  String workbenchDurationSeconds(int seconds) {
    return '$seconds秒';
  }

  @override
  String get workbenchEditDurationTitle => 'ショットの長さを編集';

  @override
  String get workbenchDurationFieldLabel => '長さ（秒）';

  @override
  String get workbenchEditPromptTitle => 'カメラワークのプロンプトを編集';

  @override
  String get workbenchPromptFieldHint => 'このショットのカメラワークと動きを記述';

  @override
  String get workbenchPromptEmpty => 'カメラワークのプロンプトがまだありません。生成または編集してください。';

  @override
  String get cornerScapeAudition => '試聴';

  @override
  String get cornerScapeStopAudition => '停止';

  @override
  String get cornerScapeAudioMissing => '音声ファイルがありません';

  @override
  String get cornerScapeAuditionFailed => '音声の再生に失敗しました';

  @override
  String get settingsOtherSection => 'その他';

  @override
  String get settingsOtherTitle => 'その他の設定';

  @override
  String get settingsOtherChapterReg => '章区切り正規表現';

  @override
  String get settingsOtherChapterRegHint => '空欄の場合は内蔵のデフォルト章正規表現を使用します';

  @override
  String get settingsOtherChapterRegRestore => 'デフォルトに戻す';

  @override
  String get settingsOtherEpisodeLength => '1話あたりの最大文字数';

  @override
  String get settingsOtherBatchSize => '一括生成数';

  @override
  String get settingsOtherSaved => 'その他の設定を保存しました';

  @override
  String get settingsOtherInvalidNumber => '0 より大きい整数を入力してください';

  @override
  String get settingsStorageOpenFolder => 'データフォルダを開く';

  @override
  String settingsStorageOpenFolderFailed(String reason) {
    return 'データフォルダを開けませんでした：$reason';
  }

  @override
  String get settingsStorageDbInfo => 'データベース情報';

  @override
  String get settingsStorageDbInfoTitle => 'データベース情報';

  @override
  String get settingsStorageTableColumn => 'テーブル';

  @override
  String get settingsStorageRowsColumn => '行数';

  @override
  String get settingsStorageClear => 'データを消去';

  @override
  String get settingsStorageClearConfirmTitle => 'すべてのデータを消去';

  @override
  String get settingsStorageClearConfirmBody =>
      'この操作はすべてのプロジェクト・章・脚本・アセット・タスク・メディアファイルを削除し、元に戻せません。続行しますか？';

  @override
  String get settingsStorageClearDone => 'データを消去しました';

  @override
  String get settingsAboutSection => '情報';

  @override
  String get settingsAboutTitle => 'DramaFlow について';

  @override
  String get settingsAboutAppName => 'アプリ名';

  @override
  String get settingsAboutVersion => 'バージョン';

  @override
  String get settingsAboutEngine => 'エンジンバージョン';

  @override
  String get settingsAboutDescription =>
      'DramaFlow はローカルで動作する AI ショートドラマ制作スタジオです。データとメディアはすべて本機に保存されます。';

  @override
  String get settingsProviderTestKind => 'モダリティ';

  @override
  String get settingsProviderTestNoModel => '先にテスト可能なモデルを 1 つ以上有効にしてください';

  @override
  String get taskFilterClass => 'タスク種別';

  @override
  String get taskFilterState => '状態';

  @override
  String get taskFilterAll => 'すべて';

  @override
  String get taskDetailTitle => 'タスク詳細';

  @override
  String get taskDetailClass => 'タスク種別';

  @override
  String get taskDetailState => '状態';

  @override
  String get taskDetailDescribe => '説明';

  @override
  String get taskDetailModel => 'モデル';

  @override
  String get taskDetailRelated => '関連オブジェクト';

  @override
  String get taskDetailReason => '失敗理由';

  @override
  String get taskDetailTiming => '開始時刻';

  @override
  String get taskDetailNone => 'なし';

  @override
  String get taskStatePending => '待機中';

  @override
  String get taskStateProcessing => '処理中';

  @override
  String get taskStateSuccess => '完了';

  @override
  String get taskStateFailed => '失敗';

  @override
  String get taskStateCanceled => 'キャンセル済み';

  @override
  String get commonClear => 'クリア';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonTest => 'テスト';

  @override
  String get commonRefresh => '更新';

  @override
  String get commonEnabled => '有効';

  @override
  String get commonActions => '操作';

  @override
  String get commonName => '名前';

  @override
  String get commonType => '種類';

  @override
  String get commonModel => 'モデル';

  @override
  String get commonUnset => '未設定';

  @override
  String get statusQueued => 'キュー中';

  @override
  String get statusPending => '待機中';

  @override
  String get statusRunning => '生成中';

  @override
  String get statusDone => '完了';

  @override
  String get statusFailed => '失敗';

  @override
  String get statusCanceled => 'キャンセル済み';

  @override
  String get statusDraft => '未生成';

  @override
  String get statusNotGenerated => '未生成';

  @override
  String get statusSuccessShort => '成功';

  @override
  String get statusPendingShort => '未処理';

  @override
  String dataTableTotal(int total) {
    return '全 $total 件';
  }

  @override
  String get dataTablePrevPage => '前のページ';

  @override
  String get dataTableNextPage => '次のページ';

  @override
  String get imageVersionsTitle => '画像バージョン';

  @override
  String get imageVersionsEmpty => '画像バージョンはまだありません';

  @override
  String imageVersionLabel(int index) {
    return 'バージョン $index';
  }

  @override
  String get repaintImageTitle => '画像を再生成';

  @override
  String get repaintImageHint => '例：服を赤色に変更';

  @override
  String get repaintInstructionRequired => '修正内容を入力してください';

  @override
  String get repaintAction => '再生成';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsAppearanceSection => '外観';

  @override
  String get settingsProvidersSection => 'プロバイダー';

  @override
  String get settingsBindingsSection => 'モデル割り当て';

  @override
  String get settingsPromptsSection => 'プロンプト';

  @override
  String get settingsStorageSection => 'ストレージとエンジン';

  @override
  String get settingsThemeLight => 'ライト';

  @override
  String get settingsThemeDark => 'ダーク';

  @override
  String get settingsThemeSystem => 'システム';

  @override
  String get settingsThemeUpdated => '外観を更新しました';

  @override
  String get localeChinese => '中文';

  @override
  String get localeJapanese => '日本語';

  @override
  String get modelKindText => 'テキスト';

  @override
  String get modelKindImage => '画像';

  @override
  String get modelKindVideo => '動画';

  @override
  String get modelKindTts => '音声';

  @override
  String get providerProtocolVolcengine => 'Volcengine';

  @override
  String get providerProtocolOpenAiCompatible => 'OpenAI 互換';

  @override
  String get settingsAddProvider => 'プロバイダーを追加';

  @override
  String get settingsProviderEmptyTitle => 'プロバイダーはまだありません';

  @override
  String get settingsProviderEmptySubtitle =>
      'OpenAI 互換または Volcengine プロバイダーを追加してから、モデルとステージ割り当てを設定してください。';

  @override
  String get settingsProviderAdded => 'プロバイダーを追加しました';

  @override
  String get settingsProviderUpdated => 'プロバイダーを更新しました';

  @override
  String get settingsProviderConfigMissing => '設定データにプロバイダー一覧がありません';

  @override
  String get settingsProviderMissing => 'プロバイダーが見つかりません';

  @override
  String get settingsProviderEnabled => 'プロバイダーを有効にしました';

  @override
  String get settingsProviderDisabled => 'プロバイダーを無効にしました';

  @override
  String settingsProviderTestSuccess(int elapsedMs) {
    return '接続成功：$elapsedMs ms';
  }

  @override
  String settingsProviderTestTitle(String name) {
    return '接続テスト · $name';
  }

  @override
  String get settingsDeleteProviderTitle => 'プロバイダーを削除';

  @override
  String settingsDeleteProviderMessage(String name) {
    return '“$name”を削除しますか？ステージに割り当てられている場合、エンジンは削除を拒否します。';
  }

  @override
  String get settingsProviderDeleted => 'プロバイダーを削除しました';

  @override
  String get settingsModelCount => 'モデル数';

  @override
  String get settingsManageModels => 'モデル管理';

  @override
  String get settingsTestConnection => '接続テスト';

  @override
  String get settingsEditProvider => 'プロバイダーを編集';

  @override
  String get settingsProviderName => '名前';

  @override
  String get settingsProviderNameHint => '例：azt';

  @override
  String get settingsKeepEmptyUnchanged => '空欄なら変更しません';

  @override
  String get settingsExportConfig => '設定をエクスポート';

  @override
  String get settingsImportConfig => '設定をインポート';

  @override
  String get settingsConfigPlaintextWarning =>
      '設定 JSON には平文のキーが含まれます。安全に保管してください。';

  @override
  String get settingsEmbeddedEngineNote =>
      'エンジンはアプリ内で動作し、データとメディアはすべてこの端末に保存されます。バックグラウンドサービスは不要です。';

  @override
  String get settingsEngineStatus => 'エンジン状態';

  @override
  String settingsExportPanelFailed(String reason) {
    return '保存パネルを開けませんでした：$reason';
  }

  @override
  String settingsExportFailed(String reason) {
    return '設定のエクスポートに失敗しました：$reason';
  }

  @override
  String get settingsConfigExported => '設定をエクスポートしました';

  @override
  String settingsOpenFileFailed(String reason) {
    return 'ファイル選択を開けませんでした：$reason';
  }

  @override
  String get settingsImportConfigTitle => '設定をインポート';

  @override
  String get settingsImportConfigMessage =>
      '同名のプロバイダー・モデル・割り当て・プロンプトが上書きされます。続行しますか？';

  @override
  String get settingsConfigInvalidFormat => '設定ファイル形式が無効です';

  @override
  String get settingsConfigInvalidJson => '設定ファイルは有効な JSON ではありません';

  @override
  String settingsImportFailed(String reason) {
    return '設定のインポートに失敗しました：$reason';
  }

  @override
  String get settingsConfigImported => '設定をインポートしました';

  @override
  String get settingsEngineChecking => 'エンジンを確認中…';

  @override
  String settingsEngineOk(String version) {
    return 'エンジン正常 · v$version';
  }

  @override
  String get settingsEngineUnknown => '不明';

  @override
  String get settingsProviderColumnProtocol => 'プロトコル';

  @override
  String get settingsProviderColumnBaseUrl => 'Base URL';

  @override
  String settingsModelManagementTitle(String name) {
    return 'モデル管理 · $name';
  }

  @override
  String get settingsAddModel => 'モデルを追加';

  @override
  String get settingsSaveModels => '保存';

  @override
  String get settingsModelsEmptyTitle => 'モデルはまだありません';

  @override
  String get settingsModelsEmptySubtitle =>
      'テキスト・画像・動画・音声モデルを少なくとも 1 つ追加してください。';

  @override
  String get settingsModelIdRequired => 'モデル ID は空にできません';

  @override
  String get settingsModelsSaved => 'モデルを保存しました';

  @override
  String get settingsDeleteModel => 'モデルを削除';

  @override
  String get settingsBindingModel => '割り当てモデル';

  @override
  String get settingsSelectEnabledModel => '有効なモデルを選択してください';

  @override
  String get settingsSelectModel => 'モデルを選択';

  @override
  String get settingsPromptContent => 'プロンプト内容';

  @override
  String get taskCenterTitle => 'タスクセンター';

  @override
  String get taskActiveTitle => '進行中';

  @override
  String get taskActiveEmpty => '進行中のタスクはありません';

  @override
  String get taskHistoryTitle => '履歴';

  @override
  String get taskNoProjects => 'プロジェクトはまだありません';

  @override
  String get taskHistoryEmpty => 'このプロジェクトに履歴タスクはありません';

  @override
  String get taskFilterEmpty => '条件に一致するタスクはありません';

  @override
  String get taskEmpty => 'タスクはありません';

  @override
  String taskProjectLabel(int id) {
    return 'プロジェクト #$id';
  }

  @override
  String get taskCancelTooltip => 'タスクをキャンセル';

  @override
  String get taskCanceledMessage => 'タスクをキャンセルしました';

  @override
  String get taskRetryQueued => '再度キューに追加しました';

  @override
  String get taskClassEventGeneration => 'イベント生成';

  @override
  String get taskClassAssetExtraction => 'アセット抽出';

  @override
  String get taskClassGeneric => 'タスク';

  @override
  String get webPreviewBuildableTitle => 'Web プレビュー入口をビルドできるようになりました。';

  @override
  String get webPreviewMessage =>
      '完全なローカルエンジンはまだ移植中です。ブラウザ版には Web データベース、ブラウザ内ファイル保存、WebCodecs/Mediabunny 合成器、Web 向けメディアプレビュー対応が必要です。現時点では macOS、iOS、Android クライアントがフル機能の本線です。';

  @override
  String get webPreviewMacClient => 'macOS フルクライアント';

  @override
  String get webPreviewIosClient => 'iOS フルクライアント';

  @override
  String get webPreviewAndroidClient => 'Android APK ビルド可';

  @override
  String get webPreviewEnginePending => 'Web エンジン移植待ち';
}
