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
| [!] | S1-08..09 | App nối auth + gọi getMe | `App/oneai_v2/lib/features/auth/` | chặn bởi `flutter create` |
| [x] | S1-11 | GitHub Actions: backend (lint/unit/build → emulator integration → v1 syntax) + app (analyze/test) | `.github/workflows/*.yml` | badge xanh khi push |
| [ ] | S1-10 | Deploy v2 lên dev | — | **Toan chạy** `firebase deploy --only functions:v2 -P dev` |

## S2 — BE: data model + CRUD

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [x] | S2-00 | Refactor `getMe` sang handler/wrapper + unit test | `users/handler.ts`, `users/getMe.ts`, `test/unit/users.test.ts` | handler test không cần Firestore cho nhánh lỗi |
| [x] | S2-01 | `createMinute` | `minutes/types.ts`, `minutes/_shared.ts`, `minutes/handler.ts`, `minutes/createMinute.ts` | trả `minuteId` + upload path; doc `status:"uploading"`; `sourceType` ∈ audio\|pdf; `sizeBytes` ≤ 300MB |
| [x] | S2-02 | `listMinutes` | `minutes/listMinutes.ts` + handler | cursor `[createdAtMillis, id]`; `tagIds` ≤10; sort enum; **thiếu index → ném `failed-precondition`, không trả rỗng** |
| [x] | S2-03 | `getMinute` | `minutes/getMinute.ts` | minute người khác → `not-found`; kèm `summary`, `transcriptPreview`, `speakers`, `artifacts` có sẵn |
| [x] | S2-04 | `updateMinute` | `minutes/updateMinute.ts` | chỉ `title`\|`iconEmoji`\|`tagIds`; `tagIds` phải tồn tại dưới `users/{uid}/tags`; rỗng → `invalid-argument` |
| [x] | S2-05 | `deleteMinute` | `minutes/deleteMinute.ts` | `recursiveDelete` + `deleteFiles(prefix)`; idempotent (xoá 2 lần → lần 2 `not-found`) |
| [x] | S2-06 | Tags CRUD | `tags/types.ts`, `tags/handler.ts`, `tags/{create,list,update,delete}Tag.ts` | `nameLower` unique → `already-exists`; delete gỡ `tagIds` khỏi minutes bằng batch ≤500 |
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
| [x] | S4-06 | `calendarEvents` validate | `ai/_calendar.ts` | zod, không spread body |
| [x] | S4-07 | Cost: token cap + log + **trần AI call/ngày theo user** | adapter, `quota/aiCalls.ts` | `tokenCount` trong log mọi call; maxOutputTokens từng loại; transcript trim 120k ký tự |
| [x] | S4-08 | Prompts gộp + test | `src/prompts/*.txt`, `test/unit/prompts.test.ts` | 7 prompt, mỗi cái ≥1 test placeholder |

## S5–S7 — App (chặn bởi `flutter create` + watcher)

Viết trước trong lúc chờ, **chưa compile** — lần `.build-request` đầu tiên sẽ dọn lỗi cú pháp nếu có:

| | ID | Task | File | Nghiệm thu |
|---|---|---|---|---|
| [~] | S5-04a | Models mirror contract TS: minute, tag, user, ai, transcribe | `lib/data/models/*.dart` | dùng `json_read`, enum khoan dung, `fromFirestore` cho Timestamp |
| [~] | S5-04b | Repositories: minutes (snapshots + callable), transcription (upload resumable + start/cancel), tags, user (watchQuota), ai (chat stream sealed event) | `lib/data/repositories/*.dart` | client không bao giờ ghi Firestore |
| [~] | — | `FunctionsClient.stream` map `ChunkResponse`/`ResultResponse` | `lib/data/firebase/functions_client.dart` | |
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
| [~] | S8-06 | Dart `AdGate` + `AdLedger` + `AdsConfig` | `App/oneai_v2/lib/features/ads/` | 27 test viết sẵn — **chưa compile** (chờ Flutter) |

---

## Việc chỉ Toan làm được (chặn automation)

| # | Việc | Mở khoá |
|---|---|---|
| T1 | `cd App/oneai_v2 && flutter create --platforms=ios,android --org top.doxutostudio --project-name one_ai . && flutter pub get` | toàn bộ S5–S8 phía App |
| T2 | Mở 4 tab watcher (`12-AGENT-WORKFLOW.md`) | build/test App; integration test BE |
| T3 | `firebase functions:secrets:set` ×4 | deploy dev |
| T4 | Tạo project `oneai-dev`, `oneai-staging` | deploy dev/staging |
| T5 | Bật App Check monitor trong console | S1-07 |
| T6 | Chốt OQ-01, OQ-02 | S3-00 dùng mặc định tạm nếu chưa chốt |
| T7 | Revoke SOCKS proxy credential ở nhà cung cấp | bảo mật |
