# 20 — Checklist parity app v1 → v2 (S9-01)

Đối chiếu **từng phần tử UI / hành vi** của app cũ (`02-AUDIT-APP.md` §3, §6) với
màn tương ứng trong `App/oneai_v2/lib/`. Trạng thái: ✅ có (cùng layout/chữ/hành vi) ·
➕ v2 mở rộng · ✂️ bỏ có chủ ý · ⚠️ khác — cần sửa hoặc cần quyết.
Quy ước chung áp dụng cho mọi bảng: mọi chuỗi tiếng Anh hardcoded của v1 đã đi qua
l10n (`core/l10n/app_{en,es,vi}.arb`) → không liệt kê lại từng dòng, chỉ ghi ✂️ một lần
ở dòng "chuỗi hardcoded". Mọi dialog v1 (`AlertDialog` radius 16, divider, hai nút
xanh/đỏ) gom về `core/widgets/styled_dialog.dart` → `StyledDialog`.

## 3.1 LoginPage → `features/auth/login_screen.dart`

| # | v1 (02-AUDIT-APP) | v2 file / symbol | Trạng thái |
|---|---|---|---|
| 1 | Logo 50×50 + `oneAi` 28 bold, RichText tagline `0xFF0767F8` | `LoginScreen.build`, `AppColors.brandBlue` | ✅ |
| 2 | Google `OutlinedButton` radius 24, spinner 16×16 khi loading | `_GoogleButton` | ✅ ➕ khoá cả hai nút khi đang busy |
| 3 | Apple `ElevatedButton` đen, chỉ iOS | `_AppleButton` trong `if (Platform.isIOS)` | ✅ |
| 4 | Nhãn "(Previously signed in with …)" hardcoded, chỉ iOS | `lastLoginMethodProvider` + `l10n.previouslySignedInWith*`, key prefs `LOGIN_METHOD` giữ nguyên | ➕ hiện cả Android, l10n |
| 5 | Haptic + `AuthEvent.signInWithGoogle/Apple` | `authControllerProvider.notifier.signInWith*` | ✅ |
| 6 | `SnackBar(state.message)` khi `ErrorAuthState` | `ref.listen` → `AppSnack.failure` + `dismissError()` | ✅ |
| 7 | Router `_authGuard` redirect về `/` | `core/router/app_router.dart` `redirect:` | ✅ |
| 8 | `SharedPreferencesService()` tự new trong widget | `PrefsLoginMethodStore` qua provider | ✅ (DI) |

## 3.2 HomeScreen → `features/minutes/home/home_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | Header: `PremiumButton` + feedback + settings (InkWell r8, pad 8) | `_Header`, `_ActionButton`, `features/credits/premium_button.dart` | ✅ |
| 2 | Premium button: chưa premium → paywall; premium → disabled | `paywallProvider.present()`; `onPressed: null` khi premium | ✅ |
| 3 | Feedback icon → `SentryFeedbackDialog` | `showFeedbackDialog` (`detail/feedback_dialog.dart`) | ✅ (dialog khác — xem 3.11 #12) |
| 4 | Settings icon → `context.go(Routes.settings)` | `context.push(Routes.settings)` | ✅ (push thay go, cùng UX) |
| 5 | Title `'My Notes'` hardcoded | `l10n.myNotes` | ✂️ l10n |
| 6 | — | `_SearchField` (title + transcript preview, bỏ dấu) | ➕ mới (OQ-07 bước 1) |
| 7 | Tag row 44h: pill tạo tag, "All" khi >2 tag, `TagChip` từng tag | `_TagRow`, `_CreateTagButton`, `features/tags/tag_chip.dart` | ✅ |
| 8 | Lọc AND theo `selectedTagIds` | `SelectedTagIds`, `filterMinutes` (thuần, có test) | ✅ ➕ tự bỏ tag đã xoá trên server |
| 9 | `RefreshIndicator` → `loadMinuteItems(isRefresh)` | không có `RefreshIndicator` (list là Firestore stream) | ⚠️ thiếu: comment đầu file nói "pull-to-refresh re-reads getMe" nhưng widget không có; hoặc thêm `RefreshIndicator` invalidate `minutesListProvider`+`quotaProvider`, hoặc sửa comment |
| 10 | Overlay `CircularProgressIndicator` khi `isLoading` | `LoadingState` / `ErrorState(onRetry)` theo `AsyncValue` | ✅ ➕ có trạng thái lỗi + retry |
| 11 | Empty state: vòng tròn `0xFFE1EDFF` + clock icon + 2 dòng | `_EmptyNotes` | ✅ ➕ `_NoSearchResults` khi đang search |
| 12 | `ListView.builder(bottom: 80)` + `MinuteItemCard` | như v1 | ✅ |
| 13 | Infinite scroll 200px/400px + `LoadingDots` cuối list | bỏ — stream mang 100 note mới nhất | ✂️ paging (theo 16-PARITY #8/18) ⚠️ cần quyết: user >100 note không thấy note cũ |
| 14 | FAB full-width 56h, ẩn khi bàn phím mở (AnimatedSlide/Opacity) | `_NewNoteButton` + `AnimatedSlide` | ✅ |
| 15 | Create-tag dialog (title, hint, Cancel/Create) | `tags/tag_dialogs.dart` `showCreateTagDialog` | ✅ |
| 16 | Delete-tag dialog long-press, chữ hardcoded, nút đỏ | `showDeleteTagDialog` (`l10n.deleteTag`, `deleteTagConfirm(name)`) | ✅ ✂️ l10n |
| 17 | Intro-basic popup: gate premium / RC enabled / freq hours / key `INTRO_BASIC_LAST_SHOWN_TIME` | `home/intro_basic_popup.dart` `maybeShowIntroBasicPopup` | ✅ (giữ key v1) |
| 18 | Popup: cả hai nút gọi ATT `requestTrackingAuthorization` | ATT chuyển sang sau UMP trong `ads/runtime/consent.dart` | ✂️ (08-ADS-FLOW §4) |
| 19 | Popup: "Go Premium" đỏ → paywall | `StyledDialog(destructive: true)` → `paywallProvider.present()` | ✅ |
| 20 | RC default `popup_intro_basic_enabled = true` | `RemoteConfigService.defaults` = `false`, text `''` | ⚠️ khác: mặc định tắt + bỏ qua khi text rỗng → nếu console không set key thì popup không bao giờ hiện |
| 21 | `Purchases.addCustomerInfoUpdateListener` trực tiếp trong màn | `isPremiumProvider` (`billing/entitlement.dart`) | ✅ (DI) |

## 3.3 RecordAudioScreen → `features/transcription/record_audio_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | AppBar trắng, back, logo 32 + `'One AI'` hardcoded | `l10n.oneAi`, back tự xử lý exit-guard | ✅ ✂️ l10n |
| 2 | 4 vòng ripple 3000ms, `_waveOpacities`, border `primary.withAlpha(128)` 1.5 | `_wave` + `List.generate(4)` | ✅ ➕ bán kính co giãn theo `rec.amplitude` |
| 3 | Nút 120×120: fill primary khi ghi, border 2 khi pause, mic 36 | như v1 | ✅ |
| 4 | Status text 3 trạng thái, timer `mm:ss` ẩn khi initial | `switch (rec.phase)`, `_clock` | ✅ |
| 5 | `TextButton.icon` 48h `promptAndLanguage` → `PromptLanguageSheet` | `_openPromptSheet` | ✅ |
| 6 | Nút Transcribe chỉ hiện khi paused (`Visibility maintain*`), 56h r28 | như v1 | ✅ |
| 7 | Nhãn `'Watch Ad to Transcribe'` khi `nonPremiumNoCredits` | `creditGateLabel` → `l10n.watchAdToTranscribe` | ✅ ✂️ l10n |
| 8 | `premiumActionWrapper` → `stop()` → push `/audioProcessing` với map | `runWithCreditGate` → `recorder.finish()` → `AudioProcessingArgs(request)` | ✅ (extra có kiểu) |
| 9 | `RecordConfig aacLc 128k/44.1k`, file `minutes_ai_<ts>.m4a` | `recorder_controller.dart` | ✅ |
| 10 | Từ chối mic → im lặng | `permissionDenied` → `AppSnack(l10n.microphonePermissionNeeded)` | ➕ |
| 11 | `PopScope(canPop: initial)` + dialog cảnh báo (icon tam giác vàng, Exit đỏ) | `_showExitWarning` `StyledDialog` | ⚠️ khác: thiếu `Assets.warningTriangleIcon` 18×18 `0xFFF8C307` cạnh title |
| 12 | Ngôn ngữ đọc từ prefs mỗi lần vào màn | `defaultPromptSettings(languageSettingsProvider)` | ✅ |

## 3.4 UploadFileScreen → `features/transcription/upload_file_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | AppBar trong suốt, `uploadFromFiles` titleLarge bold | như v1 | ✅ |
| 2 | Body pad 24: mô tả, Audio lang, Summary lang, Spacer, nút | `_section` ×2 | ✅ |
| 3 | `LanguageSelector` trigger 40h `0xFFF5F5F5`, chevron xoay tint primary | `LanguageTriggerButton(tintArrows: true)` | ✅ |
| 4 | Nút 56h `selectFile` / `'Watch Ad to Transcribe'` | `creditGateLabel` | ✅ |
| 5 | `pickFiles(['mp3','wav','m4a','aac'])` | thêm `ogg, flac, mp4, pdf` | ➕ (PDF nhánh S3-08) |
| 6 | Huỷ picker → im lặng; không persist ngôn ngữ | giống v1 | ✅ |
| 7 | — | Summary chỉ cho chọn `summaryChoices` (không `auto`) | ➕ |

## 3.5 YouTubeVideoScreen

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | Toàn màn `/youtubeVideo`, paste chip, footer link, transcribe YouTube | không có route/màn | ✂️ OQ-06 (chốt 23/09) |

## 3.6 AudioProcessingScreen → `features/transcription/audio_processing_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | AppBar logo + `appName` + nút close | như v1, `automaticallyImplyLeading: false` | ✅ |
| 2 | Card 5 bước (icon check/close/spinner 24, `%` phải) | `_StepsCard`/`_StepRow` | ✅ |
| 3 | Tiến trình giả `Timer 50ms`, `+0.001`, fallback ~250s | trạng thái thật từ `newMinuteFlowProvider` (upload % thật) | ✂️ (07 §3 yêu cầu) |
| 4 | Lỗi 402 → dialog `'Premium Required'` Cancel/Go Premium | `isOutOfCredits` → `paywallProvider.present()` thẳng | ⚠️ khác: không có dialog trung gian (key `premiumRequired` có trong arb nhưng không dùng) — quyết: giữ dialog hay mở paywall thẳng |
| 5 | Lỗi khác → SnackBar đỏ hardcoded | `_FailureCard` + nút Retry khi `retryable` | ➕ |
| 6 | Xong: premium hoặc không có ad → tự `go(summary)` sau 200µs; ngược lại nút "Show Results" | luôn hiện nút `showResults` → `pushReplacement` | ⚠️ khác: bỏ auto-navigate cho mọi user (kể cả premium) — cần quyết |
| 7 | Reward card (`!_isPremium`): gift 48, title, blurb, nút cam `0xFFFEA200` r82 `'🔥 Watch Ad & Earn Credit'` | `_RewardCard`, chỉ hiện khi `rewarded.isReady` | ✅ ➕ ẩn khi chưa có ad (08 §6) |
| 8 | Blurb card riêng ("Your audio is being processed… earn 1 free credit?") | dùng lại `l10n.processingExplanation` cho cả card và dòng dưới | ⚠️ khác: mất câu mời xem ad; thêm key `earnCreditBlurb` |
| 9 | `recordingProcessingMessage` dưới card | `l10n.processingExplanation` | ✅ |
| 10 | Close pop mà không huỷ upload | `_close` → dialog `cancelProcessing` → `flow.cancel()` | ➕ |
| 11 | Ads: `showWhenWaitingTranscribeProcess` + client `/user/reward` | `rewarded.show()` → `waitForRewardCredit` (SSV) | ✂️ client tự cộng credit |
| 12 | — | Congratulation dialog + xin quyền push khi note đầu tiên `NewMinuteReady` | ➕ chuyển từ 3.7 #14 sang đây, key prefs mới `FIRST_NOTE_CELEBRATED` |

## 3.7 TranscriptionSummaryScreen → `features/minutes/detail/summary_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | Extra `String`, pop nếu sai kiểu | `SummaryArgs.from(extra, query)` → `_ErrorPage` nếu null | ✅ ➕ deep link `?minuteId=` |
| 2 | AppBar: back `0xFF2C7DF7`, title `back`, `titleSpacing 0` | `AppColors.brandBlueAlt` | ✅ |
| 3 | Share menu 5 mục 44h, SVG 20 phải, divider; `audioFile` chỉ khi có audio | `_ShareMenu`, `detail.canPlaySource` | ✅ |
| 4 | Header title + `'<date> • <duration>'` + `TranscriptTabSelector` | `_body` | ✅ (PDF không hiện duration ➕) |
| 5 | Loading spinner / error SnackBar / null → `SizedBox.shrink` | `LoadingState` / `ErrorState(onRetry)` / `_NotReady` | ✅ ➕ |
| 6 | Summary tab: banner + `MinuteSectionWidget` + `FeedbackWidget` | `summary_tab.dart` `_SectionWidget` | ✅ ➕ calendar events, action items, `AiToolsRow` |
| 7 | Transcript tab: banner + `TranscriptMessageWidget` (avatar màu theo speaker, đổi tên, LoadingDots) | `transcript_tab.dart` `_SegmentRow`, `speakerColor` | ✅ ➕ chapters, talk-time, highlight đoạn đang phát, tap timestamp seek |
| 8 | Chat tab: banner, list, `ChatTypingIndicator`, `ChatInputWidget` (chip gợi ý 38h, input 43h r45, hint `'Message...'`) | `chat_tab.dart` `_Bubble/_TypingIndicator/_ChatInput` | ✅ ➕ streaming, lịch sử `loadOlder`, retry |
| 9 | Chọn tab Chat → `initChat()` + scroll đáy 300ms | `ChatController` load lịch sử; scroll 200ms | ✅ |
| 10 | Share: `_showLoadingDialog` `preparingContent` không dismiss, xong → interstitial `afterShare` → pop | `minuteSharerProvider.share()` rồi `maybeShow(afterShare)`; không có dialog | ⚠️ thiếu dialog `preparingContent` khi tạo PDF/tải audio (key có trong arb) |
| 11 | Share audio: đang tải → `audioIsDownloading`; chưa tải → `downloadAudio()` + snackbar | `ShareSheetSharer.audioFile` tải rồi share luôn | ✅ (không cần bước trung gian) |
| 12 | FAB player chỉ tab Summary khi `gcsUri != null` | tab Summary **và** Transcript khi `canPlaySource` | ➕ |
| 13 | FAB mini 42 `0xFF2C7DF7`, spinner trắng khi loading; lỗi → `audioIsNotReady` snackbar | `_PlayerFab`; `PlayerPhase.failed` chỉ log | ⚠️ thiếu snackbar `audioIsNotReady` khi `phase == failed` |
| 14 | Dashboard: speed `[0.5,1,1.5,2]`, ±10s, play/pause 32, close, slider seek `onChangeEnd`, mm:ss 12 black54 | như v1; slider `onChanged` seek liên tục | ⚠️ khác: seek mỗi tick khi kéo → nên `_sliderPosition` + `onChangeEnd` như v1 |
| 15 | `PopScope(false)`: interstitial `summaryExit` + pop, **trừ** nhánh Congratulation | `_exit()` luôn qua `maybeShow(summaryExit)` | ✅ (sửa OQ-11) |
| 16 | Congratulation dialog (`SHOW_CONGRATULATION_DIALOG`, `minutes.length == 1`, InAppReview) | chuyển sang 3.6 #12 | ➕ đổi vị trí |
| 17 | Route extra `context.go` sau processing | `pushReplacement` | ✅ |

## 3.8 SettingsScreen → `features/settings/settings_screen.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | URL/email hardcoded `doxutostudio.top` | `appConfigProvider` (`termsUrl`, `privacyUrl`, `supportEmail`) | ✅ (config) |
| 2 | AppBar `'Settings'` center, `PopScope(false)` → interstitial `settingsExit` | `_exit` | ✅ ✂️ l10n |
| 3 | `_sectionLabel` 13/`0xFFBDBDBD`/w600/ls1; `_card` r14 shadow .03; `_divider` `0xFFF0F0F0`; `_iconRow` 30 SVG + chevron | `_SectionLabel/_Card/_RowDivider/_IconRow` | ✅ |
| 4 | NOTES: Audio/Summary language chip `0xFFF5F5F5`, `expand_more` grey | `_LanguageRow` → `languageSettingsProvider` (persist) | ✅ |
| 5 | — | NOTES thêm "Manage tags" (`TagManagerSheet`) + toggle "Notify when ready" | ➕ (OQ-15) |
| 6 | SUPPORT: feedback / contact mailto (uid, version) / review | `showFeedbackDialog`, `_contact` (`ClientInfo`), `InAppReview` | ✅ |
| 7 | LEGAL: privacy / terms `launchUrl` + snackbar lỗi | `_open` → `AppSnack(somethingWentWrong)` | ✅ |
| 8 | — | LEGAL thêm "Privacy options" (UMP form) | ➕ ⚠️ luôn hiện; nên ẩn khi `privacyOptionsRequired == false` |
| 9 | ACCOUNT: `'Email: <email>'` 15px black87 | `l10n.emailLabel(email)` | ✅ |
| 10 | Manage subscription → paywall / customer center | `paywallProvider.present()/customerCenter()` | ✅ |
| 11 | Free credits: `'Unlimited'` khi ≥888 else số | `premium ? unlimited : '<remaining>/<limit>'` | ➕ hiện `x/y` (bỏ sentinel 888) |
| 12 | Sign out → `AuthEvent.signOut()` | `authController.signOut()` | ✅ |
| 13 | DANGER ZONE `0xFFFFB300`: Delete account dialog → `SettingsEvent.deleteAccount` | `_deleteAccount` → `authController.deleteAccount()` (callable `deleteAccount`) | ✅ ✂️ client không gọi `user.delete()` trực tiếp |
| 14 | `SettingsLoading` dialog spinner; success snackbar; error snackbar | overlay `AuthBusy` + `AppSnack(accountDeleted)` / `AppSnack.failure` | ✅ |

## 3.9 NewMinutesBottomSheet → `features/minutes/home/new_minutes_bottom_sheet.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | Sheet trắng top r20, pad 16, header `newNote` + close 24 | `NewMinutesBottomSheet.show` | ✅ |
| 2 | 3 option `0xFFEBF3FF` r12, SVG 26, pop rồi push | `_Option` ×2 | ✅ |
| 3 | Option YouTube | bỏ | ✂️ OQ-06 |
| 4 | `LanguageSelector` comment-out + field chết | không mang theo | ✂️ dead code |

## 3.10 PromptLanguageSheet → `features/transcription/prompt_language_sheet.dart`

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | Cao 90%, Scaffold trong suốt, DecoratedBox trắng top r16 | như v1 | ✅ |
| 2 | Header title giữa + `done` phải → pop map | pop `PromptSettings` (typed) | ✅ |
| 3 | Body: context field, keywords field, divider, 2 language selector (chevron không tint) | như v1, `LanguageTriggerButton()` không tint | ✅ ➕ `maxLength: 500` cho context |
| 4 | Không Cancel; swipe → null, giữ giá trị cũ | như v1 | ✅ |
| 5 | Keywords là 1 chuỗi | `keywordList` tách `, ; \n`, ≤20 | ➕ |

## 3.11 Widget phụ trợ

| # | v1 | v2 | Trạng thái |
|---|---|---|---|
| 1 | `MinuteItemCard`: Card r12, avatar 24 `0xFFEDF4FF` emoji, title, `date · dot · duration` | `home/minute_item_card.dart` | ✅ ➕ icon pin, trạng thái uploading/queued/… + LoadingDots, `failed` đỏ, PDF |
| 2 | Tap card → interstitial `preSummary` → push summary | `interstitialHookProvider.maybeShow(AdPlacement.preSummary)` | ✅ |
| 3 | Menu: edit_name / edit_icon / manage_tags / delete (đỏ), divider `0xFFBDBDBD` | `_MoreButton` | ✅ ➕ mục Pin/Unpin |
| 4 | Edit icon: regex 1 emoji, lỗi `'Please enter a single emoji.'` | `singleEmoji`, `l10n.singleEmojiOnly` | ✅ ✂️ l10n |
| 5 | Manage tags: `Dialog` + `MinuteItemBloc`, Wrap chip, empty box 48h `0xFFF5F5F5`, Done | `_ManageTagsDialog` (local state) | ✅ ➕ chip "+ Create tag" ngay trong dialog |
| 6 | Delete → confirm → `deleteMinuteItem` | `StyledDialog` → `minuteActions.delete` (optimistic) | ✅ ➕ |
| 7 | `TagChip` 40h r20 `0xFF0767F8`/`0xFFEDF4FF`, 15 w500, haptic | `tags/tag_chip.dart` | ✅ |
| 8 | `TranscriptTabSelector`: 3 nút r24 `0xFF2C7DF7`/`0xFFE6F0FF`, SVG 16, `'Summary'` hardcoded | `detail/transcript_tab_selector.dart` | ✅ ✂️ l10n |
| 9 | `MinuteSectionWidget`: titleSmall bold, bullet pad 8/8, lặp title nếu rỗng, `timeRange` không render | `_SectionWidget` | ✅ |
| 10 | `TranscriptMessageWidget`: avatar 28 màu theo `speakerId % 5`, tên = TextButton đổi tên | `_SegmentRow` màu theo thứ tự xuất hiện | ✅ |
| 11 | `ChatMessageWidget` / `ChatTypingIndicator` (dot 8 primary, bubble `0xFFF2F2F2` r18, 3 dot 1200ms) | `_Bubble` / `_TypingIndicator` | ✅ |
| 12 | `SentryFeedbackDialog`: full-width, Cancel/`'Feedback & Support'`/Submit, field 6 dòng, footer email, `contactEmail`, snackbar cảm ơn, lỗi đỏ | `feedback_dialog.dart`: `StyledDialog` title `giveFeedback`, field 3–5 dòng, `captureFeedback(message)` thôi | ⚠️ khác: mất `contactEmail`, footer email, snackbar "Thank you", báo lỗi gửi — quyết giữ chrome mới hay port đủ |
| 13 | `FeedbackWidget`: `0xFFF0F6FF` r12, dislike → feedback dialog, like → nút `giveFeedback` → InAppReview | `detail/feedback_widget.dart` | ✅ |
| 14 | `LoadingDots` (blue, 10, 5 dot, 8 spacing, 1200ms) | `core/widgets/loading_dots.dart` | ✅ |
| 15 | `PremiumButton` premium `0xFFFFBB00` / upgrade `0xFF4285F4`, 16 SVG, r8 | `credits/premium_button.dart` | ✅ |
| 16 | `AppButton` không dùng; `keyboard_dismiss_on_tap` bọc app | `core/widgets/app_button.dart` có; không thấy keyboard-dismiss wrapper | ⚠️ thiếu `KeyboardDismissOnTap` quanh `MaterialApp.router` (`app.dart`) — tap ngoài field không đóng bàn phím |
| 17 | `getDialogWidth`: 90% <600, 80% <1200, 60% | `dialogWidth`: 90% <600, 60% <1200, 500 | ⚠️ khác (chỉ tablet) — sửa về 80%/60% |

## 6. Ads / paywall / Remote Config → `features/ads/**`, `features/billing/**`, `core/config/remote_config.dart`

| # | v1 (§6) | v2 | Trạng thái |
|---|---|---|---|
| 1 | 3 service fullscreen + `InlineAdaptiveBannerAd`, `MobileAds.initialize()` trong `main()` | `AdsRuntime` (một lớp, `InterstitialHook`+`RewardedHook`), `BannerAdWidget`; init sau UMP trong `ConsentGate` | ✅ ➕ không chặn first paint |
| 2 | Không UMP; ATT từ popup intro | `ConsentGate.gather()`: UMP → ATT (iOS) → `MobileAds.initialize` → AppsFlyer | ➕ (08 §4) |
| 3 | 7 key `ad_unit_*` JSON `{Android, iOS}` | 1 key `ad_units` (`ad_units.dart`) | ➕ gộp key (13-CONFIG) |
| 4 | Cold start: `showAtColdStart` sau RC, chặn UI; bỏ qua khi chưa có `INTRO_BASIC_LAST_SHOWN_TIME` | `AdsRuntime` chỉ gọi `_maybeShowAppOpen` trong `resumed` | ⚠️ thiếu App Open cold start (08 §6 nói "bỏ qua 3 session đầu, không chặn first paint" — chưa có đường gọi) |
| 5 | Warm start: nền ≥ `ad_open_app_background_threshold_minutes` (30) | `AdGate.appOpen`: `minimumBackgroundSeconds` 45 + spacing 300s + cap 4/ngày + skip 3 session | ➕ |
| 6 | Interstitial 4 vị trí: preSummary / summaryExit / afterShare / settingsExit | `AdPlacement.*` đúng 4 vị trí; `recordCompletion` ở preSummary/afterShare | ✅ |
| 7 | Rewarded khi hết credit (3 màn) + card chờ xử lý | `runWithCreditGate` (2 màn) + `_RewardCard` | ✅ |
| 8 | Banner 1 instance dùng chung 3 tab, inline adaptive max 60, không refresh | `AdBannerSlot` mỗi tab một `BannerAdWidget`, **anchored** adaptive; `banner.placements` mặc định chỉ `summaryTab`; `refreshSeconds` không đọc | ⚠️ khác: (a) mặc định transcript/chat không có banner — cần quyết; (b) 08 §6 hứa refresh theo `refreshSeconds` nhưng widget chưa có timer; (c) anchored thay inline (cao hơn 60) |
| 9 | Gate: lock / global freq 120s / premium / flag format / daily limit rewarded 5 / internet / timeout load 5s / preload 60' | `AdGate` thuần (`ad_gate.dart`, có test) + `AdLedger`; không có check internet/timeout riêng (SDK lo) | ✅ ➕ pacing theo completion |
| 10 | Dialog spinner chặn màn khi chờ ad load | không bao giờ chờ load (`maybeShow` return ngay nếu chưa có ad) | ✂️ (08 §6) |
| 11 | Reward: client `POST /user/reward` retry 3, toast ✅/⚠️ hardcoded | `waitForRewardCredit` nghe `quotaStreamProvider` (SSV), timeout 15s; toast `rewardOnItsWay / rewardReceived / adNotCompleted / somethingWentWrong` | ✂️ client tự cộng ✅ l10n |
| 12 | Toast `ad_toast_freq_limit_message` khi dính freq cap | không toast khi gate từ chối (chỉ `dev.log`) | ✂️ (skill: không có ad thì im lặng) |
| 13 | RevenueCat: `configure` key hardcoded, `logIn(uid)` sau sign-in, `logOut` | `auth/billing_identity.dart`, key từ `AppConfig` | ✅ (config) |
| 14 | `Constants.entitlementId = 'pro'` | `appConfig.entitlementId` | ✅ |
| 15 | 4 điểm mở paywall + customer center khi premium | `Paywall.present()` (Home, intro popup, Settings, 402) / `customerCenter()` | ✅ ➕ `present()` trả về premium sau khi đóng |
| 16 | `PremiumStatus` 3 giá trị, `PremiumStatusBuilder` từ RevenueCat + `creditStream` | `premiumStatusProvider` = `isPremiumProvider` + `quotaProvider` | ✅ |
| 17 | `isPremium()` nuốt exception → false | `RevenueCatEntitlements` stream | ✅ |
| 18 | RC: 21 key, fetchTimeout 1', `onConfigUpdated` re-activate, `waitForInitialization` chặn toàn UI | 5 key (`ads_config`, `ad_units`, 3 `popup_*`), timeout 8s, không chặn UI | ✅ ➕ ⚠️ chưa có `onConfigUpdated` — đổi config chỉ ăn sau 1h/khởi động lại (quyết: có cần không) |
| 19 | Prefs: `FULL_SCREEN_AD_LAST_SHOWN_TIME`, `REWARDED_AD_SHOWN_TODAY`, `REWARDED_AD_LAST_RESET_DATE` | `AdLedger` JSON qua `ledger_store.dart` | ✂️ key cũ (không cần migrate) |
| 20 | AppsFlyer/Sentry key hardcoded trong `main()` | `analytics/appsflyer_boot.dart`, `observability/sentry_boot.dart` từ `AppConfig` | ✅ (config) |

## Tổng hợp

Đếm theo trạng thái chính của từng dòng (dòng ghi `✅ ➕` tính là ✅; dòng có ⚠️ tính là ⚠️):
**✅ 94 · ➕ 16 · ✂️ 11 · ⚠️ 17** trên 138 dòng (17 ⚠️ = 13 việc sửa được ngay + 4 việc chờ quyết ở mục dưới; Ads #8 nằm cả hai).

13 việc sửa được ngay — **đã sửa cùng ngày** (commit `[fix][app] parity sweep`), giữ dòng ⚠️ ở bảng trên làm bằng chứng đối chiếu:

| # | Việc | Sửa ở |
|---|---|---|
| Home #9 | `RefreshIndicator` invalidate `minutesListProvider` + `quotaProvider` | `home_screen.dart` |
| Home #20 | `popup_intro_basic_enabled` default `true` như v1 (text rỗng vẫn ẩn) | `remote_config.dart` |
| Record #11 | `StyledDialog.titleIcon` + tam giác vàng 18×18 | `styled_dialog.dart`, `record_audio_screen.dart` |
| Processing #8 | key `earnCreditBlurb` (en/vi/es) cho card reward | `audio_processing_screen.dart`, ARB |
| Summary #10 | dialog `preparingContent` (barrier, `PopScope(canPop:false)`) quanh `share()` | `summary_screen.dart` |
| Summary #13 | `PlayerPhase.failed` → snack `audioIsNotReady` | `summary_screen.dart` |
| Summary #14 | `_SeekSlider`: kéo local, `seek` ở `onChangeEnd` | `summary_screen.dart` |
| Settings #8 | ẩn "Privacy options" khi `privacyOptionsRequiredProvider` = false | `settings_screen.dart`, `ad_hooks.dart`, `ads_runtime.dart` |
| Widget #16 | `GestureDetector` translucent unfocus quanh app (thay `KeyboardDismissOnTap`) | `app.dart` |
| Widget #17 | `dialogWidth` 90 / 80 / 60 % | `styled_dialog.dart` |
| Ads #4 | App Open cold start: show ngay khi ad đầu tiên của session load xong, qua `AdGate.appOpen` (skipFirstSessions), không chặn first paint | `ads_runtime.dart` |
| Ads #8b | `BannerAdWidget` refresh theo `banner.refreshSeconds` | `ads_runtime.dart` |
| Ads #18 | `onConfigUpdated.listen(activate)` | `remote_config.dart` |

Còn lại ⚠️ = 4 việc chờ quyết (+2 câu về banner/toast) ở mục dưới.

## Cần Toan quyết — **đã chốt 24/09** (xem `11-OPEN-QUESTIONS.md` OQ-17..21): Load more ✔ đã làm · dialog Premium Required ✔ đã làm · tự chuyển summary ✔ đã làm · feedback giữ bản gọn · banner/toast giữ mặc định

- **Home #13** — bỏ paging: user có >100 note không thấy note cũ (stream cắt 100). Chấp nhận hay thêm "Load more" bằng `listMinutes(cursor)`?
- **Processing #4** — 402 hết credit: mở paywall thẳng (v2) hay giữ dialog "Premium Required" (v1)?
- **Processing #6** — xong xử lý: luôn hiện nút "Show Results" (v2) hay tự chuyển sang summary như v1 cho premium/không ad?
- **Widget #12** — feedback dialog: giữ `StyledDialog` gọn (v2) hay port đủ v1 (email footer, `contactEmail`, snackbar cảm ơn, báo lỗi)?
- **Ads #8a/#8c** — banner: mặc định chỉ tab Summary (v2 config) hay cả 3 tab như v1? Anchored adaptive (cao hơn) hay inline max 60 như v1?
- **Ads #12** — gate từ chối rewarded (cap/ngày, cooldown): im lặng (skill) hay toast như v1 `ad_toast_freq_limit_message`?
