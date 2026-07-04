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
  String get errPlatformComposer => 'Platform video composing failed';

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
  String get promptGlobalTemplates => 'Global Templates';

  @override
  String get promptModelTemplates => 'Model-Specific Templates';

  @override
  String get promptModelTemplatesEmpty =>
      'No model-specific templates yet. Imported configs or model templates will appear here.';

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
  String get projectTitle => 'My Projects';

  @override
  String get projectSubtitle => 'Manage all your short drama projects';

  @override
  String get projectNewProject => 'New Project';

  @override
  String projectStatChapters(int count) {
    return 'Chapters $count';
  }

  @override
  String projectStatScripts(int count) {
    return 'Scripts $count';
  }

  @override
  String projectStatAssets(int count) {
    return 'Assets $count';
  }

  @override
  String projectStatStoryboards(int count) {
    return 'Storyboards $count';
  }

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
  String get scriptMsgExtracting => 'Extracting assets';

  @override
  String get scriptMsgExtractFailed => 'Asset extraction failed';

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
  String get scriptMarkdownBold => 'Bold';

  @override
  String get scriptMarkdownItalic => 'Italic';

  @override
  String get scriptMarkdownHeading => 'Heading';

  @override
  String get scriptMarkdownDialogue => 'Dialogue';

  @override
  String get scriptMarkdownEdit => 'Edit';

  @override
  String get scriptMarkdownPreview => 'Preview';

  @override
  String get scriptMarkdownPreviewEmpty => 'No content yet';

  @override
  String get scriptMarkdownBoldPlaceholder => 'emphasis';

  @override
  String get scriptMarkdownItalicPlaceholder => 'tone';

  @override
  String get scriptMarkdownDialogueSnippet => 'Character: line';

  @override
  String get scriptDeleteScript => 'Delete scripts in batches';

  @override
  String get scriptExtractAssets => 'Extract Assets';

  @override
  String get scriptImportGetAiRegex => 'AI-Generated Regex';

  @override
  String get scriptImportEpisodeRegexPh =>
      'Customize the script splitting rule, leave it blank to use the default splitting rule (the default is to split according to the Episode X format)';

  @override
  String get scriptBatchAdd => 'Batch Add';

  @override
  String get scriptGenerateFromEvents => 'Generate from events';

  @override
  String get scriptGenerateFromEventsTitle =>
      'Select events to generate scripts';

  @override
  String get scriptGenerateFromEventsEmpty =>
      'No events are available. Generate chapter events first.';

  @override
  String get scriptGenerateFromEventsConfirm => 'Generate scripts';

  @override
  String get scriptGenerateFromEventsSelectHint => 'Select at least one event';

  @override
  String get scriptGenerateFromEventsSubmitted => 'Script generation submitted';

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
  String get assetsGenerateSpeech => 'Text to Speech';

  @override
  String get assetsTtsGenerate => 'Generate Speech';

  @override
  String get assetsTtsText => 'Speech text';

  @override
  String get assetsTtsTextPh => 'Enter dialogue or narration to synthesize';

  @override
  String get assetsTtsVoice => 'Voice ID';

  @override
  String get assetsTtsVoicePh => 'alloy / custom voice id';

  @override
  String get assetsTtsTextRequired => 'Please enter speech text';

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
  String get productionMobileNodeInspector => 'Node Inspector';

  @override
  String get productionMobileCurrentNode => 'Current node';

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
  String get workbenchGenerateAllPrompts => 'Generate All Motion Prompts';

  @override
  String get workbenchClearSelectedTracks => 'Clear Selected Tracks';

  @override
  String get workbenchClearSelectedTracksConfirm =>
      'This clears video tracks and candidate videos for the checked shots. Storyboard rows are kept.';

  @override
  String get workbenchClearTracksAction => 'Clear';

  @override
  String get workbenchClearSelectedTracksDone => 'Selected tracks cleared';

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
  String get workbenchPickClip => 'Assets';

  @override
  String get workbenchPickClipTitle => 'Choose Clip Asset';

  @override
  String get workbenchNoClipAssets => 'No video clip assets yet';

  @override
  String get workbenchSaveCandidateToAssets => 'Save to Assets';

  @override
  String workbenchCandidateClipName(int videoId) {
    return 'Shot candidate #$videoId';
  }

  @override
  String get workbenchShotAudioLabel => 'Shot Voice';

  @override
  String get workbenchShotAudioNone => 'No voice';

  @override
  String get workbenchEditPrompt => 'Edit Motion Prompt';

  @override
  String get workbenchOutputPath => 'Output path';

  @override
  String get workbenchDuration => 'Duration';

  @override
  String workbenchSavedToAssets(int assetId) {
    return 'Saved to Assets (asset #$assetId)';
  }

  @override
  String get workbenchTimelineOverview => 'Timeline Overview';

  @override
  String get workbenchTimelineVideoTrack => 'Video Track';

  @override
  String get workbenchTimelineAudioTrack => 'Audio Track';

  @override
  String get workbenchTimelineOverlayTrack => 'Overlay';

  @override
  String get workbenchTimelineMediaLibrary => 'Media Library';

  @override
  String get workbenchTimelineMediaLibraryTitle => 'Timeline Media Library';

  @override
  String get workbenchTimelineAddAtPlayhead => 'Add at playhead';

  @override
  String get workbenchTimelineMediaBin => 'Draggable media';

  @override
  String workbenchTimelineDraggableClipName(String name) {
    return 'Drag: $name';
  }

  @override
  String get workbenchTimelineAddClip => 'Add Overlay';

  @override
  String get workbenchTimelineAddClipTitle => 'Add Overlay Clip';

  @override
  String get workbenchTimelineAdd => 'Add';

  @override
  String get workbenchTimelineAutoLayerAdd => 'Auto layer add';

  @override
  String get workbenchTimelineRippleInsert => 'Ripple insert';

  @override
  String get workbenchTimelineLayer => 'Layer';

  @override
  String get workbenchTimelineStartMs => 'Start (ms)';

  @override
  String get workbenchTimelineDurationMs => 'Duration (ms)';

  @override
  String get workbenchTimelineClipAdded => 'Overlay clip added';

  @override
  String get workbenchTimelineSplitMidpoint => 'Split midpoint';

  @override
  String get workbenchTimelineDuplicate => 'Duplicate overlay';

  @override
  String get workbenchTimelineRippleDuplicate => 'Ripple duplicate';

  @override
  String get workbenchTimelineRippleMove => 'Ripple move';

  @override
  String get workbenchTimelineRippleMoveTitle => 'Ripple Move Overlay';

  @override
  String get workbenchTimelineSplitAt => 'Split at playhead';

  @override
  String get workbenchTimelineSplitAtTitle => 'Split Overlay at Playhead';

  @override
  String get workbenchTimelineSplitAtMs => 'Playhead (ms)';

  @override
  String get workbenchTimelineSplit => 'Split';

  @override
  String get workbenchTimelineRippleTrimEnd => 'Ripple trim end';

  @override
  String get workbenchTimelineRippleTrimTitle => 'Ripple Trim Overlay End';

  @override
  String get workbenchTimelineEditClip => 'Edit overlay properties';

  @override
  String get workbenchTimelineEditClipTitle => 'Edit Overlay Properties';

  @override
  String get workbenchTimelineClipActions => 'Overlay actions';

  @override
  String get workbenchTimelineDelete => 'Delete';

  @override
  String get workbenchTimelineRippleDelete => 'Ripple delete';

  @override
  String workbenchTimelineSelectedClips(int count) {
    return '$count selected';
  }

  @override
  String get workbenchTimelineSplitSelected => 'Split selected';

  @override
  String get workbenchTimelineDuplicateSelected => 'Duplicate selected';

  @override
  String get workbenchTimelineRippleDuplicateSelected =>
      'Ripple duplicate selected';

  @override
  String get workbenchTimelineDeleteSelected => 'Delete selected';

  @override
  String get workbenchTimelineRippleDeleteSelected => 'Ripple delete selected';

  @override
  String get workbenchTimelineUnselected => 'No video selected';

  @override
  String get workbenchTimelineNoAudio => 'No voice bound';

  @override
  String get workbenchReorderShot => 'Drag to reorder';

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

  @override
  String get promptStoryboardGenTitle => 'Storyboard Generation';

  @override
  String get promptStoryboardGenDescription =>
      'Splits the script into a shot list';

  @override
  String get promptVideoPromptGenTitle => 'Motion Prompt Generation';

  @override
  String get promptVideoPromptGenDescription =>
      'Turns a shot into an image-to-video motion prompt';

  @override
  String get promptAudioBindTitle => 'Voice Matching';

  @override
  String get promptAudioBindDescription =>
      'Matches the best-fit voice by role description';

  @override
  String get promptEventAnalysisTitle => 'Event Analysis';

  @override
  String get promptEventAnalysisDescription =>
      'Analyzes adaptation value of chapter events';

  @override
  String get stageEventExtractTitle => 'Event Extraction';

  @override
  String get stageEventExtractDescription =>
      'Extracts structured event summaries from chapters';

  @override
  String get stageVideoPromptGenTitle => 'Motion Prompt Generation';

  @override
  String get stageVideoPromptGenDescription =>
      'Turns shot descriptions into image-to-video prompts';

  @override
  String get stageScriptGenTitle => 'Script Generation';

  @override
  String get stageScriptGenDescription =>
      'Adapts the novel into a short-drama script';

  @override
  String get stageAssetExtractTitle => 'Asset Extraction';

  @override
  String get stageAssetExtractDescription =>
      'Extracts roles, scenes and props from the script';

  @override
  String get stageStoryboardGenTitle => 'Storyboard Generation';

  @override
  String get stageStoryboardGenDescription =>
      'Splits episodes into shots and shot prompts';

  @override
  String get stageAssetImageTitle => 'Asset Image Generation';

  @override
  String get stageAssetImageDescription =>
      'Generates role, scene and prop asset images';

  @override
  String get stageShotImageTitle => 'Shot Image Generation';

  @override
  String get stageShotImageDescription =>
      'Generates the still frame for each shot';

  @override
  String get stageShotVideoTitle => 'Shot Video Generation';

  @override
  String get stageShotVideoDescription =>
      'Generates a short video clip from the shot image';

  @override
  String get stageTtsTitle => 'Voice Generation';

  @override
  String get stageTtsDescription => 'Generates speech for shot dialogue';

  @override
  String stageBindingUpdated(String title) {
    return '$title binding updated';
  }

  @override
  String get stageBindingMissing => 'No model bound';

  @override
  String get agentChatTitle => 'Script Agent';

  @override
  String get agentChatInputPlaceholder =>
      'Tell me what to work on next, or ask \"what\'s the status\"';

  @override
  String get agentChatSend => 'Send';

  @override
  String get agentChatThinking => 'Thinking...';

  @override
  String get agentChatAutoMode => 'Auto chain';

  @override
  String get agentChatManualMode => 'Manual confirm';

  @override
  String get agentChatClearMemory => 'Clear memory';

  @override
  String get agentChatConfirmClearTitle => 'Clear memory';

  @override
  String get agentChatConfirmClearBody =>
      'Clear the entire conversation history? This cannot be undone.';

  @override
  String get agentChatMemoryCleared => 'Memory cleared';

  @override
  String get agentChatWelcome =>
      'Hi, I\'m the Script Agent. I can help with event extraction, asset extraction, storyboard generation, first-frame images, video generation, voice binding, and final compose. Tell me what to do, or ask \"what\'s the status\".';

  @override
  String agentChatToolExecuted(String tool) {
    return 'Executed: $tool';
  }

  @override
  String get agentChatModeHint =>
      'Manual mode runs one step and waits for you; auto mode chains steps automatically (within a safety cap).';

  @override
  String get agentChatSkillsInfo => 'Built-in capabilities';

  @override
  String get agentChatSkillsBody =>
      'I can call real pipeline actions and local custom skills. Pipeline actions leave reviewable, retryable records in Task Center; custom skills currently support the v1 JS return-template bridge.';

  @override
  String get agentTabChat => 'Chat';

  @override
  String get agentTabDeploy => 'Deploy';

  @override
  String get agentTabSkills => 'Skills';

  @override
  String get agentTabMemory => 'Memory';

  @override
  String get agentDeployExecutionMode => 'Execution mode';

  @override
  String get agentDeployModeSaved =>
      'This setting is saved as the default Agent execution mode';

  @override
  String get agentDeployStagesTitle => 'Stage deployments';

  @override
  String get agentDeployStagesHint =>
      'Choose text models and call parameters for each Agent stage. Enabled rows override the normal model binding.';

  @override
  String get agentDeployModel => 'Model';

  @override
  String get agentDeployMaxTokens => 'Max output';

  @override
  String get agentDeployTemperature => 'Temperature x100';

  @override
  String get agentDeploySaved => 'Agent deployment saved';

  @override
  String get agentSkillsBuiltinTitle => 'Built-in skills';

  @override
  String get agentSkillsEditableHint =>
      'Skill definitions are stored locally in o_skillList. You can edit descriptions and enable or disable skills; tool names stay fixed so Task Center records remain traceable and retryable.';

  @override
  String get agentSkillEditTitle => 'Edit skill';

  @override
  String get agentSkillDescription => 'Skill description';

  @override
  String get agentSkillEnabled => 'Enable skill';

  @override
  String get agentSkillEnabledTag => 'Enabled';

  @override
  String get agentSkillDisabledTag => 'Disabled';

  @override
  String get agentCustomSkillAdd => 'Add custom skill';

  @override
  String get agentCustomSkillCreateTitle => 'Add custom skill';

  @override
  String get agentCustomSkillEditTitle => 'Edit custom skill';

  @override
  String get agentCustomSkillId => 'Tool ID';

  @override
  String get agentCustomSkillName => 'Skill name';

  @override
  String get agentCustomSkillSchema => 'Parameter Schema JSON';

  @override
  String get agentCustomSkillScript => 'Script';

  @override
  String get agentCustomSkillScriptHint =>
      'v1 supports return strings, args.xxx, projectId, JSON.stringify(args), and template strings.';

  @override
  String get agentCustomSkillInvalidSchema => 'Schema must be a JSON object';

  @override
  String get agentCustomSkillSaved => 'Custom skill saved';

  @override
  String get agentCustomSkillTag => 'Custom';

  @override
  String agentMemoryCount(int count) {
    return '$count memory items';
  }

  @override
  String get agentMemoryEmpty =>
      'No memory yet. Sent messages will appear here as inspectable context records.';

  @override
  String agentLongTermMemoryCount(int count) {
    return '$count long-term memories';
  }

  @override
  String get agentLongTermMemoryEmpty =>
      'No long-term memories yet. Save character rules, forbidden directions, or worldbuilding notes here.';

  @override
  String get agentMemoryAdd => 'Add memory';

  @override
  String get agentMemoryCreateTitle => 'Add long-term memory';

  @override
  String get agentMemoryEditTitle => 'Edit long-term memory';

  @override
  String get agentMemoryName => 'Memory name';

  @override
  String get agentMemoryContent => 'Memory content';

  @override
  String get agentMemorySaved => 'Long-term memory saved';

  @override
  String get agentMemoryUpdated => 'Long-term memory updated';

  @override
  String get agentMemoryDeleted => 'Long-term memory deleted';

  @override
  String get cornerScapeSearchHint => 'Search role name';

  @override
  String get cornerScapeFilterAll => 'All';

  @override
  String get cornerScapeFilterBound => 'Bound';

  @override
  String get cornerScapeFilterUnbound => 'Unbound';

  @override
  String get cornerScapeSelectAllUnbound => 'Select all unbound';

  @override
  String cornerScapeBoundSummary(int bound, int total) {
    return 'Bound $bound/$total';
  }

  @override
  String get cornerScapeNoMatch => 'No roles match the current filter';

  @override
  String get storyboardPreviewAll => 'Preview all';

  @override
  String get storyboardPreviewEmpty => 'No shots to preview';

  @override
  String get storyboardPreviewImageMissing => 'Failed to load image';

  @override
  String storyboardPreviewCounter(String shot, String current, String total) {
    return '$shot ($current/$total)';
  }

  @override
  String storyboardPreviewShotPlaceholder(String shot) {
    return '$shot has no first-frame image yet';
  }

  @override
  String get storyboardExportAll => 'Export all';

  @override
  String get storyboardExportNoImages => 'No first-frame images to export yet';

  @override
  String storyboardExportSuccess(String count) {
    return 'Exported $count first-frame images';
  }

  @override
  String storyboardExportFailed(String reason) {
    return 'Export failed: $reason';
  }

  @override
  String get scriptPlanEmpty =>
      'No script plan yet. Tap to write the overall direction, pacing, and key points.';

  @override
  String get scriptPlanWrite => 'Write plan';

  @override
  String get scriptPlanEditTitle => 'Edit script plan';

  @override
  String get scriptPlanEditHint =>
      'Use Markdown to capture the project plan: main plot, character arcs, per-episode pacing, tone and style...';

  @override
  String get scriptPlanSaved => 'Script plan saved';

  @override
  String get canvasChatTitle => 'Script Agent';

  @override
  String get canvasChatOpen => 'Agent chat';

  @override
  String get canvasChatClose => 'Close';

  @override
  String get imageEditorModel => 'Model';

  @override
  String get imageEditorRatio => 'Ratio';

  @override
  String get imageEditorQuality => 'Quality';

  @override
  String get imageEditorSelectModel => 'Please select a model first';

  @override
  String get imageEditorSelectQuality => 'Please select a quality';

  @override
  String get imageEditorSelectRatio => 'Please select a ratio';

  @override
  String get imageEditorNoImageModel => 'No image model available';

  @override
  String get novelGenerateSelectedEvents => 'Generate events';

  @override
  String scriptBatchAddMsgOverLimit(String limit) {
    return 'Some episodes exceed the per-episode length limit ($limit). Deselect them or shorten the content.';
  }

  @override
  String get artStyleLibraryTitle => 'Art Style Library';

  @override
  String get artStyleManage => 'Manage art styles';

  @override
  String get artStyleAddTitle => 'Add art style';

  @override
  String get artStyleEditTitle => 'Edit art style';

  @override
  String get artStyleName => 'Style name';

  @override
  String get artStyleNamePh => 'e.g. 2D anime, photorealistic, 3D CG';

  @override
  String get artStylePrompt => 'Style prompt';

  @override
  String get artStylePromptPh => 'e.g. (style: 2D anime, 2d animation style)';

  @override
  String get artStyleCover => 'Cover image';

  @override
  String get artStyleUploadCover => 'Upload cover';

  @override
  String get artStyleNameRequired => 'Please enter a style name';

  @override
  String get artStyleAddSuccess => 'Art style added';

  @override
  String get artStyleEditSuccess => 'Art style updated';

  @override
  String get artStyleDeleted => 'Art style deleted';

  @override
  String get artStyleDeleteHeader => 'Delete art style';

  @override
  String artStyleDeleteBody(String name) {
    return 'Delete art style \"$name\"?';
  }

  @override
  String get artStyleEmpty => 'No art styles yet. Add one above.';

  @override
  String get artStyleClose => 'Close';

  @override
  String get clipUpload => 'Upload clip';

  @override
  String get clipUploadTitle => 'Upload clip file';

  @override
  String get clipPickFile => 'Choose file';

  @override
  String get clipNoFile => 'No file selected';

  @override
  String get clipName => 'Clip name';

  @override
  String get clipNamePh => 'Leave blank to use the file name';

  @override
  String get clipUploadSuccess => 'Clip uploaded';

  @override
  String get clipUploadFailed => 'Clip upload failed';

  @override
  String get assetBatchModel => 'Model';

  @override
  String get assetBatchResolution => 'Resolution';

  @override
  String get assetBatchConcurrency => 'Concurrency';

  @override
  String get assetBatchConcurrencyPh => '1-8';

  @override
  String get assetBatchOtherPrompt => 'Extra prompt';

  @override
  String get assetBatchOtherPromptPh =>
      'Appended to the polish system prompt (optional)';

  @override
  String get assetBatchPickModel => 'Use stage default';

  @override
  String get manualImportFile => 'Import file';

  @override
  String get manualImportSuccess => 'File imported into the current tab';

  @override
  String get manualImportFailed => 'File import failed';

  @override
  String get storyboardTableEmpty =>
      'No storyboard table yet. Tap to write shot breakdown, durations and key visuals.';

  @override
  String get storyboardTableWrite => 'Write storyboard table';

  @override
  String get storyboardTableEditTitle => 'Edit storyboard table';

  @override
  String get storyboardTableEditHint =>
      'Use Markdown to record this episode\'s shot breakdown: shot number, visuals, camera moves, duration...';

  @override
  String get storyboardTableSaved => 'Storyboard table saved';

  @override
  String get scriptNodeEditTitle => 'Edit script';

  @override
  String get scriptNodeName => 'Name';

  @override
  String get scriptNodeNamePlaceholder => 'Enter script name';

  @override
  String get scriptNodeContent => 'Content';

  @override
  String get scriptNodeContentPlaceholder => 'Enter script content';

  @override
  String get scriptNodeNameRequired => 'Please enter a script name';

  @override
  String get scriptNodeSaved => 'Script saved';

  @override
  String get productionStoryboardInsertBefore => 'Insert storyboard before';

  @override
  String get imageEditorPickFromAssets => 'Choose from asset library';

  @override
  String get imageEditorPickFromStoryboard => 'Choose from storyboard';

  @override
  String get imageEditorPickImageTitle => 'Choose reference image';

  @override
  String get imageEditorPickImageSource => 'Choose image source';

  @override
  String get imageEditorPickLocalFile => 'Local file';

  @override
  String get imageEditorNoAssetsImages =>
      'No generated images in the asset library';

  @override
  String get imageEditorNoStoryboardImages =>
      'No generated storyboard frames yet';

  @override
  String get imageEditorRemoveEdge => 'Remove this connection';

  @override
  String get imageEditorEdgeRemoved => 'Connection removed';

  @override
  String get workbenchPlayVideo => 'Play';

  @override
  String get workbenchVideoLoadFailed => 'Failed to load video';

  @override
  String get workbenchDeleteCandidate => 'Delete candidate';

  @override
  String get workbenchDeleteCandidateConfirm => 'Delete this candidate video?';

  @override
  String get workbenchSelectAsMain => 'Use as final';

  @override
  String get workbenchDurationSection => 'Shot duration';

  @override
  String get workbenchDurationUnset => 'Not set';

  @override
  String workbenchDurationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get workbenchEditDurationTitle => 'Edit shot duration';

  @override
  String get workbenchDurationFieldLabel => 'Duration (seconds)';

  @override
  String get workbenchEditPromptTitle => 'Edit camera prompt';

  @override
  String get workbenchPromptFieldHint =>
      'Describe the camera movement and action for this shot';

  @override
  String get workbenchPromptEmpty =>
      'No camera prompt yet. Tap to generate or edit.';

  @override
  String get workbenchTransitionNone => 'No transition';

  @override
  String get workbenchTransitionFade => 'Fade';

  @override
  String get workbenchTransitionDissolve => 'Dissolve';

  @override
  String get workbenchTransitionWhipPan => 'Whip pan';

  @override
  String get workbenchFilterNone => 'No filter';

  @override
  String get workbenchFilterCinematic => 'Cinematic';

  @override
  String get workbenchFilterWarm => 'Warm';

  @override
  String get workbenchFilterCool => 'Cool';

  @override
  String get workbenchFilterVintage => 'Vintage';

  @override
  String get cornerScapeAudition => 'Audition';

  @override
  String get cornerScapeStopAudition => 'Stop';

  @override
  String get cornerScapeAudioMissing => 'Audio file missing';

  @override
  String get cornerScapeAuditionFailed => 'Audio playback failed';

  @override
  String get settingsOtherSection => 'Other';

  @override
  String get settingsOtherTitle => 'Other Settings';

  @override
  String get settingsOtherChapterReg => 'Chapter split regex';

  @override
  String get settingsOtherChapterRegHint =>
      'Leave empty to use the built-in default chapter regex';

  @override
  String get settingsOtherChapterRegRestore => 'Restore default';

  @override
  String get settingsOtherEpisodeLength => 'Max characters per episode';

  @override
  String get settingsOtherBatchSize => 'Batch generation size';

  @override
  String get settingsOtherSaved => 'Other settings saved';

  @override
  String get settingsOtherInvalidNumber =>
      'Please enter an integer greater than 0';

  @override
  String get settingsStorageOpenFolder => 'Open data folder';

  @override
  String settingsStorageOpenFolderFailed(String reason) {
    return 'Could not open the data folder: $reason';
  }

  @override
  String get settingsStorageDbInfo => 'Database info';

  @override
  String get settingsStorageDbInfoTitle => 'Database info';

  @override
  String get settingsStorageTableColumn => 'Table';

  @override
  String get settingsStorageRowsColumn => 'Rows';

  @override
  String get settingsStorageClear => 'Clear data';

  @override
  String get settingsStorageClearConfirmTitle => 'Clear all data';

  @override
  String get settingsStorageClearConfirmBody =>
      'This deletes all projects, chapters, scripts, assets, tasks and media files and cannot be undone. Continue?';

  @override
  String get settingsStorageClearDone => 'Data cleared';

  @override
  String get settingsAboutSection => 'About';

  @override
  String get settingsAboutTitle => 'About DramaFlow';

  @override
  String get settingsAboutAppName => 'App name';

  @override
  String get settingsAboutVersion => 'Version';

  @override
  String get settingsAboutEngine => 'Engine version';

  @override
  String get settingsAboutDescription =>
      'DramaFlow is a locally running AI short-drama studio. All data and media stay on your machine.';

  @override
  String get settingsProviderTestKind => 'Kind';

  @override
  String get settingsProviderTestNoModel =>
      'Enable at least one testable model first';

  @override
  String get taskFilterClass => 'Task type';

  @override
  String get taskFilterState => 'State';

  @override
  String get taskFilterAll => 'All';

  @override
  String get taskDetailTitle => 'Task detail';

  @override
  String get taskDetailClass => 'Task type';

  @override
  String get taskDetailState => 'State';

  @override
  String get taskDetailDescribe => 'Description';

  @override
  String get taskDetailModel => 'Model';

  @override
  String get taskDetailRelated => 'Related objects';

  @override
  String get taskDetailReason => 'Failure reason';

  @override
  String get taskDetailTiming => 'Start time';

  @override
  String get taskDetailNone => 'None';

  @override
  String get taskStatePending => 'Pending';

  @override
  String get taskStateProcessing => 'Processing';

  @override
  String get taskStateSuccess => 'Completed';

  @override
  String get taskStateFailed => 'Failed';

  @override
  String get taskStateCanceled => 'Canceled';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonTest => 'Test';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonEnabled => 'Enabled';

  @override
  String get commonActions => 'Actions';

  @override
  String get commonName => 'Name';

  @override
  String get commonType => 'Type';

  @override
  String get commonModel => 'Model';

  @override
  String get commonUnset => 'Not set';

  @override
  String get statusQueued => 'Queued';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusRunning => 'Generating';

  @override
  String get statusDone => 'Completed';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusCanceled => 'Canceled';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusNotGenerated => 'Not generated';

  @override
  String get statusSuccessShort => 'Success';

  @override
  String get statusPendingShort => 'Pending';

  @override
  String dataTableTotal(int total) {
    return '$total total';
  }

  @override
  String get dataTablePrevPage => 'Previous page';

  @override
  String get dataTableNextPage => 'Next page';

  @override
  String get imageVersionsTitle => 'Image versions';

  @override
  String get imageVersionsEmpty => 'No image versions yet';

  @override
  String imageVersionLabel(int index) {
    return 'Version $index';
  }

  @override
  String get repaintImageTitle => 'Repaint image';

  @override
  String get repaintImageHint => 'e.g. change the outfit to red';

  @override
  String get repaintInstructionRequired => 'Enter repaint instructions';

  @override
  String get repaintAction => 'Repaint';

  @override
  String get inpaintAction => 'Local repaint';

  @override
  String get inpaintTitle => 'Local Repaint';

  @override
  String get inpaintHint =>
      'Brush the area to repaint, then describe the edit.';

  @override
  String get inpaintMaskRequired => 'Brush the area to repaint first.';

  @override
  String get inpaintMaskCreateFailed => 'Failed to create the repaint mask';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsProvidersSection => 'Providers';

  @override
  String get settingsBindingsSection => 'Model bindings';

  @override
  String get settingsPromptsSection => 'Prompts';

  @override
  String get settingsStorageSection => 'Storage & engine';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeUpdated => 'Appearance updated';

  @override
  String get localeChinese => '中文';

  @override
  String get localeJapanese => '日本語';

  @override
  String get modelKindText => 'Text';

  @override
  String get modelKindImage => 'Image';

  @override
  String get modelKindVideo => 'Video';

  @override
  String get modelKindTts => 'Voice';

  @override
  String get providerProtocolVolcengine => 'Volcengine';

  @override
  String get providerProtocolOpenAiCompatible => 'OpenAI-compatible';

  @override
  String get settingsAddProvider => 'Add provider';

  @override
  String get settingsProviderEmptyTitle => 'No providers yet';

  @override
  String get settingsProviderEmptySubtitle =>
      'Add an OpenAI-compatible or Volcengine provider, then configure models and stage bindings.';

  @override
  String get settingsProviderAdded => 'Provider added';

  @override
  String get settingsProviderUpdated => 'Provider updated';

  @override
  String get settingsProviderConfigMissing =>
      'Provider list missing from configuration data';

  @override
  String get settingsProviderMissing => 'Provider not found';

  @override
  String get settingsProviderEnabled => 'Provider enabled';

  @override
  String get settingsProviderDisabled => 'Provider disabled';

  @override
  String settingsProviderTestSuccess(int elapsedMs) {
    return 'Connection OK: $elapsedMs ms';
  }

  @override
  String settingsProviderTestTitle(String name) {
    return 'Test connection · $name';
  }

  @override
  String get settingsDeleteProviderTitle => 'Delete provider';

  @override
  String settingsDeleteProviderMessage(String name) {
    return 'Delete “$name”? If it is bound to any stage, the engine will reject the deletion.';
  }

  @override
  String get settingsProviderDeleted => 'Provider deleted';

  @override
  String get settingsModelCount => 'Models';

  @override
  String get settingsManageModels => 'Manage models';

  @override
  String get settingsTestConnection => 'Test connection';

  @override
  String get settingsEditProvider => 'Edit provider';

  @override
  String get settingsProviderName => 'Name';

  @override
  String get settingsProviderNameHint => 'e.g. azt';

  @override
  String get settingsKeepEmptyUnchanged => 'Leave empty to keep unchanged';

  @override
  String get settingsExportConfig => 'Export config';

  @override
  String get settingsImportConfig => 'Import config';

  @override
  String get settingsConfigPlaintextWarning =>
      'The JSON config contains plaintext keys. Store it carefully.';

  @override
  String get settingsEmbeddedEngineNote =>
      'The engine runs inside the app. Data and media stay on this device; no background service is required.';

  @override
  String get settingsEngineStatus => 'Engine status';

  @override
  String settingsExportPanelFailed(String reason) {
    return 'Could not open the save panel: $reason';
  }

  @override
  String settingsExportFailed(String reason) {
    return 'Config export failed: $reason';
  }

  @override
  String get settingsConfigExported => 'Config exported';

  @override
  String settingsOpenFileFailed(String reason) {
    return 'Could not open the file picker: $reason';
  }

  @override
  String get settingsImportConfigTitle => 'Import config';

  @override
  String get settingsImportConfigMessage =>
      'Importing will overwrite providers, models, bindings and prompts with the same names. Continue?';

  @override
  String get settingsConfigInvalidFormat => 'Invalid config file format';

  @override
  String get settingsConfigInvalidJson => 'Config file is not valid JSON';

  @override
  String settingsImportFailed(String reason) {
    return 'Config import failed: $reason';
  }

  @override
  String get settingsConfigImported => 'Config imported';

  @override
  String get settingsEngineChecking => 'Checking engine…';

  @override
  String settingsEngineOk(String version) {
    return 'Engine OK · v$version';
  }

  @override
  String get settingsEngineUnknown => 'Unknown';

  @override
  String get settingsProviderColumnProtocol => 'Protocol';

  @override
  String get settingsProviderColumnBaseUrl => 'Base URL';

  @override
  String settingsModelManagementTitle(String name) {
    return 'Model management · $name';
  }

  @override
  String get settingsAddModel => 'Add model';

  @override
  String get settingsSaveModels => 'Save';

  @override
  String get settingsModelsEmptyTitle => 'No models yet';

  @override
  String get settingsModelsEmptySubtitle =>
      'Add at least one text, image, video or voice model.';

  @override
  String get settingsModelIdRequired => 'Model ID cannot be empty';

  @override
  String get settingsModelsSaved => 'Models saved';

  @override
  String get settingsDeleteModel => 'Delete model';

  @override
  String get settingsBindingModel => 'Bound model';

  @override
  String get settingsSelectEnabledModel => 'Choose an enabled model';

  @override
  String get settingsSelectModel => 'Select model';

  @override
  String get settingsPromptContent => 'Prompt content';

  @override
  String get taskCenterTitle => 'Task Center';

  @override
  String get taskActiveTitle => 'Active';

  @override
  String get taskActiveEmpty => 'No active tasks';

  @override
  String get taskHistoryTitle => 'History';

  @override
  String get taskNoProjects => 'No projects';

  @override
  String get taskHistoryEmpty => 'No task history for this project';

  @override
  String get taskFilterEmpty => 'No tasks match the filters';

  @override
  String get taskEmpty => 'No tasks';

  @override
  String taskProjectLabel(int id) {
    return 'Project #$id';
  }

  @override
  String get taskCancelTooltip => 'Cancel task';

  @override
  String get taskCanceledMessage => 'Task canceled';

  @override
  String get taskRetryQueued => 'Queued again';

  @override
  String get taskClassEventGeneration => 'Event generation';

  @override
  String get taskClassScriptGeneration => 'Script generation';

  @override
  String get taskClassAssetExtraction => 'Asset extraction';

  @override
  String get taskClassAssetPromptPolish => 'Asset prompt polish';

  @override
  String get taskClassAssetImageGeneration => 'Asset image generation';

  @override
  String get taskClassStoryboardGenerate => 'Storyboard generation';

  @override
  String get taskClassStoryboardImageGeneration => 'First-frame generation';

  @override
  String get taskClassVideoGeneration => 'Video generation';

  @override
  String get taskClassAudioBind => 'Dubbing match';

  @override
  String get taskClassGeneric => 'Task';

  @override
  String get webPreviewBuildableTitle => 'The Web preview entry now builds.';

  @override
  String get webPreviewMessage =>
      'The full local engine is still being ported: the browser build still needs a Web database, browser file storage, a WebCodecs/Mediabunny composer, and Web media preview adapters. The macOS, iOS, and Android clients remain the complete-function mainline for now.';

  @override
  String get webPreviewMacClient => 'Full macOS client';

  @override
  String get webPreviewIosClient => 'Full iOS client';

  @override
  String get webPreviewAndroidClient => 'Android APK builds';

  @override
  String get webPreviewEnginePending => 'Web engine pending';
}
