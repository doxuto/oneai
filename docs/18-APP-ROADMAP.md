# 18 — Roadmap phía App (Flutter, Riverpod 3)

Ngày 23/09/2026. Tách từ `09-ROADMAP.md` S5–S9 thành 6 sprint app **A1–A6** ở mức
file, để agent chạy tuần tự. Ràng buộc bất biến: **bố cục, màu, chữ giữ nguyên
v1** (`07-APP-UI-FLOW-SPEC.md`), mọi chuỗi qua `context.l10n`, mọi màu qua
theme token, client không ghi Firestore, không có màn nào chờ ad để hiện.

Trạng thái thực thi: vì máy Toan chưa có Flutter, agent viết toàn bộ Dart
**chưa compile**; lần `.build-request` đầu tiên sau T1/T2 sẽ dọn lỗi. Mỗi màn
port từ file v1 tương ứng (cột "Nguồn v1") — đọc file gốc, giữ widget tree,
thay BLoC bằng provider đã viết ở tầng logic.

| Sprint | Tên | Cổng ra |
|---|---|---|
| A1 | Khung app + Login | đăng nhập thật, redirect đúng, mọi màn còn lại là route thật (không placeholder) |
| A2 | Home + danh sách note | note live từ Firestore, lọc tag, sheet tạo note, hành động trên card |
| A3 | Tạo note: ghi âm / upload / xử lý | ghi âm → upload thật → processing thật → ready; huỷ đúng pha; credit gate |
| A4 | Xem note: Summary / Transcript / Chat + AI tools | 3 tab, player + chương, speakers, chat stream, 7 artifact |
| A5 | Settings, tag, share/xuất, xoá tài khoản | không còn mục nào của Settings v1 thiếu |
| A6 | Monetization + push + chất lượng | ads runtime + UMP, paywall, quyền push, golden ≥30, a11y, perf |

## A1 — Khung app + Login

| ID | Task | File | Nguồn v1 |
|---|---|---|---|
| A1-01 | Widget dùng chung: `AppButton` (primary/outline/text, loading), `LoadingDots`, `EmptyState`, `ErrorState`, `ConfirmDialog`, `AppSnack` (map `ApiFailure` → chuỗi l10n) | `core/widgets/*` | `core/widgets/app_button.dart`, `home/widgets/loading_dots.dart` |
| A1-02 | `LoginScreen`: logo, tagline, nút Google (+ Apple chỉ iOS), nhãn "Previously signed in with …", loading theo nút, lỗi qua snack, không nuốt cancel | `features/auth/login_screen.dart` | `auth/login_page.dart` |
| A1-03 | Router thật: mọi route trỏ màn thật, `extra` typed cho `/audioProcessing` và `/transcriptionSummary`, redirect theo auth, transition theo spec | `core/router/app_router.dart` | `routing/*` |
| A1-04 | `SplashGate`: chờ auth resolve lần đầu (không nháy Login khi đã đăng nhập) | `features/auth/splash_gate.dart` | `main.dart` |

## A2 — Home + danh sách note

| ID | Task | File | Nguồn v1 |
|---|---|---|---|
| A2-01 | `HomeScreen`: app bar (avatar, tiêu đề, credits pill/premium button, settings), tag chips (All + tags, multi-select), list, empty state, FAB | `features/minutes/home/home_screen.dart` | `home/screens/home_screen.dart` |
| A2-02 | `MinuteItemCard`: emoji/icon, title, ngày, thời lượng, trạng thái (processing dots, failed), tag chips, menu (rename, emoji, tags, delete) | `features/minutes/home/minute_item_card.dart` | `home/widgets/minute_item_card.dart` |
| A2-03 | `TagChip`, `TagPickerSheet` (gắn tag cho note, tạo tag mới tại chỗ) | `features/tags/*` | `home/widgets/tag_chip.dart` |
| A2-04 | `NewMinutesBottomSheet` — 2 lối: ghi âm, tải file (không YouTube) | `features/minutes/home/new_minutes_bottom_sheet.dart` | `home/widgets/new_minutes_bottom_sheet.dart` |
| A2-05 | `PremiumButton` / credits pill đọc `isPremiumProvider` + `watchQuota` | `features/credits/credits_pill.dart` | `home/widgets/premium_button.dart` |
| A2-06 | Rename dialog, emoji picker sheet, delete confirm → `MinuteActions` | trong A2-02 | `minute_item_bloc` |

## A3 — Tạo note

| ID | Task | File | Nguồn v1 |
|---|---|---|---|
| A3-01 | `PromptLanguageSheet`: audio language, summary language, keywords, description → `TranscriptionOptions` | `features/transcription/prompt_language_sheet.dart` | `home/widgets/prompt_language_sheet.dart` |
| A3-02 | `RecordAudioScreen`: `record` package (AAC m4a), timer, waveform amplitude, pause/resume, huỷ, xin quyền mic, khoá màn hình không dừng ghi | `features/transcription/record_audio_screen.dart` + `recorder_controller.dart` | `home/screens/record_audio_screen.dart` |
| A3-03 | `UploadFileScreen`: `file_picker` audio/PDF, hiện tên/kích thước, kiểm size theo `maxSizeBytes` | `features/transcription/upload_file_screen.dart` | `home/screens/upload_file_screen.dart` |
| A3-04 | `AudioProcessingScreen` trên `NewMinuteFlow`: 5 bước hiển thị như v1 nhưng theo trạng thái thật, tiến trình upload thật, nút huỷ theo pha, lỗi + retry, hết credit → paywall/ad | `features/transcription/audio_processing_screen.dart` | `transcription/screens/audio_processing_screen.dart` |
| A3-05 | `CreditGate` nối UI: `creditGateDecide` → chạy / rewarded ad / paywall; `waitForRewardCredit` | `features/credits/credit_gate_ui.dart` | `premium_status_builder.dart` |

## A4 — Xem note

| ID | Task | File | Nguồn v1 |
|---|---|---|---|
| A4-01 | `TranscriptionSummaryScreen`: app bar (back, title, share, menu), `TranscriptTabSelector` 3 tab, banner slot | `features/minutes/detail/summary_screen.dart` | `transcription/screens/transcription_summary_screen.dart` |
| A4-02 | Tab Summary: title, icon, sections bullets (2 cấp), calendar events (Thêm vào Lịch), action items + decisions (tick), key terms | `features/minutes/detail/summary_tab.dart` | phần Summary của file trên |
| A4-03 | Tab Transcript: `TranscriptMessageWidget` theo speaker, player `just_audio` (download URL từ `sourcePath`), chương (`chapters`) tua được, highlight segment theo thời gian, đổi tên speaker inline, talk-time bar; `expired` → thông báo thay player | `features/minutes/detail/transcript_tab.dart`, `audio_player_controller.dart` | `transcript_message_widget.dart` |
| A4-04 | Tab Chat: `ChatMessageWidget`, `ChatInputWidget`, streaming, retry, câu hỏi gợi ý (`shortQuestions`) | `features/minutes/detail/chat_tab.dart` | `chat_*_widget.dart` |
| A4-05 | AI tools sheet: Quiz, Flashcards, Mindmap (cây thu gọn), Key terms, regenerate | `features/minutes/detail/ai_tools/*` | — (v1 chỉ có API) |
| A4-06 | `FeedbackWidget` (Sentry user feedback) | `features/minutes/detail/feedback_widget.dart` | `feedback_widget.dart` |

## A5 — Settings, tag, share

| ID | Task | File | Nguồn v1 |
|---|---|---|---|
| A5-01 | `SettingsScreen`: audio/summary language, thông báo (bật/tắt), feedback, contact, review, privacy, terms, manage subscription, free credits, sign out, delete account | `features/settings/settings_screen.dart` | `settings/screens/settings_screen.dart` |
| A5-02 | `TagManagerSheet`: tạo/sửa/xoá tag, số note | `features/tags/tag_manager_sheet.dart` | — |
| A5-03 | Export: Markdown + PDF (`pdf`/`printing`) có summary, chương, action items, transcript; share sheet | `features/minutes/share/export.dart` | phần share của summary screen |
| A5-04 | Delete account: xác nhận 2 bước → `AuthController.deleteAccount` | trong A5-01 | settings |

## A6 — Monetization, push, chất lượng

| ID | Task | File |
|---|---|---|
| A6-01 | `AdsRuntime`: GMA init sau UMP, preload app-open/interstitial/rewarded, `AdGate` quyết định, `AdLedger` lưu prefs, SSV options trên rewarded | `features/ads/runtime/*` |
| A6-02 | UMP consent + Privacy options; ATT sau UMP (iOS) | `features/ads/consent.dart` |
| A6-03 | Banner trong 3 tab, native trong list (mặc định tắt) | `features/ads/widgets/*` |
| A6-04 | Paywall RevenueCat (`purchases_ui_flutter`) ở 4 điểm v1 | `features/billing/paywall.dart` |
| A6-05 | Xin quyền push sau lần ghi âm đầu; Settings bật/tắt | `features/notifications/permission_prompt.dart` |
| A6-06 | Sentry + AppsFlyer init, debug tắt ở prod | `bootstrap.dart` |
| A6-07 | Golden ≥30, widget test, a11y AA, cold start < 2s | `test/golden/*` |

## Thứ tự thực thi

A1 → A2 → A3 → A4 → A5 (viết trước, chưa compile) → khi có Flutter: build-request
dọn lỗi theo từng sprint → A6 (cần SDK thật trên máy).
