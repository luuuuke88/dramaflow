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

  @override
  String get errTaskUnsupported => 'Unsupported task type';

  @override
  String get shellSelectProject => 'Select a project';

  @override
  String shellComingSoon(String batch) {
    return 'This area ships with batch $batch';
  }

  @override
  String shellComingSoonBadge(String batch) {
    return '$batch';
  }

  @override
  String get projectTitle => 'My Projects';

  @override
  String get projectSubtitle => 'Manage all your short drama projects';

  @override
  String get projectNewProject => 'New Project';

  @override
  String get projectDialogEditTitle => 'Edit Project';

  @override
  String get projectDialogAddTitle => 'New Project';

  @override
  String get projectDialogSave => 'Save';

  @override
  String get projectDialogOk => 'OK';

  @override
  String get projectDialogCancel => 'Cancel';

  @override
  String get projectDialogProjectType => 'Project Type';

  @override
  String get projectDialogSelectType => 'Select Project Type';

  @override
  String get projectDialogBasedOnNovel => 'Based on Novel Text';

  @override
  String get projectDialogProjectName => 'Project Name';

  @override
  String get projectDialogProjectNamePh => 'Please enter project name';

  @override
  String get projectDialogNovelType => 'Novel Genre';

  @override
  String get projectDialogNovelTypePh => 'e.g., Fantasy, Sci-Fi, Romance';

  @override
  String get projectDialogArtStyle => 'Art Style';

  @override
  String get projectDialogSelected => 'Selected:';

  @override
  String get projectDialogSelectArtStyle => 'Please select an art style';

  @override
  String get projectDialogNewArtStyle => 'New art style';

  @override
  String get projectDialogLoading => 'Loading...';

  @override
  String get projectDialogVideoRatio => 'Video Ratio';

  @override
  String get projectDialogNovelIntro => 'Novel Synopsis';

  @override
  String get projectDialogNovelIntroPh => 'Please enter novel synopsis';

  @override
  String get projectDialogEditArtStyleTitle => 'Edit art style';

  @override
  String get projectDialogNewArtStyleTitle => 'New art style';

  @override
  String get projectDialogArtStyleName => 'Art style name';

  @override
  String get projectDialogArtStyleNamePh => 'Please enter art style name';

  @override
  String get projectDialogArtStyleImage => 'Art style image';

  @override
  String get projectDialogRemove => 'Remove';

  @override
  String get projectDialogUploadCover => 'Upload Cover';

  @override
  String get projectDialogArtStylePrompt => 'Prompt';

  @override
  String get projectDialogAiExtract => 'AI Extract Prompt';

  @override
  String get projectDialogPromptPlaceholder => 'Enter prompt';

  @override
  String get projectDialogVisualManual => 'Visual Manual';

  @override
  String get projectDialogNewVisualManual => 'New visual manual';

  @override
  String get projectDialogEditVisualManualTitle => 'Edit visual manual';

  @override
  String get projectDialogNewVisualManualTitle => 'New visual manual';

  @override
  String get projectDialogVisualManualName => 'Visual manual name';

  @override
  String get projectDialogVisualManualNamePh =>
      'Please enter visual manual name';

  @override
  String get projectDialogVisualManualCover => 'Visual manual cover';

  @override
  String get projectDialogVisualManualPrompt => 'Visual manual prompt';

  @override
  String get projectDialogModelData => 'Select image model';

  @override
  String get projectDialogVideoModelData => 'Select video model';

  @override
  String get projectDialogPromptSaveSuccess => 'Update successful';

  @override
  String get projectDialogPromptTitle => 'prompt word';

  @override
  String get projectDialogBasedOnScript => 'based on script';

  @override
  String get projectDialogMdFile => 'visual manual file';

  @override
  String get projectDialogDirectorManual => 'Director\'s Handbook';

  @override
  String get projectDialogAddDirectorManual => 'New director manual';

  @override
  String get projectDialogEditingDirectorManual => 'Edit Director\'s Manual';

  @override
  String get projectDialogNewDirecorManualTitle => 'New director manual';

  @override
  String get projectDialogDirectorManualPrompt =>
      'Director\'s Manual Prompt Words';

  @override
  String get projectDialogDirectorManualName => 'Director\'s Manual Name';

  @override
  String get projectDialogDirectorManualNamePh =>
      'Enter Director\'s Manual name';

  @override
  String get projectDialogDirectorFile => 'Director\'s Manual Document';

  @override
  String get projectDialogDirectorManualCover => 'Director\'s Manual Cover';

  @override
  String get projectMsgFetchFailed => 'Failed to fetch project list';

  @override
  String get projectMsgNotFound => 'Project not found!';

  @override
  String get projectMsgEditSuccess => 'Project edited successfully';

  @override
  String get projectMsgEditFailed => 'Failed to edit project';

  @override
  String get projectMsgAddSuccess => 'Project created successfully';

  @override
  String get projectMsgAddFailed => 'Failed to create project';

  @override
  String get projectMsgDeleteHeader => 'Delete Project';

  @override
  String get projectMsgDeleteBody =>
      'Are you sure you want to delete this project?';

  @override
  String get projectMsgDeleteConfirm => 'Delete';

  @override
  String get projectMsgDeleteCancel => 'Cancel';

  @override
  String get projectMsgDeleteSuccess => 'Project deleted successfully';

  @override
  String get projectMsgDeleteFailed => 'Failed to delete project';

  @override
  String get projectMsgExtractSuccess => 'Prompt extracted successfully';

  @override
  String get projectMsgExtractFailed => 'Extraction failed';

  @override
  String get projectMsgEnterArtStyleName => 'Please enter art style name';

  @override
  String get projectMsgArtStyleUpdated => 'Art style updated';

  @override
  String get projectMsgArtStyleAdded => 'Art style added';

  @override
  String get projectMsgOperationFailed => 'Operation failed';

  @override
  String get projectMsgEnterVisualManualName =>
      'Please enter visual manual name';

  @override
  String get projectMsgEnterVisualManualImage =>
      'Please upload a cover image for the visual manual';

  @override
  String get projectMsgEnterVisualManualTabData => 'prompt cannot be empty';

  @override
  String get projectMsgVisualManualUpdated => 'Visual manual updated';

  @override
  String get projectMsgVisualManualAdded => 'Visual manual added';

  @override
  String get projectMsgDeleteVisualManualHeader => 'Delete Visual Manual';

  @override
  String projectMsgDeleteVisualManualBody(String name) {
    return 'Are you sure you want to delete visual manual \"$name\"?';
  }

  @override
  String get projectMsgDeleteVisualManualConfirm => 'Delete';

  @override
  String get projectMsgDeleteVisualManualCancel => 'Cancel';

  @override
  String get projectMsgEnterProjectName => 'Please enter project name';

  @override
  String get projectMsgEnterProjectIntro =>
      'Please enter the novel introduction';

  @override
  String get projectMsgEnterProjectType => 'Please enter project type';

  @override
  String get projectMsgEnterArtStyle =>
      'Please select a project visual brochure';

  @override
  String get projectMsgEnterVideoRatio => 'Please select video ratio';

  @override
  String get projectMsgEnterImageModel => 'Please select a picture model';

  @override
  String get projectMsgEnterVideoModel => 'Please select a video model';

  @override
  String get projectMsgVisualManualDeleted => 'Delete successfully';

  @override
  String get projectMsgSelectMode => 'Please select mode';

  @override
  String get projectMsgDeleteDirectorManualHeader =>
      'Delete Director\'s Manual';

  @override
  String projectMsgDeleteDirectorManualBody(String name) {
    return 'Are you sure you want to delete Director\'s Manual \"$name\"?';
  }

  @override
  String get projectMsgDirectorManualUpdated => 'Director\'s Manual updated';

  @override
  String get projectMsgDirectorManualAdded => 'Director\'s Manual added';

  @override
  String get projectMsgDirectorManual =>
      'Please select Project Director\'s Manual';

  @override
  String get projectMsgModelProviderDisabled =>
      'The video model or picture model supplier is not enabled or there is no model supplier, please configure it first';

  @override
  String get projectTypeNovel => 'Based on the original novel';

  @override
  String get projectTypeScript => 'Based on novel script';

  @override
  String get commonEdit => 'Edit';

  @override
  String get manualTabReadme => 'README';

  @override
  String get manualTabPrefix => 'Prefix';

  @override
  String get manualTabCharacter => 'Character';

  @override
  String get manualTabCharacterDerivative => 'Character Derivative';

  @override
  String get manualTabProp => 'Prop';

  @override
  String get manualTabPropDerivative => 'Prop Derivative';

  @override
  String get manualTabScene => 'Scene';

  @override
  String get manualTabSceneDerivative => 'Scene Derivative';

  @override
  String get manualTabStoryboard => 'Storyboard';

  @override
  String get manualTabStoryboardVideo => 'Storyboard Video';

  @override
  String get manualTabDirectorPlanning => 'Technique - Director Planning';

  @override
  String get manualTabStoryboardTable => 'Technique - Storyboard Table';

  @override
  String get manualTabNarrativePlanning => 'Director Planning';

  @override
  String get manualTabNarrativeTable => 'Storyboard Table';

  @override
  String get errManualInvalid => 'Invalid manual data';

  @override
  String get novelImportText => 'Import Text';

  @override
  String get novelBatchDelete => 'Batch Delete';

  @override
  String get novelEventAnalysis => 'Event Analysis';

  @override
  String get novelSearchPlaceholder => 'Search text names...';

  @override
  String get novelSearch => 'Search';

  @override
  String get novelGenerating => 'Generating...';

  @override
  String get novelGenFailed => 'Generation failed';

  @override
  String get novelViewDetail => 'View Details';

  @override
  String get novelNone => 'None';

  @override
  String get novelEdit => 'Edit';

  @override
  String get novelDelete => 'Delete';

  @override
  String get novelColId => 'No.';

  @override
  String get novelColReel => 'Volume';

  @override
  String get novelColChapter => 'Chapter Name';

  @override
  String get novelColChapterData => 'Chapter Content';

  @override
  String get novelColEvent => 'Event';

  @override
  String get novelColOperation => 'Operation';

  @override
  String get novelMsgBatchDeleteHeader => 'Batch Delete';

  @override
  String novelMsgBatchDeleteBody(String count) {
    return 'Are you sure you want to delete the selected $count items?';
  }

  @override
  String get novelMsgBatchDeleteSuccess => 'Batch delete successful';

  @override
  String get novelMsgDeleteHeader => 'Confirm Deletion';

  @override
  String novelMsgDeleteBody(String name) {
    return 'Are you sure you want to delete the chapter named \"$name\"?';
  }

  @override
  String get novelMsgDeleteSuccess => 'Deleted successfully';

  @override
  String get novelMsgEventAnalysisHeader => 'Event Analysis';

  @override
  String novelMsgEventAnalysisBody(String count) {
    return 'Are you sure you want to analyze events for the selected $count items?';
  }

  @override
  String get novelImportTitle => 'Upload Novel Text';

  @override
  String get novelImportStep1 => 'Step 1';

  @override
  String get novelImportStep2 => 'Step 2';

  @override
  String get novelImportStep3 => 'Step 3';

  @override
  String get novelImportDragUpload =>
      'Drag and drop your novel file here or click to upload';

  @override
  String get novelImportUploadHint =>
      'Supports .txt, .docx. Recommended file size under 10MB';

  @override
  String get novelImportOr => 'OR';

  @override
  String get novelImportPasteLabel => 'Directly paste novel text';

  @override
  String get novelImportPastePlaceholder => 'Please paste novel text here';

  @override
  String get novelImportChars => 'chars';

  @override
  String get novelImportTooShort =>
      'Content is too short, recommend at least 100 characters';

  @override
  String novelImportParsedChapters(String count) {
    return '$count chapters parsed';
  }

  @override
  String get novelImportNextStep => 'Next';

  @override
  String get novelImportPrevStep => 'Previous';

  @override
  String novelImportSelectedInfo(String count) {
    return 'Selected: $count chars (Must be < 200,000)';
  }

  @override
  String get novelImportEventAnalysis => 'Event Analysis';

  @override
  String get novelImportSaveAndAnalyze => 'Save Text and Analyze Events';

  @override
  String get novelImportColChapter => 'Chapter';

  @override
  String get novelImportColReel => 'Volume';

  @override
  String get novelImportColChapterName => 'Chapter Name';

  @override
  String get novelImportColChapterData => 'Chapter Content';

  @override
  String get novelImportMsgParseFailed =>
      'Failed to parse file. Please re-upload';

  @override
  String get novelImportMsgSelectFile => 'Select file';

  @override
  String get novelImportMsgDocNotSupported =>
      '.doc files do not support parsing, please convert to .ts files';

  @override
  String get novelImportMsgUnsupportedType => 'Unsupported file type';

  @override
  String get novelImportMsgFileTooLarge =>
      'File exceeds 10MB. Please upload a smaller file';

  @override
  String get novelImportMsgSelectChapters => 'Please select chapters first';

  @override
  String get novelImportMsgSaveSuccess => 'Novel text saved successfully';

  @override
  String get novelImportImportAdd =>
      'Drag and drop files here or click to upload';

  @override
  String get novelImportLimit => 'Support .ts format';

  @override
  String get novelEditDialogTitle => 'Edit Novel Text';

  @override
  String get novelEditDialogChapterName => 'Chapter Name';

  @override
  String get novelEditDialogChapterNamePh => 'Please enter chapter name';

  @override
  String get novelEditDialogEventContent => 'Event Content';

  @override
  String get novelEditDialogEventContentPh => 'Enter event content';

  @override
  String get novelEditDialogChapterContent => 'Chapter Content';

  @override
  String get novelEditDialogChapterContentPh => 'Please enter chapter content';

  @override
  String get novelEditDialogCancel => 'Cancel';

  @override
  String get novelEditDialogSave => 'Save';

  @override
  String get novelEditDialogMsgUpdateSuccess =>
      'Novel text updated successfully';

  @override
  String get novelEventRegenerate => 'Regenerate Events';

  @override
  String get novelEventBatchDelete => 'Batch Delete';

  @override
  String get novelEventNoData => 'No event data. Click to start generation';

  @override
  String get novelEventGenerate => 'Generate Events';

  @override
  String get novelEventGeneratingHint => 'Generating events, please wait...';

  @override
  String get novelEventLoading => 'Loading...';

  @override
  String get novelEventDelete => 'Delete';

  @override
  String get novelEventColId => 'Event ID';

  @override
  String get novelEventColEventName => 'Event Name';

  @override
  String get novelEventColChapters => 'Source Chapter';

  @override
  String get novelEventColDetail => 'Event Details';

  @override
  String get novelEventColCreateTime => 'Created Time';

  @override
  String get novelEventColOperation => 'Operation';

  @override
  String get novelEventMsgDeleteHeader => 'Delete Event';

  @override
  String get novelEventMsgDeleteBody =>
      'Are you sure you want to delete this event?';

  @override
  String get novelEventMsgDeleteSuccess => 'Deleted successfully';

  @override
  String get novelEventMsgGenerateSuccess => 'Events generated successfully';

  @override
  String get novelEventMsgBatchDeleteHeader => 'Batch Delete';

  @override
  String novelEventMsgBatchDeleteBody(String count) {
    return 'Are you sure you want to delete the selected $count items?';
  }

  @override
  String get novelEventMsgBatchDeleteSuccess => 'Batch delete successful';

  @override
  String get novelAnalysisAnalyzeFirst => 'Please analyze events first';

  @override
  String get novelAnalysisStartAnalysis => 'Start Analysis';

  @override
  String novelAnalysisChapterHeader(String index, String name) {
    return 'Chapter $index - $name';
  }

  @override
  String get novelAnalysisAnalyzing => 'Analyzing events';

  @override
  String get scriptSearchPlaceholder => 'Search script names...';

  @override
  String get scriptSearch => 'Search';

  @override
  String get scriptAddScript => 'New Script';

  @override
  String get scriptCancelSelectAll => 'Deselect All';

  @override
  String get scriptSelectAll => 'Select All';

  @override
  String get scriptExportScript => 'Export Script';

  @override
  String get scriptMsgExtracting => '资产提取中';

  @override
  String get scriptMsgExtractFailed => '资产提取失败';

  @override
  String get scriptMsgExtractingInProgress => 'Extracting';

  @override
  String get scriptMsgProjectNotFound => 'Item not found';

  @override
  String get scriptMsgSelectExport => 'Please select a script to export';

  @override
  String get scriptMsgDeleteHeader => 'Confirm Deletion';

  @override
  String get scriptMsgDeleteBody =>
      'Are you sure you want to delete this script? This cannot be undone.';

  @override
  String get scriptMsgDeleteConfirm => 'Delete';

  @override
  String get scriptMsgCancel => 'Cancel';

  @override
  String get scriptMsgDeleteSuccess => 'Deleted successfully';

  @override
  String get scriptMsgDeleteFailed => 'Deletion failed';

  @override
  String get scriptMsgSelectDelScript => 'Please choose to delete the script';

  @override
  String get scriptMsgBatchDeleteHeader => 'Batch Delete';

  @override
  String scriptMsgBatchDeleteBody(String count) {
    return 'Are you sure you want to delete the selected $count scripts? This cannot be undone.';
  }

  @override
  String get scriptMsgBatchDeleteSuccess => 'Batch deletion successful';

  @override
  String get scriptMsgSearchFailed => 'Failed to search scripts';

  @override
  String get scriptMsgSelectsExport => 'Please choose to export the script';

  @override
  String get scriptAddTitle => 'Add Script';

  @override
  String get scriptAddScriptName => 'Script Name';

  @override
  String get scriptAddScriptNamePh => 'Please enter script name';

  @override
  String get scriptAddUploadFile => 'Upload File';

  @override
  String get scriptAddDragUpload =>
      'Drag and drop your script file here or click to upload';

  @override
  String get scriptAddUploadHint =>
      'Supports .txt, .docx. Recommended file size under 10MB';

  @override
  String get scriptAddScriptContent => 'Script Content';

  @override
  String get scriptAddScriptContentPh =>
      'Please upload or enter script content...';

  @override
  String get scriptAddRelatedAssets => 'Related Assets';

  @override
  String get scriptAddSelectAssets => 'Select Assets';

  @override
  String get scriptAddNoAssets => 'No related assets';

  @override
  String get scriptAddCancel => 'Cancel';

  @override
  String get scriptAddConfirm => 'Confirm';

  @override
  String get scriptAddMsgFileReadFailed => 'Failed to read file';

  @override
  String get scriptAddMsgDocNotSupported =>
      '.doc parsing is not supported. Please convert to .txt or .docx';

  @override
  String get scriptAddMsgUnsupportedType => 'Unsupported file type';

  @override
  String get scriptAddMsgFileTooLarge =>
      'File exceeds 10MB. Please upload a smaller file';

  @override
  String get scriptAddMsgParsing => 'Parsing file...';

  @override
  String get scriptAddMsgParseFailed =>
      'Failed to parse file, please re-upload';

  @override
  String get scriptAddMsgSelectAssetsTitle => 'Select Related Assets';

  @override
  String get scriptAddMsgEnterContent =>
      'Please upload or enter script content';

  @override
  String get scriptAddMsgEnterName => 'Please enter script name';

  @override
  String get scriptAddMsgAddSuccess => 'Script added successfully';

  @override
  String get scriptAddMsgAddFailed =>
      'Failed to add script, please try again later';

  @override
  String get scriptEditTitle => 'Script Details';

  @override
  String get scriptEditScriptName => 'Script Name';

  @override
  String get scriptEditScriptNamePh => 'Please enter script name';

  @override
  String get scriptEditScriptContent => 'Script Content';

  @override
  String get scriptEditScriptContentPh => 'Please enter script content...';

  @override
  String get scriptEditRelatedAssets => 'Related Assets';

  @override
  String get scriptEditSelectAssets => 'Select Assets';

  @override
  String get scriptEditNoAssets => 'No related assets';

  @override
  String get scriptEditMsgSelectAssetsTitle => 'Select Related Assets';

  @override
  String get scriptEditMsgUpdateSuccess => 'Script updated successfully';

  @override
  String get scriptEditMsgUpdateFailed =>
      'Failed to update script, please try again later';

  @override
  String get scriptDeleteScript => 'Delete scripts in batches';

  @override
  String get scriptExtractAssets => '';

  @override
  String get scriptImportGetAiRegex => 'AI解析正则';

  @override
  String get scriptImportEpisodeRegexPh =>
      'Customize the script splitting rule, leave it blank to use the default splitting rule (the default is to split according to the Episode X format)';

  @override
  String get scriptBatchAdd => 'Batch Add';

  @override
  String get scriptStateWaiting => 'Waiting...';

  @override
  String get scriptStateExtracting => 'Extracting...';

  @override
  String get scriptStateFailed => 'Extraction failed';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get localeSystem => 'System';

  @override
  String get assetsTabRole => 'Roles';

  @override
  String get assetsTabTool => 'Props';

  @override
  String get assetsTabScene => 'Scenes';

  @override
  String get assetsTabClip => 'Clips';

  @override
  String get assetsTabAudio => 'Audio';

  @override
  String get assetsAddPrefix => 'Add';

  @override
  String get assetsGeneratePrompt => 'Generate Prompts';

  @override
  String get assetsGenerateImage => 'Generate Images';

  @override
  String get assetsBatchDelete => 'Batch Delete';

  @override
  String get assetsSearchPlaceholder => 'Search asset name...';

  @override
  String get assetsColPreview => 'Preview';

  @override
  String get assetsColName => 'Name';

  @override
  String get assetsColPrompt => 'Prompt';

  @override
  String get assetsColDescribe => 'Description';

  @override
  String get assetsColRemark => 'Remark';

  @override
  String get assetsColCreateTime => 'Created';

  @override
  String get assetsColOperation => 'Actions';

  @override
  String get assetsGenerate => 'Generate';

  @override
  String get assetsEdit => 'Edit';

  @override
  String get assetsDelete => 'Delete';

  @override
  String get assetsGenerating => 'Generating...';

  @override
  String get assetsConfirmDeleteHeader => 'Confirm Delete';

  @override
  String get assetsConfirmDeleteBody =>
      'Delete this asset? Its image versions and children will also be removed';

  @override
  String assetsConfirmBatchDeleteBody(String count) {
    return 'Delete the selected $count assets?';
  }

  @override
  String get assetsDeleteSuccess => 'Deleted';

  @override
  String get assetsSex => 'Gender';

  @override
  String get assetsAudioName => 'Voice';

  @override
  String get assetsAudioText => 'Audio Text';

  @override
  String get assetsPlay => 'Play';

  @override
  String get assetsAddName => 'Name';

  @override
  String get assetsAddNamePh => 'Enter asset name';

  @override
  String get assetsAddNameRequired => 'Please enter asset name';

  @override
  String get assetsAddDescribe => 'Description';

  @override
  String get assetsAddDescribePh => 'Enter asset description';

  @override
  String get assetsAddDescribeRequired => 'Please enter description';

  @override
  String get assetsAddRemark => 'Remark';

  @override
  String get assetsAddRemarkPh => 'Enter remark';

  @override
  String get assetsAddPrompt => 'Prompt';

  @override
  String get assetsAddPromptPh => 'Enter generation prompt';

  @override
  String get assetsAddAddSuccess => 'Asset added';

  @override
  String get assetsAddUpdateSuccess => 'Asset updated';

  @override
  String get assetsAddAudioNamePh => 'Enter voice name';

  @override
  String get assetsAddSexPh => 'Enter gender';

  @override
  String get assetsAddAudioFile => 'Audio file';

  @override
  String get assetsAddAudioTextPh => 'Enter the text of this audio';

  @override
  String get assetsAddAudioDescPh => 'Enter audio description';

  @override
  String get assetsAddAudioItem => 'Add audio';

  @override
  String get assetsAddPleaseUploadAudio => 'Please upload an audio file';

  @override
  String get assetsGenHeader => 'Generate Image';

  @override
  String get assetsGenUploadRef => 'Reference';

  @override
  String get assetsGenOptional => 'optional';

  @override
  String get assetsGenPromptLabel => 'Prompt';

  @override
  String get assetsGenSmartGenerate => 'Smart Generate';

  @override
  String get assetsGenSelectModel => 'Model';

  @override
  String get assetsGenSelectResolution => 'Resolution';

  @override
  String get assetsGenGenerateBtn => 'Generate';

  @override
  String get assetsGenFillPrompt => 'Please fill the prompt';

  @override
  String get assetsGenPickModel => 'Please pick a model';

  @override
  String assetsGenGeneratedCount(String count) {
    return '$count generated';
  }

  @override
  String get assetsGenGeneratingLabel => 'Generating...';

  @override
  String get assetsGenGenFailed => 'Failed';

  @override
  String get assetsGenImageSaved => 'Image saved';

  @override
  String get assetsGenAssetGenSuccess => 'Generation submitted';

  @override
  String get assetsGenPromptSuccess => 'Prompt generated';

  @override
  String get assetsGenConfirmSelect => 'Select an image first';

  @override
  String get assetsGenResultTitle => 'Results';

  @override
  String get assetsBatchHeader => 'Batch Generation';

  @override
  String assetsBatchSelected(String count) {
    return '$count selected';
  }

  @override
  String get assetsBatchSelectAll => 'Select All';

  @override
  String get assetsBatchClearSelection => 'Clear';

  @override
  String get assetsBatchColPreviewImg => 'Preview';

  @override
  String get assetsBatchInputPh => 'Enter prompt';

  @override
  String assetsBatchSaveSelected(String count) {
    return 'Save selected ($count)';
  }

  @override
  String get assetsBatchMissingPrompts =>
      'Generate prompts for selection first';

  @override
  String get assetsBatchPromptDone => 'Batch prompt generation submitted';

  @override
  String get assetsBatchImageDone => 'Batch image generation submitted';

  @override
  String get assetsBatchSaveSuccess => 'Saved';

  @override
  String get assetsCancelBtn => 'Cancel';

  @override
  String get assetsSelectAtLeastOne => 'Select at least one item';

  @override
  String get productionEditImageInvalidConnection =>
      'Cannot connect: target must be a generation node and not duplicate';

  @override
  String get productionEditImageUploadImage => 'Upload Image';

  @override
  String get productionEditImageImageGeneration => 'Image Generation';

  @override
  String get productionEditImageGenerating => 'Generating...';

  @override
  String get productionEditImagePromptPlaceholder =>
      'Describe what to generate';

  @override
  String get productionEditImageGenerateBtn => 'Generate';

  @override
  String get productionEditImageUpload => 'Upload Node';

  @override
  String get productionEditImageGenerate => 'Generation Node';

  @override
  String get productionNodeScriptTitle => 'Script';

  @override
  String get productionNodeScriptPlanTitle => 'Script Plan';

  @override
  String get productionNodeAssetsTitle => 'Assets';

  @override
  String get productionNodeStoryboardTableTitle => 'Storyboard Table';

  @override
  String get productionNodeStoryboardTitle => 'Storyboard';

  @override
  String get productionNodeWorkbenchTitle => 'Workbench';

  @override
  String get productionSelectEpisode => 'Select episode';

  @override
  String get productionNoScripts => 'No scripts yet — create one in Scripts';

  @override
  String get productionGoToScripts => 'Go create a script';

  @override
  String get productionStoryboardGenerate => 'Generate Storyboard';

  @override
  String get productionStoryboardGenerating => 'Generating storyboard...';

  @override
  String productionStoryboardSelectedCount(String count) {
    return '$count selected';
  }

  @override
  String get productionStoryboardSelectAll => 'Select All';

  @override
  String get productionStoryboardClearSelection => 'Clear';

  @override
  String get productionStoryboardBatchGenerateImage => 'Generate Images';

  @override
  String get productionStoryboardDeleteNode => 'Delete';

  @override
  String get productionStoryboardEditNode => 'Edit';

  @override
  String get productionStoryboardScaleRatio => 'Scale';

  @override
  String get productionStoryboardNotGenerated => 'Not generated';

  @override
  String get productionStoryboardVideoDesc => 'Shot description';

  @override
  String get productionStoryboardVideoDescPlaceholder =>
      'Enter shot description';

  @override
  String get productionStoryboardPrompt => 'Prompt';

  @override
  String get productionStoryboardPromptPlaceholder => 'Enter shot prompt';

  @override
  String get productionStoryboardConfirmDeleteBody => 'Delete this shot?';

  @override
  String productionStoryboardConfirmBatchDeleteBody(String count) {
    return 'Delete the selected $count shots?';
  }

  @override
  String get productionStoryboardInsertHint => 'Insert shot';

  @override
  String get productionStoryboardEditImageEntry => 'Node Editor';

  @override
  String get productionChatDisabledHint => 'Agent chat ships in a later batch';

  @override
  String get productionEmptyProject => 'Select a project first';

  @override
  String get workbenchTitle => 'Workbench';

  @override
  String get workbenchOpen => 'Open Workbench';

  @override
  String get workbenchGenerateVideo => 'Generate Video';

  @override
  String get workbenchGenerateAll => 'Generate All Videos';

  @override
  String get workbenchCompose => 'Compose Episode';

  @override
  String get workbenchComposing => 'Composing...';

  @override
  String get workbenchComposeSuccess => 'Composed successfully';

  @override
  String workbenchComposeMissing(String count) {
    return '$count shots have no selected video';
  }

  @override
  String get workbenchNoShots =>
      'No shots yet — generate storyboard in Production first';

  @override
  String get workbenchCandidateNotGenerated => 'Not generated';

  @override
  String get workbenchSelectCandidate => 'Use this take';

  @override
  String get workbenchSelected => 'Selected';

  @override
  String get workbenchGeneratePrompt => 'Generate Motion Prompt';

  @override
  String get workbenchEditPrompt => 'Edit Motion Prompt';

  @override
  String get workbenchOutputPath => 'Output path';

  @override
  String get workbenchDuration => 'Duration';

  @override
  String get cornerScapeTitle => 'Voice';

  @override
  String get cornerScapeAutoMatch => 'AI Auto-Match';

  @override
  String get cornerScapeAutoMatching => 'Matching...';

  @override
  String get cornerScapeSelectAudio => 'Select audio';

  @override
  String get cornerScapeNoAudio => 'Unbound';

  @override
  String get cornerScapeNoAudioPool =>
      'No audio assets yet — upload some in Assets first';

  @override
  String get cornerScapeNoRoles =>
      'No role assets yet — create roles in Assets first';

  @override
  String get cornerScapeSelectAtLeastOne => 'Select at least one role';

  @override
  String get cornerScapeBindSuccess => 'Bound';

  @override
  String get cornerScapeUnbind => 'Unbind';
}
