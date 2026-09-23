# 14 — Kế hoạch thực thi (ledger của automation)

File này là **sổ cái**: agent cập nhật trạng thái từng task ngay khi làm, theo
quy tắc một task → build xanh → một commit. `09-ROADMAP.md` là góc nhìn theo
sprint và mốc; file này là góc nhìn theo file và tiêu chí nghiệm thu.

Trạng thái: `[ ]` chưa · `[~]` đang làm · `[x]` xong (đã commit) · `[!]` chặn

Quy tắc commit: chỉ author + message. **Không** trailer, không `Co-Authored-By`.
Format: `[type][scope] Mô tả` — type ∈ feat fix test chore docs refactor;
scope ∈ be app docs repo.

---

## Chiến lược test backend (do môi trường)

| Tầng | Ở đâu | Chạy bởi | Khi nào |
|---|---|---|---|
| Unit — logic thuần, không chạm Firestore | `test/unit/` | agent, ngay trong shell | mỗi task |
| Integration — handler chống emulator thật | `test/integration/` | watcher trên Mac (`firebase emulators:exec`) | mỗi task, sau khi watcher chạy |
| Rules | `test/rules/` | watcher | S2-10 |

Mọi callable tách làm hai: `handler.ts` (hàm thuần `(uid, raw, deps)`) và
wrapper `onCall` chỉ làm keo. Unit test import handler. Deps là `{ db, now }` —
không mock `firebase-admin`, chỉ đổi `db` bằng emulator.

---

## S1 — còn lại

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S1-01..04 | Skeleton BE + App | — | 22/09 |
| [!] | S1-05 | Secrets qua `functions:secrets:set` | — | **Toan chạy** (cần CLI đăng nhập) |
| [x] | S1-06 | Emulator config + `test/helpers/emulator.ts` + npm script `test:integration` | `functions-v2/test/helpers/`, `package.json` | `emulators:exec` chạy được trên Mac |
| [ ] | S1-07 | App Check monitor mode | console | **Toan bật** |
| [~] | S1-08..09 | Auth: `AuthService` (Google + Apple, nonce CSPRNG — v1 nonce là 1 ký tự lặp), `SignInFailure` sealed (cancel im lặng), `LoginMethodStore` (key `LOGIN_METHOD` như v1), `BillingIdentity` (RevenueCat logIn/logOut best-effort), `AuthController` Notifier (signIn/signOut/deleteAccount qua callable rồi signOut local) | `App/oneai_v2/lib/features/auth/`, `test/unit/auth/` (18 test) | **viết xong, chưa compile** — chờ Flutter; Apple chỉ hiện trên iOS như v1 |
| [x] | S1-11 | GitHub Actions: backend (lint/unit/build → emulator integration → v1 syntax) + app (analyze/test) | `.github/workflows/*.yml` | badge xanh khi push |
| [ ] | S1-10 | Deploy v2 lên dev | — | **Toan chạy** `firebase deploy --only functions:v2 -P dev` |

## S2 — BE: data model + CRUD

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S9-05a | `deleteAccount` callable (`confirm:true` → `deletionRequestedAt` → `auth.deleteUser`; `onUserDeleted` dọn dữ liệu) | `users/deleteAccount.ts` | user-not-found → `not-found`; 3 unit + 2 integration test |
| [x] | S2-00 | Refactor `getMe` sang handler/wrapper + unit test | `users/handler.ts`, `users/getMe.ts`, `test/unit/users.test.ts` | handler test không cần Firestore cho nhánh lỗi |
| [x] | S2-01 | `createMinute` | `minutes/types.ts`, `minutes/_shared.ts`, `minutes/handler.ts`, `minutes/createMinute.ts` | trả `minuteId` + upload path; doc `status:"uploading"`; `sourceType` ∈ audio\|pdf; `sizeBytes` ≤ 300MB |
| [x] | S2-02 | `listMinutes` | `minutes/listMinutes.ts` + handler | cursor `[createdAtMillis, id]`; `tagIds` ≤10; sort enum; **thiếu index → ném `failed-precondition`, không trả rỗng** |
| [x] | S2-03 | `getMinute` | `minutes/getMinute.ts` | minute người khác → `not-found`; kèm `summary`, `transcriptPreview`, `speakers`, `artifacts` có sẵn |
| [x] | S2-04 | `updateMinute` | `minutes/updateMinute.ts` | chỉ `title`\|`iconEmoji`\|`tagIds`; `tagIds` phải tồn tại dưới `users/{uid}/tags`; rỗng → `invalid-argument` |
| [x] | S2-05 | `deleteMinute` | `minutes/deleteMinute.ts` | `recursiveDelete` + `deleteFiles(prefix)`; idempotent (xoá 2 lần → lần 2 `not-found`) |
| [x] | S2-06 | Tags CRUD | `tags/types.ts`, `tags/handler.ts`, `tags/{create,list,update,delete}Tag.ts` | `nameLower` unique → `already-exists`; delete gỡ `tagIds` khỏi minutes bằng batch ≤500 |
| [x] | S1-13 | Auth trigger tách handler: `users/lifecycle.ts` — `provisionUser` (transaction, **redeliver không reset profile/quota**), `wipeUser` (Firestore + Storage, báo cáo nửa hỏng → trigger throw để retry) | `users/{lifecycle,onUserCreated,onUserDeleted}.ts`, `test/integration/lifecycle.test.ts` (6 test) | wipe không đụng user khác; idempotent |
| [x] | S2-07 | Trigger `onMinuteWritten` duy trì `minuteCount` (user + tag) | `minutes/onMinuteWritten.ts` | tạo/xoá/đổi tag → count đúng; idempotent theo `event.id` |
| [x] | S2-08 | Output mapper tường minh | `minutes/_shared.ts` | không có `snap.data()` trả thẳng; `Timestamp` → ISO |
| [x] | S2-09 | Contract snapshot test | `test/unit/contract.test.ts` | JSON shape từng output snapshot |
| [x] | S2-10 | Rules unit test | `test/rules/firestore.rules.test.ts` | mỗi nhánh allow: pass/wrong-user/unauth |
| [x] | S2-11 | `firestore.indexes.json` khớp query thật | — | mọi query trong `listMinutes` có index |

## S3 — BE: pipeline transcribe

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S3-00 | Quota module thuần | `quota/quota.ts`, `test/unit/quota.test.ts` | `canConsume(period, plan)`, `consume(tx)`, `refund(tx)`; premium ghi `used` nhưng không chặn |
| [x] | S3-01 | `startTranscription` | `transcribe/startTranscription.ts` + handler | transaction: đọc minute + quota → trừ → set `queued` → enqueue; 20 song song với quota 1 → 1 qua |
| [x] | S3-02 | `processTranscription` task worker | `transcribe/processTranscription.ts`, `transcribe/pipeline.ts` | `onTaskDispatched` 2GiB/540s retry 3; máy trạng thái `transcribing→summarizing→ready` |
| [x] | S3-03b | **STT trừu tượng**: `SttClient` trả `SttResult{transcript, vendor, model}` chuẩn hoá; adapter Gemini (inline ≤14MB / Files API + poll, JSON `responseSchema`, MIME canonical); `makeStt` + `withSttFallback` theo `STT_VENDOR`/`STT_FALLBACK_VENDOR`; note + job ghi `stt{vendor,model}` | `lib/stt/{types,gemini,index}.ts`, `test/unit/stt.test.ts` (29) | fallback chỉ với lỗi vendor, không với deadline/safety |
| [x] | S3-13 | **Retention audio gốc**: `sourceExpiryFor` đóng dấu lúc ready theo plan (`FREE/PREMIUM_SOURCE_RETENTION_DAYS` 7/90, -1 = mãi); bước 5 sweep xoá `source/` quá hạn → `sourceState:"expired"`, `sourcePath:null`, giữ transcript/summary; đọc lại plan hiện tại trước khi xoá (upgrade → kéo hạn); `storage.lifecycle.json` backstop 180 ngày áp trong `deploy.sh`; index CG `(sourceState, sourceExpiresAt)` | `jobs/retention.ts`, `jobs/sweep.ts`, `transcribe/pipeline.ts` | 4 integration + 2 unit |
| [x] | S3-12 | **Quản lý job nặng**: `reapStaleJobs` 15 phút (running>30', queued>60' → `failJob`: hoàn credit 1 lần + note failed + push); `failJob` dùng chung pipeline/sweep/reaper; trần `maxActiveJobs` theo plan kiểm tra trước khi trừ quota; index `(uid,state)`, `(state,startedAt)`, `(state,createdAt)` | `jobs/{reap,reapStaleJobs}.ts`, `transcribe/{pipeline,handler}.ts` | integration: cap premium=2, reaper running/queued, không hoàn 2 lần |
| [x] | S8-08 | **Push FCM**: `registerDevice` (token chuyển uid khi đổi tài khoản cùng máy) / `unregisterDevice` / `updateNotificationPrefs`; `notifyMinuteResult` từ pipeline done/failed + reaper, copy en/vi/es theo locale máy, `collapseKey` theo note, prune token chết, không bao giờ throw; `getMe.notifications` | `lib/push/{types,fcm}.ts`, `push/*`, `test/unit/push.test.ts` (9), `test/integration/push.test.ts` (9) + pipeline push tests | rules: `devices/` server-only |
| [x] | S3-03 | ElevenLabs adapter | `lib/stt/elevenlabs.ts` | timeout 480s < 540s; 429→`resource-exhausted`; 5xx→`unavailable`; fetch native, không axios |
| [x] | S3-04 | `convertTranscript` + ISO-639-3 | `lib/stt/convert.ts`, `lib/stt/languages.ts` | `startSeconds`/`endSeconds` số; test với fixture ElevenLabs thật |
| [x] | S3-05 | Summarize prompt loader | `lib/llm/prompts.ts` | `__dirname`; prompt copy vào `src/prompts/`; test load được |
| [x] | S3-06 | Failure → refund | trong pipeline | `failed` + `creditRefunded:true`; test kill giữa chừng |
| [x] | S3-07 | `cancelTranscription` | `transcribe/cancelTranscription.ts` | chỉ khi `queued`/`transcribing`; refund |
| [x] | S3-08 | PDF branch | `lib/pdf/extract.ts` | `pdf-parse`; 20MB |
| [x] | S3-09 | `sweepOrphanFiles` | `jobs/sweepOrphanFiles.ts` | `onSchedule` 03:00 VN; test handler thuần |
| [x] | S3-10 | Idempotency `requestId` | trong `startTranscription` | `ref.create()` → code 6 → trả job cũ |
| [x] | S3-11 | Transcript ra Storage + preview | pipeline | `transcript.json` ở Storage, `transcriptPreview` ≤2000 |

## S4 — BE: AI

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S4-01 | LLM interface + OpenAI + Gemini | `lib/llm/{types,openai,gemini,index}.ts` | `generate(prompt, schema)` trả object đã validate; chọn vendor qua param |
| [x] | S4-02 | Structured output | trong adapter | zod schema → JSON schema → `response_format`; sai → `unavailable`, không cache |
| [x] | S4-03 | `chat` streaming + `chat/` subcollection + `listChatMessages` | `ai/chat.ts`, `ai/listChatMessages.ts` | `acceptsStreaming` → `sendChunk({delta})`; lưu cả 2 message |
| [x] | S4-04 | 4 `generate*` với cache `sourceHash` | `ai/generate{ShortQuestions,Quiz,Flashcards,Mindmap}.ts`, `ai/_artifacts.ts` | hit cache không gọi LLM; fail không ghi |
| [x] | S4-05 | `mapSpeakers` + `renameSpeaker` | `ai/mapSpeakers.ts`, `ai/renameSpeaker.ts` | speakers là artifact; rename không gọi LLM |
| [x] | S4-06 | `calendarEvents`: rút lúc summarize (zod), **lộ qua `getMinute().calendarEvents`** + callable `generateCalendarEvents` (timezone: input → minute.timezone → UTC); `getMinute` thêm `availableArtifacts` (1 lần đọc subcollection thay vì get từng kind) | `ai/summarize.ts`, `ai/generateCalendarEvents.ts`, `minutes/_shared.ts` | unit: mapper/prompt/schema/validate; integration: getMinute artifacts, cache sau lần sinh đầu, timezone ưu tiên |
| [x] | S4-07 | Cost: token cap + log + **trần AI call/ngày theo user** | adapter, `quota/aiCalls.ts` | `tokenCount` trong log mọi call; maxOutputTokens từng loại; transcript trim 120k ký tự |
| [x] | S4-09 | **Tính năng theo use case** (`17-FEATURE-RESEARCH.md`): `generateActionItems` (owner/due/quote + decisions, timezone như calendar), `generateKeyTerms`, `generateChapters` (transcript kèm `[start-end]`, clamp về duration, PDF → `noTimeline`), `talkTime` thuần trong `getMinute` | `ai/handler.ts`, `ai/generate{ActionItems,KeyTerms,Chapters}.ts`, `prompts/ai.ts`, `minutes/_shared.ts` | 3 integration + 4 unit; Dart model/repo/controller viết sẵn |
| [x] | S4-08 | Prompts gộp + test | `src/prompts/*.txt`, `test/unit/prompts.test.ts` | 7 prompt, mỗi cái ≥1 test placeholder |

## App A1–A6 (`18-APP-ROADMAP.md`) — viết trước, chưa compile

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [~] | A1-01 | Widget chung: `AppButton` (loading giữ chiều rộng), `LoadingDots`, `EmptyState`/`ErrorState`/`LoadingState`, `showConfirmDialog`, `AppSnack` + `failureText` (mọi lỗi → 1 chuỗi l10n); `ApiFailure` thêm `QuotaFailure.reason`, `PreconditionFailure.limitSeconds` | `core/widgets/*`, `core/theme/{gaps,theme_context}.dart` | chưa compile |
| [~] | A1-02 | `LoginScreen` port từ `login_page.dart`: cùng bố cục/màu/chữ, Apple chỉ iOS, loading theo nút, lỗi qua snack, cancel im lặng | `features/auth/login_screen.dart` | |
| [~] | A1-03 | `route_args.dart` typed extra; router dùng `LoginScreen` thật | `core/router/*` | các màn khác nối ở A2–A5 |
| [~] | A1-04 | `SplashGate` chờ auth resolve lần đầu | `features/auth/splash_gate.dart`, `app.dart` | |
| [~] | A2-01 | `HomeScreen` port: header (PremiumButton/feedback/settings), "My Notes", chip row (Create tag / All / tags, long-press xoá), list live, empty state v1, FAB trượt khi bàn phím mở; intro-basic popup từ Remote Config (không xin ATT ở đây nữa) | `features/minutes/home/{home_screen,intro_basic_popup}.dart`, `core/config/remote_config.dart` | |
| [~] | A2-02 | `MinuteItemCard` port + menu 4 mục; dialog rename/emoji (regex single-emoji v1)/xoá qua `StyledDialog`; trạng thái live (processing dots / failed) thay chỗ thời lượng | `features/minutes/home/minute_item_card.dart`, `core/widgets/{styled_dialog,format}.dart` | |
| [~] | A2-03 | `TagChip`, `TagActions`, dialog tạo/xoá tag, dialog Manage tags (chọn local, Done lưu 1 lần, tạo tag tại chỗ) | `features/tags/*` | |
| [~] | A2-04 | `NewMinutesBottomSheet` 2 lối | `features/minutes/home/new_minutes_bottom_sheet.dart` | |
| [~] | A2-05 | `PremiumButton`, `meProvider`/`quotaProvider`/`premiumStatusProvider`, `Paywall` (RevenueCatUI + refresh entitlement), `interstitialHook`/`rewardedHook` no-op cho tới A6 | `features/credits/*`, `features/billing/paywall.dart`, `features/ads/runtime/ad_hooks.dart` | |
| [~] | A2-06 | Feedback dialog (Sentry captureFeedback) | `features/minutes/detail/feedback_dialog.dart` | |
| [~] | A3-01 | `PromptLanguageSheet` port (typed `PromptSettings`), `LanguageSelector` + `LanguageTriggerButton` v1 | `features/transcription/{prompt_language_sheet,language_selector}.dart` | |
| [~] | A3-02 | `RecordAudioScreen` port + `RecorderController` (record: AAC m4a 128k/44.1k, pause/resume, amplitude vào vòng sóng, xin quyền, huỷ khi rời màn) | `features/transcription/{record_audio_screen,recorder_controller}.dart` | |
| [~] | A3-03 | `UploadFileScreen` port (file_picker, thêm PDF), `buildNewMinuteRequest` + `contentTypeFor` | `features/transcription/{upload_file_screen,new_minute_request_builder}.dart` | |
| [~] | A3-04 | `AudioProcessingScreen` trên `NewMinuteFlow`: 5 bước v1 theo trạng thái thật, % upload thật, đóng = huỷ theo pha (dialog), lỗi + Retry, hết credit → paywall, Congratulation lần đầu → xin quyền push + in-app review, reward card chỉ khi ad đã load | `features/transcription/audio_processing_screen.dart` | |
| [~] | A3-05 | `runWithCreditGate` (thay `premiumActionWrapper`) + `creditGateLabel`; `quotaStreamProvider` cho chờ SSV | `features/credits/credit_gate_ui.dart` | |
| [~] | A3-06 | Router: record/upload/processing là màn thật, transition slide v1, `AudioProcessingArgs` bắt buộc | `core/router/app_router.dart` | |
| [~] | A4-01 | `TranscriptionSummaryScreen` port: app bar Back + share menu 5 mục (audio chỉ khi `canPlaySource`), title, "date • duration", `TranscriptTabSelector` v1, tab theo `initialTab`, exit → interstitial `summary_exit`, note chưa ready/failed → màn chờ; `_PlayerFab` mini → dashboard (speed/±10s/play/close/slider) | `features/minutes/detail/{summary_screen,transcript_tab_selector,audio_player_controller}.dart` | player stream từ download URL, không tải cả file |
| [~] | A4-02 | Tab Summary: sections v1, **Events** (Thêm vào Lịch qua `add_2_calendar`), **Action items + decisions** (sinh theo yêu cầu, tick lưu local), `AiToolsRow`, FeedbackWidget | `features/minutes/detail/{summary_tab,feedback_widget}.dart` | |
| [~] | A4-03 | Tab Transcript: dòng speaker v1 (màu theo thứ tự xuất hiện, rename), timestamp tua được, highlight segment đang phát, **talk-time bar**, **chapters strip** (sinh theo yêu cầu, tap → tua), thông báo audio hết hạn | `features/minutes/detail/transcript_tab.dart` | |
| [~] | A4-04 | Tab Chat trên `ChatController`: bubble v1, typing dots, câu hỏi gợi ý (`shortQuestions`), pill input, retry, tải tin cũ | `features/minutes/detail/chat_tab.dart` | |
| [~] | A4-05 | Study tools: `ToolSheet<T>` chung + Quiz (chấm điểm), Flashcards (lật thẻ, PageView), Mindmap (cây thu gọn), Key terms; regenerate | `features/minutes/detail/ai_tools/*` | |
| [~] | A4-06 | `MinuteSharer` hook (A5 hiện thực), `AdBannerSlot` (A6), router `/transcriptionSummary` nhận `SummaryArgs` hoặc `?minuteId=` | `features/minutes/share/share_hooks.dart`, `features/ads/runtime/ad_hooks.dart`, `core/router/app_router.dart` | |
| [~] | A5-01 | `SettingsScreen` port: 5 section v1 + Manage tags + toggle "Báo khi ghi chú xong" (server prefs, bật → xin quyền OS), Privacy options hook (UMP ở A6), credits từ quota live, exit → interstitial `settings_exit` | `features/settings/settings_screen.dart`, `features/notifications/notification_prefs.dart` | |
| [~] | A5-02 | `TagManagerSheet`: tạo/sửa/xoá, số note | `features/tags/tag_manager_sheet.dart` | |
| [~] | A5-03 | Export: `MinuteExport.notesMarkdown` (sections, action items, decisions, events, chapters — chỉ artifact đã sinh, không gọi AI), `transcriptText`, PDF từ cùng cấu trúc; `ShareSheetSharer` 5 lựa chọn v1 (audio tải từ Storage) | `features/minutes/share/export.dart`, `test/unit/share/export_test.dart` (4 test) | |
| [~] | A5-04 | Xoá tài khoản: dialog xác nhận → `AuthController.deleteAccount` → snack | trong A5-01 | |
| [~] | A5-05 | Router: không còn placeholder nào — mọi route là màn thật | `core/router/app_router.dart` | |
| [~] | A6-01 | `AdsRuntime`: UMP → ATT → `MobileAds.initialize`, preload app-open/interstitial/rewarded, mọi quyết định qua `AdGate` + `AdLedger` (SharedPreferences `AD_LEDGER_V2`), chỉ show ad **đã load**, premium → drop ad ngay, app-open khi resume theo giây nền, rewarded gắn `ServerSideVerificationOptions(userId: uid)`; 4 hook provider override trong `bootstrap` (`adsOverrides()`), test/preview giữ no-op | `features/ads/runtime/{ads_runtime,consent,ad_units,ledger_store,ad_hooks}.dart`, `test/unit/ads/{ad_units,ad_placements}_test.dart` (6 test) | **chưa compile** |
| [~] | A6-02 | UMP consent + Privacy options (Settings), ATT sau UMP; UMP lỗi → vẫn init (không khoá ads ngoài vùng GDPR) | `features/ads/runtime/consent.dart` | |
| [~] | A6-03 | `BannerAdWidget` anchored-adaptive trong 3 tab qua `AdBannerSlot`; placement = tên trong `ads_config` (`summaryTab` mặc định, `transcriptTab`/`chatTab` bật từ RC); native **chưa** (RC mặc định tắt, `AdGate.nativeRows` sẵn) | `features/ads/runtime/ads_runtime.dart` | 0 chiều cao khi no-fill |
| [x] | A6-04 | Paywall RevenueCat — đã có từ A3 (`paywallProvider`, `presentPaywallIfNeeded`) | `features/billing/paywall.dart` | |
| [x] | A6-05 | Quyền push: xin sau lần xử lý đầu (`audio_processing_screen`) + toggle Settings — đã có từ A3/A5 | | |
| [~] | A6-06 | Sentry bọc `runApp` (DSN rỗng ở dev), AppsFlyer start sau ATT (không chạy ở dev), debug log tắt ở prod | `core/observability/sentry_boot.dart`, `features/analytics/appsflyer_boot.dart`, `bootstrap.dart` | |
| [ ] | A6-07 | Golden ≥30, widget test, a11y AA, cold start < 2s — **cần Flutter** (T1/T2) | `test/golden/*` | |
| [x] | S7-09a | BE: `updateMinute.pinned` → `pinned` + `pinnedAt`; `MinuteSummary.pinned/pinnedAt` | `minutes/{types,_shared,handler}.ts`, contract snapshot, 1 unit + 1 integration | |
| [~] | S7-09b | App: menu Ghim/Bỏ ghim trên card, icon ghim, ghim lên đầu theo `pinnedAt` (thuần `filterMinutes`) | `home/{home_controller,minute_item_card}.dart`, 1 test | chưa compile |
| [~] | S7-08 | App: tìm kiếm client-side title + `transcriptPreview` (AND theo từ, bỏ dấu tiếng Việt), ô search dưới "My Notes", trạng thái không kết quả | `home/{home_controller,home_screen}.dart`, 3 test | chưa compile — bước 1 OQ-07 |
| [x] | S6-12a | BE: `setActionItemDone {minuteId,itemId,done}` — tick nằm trong artifact, không gọi model/không quota; `ActionItemsData.items[].done` | `ai/{types,handler,setActionItemDone}.ts`, 3 unit + 2 integration | `force` sinh lại xoá tick (ghi trong contract) |
| [~] | S6-12b | App: tick action item optimistic → server (thay SharedPreferences), rollback + snack khi lỗi | `minute_detail_controller.dart` (`ActionItemsController.setDone`), `summary_tab.dart`, 2 test | chưa compile |
| [~] | S10-07/08 | Store compliance: bảng dữ liệu thu thập theo SDK, App Privacy labels, Play Data safety, điều khoản Terms/Privacy, trang xoá tài khoản, listing, checklist nộp | `docs/19-STORE-COMPLIANCE.md` | **[Toan]** điền console + đăng web (T13) |
| [~] | S9-01 | Parity app v1 → v2 màn-theo-màn (138 dòng); 13 lệch đã sửa (pull-to-refresh, intro popup default, icon cảnh báo, blurb reward, dialog preparing, snack audio lỗi, seek onChangeEnd, ẩn Privacy options, keyboard dismiss, dialogWidth, app-open cold start, banner refresh, RC live update) | `docs/20-PARITY-APP.md` + 9 file app | 4 mục chờ Toan quyết (OQ-16..19) |

## S5–S7 — App (chặn bởi `flutter create` + watcher)

Viết trước trong lúc chờ, **chưa compile** — lần `.build-request` đầu tiên sẽ dọn lỗi cú pháp nếu có:

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [~] | S5-04a | Models mirror contract TS: minute, tag, user, ai, transcribe | `lib/data/models/*.dart` | dùng `json_read`, enum khoan dung, `fromFirestore` cho Timestamp |
| [~] | S5-04b | Repositories: minutes (snapshots + callable), transcription (upload resumable + start/cancel), tags, user (watchQuota), ai (chat stream sealed event) | `lib/data/repositories/*.dart` | client không bao giờ ghi Firestore |
| [~] | — | `FunctionsClient.stream` map `ChunkResponse`/`ResultResponse` | `lib/data/firebase/functions_client.dart` | |
| [~] | S6-01 | `NewMinuteFlow` — máy trạng thái thật cho `/audioProcessing`: creating → uploading (tiến trình thật) → starting (1 `requestId` cho cả flow, retry không trừ 2 lần) → processing (Firestore listener) → ready/failed/cancelled; cancel đúng theo pha (chưa queued → xoá minute; đã queued → `cancelTranscription`, server hoàn credit); kiểm tra kích thước theo `maxSizeBytes` server trả | `lib/features/transcription/{new_minute_gateway,new_minute_flow}.dart`, `test/unit/transcription/new_minute_flow_test.dart` (17 test) | **chưa compile** |
| [~] | S6-07 | `ChatController` — lịch sử phân trang (cursor), gửi câu hỏi stream delta vào dòng assistant, `ChatDone` thay text/id server, lỗi giữa chừng giữ phần đã nhận + `retryLast`, `QuotaFailure` = trần AI call/ngày | `lib/features/minutes/chat/chat_controller.dart`, `test/unit/minutes/chat_controller_test.dart` (11 test) | **chưa compile** |
| [~] | S8-05 | `EntitlementSource` (RevenueCat `pro` → `isPremiumProvider`), `PremiumStatus` + `creditGateDecide` (thay `premiumActionWrapper`: không credit → ad **đã load** thì show, không thì paywall — không bao giờ chờ load), `waitForRewardCredit` (chờ `rewardBonus` tăng qua Firestore listener, timeout 15s, client không tự cộng) | `lib/features/billing/entitlement.dart`, `lib/features/credits/credit_gate.dart`, `test/unit/credits/` (11 test) | **chưa compile** |
| [~] | S5-05 | Home state: `minutesListProvider`/`tagsListProvider` (Firestore live), `SelectedTagIds` (multi-select AND như v1, tự bỏ tag đã xoá), `filterMinutes` thuần, `visibleMinutesProvider`, `MinuteActions` (xoá optimistic + hoàn tác khi lỗi, rename/setTags/setIcon) | `lib/features/minutes/home/home_controller.dart`, `test/unit/minutes/home_controller_test.dart` (13 test) | **chưa compile** |
| [~] | S7-01 | `LanguageSettings` (audio/summary; key v1 `AUDIO_LANGUAGE`/`SUMMARY_LANGUAGE`, đọc được cả giá trị v1 lưu kiểu `vietnamese`/`autodetect`), mặc định summary theo ngôn ngữ máy, `aiLanguageCodeProvider` cấp cho chat/generate* | `lib/features/settings/language_settings.dart`, `test/unit/settings/` (6 test) | **chưa compile** |
| [~] | S8-09 | App push: `PushRepository` (register/unregister/prefs), `PushMessaging` interface + `FirebasePushMessaging`, `PushRegistrar` (đăng ký sau sign-in, theo token rotation, không tự xin quyền — UI gọi `requestPermission()` sau lần ghi âm đầu), `unregisterBeforeSignOut` móc vào `AuthController`, `pushTapProvider` cho deep-link `minuteId`; `NotificationPrefs` trong `OneAiUser` | `lib/features/notifications/*`, `lib/data/repositories/push_repository.dart`, `test/unit/notifications/` (8 test) | **chưa compile** — Toan làm T8 (APNs key) |
| [~] | S6-08a | Dart cho API mới: `CalendarEvent`/`ArtifactKind` trong `MinuteDetail` (`hasArtifact`), `AiRepository.calendarEvents`, `CalendarEventsController` | `lib/data/models/*.dart`, `lib/data/repositories/ai_repository.dart`, `test/unit/models/` (3 test) | **chưa compile** |
| [~] | S6-05 | Detail + artifacts: `minuteDetailProvider` (refresh giữ dữ liệu cũ), `ArtifactController<T>` chung cho shortQuestions/quiz/flashcards/mindmap/speakers (lần đầu không `force` → cache server; `regenerate` force, giữ dữ liệu cũ lúc chờ), `SpeakersController.rename` không gọi LLM và đẩy tên mới vào detail | `lib/features/minutes/detail/minute_detail_controller.dart`, `test/unit/minutes/minute_detail_controller_test.dart` (7 test) | **chưa compile** |
| [x] | S0-07a | Assets chép sẵn (44 SVG + 12 PNG), `Assets` constants, `TranscriptionLanguage` (50 mã), Riverpod composition root `core/di/providers.dart`, bootstrap init Firebase + App Check theo flavor | | **chưa compile** |
| [x] | S7-04/05 | l10n chuẩn `gen-l10n`: 190 key `en` (162 v1 − demo/YouTube/progress giả + 82 key cho chuỗi cứng cũ), `es` và **`vi`** đủ key | `lib/core/l10n/`, `l10n.yaml` | placeholder khớp 3 file; `context.l10n.*` là cách duy nhất đọc chuỗi |

Chi tiết phần còn lại trong `09-ROADMAP.md`.

## S8 — Monetization

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S8-01 | ~~`resetDailyQuota`~~ **không cần** — quota là doc theo ngày, tạo khi dùng lần đầu, TTL dọn | — | Toan bật TTL policy trên field `expiresAt` của collection group `quota` và `adRewards` (console/gcloud, không phải code) |
| [x] | S8-02 | `revenueCatWebhook` | `billing/revenueCatWebhook.ts` | `timingSafeEqual`; `app_user_id` là uid thật; `set(merge)`; `planExpiresAt` |
| [x] | S8-04 | `adRewardSsv` | `ads/adRewardSsv.ts`, `ads/verify.ts` | 5 test bắt buộc (`08` §5) |
| [x] | S8-07a | `ads_config` + `ad_units` defaults + `merge.mjs` (gộp vào template live, không ghi đè key v1) | `Backend/oneai_backend/remote-config/` | script chạy thử với template giả: giữ key cũ, gộp id thật |
| [x] | S10-03a | Migration v1→v2 + inventory CLI (`tools/migrate-v1.mjs inventory\|plan\|apply`), idempotent, dry-run mặc định | `src/tools/migrateV1.ts`, `tools/migrate-v1.mjs` | test seed dữ liệu hình v1 → migrate → đọc lại qua handler v2 |
| [x] | S1-12 | `tools/seed-emulator.mjs` — user demo + note mọi trạng thái cho dev App | `functions-v2/tools/` | |
| [x] | S10-06a | `scripts/deploy.sh` có chốt chặn + `docs/15-RUNBOOK.md` | | |
| [x] | S10-05 | Alert as-code: `monitoring/apply.sh` (channel email, 8 log-based metric khớp tên `log.*` trong code, 9 policy JSON: pipeline failed, job reaped, STT 5xx, SSV forgery, RevenueCat unauthorized, index missing, FCM failed, error rate 5xx, worker p95) | `Backend/oneai_backend/monitoring/` | Toan chạy sau deploy dev; budget cần billing id |
| [x] | S10-02 | Load test emulator: `npm run load-test` — 1 user 50 start song song = `quota.used`; 100 user start+pipeline song song, 1 STT + 1 LLM/job; redelivery 100% skip | `functions-v2/tools/load-test.mjs` | exit ≠ 0 khi bất biến vỡ |
| [x] | S9-02 | Checklist parity BE v1→v2, 28 dòng, bằng chứng test từng dòng | `docs/16-PARITY-BACKEND.md` | 0 tính năng rơi ngoài 4 mục bỏ có chủ ý |
| [~] | S8-06 | Dart `AdGate` + `AdLedger` + `AdsConfig` | `App/oneai_v2/lib/features/ads/` | 27 test viết sẵn — **chưa compile** (chờ Flutter) |

---

## Việc chỉ Toan làm được (chặn automation)

> **23/09 — Toan: "hiện tại chưa thực hiện được, sẽ check và báo sau."** Mọi mục
> dưới đây đang chờ; agent không chặn việc khác vì chúng. Khi Toan báo, cập nhật
> cột trạng thái ở đây.

| # | Việc | Mở khoá |
|---|---|---|
| T1 | `cd App/oneai_v2 && flutter create --platforms=ios,android --org top.doxutostudio --project-name one_ai . && flutter pub get` | toàn bộ S5–S8 phía App |
| T2 | Mở 4 tab watcher (`12-AGENT-WORKFLOW.md`) | build/test App; integration test BE |
| T3 | `firebase functions:secrets:set` ×4 | deploy dev |
| T4 | Tạo project `oneai-dev`, `oneai-staging` | deploy dev/staging |
| T5 | Bật App Check monitor trong console | S1-07 |
| T6 | Chốt OQ-01, OQ-02 | S3-00 dùng mặc định tạm nếu chưa chốt |
| T7 | Revoke SOCKS proxy credential ở nhà cung cấp | bảo mật |
| T8 | Upload APNs key (.p8) vào Firebase console → Cloud Messaging; bật Push Notifications + Background Modes (Remote notifications) trong Xcode | push iOS |
| T10 | `cd Backend/oneai_backend/functions-v2 && sudo rm /usr/local/bin/firebase && npm i -D firebase-tools && npm run test:integration` (binary cũ là Intel — "Bad CPU type") — cần Java 11+ | 140 integration test |
| T11 | Sau deploy dev: `PROJECT_ID=oneai-dev NOTIFY_EMAIL=… ./monitoring/apply.sh` | alert |
| T12 | `npm run load-test` trên máy (emulator) — báo p95 | S10-02 |
| T13 | Điền App Privacy (App Store Connect) + Data safety (Play Console) theo `19-STORE-COMPLIANCE.md` §2–§3; đăng Privacy/Terms/Delete-account theo §4–§5; app-ads.txt | S10-07, S10-08 |
| T9 | (tuỳ chọn) đặt `STT_VENDOR=gemini` hoặc `STT_FALLBACK_VENDOR=gemini` trong `functions-v2/.env` rồi deploy — không cần sửa code | đổi vendor STT |
