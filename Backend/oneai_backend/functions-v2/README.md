# functions-v2 — One AI backend (TypeScript)

Codebase `v2`. Deploy độc lập với `functions/` (v1, JavaScript, đóng băng).

```bash
firebase deploy --only functions:v2      # KHÔNG đụng function của v1
```

## Chạy local

```bash
cd Backend/oneai_backend/functions-v2
npm install
npm run lint      # eslint + tsc --noEmit
npm run test      # vitest
npm run build     # tsc -> lib/
npm run serve     # build + emulator suite
```

Hoặc để agent làm qua watcher:

```bash
cd Backend/oneai_backend && bash scripts/watch-build.sh
echo "" > .build-request
```

## Cấu trúc

```
src/
  index.ts              setGlobalOptions (câu lệnh ĐẦU TIÊN) + re-export, không gì khác
  lib/
    admin.ts            nơi DUY NHẤT gọi initializeApp()
    params.ts           defineSecret / defineString — không dùng process.env
    validate.ts         parse<T>() + gate min-version
    errors.ts           mapFirestoreError / mapProviderError / rethrow
    logging.ts          logger có tên sự kiện dạng domain.thing.event
    cursor.ts           cursor phân trang mờ
    time.ts             periodId theo giờ VN, Timestamp -> ISO-8601
  types/common.ts       ClientInfo, withClient(), primitive có giới hạn
  users/                getMe, onUserCreated, onUserDeleted
test/                   vitest
```

## Quy tắc (firebase-functions-pro)

- **Một function một file**, tên file = tên export.
- Hai dòng đầu mọi handler: kiểm `request.auth`, rồi `parse(Schema, request.data)`.
- `enforceAppCheck: true` trên mọi callable.
- Không có envelope `{success, data}` — lỗi là `HttpsError`.
- `Timestamp` không bao giờ ra wire, chỉ ISO-8601.
- Không `console.log` (eslint chặn), dùng `log.*`.
- Không bao giờ `return snap.data()` — luôn có output mapper tường minh.

## Secrets

```bash
firebase functions:secrets:set ELEVENLABS_API_KEY
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set GEMINI_API_KEY
firebase functions:secrets:set REVENUECAT_WEBHOOK_SECRET
```

Param không bí mật nằm trong `.env` (commit có chủ đích).

## Đã có — 29 function, parity đầy đủ với v1 (trừ YouTube)

| Nhóm | Function | Loại |
|---|---|---|
| users | `getMe` · `deleteAccount` · `onUserCreated` · `onUserDeleted` | callable ×2 · v1 auth trigger ×2 |
| minutes | `createMinute` · `listMinutes` · `getMinute` · `updateMinute` · `deleteMinute` · `onMinuteWritten` | callable ×5 · Firestore trigger |
| tags | `createTag` · `listTags` · `updateTag` · `deleteTag` | callable |
| transcribe | `startTranscription` · `cancelTranscription` · `processTranscription` | callable ×2 · task worker (2GiB/540s) |
| ai | `chat` (streaming) · `listChatMessages` · `generateShortQuestions` · `generateQuiz` · `generateFlashcards` · `generateMindmap` · `generateCalendarEvents` · `mapSpeakers` · `renameSpeaker` | callable |
| jobs | `sweepOrphanFiles` | schedule 03:00 VN |
| billing / ads | `revenueCatWebhook` · `adRewardSsv` | onRequest (webhook) |

Test: **154 unit** (chạy mọi nơi) + **117 integration/rules** (chạy qua `npm run test:integration` với emulator).

## Cấu trúc test

```
test/unit/           logic thuần, fake fetch cho STT/LLM — `npm test`
test/integration/    handler chống emulator thật, fake STT/LLM — `npm run test:integration`
test/rules/          firestore.rules qua web SDK — cùng lệnh trên
test/helpers/        emulator.ts (testDb, clearFirestore, waitFor), ssv.ts (ký P-256 thật)
test/fixtures/       scribe-small.json — response ElevenLabs thật thu gọn
```

Mỗi callable = `handler.ts` (hàm thuần `(caller, raw, deps)`) + wrapper `onCall`.
`Deps` mang `db`, `bucket`, `now`, giới hạn gói, và `services` (STT, LLM ×2, enqueue, đo
thời lượng, PDF) — tất cả lazy trong prod, fake trong test.

## Việc còn lại phía backend (cần Toan)

1. `firebase functions:secrets:set` ×4 (xem trên).
2. Bật **TTL policy** trên field `expiresAt` cho collection group `quota` và collection `adRewards`
   (Firestore console → TTL). Quota theo ngày và ledger SSV tự dọn nhờ đó — không có job reset.
3. Deploy: `firebase deploy --only functions:v2 -P dev`, rồi đăng ký URL `adRewardSsv` trong
   AdMob console (SSV của rewarded unit) và URL `revenueCatWebhook` trong RevenueCat.
4. Chạy `npm run test:integration` trên Mac một lần để xác nhận 105 test emulator xanh.
