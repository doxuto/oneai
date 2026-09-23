# 09 — Roadmap tới ngày phát hành (bản 2 — build lại từ đầu)

Lập 2026-09-22. Giả định **1 dev + agent**, sprint 1–3 tuần.

> Bản 1 lập kế hoạch cho "rework tại chỗ, giữ BLoC". Toan đổi hướng ngày 22/09:
> **dựng lại sạch cả hai phía trong thư mục mới, Riverpod 3, parity đầy đủ.**
> Tài liệu này thay thế bản cũ hoàn toàn.

**Tiến độ 23/09** — backend S1–S4 và hai `onRequest` của S8 đã xong trong một
ngày nhờ automation (27 function, 137 unit + 105 integration test). Lịch
dưới đây giữ nguyên cho phía App; phía backend còn lại chỉ là việc console
(secrets, TTL, deploy). Chi tiết từng task: `14-EXECUTION-PLAN.md`.

| Sprint | Tên | Dài | Từ → đến | Trạng thái |
|---|---|---|---|---|
| **S0** | Nền móng, secrets, môi trường | 1 tuần | 23/09 → 29/09 | 🔶 chờ Toan (T1–T7) |
| **S1** | Skeleton BE + App | 2 tuần | 30/09 → 13/10 | ✅ BE · 🔶 App: auth viết xong, chờ `flutter create` để compile |
| **S2** | BE: data model + CRUD | 2 tuần | 14/10 → 27/10 | ✅ 23/09 |
| **S3** | BE: pipeline transcribe bất đồng bộ | 2 tuần | 28/10 → 10/11 | ✅ 23/09 |
| **S4** | BE: tính năng AI | 2 tuần | 11/11 → 24/11 | ✅ 23/09 |
| **S5** | App: auth + home + danh sách note | 2 tuần | 25/11 → 08/12 | 🔶 tầng logic viết sẵn 23/09 (auth, home state, minute actions) — **chưa compile**; màn hình chờ T1+T2 |
| **S6** | App: tạo note → xử lý → xem kết quả | 3 tuần | 09/12 → 29/12 | 🔶 tầng logic viết sẵn 23/09 (`NewMinuteFlow`, chat, detail + artifacts, speakers) — **chưa compile**; màn hình chờ T1+T2 |
| **S7** | App: tag, settings, l10n, share/PDF | 2 tuần | 30/12 → 12/01/27 | 🔶 l10n en/es/vi, language settings, lọc tag, BE `deleteAccount` xong — còn màn hình, PDF/share, Sentry/AppsFlyer |
| **S8** | Monetization: quota + ads + SSV | 2 tuần | 13/01 → 26/01 | ✅ BE (quota, webhook, SSV, trần AI call/ngày) · 🔶 App: AdGate/AdLedger, credit gate, entitlement, chờ SSV viết sẵn — còn SDK runtime + UMP + paywall UI |
| **S9** | Parity sweep + chất lượng | 2 tuần | 27/01 → 09/02 | ⬜ |
| **S10** | Phát hành | 2 tuần | 10/02 → 23/02/27 | ⬜ |
| **S11** | Sau phát hành: tìm lại & ôn tập | 4 tuần | sau M6 | ⬜ đã nghiên cứu (`17`) |

**Mốc**

| Mốc | Khi |
|---|---|
| M1 — `getMe` chạy được từ app mới qua emulator | hết S1 |
| M2 — Một note đi trọn vòng đời trên BE mới | hết S3 |
| M3 — App mới đăng nhập được và hiện danh sách note thật | hết S5 |
| M4 — Luồng chính chạy end-to-end trên app mới | hết S6 |
| M5 — Parity đầy đủ, code freeze | hết S9 |
| M6 — Lên store | tuần 2 của S10 |
| M7 — Gỡ `App/oneai/` và `functions/` | M6 +30 ngày |

**Cổng chung mọi task:** `.build-request` → `.build-done` `exit=0` → 1 commit →
task kế tiếp (`12-AGENT-WORKFLOW.md`).

---

## S0 — Nền móng, secrets, môi trường · 23/09 → 29/09

| ID | Task | Xong khi |
|---|---|---|
| S0-01 | ~~scripts watch-build / watch-git / build-and-test cho cả hai phía~~ | ✅ 22/09 |
| S0-02 | ~~docs 01–13~~ | ✅ 22/09 |
| S0-03 | **Huỷ SOCKS proxy credential ở phía nhà cung cấp** (`95.164.203.157:9822`). Code đã gỡ 23/09 nhưng git history vẫn giữ | credential cũ vô hiệu |
| ~~S0-04~~ | ~~Lấy AdMob iOS App ID thật~~ | ✅ 23/09 — `ca-app-pub-8661297299230251~8024150974` |
| S0-05 | Xoay `REVENUECAT_WEBHOOK_SECRET` | |
| S0-06 | Tạo project Firebase `oneai-dev` + `oneai-staging` | `firebase use dev` chạy |
| S0-07 | Chạy `flutter create` trong `App/oneai_v2/` theo README, chép `assets/` sang | `flutter analyze` xanh |
| S0-08 | `flutterfire configure` cho 3 flavor | 3 file `firebase_options_*.dart`, đều gitignore |
| S0-09 | Info.plist + AndroidManifest theo `13-CONFIG-INVENTORY.md` §6–8 | app chạy được trên máy thật |
| S0-10 | GitHub Actions: lint + test cho `functions-v2` và `oneai_v2` | ✅ 23/09 (`.github/workflows/{backend,app}.yml`, chạy khi push lên GitHub) |

**Cổng ra:** cả hai scaffold build được trên máy Toan; 4 tab watcher chạy.

---

## S1 — Skeleton BE + App · 30/09 → 13/10

Phần lớn đã dựng sẵn 22/09; sprint này hoàn thiện và deploy lên dev.

| ID | Task | Xong khi |
|---|---|---|
| S1-01 | ~~`functions-v2/` TS + eslint + vitest + `lib/{admin,errors,validate,logging,params,cursor,time}`~~ | ✅ tsc + eslint + 11 test xanh |
| S1-02 | ~~`firebase.json` 2 codebase, `.firebaserc` 4 alias, `firestore.rules`, `firestore.indexes.json`, `storage.rules`~~ | ✅ |
| S1-03 | ~~`getMe`, `onUserCreated`, `onUserDeleted`~~ | ✅ |
| S1-04 | ~~App: pubspec sạch, analysis_options strict, theme chép nguyên si, `ApiFailure` sealed, `FunctionsClient`, router~~ | ✅ 13 file |
| S1-05 | Đặt secrets qua `firebase functions:secrets:set` | `getMe` chạy trên dev |
| S1-06 | Emulator suite + seed data + rules unit test | ✅ viết xong (140 test) — **chưa chạy được trên máy Toan**, xem T2 |
| S1-07 | Bật App Check chế độ **monitor** (DeviceCheck / Play Integrity) | dashboard thấy request hợp lệ |
| S1-08 | Nối `authStateProvider` vào `FirebaseAuth.authStateChanges()` | redirect login hoạt động thật |
| S1-09 | App gọi `getMe` qua emulator, hiện kết quả ra màn placeholder | **M1** |
| S1-10 | Deploy `functions:v2` lên dev, xác nhận v1 còn nguyên | `functions:list` có cả hai |

**Cổng ra (M1):** app mới đăng nhập dev, gọi `getMe`, nhận đúng shape.

---

## S2 — BE: data model + CRUD · 14/10 → 27/10

| ID | Task | Xong khi |
|---|---|---|
| S2-01 | `createMinute` | trả `minuteId` + resumable upload path, doc `status:"uploading"` |
| S2-02 | `listMinutes` — cursor mờ, lọc tag, sort | 3 trang liên tiếp không trùng/sót; **thiếu index phải ném lỗi, không trả mảng rỗng** |
| S2-03 | `getMinute` | minute của người khác → `not-found` |
| S2-04 | `updateMinute` | chỉ `title`/`iconEmoji`/`tagIds` |
| S2-05 | `deleteMinute` | recursive delete + xoá prefix Storage |
| S2-06 | `createTag` / `listTags` / `updateTag` / `deleteTag` | trùng `nameLower` → `already-exists` |
| S2-07 | Trigger duy trì `minuteCount` | khớp sau 20 thao tác ngẫu nhiên |
| S2-08 | Output mapper tường minh từng callable | không `return snap.data()`; `Timestamp` → ISO-8601 |
| S2-09 | Contract snapshot test | đổi shape = test đỏ |
| S2-10 | Rules unit test đầy đủ | chủ đọc được / người khác 403 / mọi client write bị chặn |

**Cổng ra:** ≥60 test server xanh.

---

## S3 — BE: pipeline transcribe bất đồng bộ · 28/10 → 10/11

| ID | Task | Xong khi |
|---|---|---|
| S3-01 | `startTranscription` — trừ quota trong `runTransaction` rồi enqueue task | 20 request song song, quota 1 → đúng 1 cái qua |
| S3-02 | `processTranscription` (`onTaskDispatched`, 2GiB/540s, retry 3) | file 100MB không OOM |
| S3-03 | Adapter ElevenLabs, timeout **nhỏ hơn** budget function, map 429/5xx — ✅ ➕ **Gemini STT** + đổi vendor bằng `STT_VENDOR`, fallback | |
| S3-04 | `convertTranscript` → `startSeconds`/`endSeconds` số; bảng ISO-639-3 một module | |
| S3-05 | Summarize: prompt load bằng `__dirname` | |
| S3-06 | Máy trạng thái + hoàn quota khi thất bại vĩnh viễn | kill task giữa chừng, quota về đúng |
| S3-07 | `cancelTranscription` | huỷ khi `queued`/`transcribing`, hoàn quota |
| S3-08 | Nhánh PDF | PDF 20MB ra summary đúng nội dung |
| S3-09 | `sweepOrphanFiles` hằng ngày — ✅ ➕ `reapStaleJobs` 15 phút, trần `maxActiveJobs`/user | file mồ côi + minute kẹt `uploading` >24h bị dọn |
| S3-10 | Idempotency `requestId` + `ref.create()` | gọi 2 lần cùng id → 1 job |
| S3-13 | **Retention audio gốc** theo plan (7/90 ngày), sweep hằng ngày, `sourceState`, lifecycle bucket backstop — ✅ 23/09 | Storage không phình; transcript/summary còn nguyên |

**Cổng ra (M2):** upload audio thật → `status:"ready"` + summary + transcript.

---

## S4 — BE: tính năng AI · 11/11 → 24/11

| ID | Task | Xong khi |
|---|---|---|
| S4-01 | `lib/llm/` — interface + adapter OpenAI/Gemini. **Không port Grok** | đổi vendor bằng config |
| S4-02 | Structured output thay `JSON.parse` chuỗi tự do | sai schema → `unavailable`, **không cache** |
| S4-03 | `chat` streaming + lưu lịch sử + `listChatMessages` | thoát app mở lại còn hội thoại |
| S4-04 | `generateShortQuestions` / `generateQuiz` / `generateFlashcards` / `generateMindmap` | cache theo `sourceHash`; thất bại không ghi |
| S4-05 | `mapSpeakers` + `renameSpeaker`, tách khỏi đường đọc | `getMinute` không gọi LLM |
| S4-06 | `calendarEvents` validate shape | không spread nguyên body |
| S4-07 | Cost control: giới hạn token, `maxInstances`, log `model` + `tokenCount` | dashboard chi phí |
| S4-08 | Prompt: gộp trùng, mỗi prompt ≥1 test — **chờ OQ-05** | |
| S4-09 | **Action items + decisions, chapters có mốc thời gian, key terms, talk-time** (`17-FEATURE-RESEARCH.md` §2.1) — ✅ 23/09 | 3 callable + `talkTime` trong `getMinute`, cache như các artifact khác |

**Cổng ra:** 6 tính năng AI chạy trên dev, không cái nào cache được kết quả rỗng.

---

## S5 — App: auth + home + danh sách note · 25/11 → 08/12

Từ đây trở đi mọi màn phải khớp `07-APP-UI-FLOW-SPEC.md` §3.

| ID | Task | Xong khi |
|---|---|---|
| S5-01 | Feature `auth`: Google + Apple, `Notifier`, **không nuốt lỗi** — ✍️ viết xong (`SignInFailure` sealed, nonce CSPRNG), chưa compile | lỗi đăng nhập hiện đúng nguyên nhân |
| S5-02 | Màn Login khớp bố cục v1 | golden xanh |
| S5-03 | RevenueCat `logIn(uid)` sau đăng nhập, `logOut()` khi thoát — ✍️ `BillingIdentity`, best-effort | |
| S5-04 | Repository + model cho minutes, đọc bằng `json_read.dart` — ✍️ viết xong, chưa compile | |
| S5-05 | Home: danh sách qua Firestore `snapshots()` + `withConverter` — ✍️ `minutesListProvider`, lọc tag AND, `visibleMinutesProvider` | tạo note máy khác → máy này tự hiện |
| S5-06 | `MinuteItemCard`, `TagChip`, empty state, loading, error | golden cho 4 trạng thái |
| S5-07 | Phân trang cursor khi cuộn | |
| S5-08 | Xoá / đổi tên / đổi emoji / gắn tag từ card — ✍️ `MinuteActions` (xoá optimistic) | |
| S5-09 | Widget test + golden cho Home và Login | ≥12 golden |

**Cổng ra (M3):** đăng nhập thật, thấy note thật từ BE mới.

---

## S6 — App: tạo note → xử lý → xem kết quả · 09/12 → 29/12

Sprint dài nhất — đây là trái tim sản phẩm.

| ID | Task | Xong khi |
|---|---|---|
| S6-01 | `NewMinutesBottomSheet` + 2 màn tạo (record / upload) khớp v1. **Không còn lối YouTube** — sheet chỉ còn 2 mục | golden xanh |
| S6-02 | Ghi âm: `record`, waveform, tạm dừng/tiếp tục, huỷ | |
| S6-03 | Upload trực tiếp Storage resumable — progress **thật**, huỷ, tiếp tục — ✍️ `NewMinuteFlow` + `NewMinuteGateway` | ngắt mạng rồi nối lại vẫn xong |
| S6-04 | `AudioProcessingScreen`: bỏ progress giả, dùng Firestore listener, nút đóng gọi `cancelTranscription` — ✍️ state machine xong, còn màn | **bố cục/màu/chữ không đổi** |
| S6-05 | Màn Summary: 3 tab Summary / Transcript / Chat | golden cho từng tab |
| S6-06 | Chat streaming trên UI — ✍️ `ChatController` xong, còn màn | chữ chạy dần |
| S6-07 | Speaker: hiện tên, đổi tên inline — ✍️ `SpeakersController.rename` | |
| S6-08 | Quiz / flashcards / mindmap / câu hỏi gợi ý — ✍️ `ArtifactController<T>` (cache server, regenerate) | |
| S6-09 | Audio player trong tab Transcript | |
| S6-10 | `QuotaFailure` → dialog "Premium Required" — ✍️ `creditGateDecide` + `NewMinuteFailed.isOutOfCredits` | test: hết quota → paywall hiện |
| S6-11 | Golden + widget test cho toàn bộ màn mới | ≥30 golden tổng |
| S6-12 | Tab **Việc cần làm** (action items, decisions, tick xong) — ✅ BE `setActionItemDone`; ✍️ app tick đồng bộ server + nút đưa việc có hạn vào Lịch (add_2_calendar) | tick theo note trên mọi máy |
| S6-13 | **Thanh chương** trên player, tua theo chương, highlight chương đang phát | dùng `chapters` |
| S6-14 | **Thêm vào Lịch** từ `calendarEvents` (EventKit / Calendar intent) | |
| S6-15 | Cảnh báo **audio gốc hết hạn sau N ngày** + nút tải về; trạng thái `expired` ẩn player | từ `sourceExpiresAt` |

**Cổng ra (M4):** ghi âm → transcribe → xem summary → chat, tất cả trên BE mới.

---

## S7 — App: tag, settings, l10n, share/PDF · 30/12 → 12/01/27

| ID | Task | Xong khi |
|---|---|---|
| S7-01 | Quản lý tag: tạo, sửa, xoá, lọc — ✍️ lọc (`SelectedTagIds`) xong; CRUD sheet còn | |
| S7-02 | Màn Settings đầy đủ mục như v1 — ✍️ `LanguageSettings` (audio/summary, key v1) xong; còn màn | golden xanh |
| S7-03 | Xuất PDF + **Markdown**, có chương + action items, share sheet (Notion/Docs qua share) | file mở được, nội dung đúng |
| S7-04 | l10n: **mọi** chuỗi qua ARB ngay từ đầu, không hardcode | grep literal tiếng Anh trong widget = 0 |
| S7-05 | `en` + `es` + **`vi`** đủ key — chờ OQ-12 | |
| S7-06 | Xoá tài khoản + xoá dữ liệu — ✅ BE `deleteAccount`; ✍️ `AuthController.deleteAccount` | |
| S7-07 | Sentry + AppsFlyer, debug flag tắt ở prod | |
| S7-08 | Tìm kiếm client-side (title + `transcriptPreview`) — bước 1 của OQ-07 — ✍️ viết xong, chưa compile | |
| S7-09 | Ghim / yêu thích note (`updateMinute.pinned`) — ✅ BE; ✍️ app viết xong | |

**Cổng ra:** không còn màn nào là placeholder.

---

## S8 — Monetization: quota + ads + SSV · 13/01 → 26/01

| ID | Task | Xong khi |
|---|---|---|
| S8-01 | Quota `users/{uid}/quota/{period}` + `resetDailyQuota` — chờ OQ-02, OQ-03 | reset đúng 00:00 giờ VN |
| S8-02 | `revenueCatWebhook`: so secret constant-time, verify uid, `set(merge)`, `planExpiresAt` | `Bearer undefined` → 403 |
| S8-03 | Kiểm hạn premium lúc dùng — ✅ `effectivePlan(planExpiresAt)` ở mọi đường đọc | webhook miss không cho premium vĩnh viễn |
| ~~S8-04~~ | `adRewardSsv` — **bỏ 24/09** (không rewarded để thêm phút); code đã xoá | — |
| ~~S8-05~~ | SSV trên AdMob — **bỏ 24/09** | — |
| S8-06 | Dart `AdGate` **thuần** + `AdLedger` | ≥30 unit test, phủ đủ 12 `AdRefusal` |
| S8-07 | Một key `ads_config` JSON, default `enabled:false` | không fetch được config → không hiện ad |
| S8-08 | UMP trước GMA init; ATT chỉ sau UMP ở iOS; nút Privacy options | test EEA giả lập hiện form |
| S8-09 | Ad không chặn màn hình, không chặn first paint | TTI < 2s lần mở đầu |
| S8-10 | App Open bỏ qua 3 session đầu; Interstitial đếm completion (sàn 2) | không bao giờ 2 interstitial liền |
| S8-11 | Banner refresh; Native ad trong danh sách (mặc định tắt) | `nativeRows`/`nativeChunks` khớp nhau, có test |
| S8-12 | Paywall RevenueCat ở 4 điểm như v1 | |
| S8-13 | **Gói & giá theo chuẩn ngành** (21-RESEARCH §4, Toan cấu hình RevenueCat/store): thêm gói **tuần** (~$4.99), trial **7 ngày** cho gói năm, gói năm mặc định trên paywall, giá địa phương VN, bật grace period + account hold (Play: 31% huỷ do lỗi thanh toán) | offering `default` có weekly/monthly/annual |
| S8-14 | **Hạn mức minh bạch**: phút/credit còn lại ngay trên nút Ghi + sheet tạo note, cảnh báo "còn 5 phút" khi ghi, paywall + listing nêu rõ hạn mức free (than phiền #1 của ngành) | user không bao giờ "đụng tường" bất ngờ |
| S8-15 | ✅ **Toan chốt 24/09**: free **10 phút/ngày** (`FREE_DAILY_SECONDS=600`, 1 bản ≤ 10 phút), **không có rewarded** để thêm phút, premium không giới hạn (`PREMIUM_DAILY_SECONDS=0`, 1 bản ≤ 4 h); quota đổi sang giây, đặt cọc + settle theo độ dài đo được; PDF = 300 giây | BE + app xong |

**Cổng ra:** ad hiện đúng tần suất trên cả 2 nền tảng; không client nào cộng được credit.

---

## S9 — Parity sweep + chất lượng · 27/01 → 09/02

| ID | Task | Xong khi |
|---|---|---|
| S9-01 | **Đối chiếu từng mục `02-AUDIT-APP.md` §3 và §5** với app mới | bảng checklist 100% |
| S9-02 | Đối chiếu từng endpoint `01-AUDIT-BACKEND-V1.md` §1 với callable v2 — ✅ `16-PARITY-BACKEND.md` (28 dòng, 0 rơi) | không tính năng nào rơi |
| S9-03 | Accessibility: touch target ≥44pt, semantics, contrast AA — ✍️ tooltip/Semantics pass + `expectAccessible` trong widget test | audit sạch |
| S9-04 | Perf: cold start < 2s trên iPhone 12 | |
| S9-05 | `integration_test` luồng chính trên CI + emulator — ✅ BE (job `integration` trong CI); App chờ Flutter | xanh |
| S9-06 | Crashlytics/Sentry alert + crash-free tracking | dashboard chạy |
| S9-07 | Chốt **toàn bộ** `11-OPEN-QUESTIONS.md` | 0 mục `CHƯA CHỐT` |
| S9-08 | Code freeze | **M5** |

---

## S10 — Phát hành · 10/02 → 23/02/27

| ID | Task | Xong khi |
|---|---|---|
| S10-01 | Deploy staging + smoke test đầy đủ | 0 lỗi |
| S10-02 | Load test 100 transcribe đồng thời — ✅ `npm run load-test` (emulator, vendor giả: contention quota, 100 job song song, redelivery); phần chi phí/OOM thật đo trên staging | không OOM, chi phí đo được |
| S10-03 | Migration dữ liệu v1 → v2 — ✅ tool `migrate-v1.mjs inventory\|plan\|apply`; **chờ OQ-01** để chạy | dry-run trên bản sao staging |
| S10-04 | App Check chuyển sang **enforce** | traffic hợp lệ không bị chặn |
| S10-05 | Alert: error rate, p95, chi phí/ngày — ✅ as-code `monitoring/apply.sh` (8 log-metric + 9 policy); Toan chạy sau deploy, budget cần billing id | bắn được khi test thủ công |
| S10-06 | Runbook sự cố + rollback từng function — ✅ `15-RUNBOOK.md`; diễn tập chờ deploy | đã diễn tập 1 lần |
| S10-07 | Terms + Privacy cập nhật theo UMP — ✍️ điều khoản cần có: `19-STORE-COMPLIANCE.md` §4; **[Toan]** đăng web | duyệt xong |
| S10-08 | App Store + Play Store listing, privacy labels, Data Safety — ✍️ bảng khai sẵn `19-STORE-COMPLIANCE.md` §2–§3, listing §6; **[Toan]** điền console | nộp được |
| S10-09 | Deploy `functions:v2` lên prod (v1 vẫn sống) | |
| S10-10 | Phased release iOS 1%→10%→50%→100%, staged rollout Android | crash-free ≥99.5% mới tăng bậc |
| S10-11 | Theo dõi 7 ngày sau 100% | **M6** |
| S10-12 | Xoá `App/oneai/`, `firebase functions:delete` codebase `default` | **M7**, sớm nhất M6+30 ngày |

---

## S11 — Sau phát hành: tìm lại & ôn tập · 4 tuần sau M6

Từ `17-FEATURE-RESEARCH.md` §2.3 — lấp khoảng trống "sau vài ngày" của cả hai use case.

| ID | Task | Xong khi |
|---|---|---|
| S11-01 | **Hỏi đáp xuyên nhiều note** — **ưu tiên #1 của S11** (21-RESEARCH: đây là thứ tách leaders 2026 khỏi phần còn lại): embedding mỗi note lúc ready, Firestore vector search `findNearest`, callable `askAll` streaming, trích dẫn nhảy tới mốc audio | "tuần trước chốt gì về X" trả đúng note + trích dẫn |
| S11-02 | Tìm kiếm toàn văn dùng chính embedding trên (thay client-side) | |
| S11-03 | **Ôn tập flashcard theo lịch** (SM-2), nhắc qua push đã có — ✍️ app: `Sm2` thuần + `ReviewStore` (per device) + chế độ Review trong FlashcardsSheet (Again/Hard/Good/Easy); nhắc push + sync server để sau | |
| S11-04 | Dịch summary/transcript (`translations/{part}_{lang}`, streaming) — ✅ BE `translate`; ✍️ app `TranslationSheet` từ hàng Study tools | |
| S11-05 | **Share link chỉ đọc** (`createShareLink`/`revokeShareLink`, `shares/{token}`, trang HTML từ function `sharePage` — không cần Hosting), thu hồi được — ✅ BE; ✍️ app menu Share | người vắng họp mở được không cần app |
| S11-06 | Share Extension iOS (Voice Memos, Files) + Android intent | |
| S11-07 | Ghi âm offline, tự upload khi có mạng — ✍️ `UploadQueue`: giữ flow sống sau khi rời màn, retry khi có mạng (connectivity_plus), lưu SharedPreferences để sống qua restart, banner ở Home | |
| S11-08 | Meeting templates (standup / 1:1 / interview / lecture / brainstorm) → prompt summary theo kiểu — ✅ BE `template` + `TEMPLATE_GUIDANCE`; ✍️ app chips trong PromptLanguageSheet | |
| S11-09 | **Ghi âm chống ngắt** (21-RESEARCH §6 #2): ghi theo chunk xuống đĩa, tự tiếp tục sau cuộc gọi / mất audio session, foreground service Android + notification, khôi phục sau crash ("đã lưu N phút"), cảnh báo pin/dung lượng | tắt máy giữa chừng vẫn còn bản ghi |
| S11-10 | **Glossary "sửa một lần, nhớ mãi"**: `users/{uid}/glossary` (tên người, sản phẩm, thuật ngữ) → tự đưa vào `keywords` STT + prompt summarize; đổi tên speaker / sửa thuật ngữ đề nghị thêm vào glossary | BE S4-11 + app Settings › Glossary |
| S11-11 | **Song ngữ trong note**: toggle "transcript VI + note EN" (và ngược) dùng `translate` đã có | không thêm BE |
| S11-12 | **Consent UX**: thẻ "Đang ghi âm" chia sẻ 1 chạm (text/ảnh), badge cloud/on-device, câu "không dùng để huấn luyện" trong onboarding | |
| S11-13 | **Benchmark tiếng Việt** (Ops, sau deploy dev): WER ElevenLabs vs Gemini trên 10 file VI bắc/trung/nam lẫn thuật ngữ EN → chọn `STT_VENDOR`; công bố "độ chính xác tiếng Việt" trên listing — không đối thủ nào làm | bảng số đo trong docs |
| S11-06b | Share Extension mở rộng: nhận file từ Zalo/Drive/Files/Voice Memos; Android intent `audio/*`, `application/pdf` | |

## S12 — Backlog dài hạn (chỉ khi có tín hiệu từ user)

| ID | Task | Vì sao chưa |
|---|---|---|
| S12-01 | Live transcription khi đang ghi (streaming STT) | XL; làm S12-06 trước thì được 80% giá trị |
| S12-02 | Workspace / team + comment | XL — đổi data model |
| S12-03 | Nhận diện giọng xuyên cuộc họp | XL, privacy |
| S12-04 | Đồng bộ lịch Google/Outlook để tự ghi | L |
| S12-05 | Cắt/ghép audio trước khi upload | M |
| S12-06 | **Draft STT on-device** (Whisper-small / Gemini Nano) ngay khi ghi, offline; cloud "re-transcribe HD" là bước trả phí/rewarded — giải bài toán live + chi phí rewarded ở VN (eCPM $2–3) | L; cần đo pin/chất lượng VI on-device |
| S12-07 | **Đồng bộ slide ↔ mốc thời gian** lecture (import PDF slide + audio, căn theo trang) | L; chỉ Notability/Goodnotes có, không VI |
| S12-08 | **Connector**: xuất thẳng Notion / Google Docs; MCP server đọc note (Fathom, Plaud, Voicenotes đã có) | M–L |
| S12-09 | Memory / cá nhân hoá cách tóm tắt theo user (Plaud Memory 07/2026) | L; cần S11-10 trước |

**Không làm** (21-RESEARCH §6): phần cứng, bot vào họp online, agent tự hành động.

## Rủi ro

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Parity sót tính năng vì viết lại từ đầu | user khiếu nại sau khi ship | S9-01/02 là checklist đối chiếu bắt buộc, không phải "rà qua" |
| Riverpod 3 mới với Toan | chậm S5–S6 | `riverpod-pro` có reference; S5 cố tình nhẹ để làm quen |
| Golden test đỏ liên tục khi dựng UI | nhiễu | Chỉ viết golden khi một màn đã xong, không viết trước |
| Migration dữ liệu (OQ-01) | +2 tuần | Quyết **trước S2**; chọn "không migrate" là rẻ nhất |
| AdMob App ID đặt nhầm platform | ads im lặng không chạy | Xác nhận `~8024150974` đúng là iOS trước S8 |
| 20 tuần là dài với 1 người | trượt lịch | S2–S4 (BE) có thể ∥ S5–S7 (App) nếu có người thứ hai |
