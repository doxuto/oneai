// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class AppLocalizations {
  AppLocalizations();

  static AppLocalizations? _current;

  static AppLocalizations get current {
    assert(
      _current != null,
      'No instance of AppLocalizations was loaded. Try to initialize the AppLocalizations delegate before accessing AppLocalizations.current.',
    );
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<AppLocalizations> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = AppLocalizations();
      AppLocalizations._current = instance;

      return instance;
    });
  }

  static AppLocalizations of(BuildContext context) {
    final instance = AppLocalizations.maybeOf(context);
    assert(
      instance != null,
      'No instance of AppLocalizations present in the widget tree. Did you add AppLocalizations.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static AppLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  /// `One AI`
  String get appTitle {
    return Intl.message(
      'One AI',
      name: 'appTitle',
      desc: 'Title of the application',
      args: [],
    );
  }

  /// `Welcome to our app`
  String get welcomeMessage {
    return Intl.message(
      'Welcome to our app',
      name: 'welcomeMessage',
      desc: 'Welcome message shown on the login page',
      args: [],
    );
  }

  /// `One AI`
  String get appName {
    return Intl.message(
      'One AI',
      name: 'appName',
      desc: 'Name of the application',
      args: [],
    );
  }

  /// `One AI`
  String get oneAi {
    return Intl.message(
      'One AI',
      name: 'oneAi',
      desc: 'Brand name shown on login page',
      args: [],
    );
  }

  /// `Instant notes from\naudio and video, `
  String get instantNotesFromAudio {
    return Intl.message(
      'Instant notes from\naudio and video, ',
      name: 'instantNotesFromAudio',
      desc: 'First part of login page tagline',
      args: [],
    );
  }

  /// `done\nwith AI`
  String get doneWithAi {
    return Intl.message(
      'done\nwith AI',
      name: 'doneWithAi',
      desc: 'Second part of login page tagline',
      args: [],
    );
  }

  /// `Sign in with Google`
  String get signInWithGoogle {
    return Intl.message(
      'Sign in with Google',
      name: 'signInWithGoogle',
      desc: 'Text for Google sign-in button',
      args: [],
    );
  }

  /// `Sign in with Apple`
  String get signInWithApple {
    return Intl.message(
      'Sign in with Apple',
      name: 'signInWithApple',
      desc: 'Text for Apple sign-in button',
      args: [],
    );
  }

  /// `(Previously signed in with Apple)`
  String get previouslySignedInWithApple {
    return Intl.message(
      '(Previously signed in with Apple)',
      name: 'previouslySignedInWithApple',
      desc: 'Text shown below Apple sign-in button for returning users',
      args: [],
    );
  }

  /// `Select theme`
  String get selectTheme {
    return Intl.message(
      'Select theme',
      name: 'selectTheme',
      desc: 'Tooltip for the theme selector button',
      args: [],
    );
  }

  /// `System theme`
  String get systemTheme {
    return Intl.message(
      'System theme',
      name: 'systemTheme',
      desc: 'Label for system theme option',
      args: [],
    );
  }

  /// `Light theme`
  String get lightTheme {
    return Intl.message(
      'Light theme',
      name: 'lightTheme',
      desc: 'Label for light theme option',
      args: [],
    );
  }

  /// `Dark theme`
  String get darkTheme {
    return Intl.message(
      'Dark theme',
      name: 'darkTheme',
      desc: 'Label for dark theme option',
      args: [],
    );
  }

  /// `Page Not Found`
  String get pageNotFound {
    return Intl.message(
      'Page Not Found',
      name: 'pageNotFound',
      desc: 'Title for the error page when a route is not found',
      args: [],
    );
  }

  /// `Premium`
  String get premium {
    return Intl.message(
      'Premium',
      name: 'premium',
      desc: 'Label for premium button',
      args: [],
    );
  }

  /// `Create tag`
  String get createTag {
    return Intl.message(
      'Create tag',
      name: 'createTag',
      desc: 'Label for creating a new tag',
      args: [],
    );
  }

  /// `Greeting Notes`
  String get greetingNotes {
    return Intl.message(
      'Greeting Notes',
      name: 'greetingNotes',
      desc: 'Title for greeting notes item',
      args: [],
    );
  }

  /// `Page not found: {path}`
  String pageNotFoundMessage(String path) {
    return Intl.message(
      'Page not found: $path',
      name: 'pageNotFoundMessage',
      desc: 'Message displayed when a page is not found',
      args: [path],
    );
  }

  /// `Go Home`
  String get goHome {
    return Intl.message(
      'Go Home',
      name: 'goHome',
      desc: 'Label for button to navigate back to home page',
      args: [],
    );
  }

  /// `MVVM + BLoC Demo`
  String get mvvmBlocDemo {
    return Intl.message(
      'MVVM + BLoC Demo',
      name: 'mvvmBlocDemo',
      desc: 'Title for the MVVM + BLoC demo app',
      args: [],
    );
  }

  /// `Flutter MVVM BLoC Demo`
  String get flutterMvvmBlocDemo {
    return Intl.message(
      'Flutter MVVM BLoC Demo',
      name: 'flutterMvvmBlocDemo',
      desc: 'Heading text for the demo app',
      args: [],
    );
  }

  /// `Users & Posts`
  String get usersAndPosts {
    return Intl.message(
      'Users & Posts',
      name: 'usersAndPosts',
      desc: 'Title for the Users and Posts feature',
      args: [],
    );
  }

  /// `View users and their posts with loading state management.`
  String get usersAndPostsDesc {
    return Intl.message(
      'View users and their posts with loading state management.',
      name: 'usersAndPostsDesc',
      desc: 'Description for the Users and Posts feature',
      args: [],
    );
  }

  /// `Settings`
  String get settings {
    return Intl.message(
      'Settings',
      name: 'settings',
      desc: 'Title for the Settings feature',
      args: [],
    );
  }

  /// `App settings and configuration options.`
  String get settingsDesc {
    return Intl.message(
      'App settings and configuration options.',
      name: 'settingsDesc',
      desc: 'Description for the Settings feature',
      args: [],
    );
  }

  /// `Categories`
  String get categories {
    return Intl.message(
      'Categories',
      name: 'categories',
      desc: 'Title for the Categories feature',
      args: [],
    );
  }

  /// `Browse content by categories.`
  String get categoriesDesc {
    return Intl.message(
      'Browse content by categories.',
      name: 'categoriesDesc',
      desc: 'Description for the Categories feature',
      args: [],
    );
  }

  /// `{title} feature coming soon!`
  String featureComingSoon(String title) {
    return Intl.message(
      '$title feature coming soon!',
      name: 'featureComingSoon',
      desc: 'Message shown when a feature is not yet implemented',
      args: [title],
    );
  }

  /// `Settings - Coming Soon`
  String get settingsComingSoon {
    return Intl.message(
      'Settings - Coming Soon',
      name: 'settingsComingSoon',
      desc: 'Message shown on the settings placeholder screen',
      args: [],
    );
  }

  /// `Categories - Coming Soon`
  String get categoriesComingSoon {
    return Intl.message(
      'Categories - Coming Soon',
      name: 'categoriesComingSoon',
      desc: 'Message shown on the categories placeholder screen',
      args: [],
    );
  }

  /// `Loading Statistics`
  String get loadingStatistics {
    return Intl.message(
      'Loading Statistics',
      name: 'loadingStatistics',
      desc: 'Title for the loading statistics dialog',
      args: [],
    );
  }

  /// `Total operations: {count}`
  String totalOperations(int count) {
    return Intl.message(
      'Total operations: $count',
      name: 'totalOperations',
      desc: 'Text showing total operations count',
      args: [count],
    );
  }

  /// `Completed: {count}`
  String completed(int count) {
    return Intl.message(
      'Completed: $count',
      name: 'completed',
      desc: 'Text showing completed operations count',
      args: [count],
    );
  }

  /// `In progress: {count}`
  String inProgress(int count) {
    return Intl.message(
      'In progress: $count',
      name: 'inProgress',
      desc: 'Text showing in-progress operations count',
      args: [count],
    );
  }

  /// `Average duration: {duration}ms`
  String averageDuration(String duration) {
    return Intl.message(
      'Average duration: ${duration}ms',
      name: 'averageDuration',
      desc: 'Text showing average duration of operations',
      args: [duration],
    );
  }

  /// `Close`
  String get close {
    return Intl.message(
      'Close',
      name: 'close',
      desc: 'Label for close button',
      args: [],
    );
  }

  /// `Users`
  String get users {
    return Intl.message(
      'Users',
      name: 'users',
      desc: 'Label for users section',
      args: [],
    );
  }

  /// `No users found`
  String get noUsersFound {
    return Intl.message(
      'No users found',
      name: 'noUsersFound',
      desc: 'Message shown when no users are available',
      args: [],
    );
  }

  /// `Posts`
  String get posts {
    return Intl.message(
      'Posts',
      name: 'posts',
      desc: 'Label for posts section',
      args: [],
    );
  }

  /// `Select a user to view posts`
  String get selectUserToViewPosts {
    return Intl.message(
      'Select a user to view posts',
      name: 'selectUserToViewPosts',
      desc: 'Message shown when no user is selected to view posts',
      args: [],
    );
  }

  /// `Error: {message}`
  String error(String message) {
    return Intl.message(
      'Error: $message',
      name: 'error',
      desc: 'Error message format',
      args: [message],
    );
  }

  /// `Retry`
  String get retry {
    return Intl.message(
      'Retry',
      name: 'retry',
      desc: 'Label for retry button',
      args: [],
    );
  }

  /// `Attempt {count}`
  String attempt(int count) {
    return Intl.message(
      'Attempt $count',
      name: 'attempt',
      desc: 'Text showing attempt count',
      args: [count],
    );
  }

  /// `Loading Statistics`
  String get loadingStatisticsTooltip {
    return Intl.message(
      'Loading Statistics',
      name: 'loadingStatisticsTooltip',
      desc: 'Tooltip for the loading statistics button',
      args: [],
    );
  }

  /// `Reset Loading States`
  String get resetLoadingStatesTooltip {
    return Intl.message(
      'Reset Loading States',
      name: 'resetLoadingStatesTooltip',
      desc: 'Tooltip for the reset loading states button',
      args: [],
    );
  }

  /// `Comments`
  String get comments {
    return Intl.message(
      'Comments',
      name: 'comments',
      desc: 'Label for comments section in post detail',
      args: [],
    );
  }

  /// `Comments would load here in a real app`
  String get commentsPlaceholder {
    return Intl.message(
      'Comments would load here in a real app',
      name: 'commentsPlaceholder',
      desc: 'Placeholder text when no comments are loaded',
      args: [],
    );
  }

  /// `User ID: {id}`
  String userId(int id) {
    return Intl.message(
      'User ID: $id',
      name: 'userId',
      desc: 'Label showing user ID',
      args: [id],
    );
  }

  /// `Post ID: {id}`
  String postId(int id) {
    return Intl.message(
      'Post ID: $id',
      name: 'postId',
      desc: 'Label showing post ID',
      args: [id],
    );
  }

  /// `Upgrade`
  String get upgrade {
    return Intl.message(
      'Upgrade',
      name: 'upgrade',
      desc: 'Label for upgrade button',
      args: [],
    );
  }

  /// `Registered`
  String get registered {
    return Intl.message(
      'Registered',
      name: 'registered',
      desc: 'Label for registered button',
      args: [],
    );
  }

  /// `Back`
  String get back {
    return Intl.message(
      'Back',
      name: 'back',
      desc: 'Label for back button',
      args: [],
    );
  }

  /// `Transcript`
  String get transcript {
    return Intl.message(
      'Transcript',
      name: 'transcript',
      desc: 'Label for transcript tab',
      args: [],
    );
  }

  /// `Chat`
  String get chat {
    return Intl.message(
      'Chat',
      name: 'chat',
      desc: 'Label for chat tab',
      args: [],
    );
  }

  /// `Opening & Key Highlight`
  String get openingAndKeyHighlight {
    return Intl.message(
      'Opening & Key Highlight',
      name: 'openingAndKeyHighlight',
      desc: 'Title for opening and key highlight section',
      args: [],
    );
  }

  /// `Product Roadmap Review`
  String get productRoadmapReview {
    return Intl.message(
      'Product Roadmap Review',
      name: 'productRoadmapReview',
      desc: 'Title for product roadmap review section',
      args: [],
    );
  }

  /// `Feature Updates & Releases`
  String get featureUpdatesAndReleases {
    return Intl.message(
      'Feature Updates & Releases',
      name: 'featureUpdatesAndReleases',
      desc: 'Title for feature updates and releases section',
      args: [],
    );
  }

  /// `Break`
  String get breakTime {
    return Intl.message(
      'Break',
      name: 'breakTime',
      desc: 'Title for break section',
      args: [],
    );
  }

  /// `Market & Competitor Insights`
  String get marketAndCompetitorInsights {
    return Intl.message(
      'Market & Competitor Insights',
      name: 'marketAndCompetitorInsights',
      desc: 'Title for market and competitor insights section',
      args: [],
    );
  }

  /// `Team Updates & Action Items`
  String get teamUpdatesAndActionItems {
    return Intl.message(
      'Team Updates & Action Items',
      name: 'teamUpdatesAndActionItems',
      desc: 'Title for team updates and action items section',
      args: [],
    );
  }

  /// `Q&A & Next Steps`
  String get qAndAAndNextSteps {
    return Intl.message(
      'Q&A & Next Steps',
      name: 'qAndAAndNextSteps',
      desc: 'Title for Q&A and next steps section',
      args: [],
    );
  }

  /// `How did we do?`
  String get howDidWeDo {
    return Intl.message(
      'How did we do?',
      name: 'howDidWeDo',
      desc: 'Text for feedback request',
      args: [],
    );
  }

  /// `Give Feedback`
  String get giveFeedback {
    return Intl.message(
      'Give Feedback',
      name: 'giveFeedback',
      desc: 'Text for give feedback button',
      args: [],
    );
  }

  /// `tab content coming soon`
  String get tabComingSoon {
    return Intl.message(
      'tab content coming soon',
      name: 'tabComingSoon',
      desc: 'Text shown for tabs that are not yet implemented',
      args: [],
    );
  }

  /// `Share`
  String get share {
    return Intl.message(
      'Share',
      name: 'share',
      desc: 'Text for share button/tooltip',
      args: [],
    );
  }

  /// `Share Notes as PDF`
  String get shareNotesAsPdf {
    return Intl.message(
      'Share Notes as PDF',
      name: 'shareNotesAsPdf',
      desc: 'Label for sharing notes as PDF option',
      args: [],
    );
  }

  /// `Error sharing PDF. Please try again.`
  String get errorSharingPdf {
    return Intl.message(
      'Error sharing PDF. Please try again.',
      name: 'errorSharingPdf',
      desc: 'Error message when PDF sharing fails',
      args: [],
    );
  }

  /// `Error sharing content. Please try again.`
  String get errorSharingContent {
    return Intl.message(
      'Error sharing content. Please try again.',
      name: 'errorSharingContent',
      desc: 'Error message when content sharing fails',
      args: [],
    );
  }

  /// `Preparing content...`
  String get preparingContent {
    return Intl.message(
      'Preparing content...',
      name: 'preparingContent',
      desc: 'Message shown while preparing content for sharing',
      args: [],
    );
  }

  /// `Generating PDF...`
  String get generatingPdf {
    return Intl.message(
      'Generating PDF...',
      name: 'generatingPdf',
      desc: 'Message shown while generating a PDF file',
      args: [],
    );
  }

  /// `Share Notes as Text`
  String get shareNotesAsText {
    return Intl.message(
      'Share Notes as Text',
      name: 'shareNotesAsText',
      desc: 'Text for sharing notes as text option',
      args: [],
    );
  }

  /// `Share Transcript as PDF`
  String get shareTranscriptAsPdf {
    return Intl.message(
      'Share Transcript as PDF',
      name: 'shareTranscriptAsPdf',
      desc: 'Text for sharing transcript as PDF option',
      args: [],
    );
  }

  /// `Share Transcript as Text`
  String get shareTranscriptAsText {
    return Intl.message(
      'Share Transcript as Text',
      name: 'shareTranscriptAsText',
      desc: 'Text for sharing transcript as text option',
      args: [],
    );
  }

  /// `Share Audio File`
  String get shareAudioFile {
    return Intl.message(
      'Share Audio File',
      name: 'shareAudioFile',
      desc: 'Text for sharing audio file option',
      args: [],
    );
  }

  /// `New Note`
  String get newNote {
    return Intl.message(
      'New Note',
      name: 'newNote',
      desc: 'Title for new note bottom sheet',
      args: [],
    );
  }

  /// `Auto Detect`
  String get autoDetect {
    return Intl.message(
      'Auto Detect',
      name: 'autoDetect',
      desc: 'Label for auto detect button in new note sheet',
      args: [],
    );
  }

  /// `selected`
  String get selected {
    return Intl.message(
      'selected',
      name: 'selected',
      desc: 'Label indicating that an option is currently selected',
      args: [],
    );
  }

  /// `Start audio recording`
  String get startAudioRecording {
    return Intl.message(
      'Start audio recording',
      name: 'startAudioRecording',
      desc: 'Label for starting audio recording option',
      args: [],
    );
  }

  /// `Upload from files`
  String get uploadFromFiles {
    return Intl.message(
      'Upload from files',
      name: 'uploadFromFiles',
      desc: 'Label for uploading from files option',
      args: [],
    );
  }

  /// `YouTube Video`
  String get youTubeVideo {
    return Intl.message(
      'YouTube Video',
      name: 'youTubeVideo',
      desc: 'Label for YouTube video option',
      args: [],
    );
  }

  /// `Bengali`
  String get bengali {
    return Intl.message(
      'Bengali',
      name: 'bengali',
      desc: 'Bengali language option',
      args: [],
    );
  }

  /// `Bulgarian`
  String get bulgarian {
    return Intl.message(
      'Bulgarian',
      name: 'bulgarian',
      desc: 'Bulgarian language option',
      args: [],
    );
  }

  /// `Catalan`
  String get catalan {
    return Intl.message(
      'Catalan',
      name: 'catalan',
      desc: 'Catalan language option',
      args: [],
    );
  }

  /// `Chinese`
  String get chinese {
    return Intl.message(
      'Chinese',
      name: 'chinese',
      desc: 'Chinese language option',
      args: [],
    );
  }

  /// `Croatian`
  String get croatian {
    return Intl.message(
      'Croatian',
      name: 'croatian',
      desc: 'Croatian language option',
      args: [],
    );
  }

  /// `Czech`
  String get czech {
    return Intl.message(
      'Czech',
      name: 'czech',
      desc: 'Czech language option',
      args: [],
    );
  }

  /// `Danish`
  String get danish {
    return Intl.message(
      'Danish',
      name: 'danish',
      desc: 'Danish language option',
      args: [],
    );
  }

  /// `Dutch`
  String get dutch {
    return Intl.message(
      'Dutch',
      name: 'dutch',
      desc: 'Dutch language option',
      args: [],
    );
  }

  /// `English`
  String get english {
    return Intl.message(
      'English',
      name: 'english',
      desc: 'English language option',
      args: [],
    );
  }

  /// `Estonian`
  String get estonian {
    return Intl.message(
      'Estonian',
      name: 'estonian',
      desc: 'Estonian language option',
      args: [],
    );
  }

  /// `Finnish`
  String get finnish {
    return Intl.message(
      'Finnish',
      name: 'finnish',
      desc: 'Finnish language option',
      args: [],
    );
  }

  /// `French`
  String get french {
    return Intl.message(
      'French',
      name: 'french',
      desc: 'French language option',
      args: [],
    );
  }

  /// `German`
  String get german {
    return Intl.message(
      'German',
      name: 'german',
      desc: 'German language option',
      args: [],
    );
  }

  /// `Greek`
  String get greek {
    return Intl.message(
      'Greek',
      name: 'greek',
      desc: 'Greek language option',
      args: [],
    );
  }

  /// `Hebrew`
  String get hebrew {
    return Intl.message(
      'Hebrew',
      name: 'hebrew',
      desc: 'Hebrew language option',
      args: [],
    );
  }

  /// `Hindi`
  String get hindi {
    return Intl.message(
      'Hindi',
      name: 'hindi',
      desc: 'Hindi language option',
      args: [],
    );
  }

  /// `Hungarian`
  String get hungarian {
    return Intl.message(
      'Hungarian',
      name: 'hungarian',
      desc: 'Hungarian language option',
      args: [],
    );
  }

  /// `Indonesian`
  String get indonesian {
    return Intl.message(
      'Indonesian',
      name: 'indonesian',
      desc: 'Indonesian language option',
      args: [],
    );
  }

  /// `Irish`
  String get irish {
    return Intl.message(
      'Irish',
      name: 'irish',
      desc: 'Irish language option',
      args: [],
    );
  }

  /// `Spanish`
  String get spanish {
    return Intl.message(
      'Spanish',
      name: 'spanish',
      desc: 'Spanish language option',
      args: [],
    );
  }

  /// `Japanese`
  String get japanese {
    return Intl.message(
      'Japanese',
      name: 'japanese',
      desc: 'Japanese language option',
      args: [],
    );
  }

  /// `Korean`
  String get korean {
    return Intl.message(
      'Korean',
      name: 'korean',
      desc: 'Korean language option',
      args: [],
    );
  }

  /// `Edit Name`
  String get editName {
    return Intl.message(
      'Edit Name',
      name: 'editName',
      desc: 'Label for edit name option in popup menu',
      args: [],
    );
  }

  /// `Edit Icon`
  String get editIcon {
    return Intl.message(
      'Edit Icon',
      name: 'editIcon',
      desc: 'Label for edit icon option in popup menu',
      args: [],
    );
  }

  /// `Manage Tags`
  String get manageTags {
    return Intl.message(
      'Manage Tags',
      name: 'manageTags',
      desc: 'Label for manage tags option in popup menu',
      args: [],
    );
  }

  /// `Delete`
  String get delete {
    return Intl.message(
      'Delete',
      name: 'delete',
      desc: 'Label for delete option in popup menu',
      args: [],
    );
  }

  /// `Confirm Deletion`
  String get confirmDeletion {
    return Intl.message(
      'Confirm Deletion',
      name: 'confirmDeletion',
      desc: 'Title for the deletion confirmation dialog',
      args: [],
    );
  }

  /// `Are you sure you want to delete this note? This cannot be undone.`
  String get deleteNoteConfirmation {
    return Intl.message(
      'Are you sure you want to delete this note? This cannot be undone.',
      name: 'deleteNoteConfirmation',
      desc: 'Message asking for confirmation before deleting a note item',
      args: [],
    );
  }

  /// `Cancel`
  String get cancel {
    return Intl.message(
      'Cancel',
      name: 'cancel',
      desc: 'Label for cancel button in dialogs',
      args: [],
    );
  }

  /// `Exit`
  String get exit {
    return Intl.message(
      'Exit',
      name: 'exit',
      desc: 'Label for exit button in dialogs',
      args: [],
    );
  }

  /// `Enter a new name`
  String get enterNewName {
    return Intl.message(
      'Enter a new name',
      name: 'enterNewName',
      desc: 'Instruction text for entering a new name in the edit name dialog',
      args: [],
    );
  }

  /// `Enter a new icon`
  String get enterNewIcon {
    return Intl.message(
      'Enter a new icon',
      name: 'enterNewIcon',
      desc: 'Instruction text for entering a new icon in the edit icon dialog',
      args: [],
    );
  }

  /// `Save`
  String get save {
    return Intl.message(
      'Save',
      name: 'save',
      desc: 'Label for save button in dialogs',
      args: [],
    );
  }

  /// `Create New Tag`
  String get createNewTag {
    return Intl.message(
      'Create New Tag',
      name: 'createNewTag',
      desc: 'Title for create new tag dialog',
      args: [],
    );
  }

  /// `Enter a name for your new tag`
  String get enterTagName {
    return Intl.message(
      'Enter a name for your new tag',
      name: 'enterTagName',
      desc: 'Instruction text for entering a new tag name',
      args: [],
    );
  }

  /// `Create`
  String get create {
    return Intl.message(
      'Create',
      name: 'create',
      desc: 'Label for create button in dialogs',
      args: [],
    );
  }

  /// `Tag name`
  String get tagName {
    return Intl.message(
      'Tag name',
      name: 'tagName',
      desc: 'Hint text for tag name input field',
      args: [],
    );
  }

  /// `No notes yet`
  String get noNotesYet {
    return Intl.message(
      'No notes yet',
      name: 'noNotesYet',
      desc: 'Message shown when no notes have been created',
      args: [],
    );
  }

  /// `Tap the button below to start`
  String get tapButtonBelowToStart {
    return Intl.message(
      'Tap the button below to start',
      name: 'tapButtonBelowToStart',
      desc: 'Instruction for user to tap the button to create first note',
      args: [],
    );
  }

  /// `Recording pause`
  String get recordingPause {
    return Intl.message(
      'Recording pause',
      name: 'recordingPause',
      desc: 'Text shown during recording when user can pause',
      args: [],
    );
  }

  /// `Recording continue`
  String get recordingContinue {
    return Intl.message(
      'Recording continue',
      name: 'recordingContinue',
      desc: 'Text for continuing recording',
      args: [],
    );
  }

  /// `Tap to stop recording...`
  String get tapToStopRecording {
    return Intl.message(
      'Tap to stop recording...',
      name: 'tapToStopRecording',
      desc: 'Instruction text shown when recording is in progress',
      args: [],
    );
  }

  /// `Tap to continue recording`
  String get tapToContinueRecording {
    return Intl.message(
      'Tap to continue recording',
      name: 'tapToContinueRecording',
      desc: 'Instruction text shown when recording is paused',
      args: [],
    );
  }

  /// `Tap to start recording`
  String get tapToStartRecording {
    return Intl.message(
      'Tap to start recording',
      name: 'tapToStartRecording',
      desc: 'Instruction text shown when recording is in initial state',
      args: [],
    );
  }

  /// `Recording paused`
  String get recordingPaused {
    return Intl.message(
      'Recording paused',
      name: 'recordingPaused',
      desc: 'Text shown when recording is paused',
      args: [],
    );
  }

  /// `Prompt & Language`
  String get promptAndLanguage {
    return Intl.message(
      'Prompt & Language',
      name: 'promptAndLanguage',
      desc: 'Button label for prompt and language settings',
      args: [],
    );
  }

  /// `Transcribe & Summarize`
  String get transcribeAndSummarize {
    return Intl.message(
      'Transcribe & Summarize',
      name: 'transcribeAndSummarize',
      desc: 'Label for transcribe and summarize button',
      args: [],
    );
  }

  /// `Warning`
  String get warning {
    return Intl.message(
      'Warning',
      name: 'warning',
      desc: 'Title for warning dialog',
      args: [],
    );
  }

  /// `Exiting the page will discard your recording. Are you sure?`
  String get exitRecordingWarning {
    return Intl.message(
      'Exiting the page will discard your recording. Are you sure?',
      name: 'exitRecordingWarning',
      desc: 'Warning message shown when user attempts to exit during recording',
      args: [],
    );
  }

  /// `Done`
  String get done {
    return Intl.message(
      'Done',
      name: 'done',
      desc: 'Label for done button',
      args: [],
    );
  }

  /// `What are you recording?`
  String get whatAreYouRecording {
    return Intl.message(
      'What are you recording?',
      name: 'whatAreYouRecording',
      desc: 'Question prompt for recording context',
      args: [],
    );
  }

  /// `This will improve the accuracy and quality of the transcription and notes.`
  String get recordingContextHint {
    return Intl.message(
      'This will improve the accuracy and quality of the transcription and notes.',
      name: 'recordingContextHint',
      desc: 'Hint explaining why recording context is important',
      args: [],
    );
  }

  /// `A marketing strategy meeting...`
  String get meetingTypeHint {
    return Intl.message(
      'A marketing strategy meeting...',
      name: 'meetingTypeHint',
      desc: 'Placeholder hint for the recording context input field',
      args: [],
    );
  }

  /// `Keywords`
  String get keywords {
    return Intl.message(
      'Keywords',
      name: 'keywords',
      desc: 'Label for keywords section in prompt and language sheet',
      args: [],
    );
  }

  /// `Specify uncommon acronyms, names, or terms to listen for. Separate with commas.`
  String get keywordsHint {
    return Intl.message(
      'Specify uncommon acronyms, names, or terms to listen for. Separate with commas.',
      name: 'keywordsHint',
      desc: 'Hint explaining how to use the keywords field',
      args: [],
    );
  }

  /// `KPI, Cache, JSON`
  String get keywordsPlaceholder {
    return Intl.message(
      'KPI, Cache, JSON',
      name: 'keywordsPlaceholder',
      desc: 'Placeholder example for keywords input',
      args: [],
    );
  }

  /// `Audio Language`
  String get audioLanguage {
    return Intl.message(
      'Audio Language',
      name: 'audioLanguage',
      desc: 'Label for audio language selection',
      args: [],
    );
  }

  /// `Summary Language`
  String get summaryLanguage {
    return Intl.message(
      'Summary Language',
      name: 'summaryLanguage',
      desc: 'Label for summary language selection',
      args: [],
    );
  }

  /// `Select file`
  String get selectFile {
    return Intl.message(
      'Select file',
      name: 'selectFile',
      desc: 'Label for select file button',
      args: [],
    );
  }

  /// `Select a video or audio file for transcript and notes.`
  String get selectFileDescription {
    return Intl.message(
      'Select a video or audio file for transcript and notes.',
      name: 'selectFileDescription',
      desc: 'Description text on the file upload screen',
      args: [],
    );
  }

  /// `YouTube video notes`
  String get youtubeVideoNotes {
    return Intl.message(
      'YouTube video notes',
      name: 'youtubeVideoNotes',
      desc: 'Title for YouTube video notes screen',
      args: [],
    );
  }

  /// `Paste a YouTube link for transcript & notes:`
  String get pasteYoutubeLink {
    return Intl.message(
      'Paste a YouTube link for transcript & notes:',
      name: 'pasteYoutubeLink',
      desc: 'Instruction text for pasting YouTube link',
      args: [],
    );
  }

  /// `Tap to Paste`
  String get tapToPaste {
    return Intl.message(
      'Tap to Paste',
      name: 'tapToPaste',
      desc: 'Text for paste button',
      args: [],
    );
  }

  /// `YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use direct file upload`
  String get youtubeUnsupportedFormats {
    return Intl.message(
      'YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use direct file upload',
      name: 'youtubeUnsupportedFormats',
      desc: 'Text explaining unsupported YouTube formats',
      args: [],
    );
  }

  /// `direct file upload`
  String get youtubeUnsupportedFormatsLinkText {
    return Intl.message(
      'direct file upload',
      name: 'youtubeUnsupportedFormatsLinkText',
      desc: 'Link text in the unsupported formats message',
      args: [],
    );
  }

  /// `.`
  String get youtubeUnsupportedFormatsPeriod {
    return Intl.message(
      '.',
      name: 'youtubeUnsupportedFormatsPeriod',
      desc: 'Period at the end of unsupported formats message',
      args: [],
    );
  }

  /// `YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use `
  String get youtubeShortsPrefixText {
    return Intl.message(
      'YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use ',
      name: 'youtubeShortsPrefixText',
      desc: 'Prefix text explaining unsupported YouTube formats',
      args: [],
    );
  }

  /// `YouTube Video`
  String get youtubeVideoScreenTitle {
    return Intl.message(
      'YouTube Video',
      name: 'youtubeVideoScreenTitle',
      desc: '',
      args: [],
    );
  }

  /// `Enter YouTube URL`
  String get youtubeUrlHint {
    return Intl.message(
      'Enter YouTube URL',
      name: 'youtubeUrlHint',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid YouTube URL`
  String get youtubeUrlErrorMessage {
    return Intl.message(
      'Please enter a valid YouTube URL',
      name: 'youtubeUrlErrorMessage',
      desc: '',
      args: [],
    );
  }

  /// `Processing Audio`
  String get processingAudio {
    return Intl.message(
      'Processing Audio',
      name: 'processingAudio',
      desc: '',
      args: [],
    );
  }

  /// `Transcribing`
  String get transcribing {
    return Intl.message(
      'Transcribing',
      name: 'transcribing',
      desc: '',
      args: [],
    );
  }

  /// `Identifying Speakers`
  String get identifyingSpeakers {
    return Intl.message(
      'Identifying Speakers',
      name: 'identifyingSpeakers',
      desc: '',
      args: [],
    );
  }

  /// `Taking Notes`
  String get takingNotes {
    return Intl.message(
      'Taking Notes',
      name: 'takingNotes',
      desc: '',
      args: [],
    );
  }

  /// `Finishing Touches`
  String get finishingTouches {
    return Intl.message(
      'Finishing Touches',
      name: 'finishingTouches',
      desc: '',
      args: [],
    );
  }

  /// `For longer recordings, this might take a minute or two.\nDon't leave the page.`
  String get recordingProcessingMessage {
    return Intl.message(
      'For longer recordings, this might take a minute or two.\nDon\'t leave the page.',
      name: 'recordingProcessingMessage',
      desc: '',
      args: [],
    );
  }

  /// `Rename`
  String get rename {
    return Intl.message('Rename', name: 'rename', desc: '', args: []);
  }

  /// `Change Icon`
  String get changeIcon {
    return Intl.message('Change Icon', name: 'changeIcon', desc: '', args: []);
  }

  /// `Select Icon`
  String get selectIcon {
    return Intl.message('Select Icon', name: 'selectIcon', desc: '', args: []);
  }

  /// `The audio is still being downloaded, please wait a moment.`
  String get audioIsDownloading {
    return Intl.message(
      'The audio is still being downloaded, please wait a moment.',
      name: 'audioIsDownloading',
      desc: '',
      args: [],
    );
  }

  /// `The audio is not ready yet, please wait a moment.`
  String get audioIsNotReady {
    return Intl.message(
      'The audio is not ready yet, please wait a moment.',
      name: 'audioIsNotReady',
      desc: '',
      args: [],
    );
  }

  /// `The audio is starting to download, please wait a moment.`
  String get audioIsStartingDownload {
    return Intl.message(
      'The audio is starting to download, please wait a moment.',
      name: 'audioIsStartingDownload',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'es'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
