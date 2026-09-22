// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(count) => "Attempt ${count}";

  static String m1(duration) => "Average duration: ${duration}ms";

  static String m2(count) => "Completed: ${count}";

  static String m3(message) => "Error: ${message}";

  static String m4(title) => "${title} feature coming soon!";

  static String m5(count) => "In progress: ${count}";

  static String m6(path) => "Page not found: ${path}";

  static String m7(id) => "Post ID: ${id}";

  static String m8(count) => "Total operations: ${count}";

  static String m9(id) => "User ID: ${id}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "appName": MessageLookupByLibrary.simpleMessage("One AI"),
    "appTitle": MessageLookupByLibrary.simpleMessage("One AI"),
    "attempt": m0,
    "audioIsDownloading": MessageLookupByLibrary.simpleMessage(
      "The audio is still being downloaded, please wait a moment.",
    ),
    "audioIsNotReady": MessageLookupByLibrary.simpleMessage(
      "The audio is not ready yet, please wait a moment.",
    ),
    "audioIsStartingDownload": MessageLookupByLibrary.simpleMessage(
      "The audio is starting to download, please wait a moment.",
    ),
    "audioLanguage": MessageLookupByLibrary.simpleMessage("Audio Language"),
    "autoDetect": MessageLookupByLibrary.simpleMessage("Auto Detect"),
    "averageDuration": m1,
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "bengali": MessageLookupByLibrary.simpleMessage("Bengali"),
    "breakTime": MessageLookupByLibrary.simpleMessage("Break"),
    "bulgarian": MessageLookupByLibrary.simpleMessage("Bulgarian"),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "catalan": MessageLookupByLibrary.simpleMessage("Catalan"),
    "categories": MessageLookupByLibrary.simpleMessage("Categories"),
    "categoriesComingSoon": MessageLookupByLibrary.simpleMessage(
      "Categories - Coming Soon",
    ),
    "categoriesDesc": MessageLookupByLibrary.simpleMessage(
      "Browse content by categories.",
    ),
    "changeIcon": MessageLookupByLibrary.simpleMessage("Change Icon"),
    "chat": MessageLookupByLibrary.simpleMessage("Chat"),
    "chinese": MessageLookupByLibrary.simpleMessage("Chinese"),
    "close": MessageLookupByLibrary.simpleMessage("Close"),
    "comments": MessageLookupByLibrary.simpleMessage("Comments"),
    "commentsPlaceholder": MessageLookupByLibrary.simpleMessage(
      "Comments would load here in a real app",
    ),
    "completed": m2,
    "confirmDeletion": MessageLookupByLibrary.simpleMessage("Confirm Deletion"),
    "create": MessageLookupByLibrary.simpleMessage("Create"),
    "createNewTag": MessageLookupByLibrary.simpleMessage("Create New Tag"),
    "createTag": MessageLookupByLibrary.simpleMessage("Create tag"),
    "croatian": MessageLookupByLibrary.simpleMessage("Croatian"),
    "czech": MessageLookupByLibrary.simpleMessage("Czech"),
    "danish": MessageLookupByLibrary.simpleMessage("Danish"),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Dark theme"),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteNoteConfirmation": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to delete this note? This cannot be undone.",
    ),
    "done": MessageLookupByLibrary.simpleMessage("Done"),
    "doneWithAi": MessageLookupByLibrary.simpleMessage("done\nwith AI"),
    "dutch": MessageLookupByLibrary.simpleMessage("Dutch"),
    "editIcon": MessageLookupByLibrary.simpleMessage("Edit Icon"),
    "editName": MessageLookupByLibrary.simpleMessage("Edit Name"),
    "english": MessageLookupByLibrary.simpleMessage("English"),
    "enterNewIcon": MessageLookupByLibrary.simpleMessage("Enter a new icon"),
    "enterNewName": MessageLookupByLibrary.simpleMessage("Enter a new name"),
    "enterTagName": MessageLookupByLibrary.simpleMessage(
      "Enter a name for your new tag",
    ),
    "error": m3,
    "errorSharingContent": MessageLookupByLibrary.simpleMessage(
      "Error sharing content. Please try again.",
    ),
    "errorSharingPdf": MessageLookupByLibrary.simpleMessage(
      "Error sharing PDF. Please try again.",
    ),
    "estonian": MessageLookupByLibrary.simpleMessage("Estonian"),
    "exit": MessageLookupByLibrary.simpleMessage("Exit"),
    "exitRecordingWarning": MessageLookupByLibrary.simpleMessage(
      "Exiting the page will discard your recording. Are you sure?",
    ),
    "featureComingSoon": m4,
    "featureUpdatesAndReleases": MessageLookupByLibrary.simpleMessage(
      "Feature Updates & Releases",
    ),
    "finishingTouches": MessageLookupByLibrary.simpleMessage(
      "Finishing Touches",
    ),
    "finnish": MessageLookupByLibrary.simpleMessage("Finnish"),
    "flutterMvvmBlocDemo": MessageLookupByLibrary.simpleMessage(
      "Flutter MVVM BLoC Demo",
    ),
    "french": MessageLookupByLibrary.simpleMessage("French"),
    "generatingPdf": MessageLookupByLibrary.simpleMessage("Generating PDF..."),
    "german": MessageLookupByLibrary.simpleMessage("German"),
    "giveFeedback": MessageLookupByLibrary.simpleMessage("Give Feedback"),
    "goHome": MessageLookupByLibrary.simpleMessage("Go Home"),
    "greek": MessageLookupByLibrary.simpleMessage("Greek"),
    "greetingNotes": MessageLookupByLibrary.simpleMessage("Greeting Notes"),
    "hebrew": MessageLookupByLibrary.simpleMessage("Hebrew"),
    "hindi": MessageLookupByLibrary.simpleMessage("Hindi"),
    "howDidWeDo": MessageLookupByLibrary.simpleMessage("How did we do?"),
    "hungarian": MessageLookupByLibrary.simpleMessage("Hungarian"),
    "identifyingSpeakers": MessageLookupByLibrary.simpleMessage(
      "Identifying Speakers",
    ),
    "inProgress": m5,
    "indonesian": MessageLookupByLibrary.simpleMessage("Indonesian"),
    "instantNotesFromAudio": MessageLookupByLibrary.simpleMessage(
      "Instant notes from\naudio and video, ",
    ),
    "irish": MessageLookupByLibrary.simpleMessage("Irish"),
    "japanese": MessageLookupByLibrary.simpleMessage("Japanese"),
    "keywords": MessageLookupByLibrary.simpleMessage("Keywords"),
    "keywordsHint": MessageLookupByLibrary.simpleMessage(
      "Specify uncommon acronyms, names, or terms to listen for. Separate with commas.",
    ),
    "keywordsPlaceholder": MessageLookupByLibrary.simpleMessage(
      "KPI, Cache, JSON",
    ),
    "korean": MessageLookupByLibrary.simpleMessage("Korean"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Light theme"),
    "loadingStatistics": MessageLookupByLibrary.simpleMessage(
      "Loading Statistics",
    ),
    "loadingStatisticsTooltip": MessageLookupByLibrary.simpleMessage(
      "Loading Statistics",
    ),
    "manageTags": MessageLookupByLibrary.simpleMessage("Manage Tags"),
    "marketAndCompetitorInsights": MessageLookupByLibrary.simpleMessage(
      "Market & Competitor Insights",
    ),
    "meetingTypeHint": MessageLookupByLibrary.simpleMessage(
      "A marketing strategy meeting...",
    ),
    "mvvmBlocDemo": MessageLookupByLibrary.simpleMessage("MVVM + BLoC Demo"),
    "newNote": MessageLookupByLibrary.simpleMessage("New Note"),
    "noNotesYet": MessageLookupByLibrary.simpleMessage("No notes yet"),
    "noUsersFound": MessageLookupByLibrary.simpleMessage("No users found"),
    "oneAi": MessageLookupByLibrary.simpleMessage("One AI"),
    "openingAndKeyHighlight": MessageLookupByLibrary.simpleMessage(
      "Opening & Key Highlight",
    ),
    "pageNotFound": MessageLookupByLibrary.simpleMessage("Page Not Found"),
    "pageNotFoundMessage": m6,
    "pasteYoutubeLink": MessageLookupByLibrary.simpleMessage(
      "Paste a YouTube link for transcript & notes:",
    ),
    "postId": m7,
    "posts": MessageLookupByLibrary.simpleMessage("Posts"),
    "premium": MessageLookupByLibrary.simpleMessage("Premium"),
    "preparingContent": MessageLookupByLibrary.simpleMessage(
      "Preparing content...",
    ),
    "previouslySignedInWithApple": MessageLookupByLibrary.simpleMessage(
      "(Previously signed in with Apple)",
    ),
    "processingAudio": MessageLookupByLibrary.simpleMessage("Processing Audio"),
    "productRoadmapReview": MessageLookupByLibrary.simpleMessage(
      "Product Roadmap Review",
    ),
    "promptAndLanguage": MessageLookupByLibrary.simpleMessage(
      "Prompt & Language",
    ),
    "qAndAAndNextSteps": MessageLookupByLibrary.simpleMessage(
      "Q&A & Next Steps",
    ),
    "recordingContextHint": MessageLookupByLibrary.simpleMessage(
      "This will improve the accuracy and quality of the transcription and notes.",
    ),
    "recordingContinue": MessageLookupByLibrary.simpleMessage(
      "Recording continue",
    ),
    "recordingPause": MessageLookupByLibrary.simpleMessage("Recording pause"),
    "recordingPaused": MessageLookupByLibrary.simpleMessage("Recording paused"),
    "recordingProcessingMessage": MessageLookupByLibrary.simpleMessage(
      "For longer recordings, this might take a minute or two.\nDon\'t leave the page.",
    ),
    "registered": MessageLookupByLibrary.simpleMessage("Registered"),
    "rename": MessageLookupByLibrary.simpleMessage("Rename"),
    "resetLoadingStatesTooltip": MessageLookupByLibrary.simpleMessage(
      "Reset Loading States",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "selectFile": MessageLookupByLibrary.simpleMessage("Select file"),
    "selectFileDescription": MessageLookupByLibrary.simpleMessage(
      "Select a video or audio file for transcript and notes.",
    ),
    "selectIcon": MessageLookupByLibrary.simpleMessage("Select Icon"),
    "selectTheme": MessageLookupByLibrary.simpleMessage("Select theme"),
    "selectUserToViewPosts": MessageLookupByLibrary.simpleMessage(
      "Select a user to view posts",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("selected"),
    "settings": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsComingSoon": MessageLookupByLibrary.simpleMessage(
      "Settings - Coming Soon",
    ),
    "settingsDesc": MessageLookupByLibrary.simpleMessage(
      "App settings and configuration options.",
    ),
    "share": MessageLookupByLibrary.simpleMessage("Share"),
    "shareAudioFile": MessageLookupByLibrary.simpleMessage("Share Audio File"),
    "shareNotesAsPdf": MessageLookupByLibrary.simpleMessage(
      "Share Notes as PDF",
    ),
    "shareNotesAsText": MessageLookupByLibrary.simpleMessage(
      "Share Notes as Text",
    ),
    "shareTranscriptAsPdf": MessageLookupByLibrary.simpleMessage(
      "Share Transcript as PDF",
    ),
    "shareTranscriptAsText": MessageLookupByLibrary.simpleMessage(
      "Share Transcript as Text",
    ),
    "signInWithApple": MessageLookupByLibrary.simpleMessage(
      "Sign in with Apple",
    ),
    "signInWithGoogle": MessageLookupByLibrary.simpleMessage(
      "Sign in with Google",
    ),
    "spanish": MessageLookupByLibrary.simpleMessage("Spanish"),
    "startAudioRecording": MessageLookupByLibrary.simpleMessage(
      "Start audio recording",
    ),
    "summaryLanguage": MessageLookupByLibrary.simpleMessage("Summary Language"),
    "systemTheme": MessageLookupByLibrary.simpleMessage("System theme"),
    "tabComingSoon": MessageLookupByLibrary.simpleMessage(
      "tab content coming soon",
    ),
    "tagName": MessageLookupByLibrary.simpleMessage("Tag name"),
    "takingNotes": MessageLookupByLibrary.simpleMessage("Taking Notes"),
    "tapButtonBelowToStart": MessageLookupByLibrary.simpleMessage(
      "Tap the button below to start",
    ),
    "tapToContinueRecording": MessageLookupByLibrary.simpleMessage(
      "Tap to continue recording",
    ),
    "tapToPaste": MessageLookupByLibrary.simpleMessage("Tap to Paste"),
    "tapToStartRecording": MessageLookupByLibrary.simpleMessage(
      "Tap to start recording",
    ),
    "tapToStopRecording": MessageLookupByLibrary.simpleMessage(
      "Tap to stop recording...",
    ),
    "teamUpdatesAndActionItems": MessageLookupByLibrary.simpleMessage(
      "Team Updates & Action Items",
    ),
    "totalOperations": m8,
    "transcribeAndSummarize": MessageLookupByLibrary.simpleMessage(
      "Transcribe & Summarize",
    ),
    "transcribing": MessageLookupByLibrary.simpleMessage("Transcribing"),
    "transcript": MessageLookupByLibrary.simpleMessage("Transcript"),
    "upgrade": MessageLookupByLibrary.simpleMessage("Upgrade"),
    "uploadFromFiles": MessageLookupByLibrary.simpleMessage(
      "Upload from files",
    ),
    "userId": m9,
    "users": MessageLookupByLibrary.simpleMessage("Users"),
    "usersAndPosts": MessageLookupByLibrary.simpleMessage("Users & Posts"),
    "usersAndPostsDesc": MessageLookupByLibrary.simpleMessage(
      "View users and their posts with loading state management.",
    ),
    "warning": MessageLookupByLibrary.simpleMessage("Warning"),
    "welcomeMessage": MessageLookupByLibrary.simpleMessage(
      "Welcome to our app",
    ),
    "whatAreYouRecording": MessageLookupByLibrary.simpleMessage(
      "What are you recording?",
    ),
    "youTubeVideo": MessageLookupByLibrary.simpleMessage("YouTube Video"),
    "youtubeShortsPrefixText": MessageLookupByLibrary.simpleMessage(
      "YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use ",
    ),
    "youtubeUnsupportedFormats": MessageLookupByLibrary.simpleMessage(
      "YouTube Shorts, Live, private, and unlisted videos are not supported. For these formats, use direct file upload",
    ),
    "youtubeUnsupportedFormatsLinkText": MessageLookupByLibrary.simpleMessage(
      "direct file upload",
    ),
    "youtubeUnsupportedFormatsPeriod": MessageLookupByLibrary.simpleMessage(
      ".",
    ),
    "youtubeUrlErrorMessage": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid YouTube URL",
    ),
    "youtubeUrlHint": MessageLookupByLibrary.simpleMessage("Enter YouTube URL"),
    "youtubeVideoNotes": MessageLookupByLibrary.simpleMessage(
      "YouTube video notes",
    ),
    "youtubeVideoScreenTitle": MessageLookupByLibrary.simpleMessage(
      "YouTube Video",
    ),
  };
}
