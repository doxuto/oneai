# 04 — Kiến trúc v2

> Quyết định đã chốt với Toan (2026-09-22, bản 2):
> **Cả hai phía build lại từ đầu** trong thư mục mới song song; chỉ mang config sang.
> **BE:** TypeScript + Cloud Functions v2 `onCall` + zod → `functions-v2/`.
> **App:** Flutter + **Riverpod 3** → `App/oneai_v2/`. Giữ nguyên design và flow.
> **Phạm vi:** parity đầy đủ trước khi ship.

---

## ADR-001 — Backend v2 là codebase riêng, không sửa v1

**Bối cảnh.** `functions/` hiện tại (JS + Express, 5193 dòng) **không load được**:
`services/ai.service.js` dùng cú pháp ESM trong một package CommonJS, nên mọi
`require()` ném `SyntaxError` ở module scope, và vì `index.js` require toàn bộ
route eagerly, **cả function `api` chết khi khởi tạo** (chi tiết: `01-AUDIT-BACKEND-V1.md` §6).
Đây chính là hiện tượng "deploy lên chết api".

**Quyết định.** Không vá v1. Tạo codebase thứ hai `functions-v2/` (TypeScript),
khai báo trong `firebase.json` với `codebase: "v2"`. Hai codebase deploy độc lập:

```jsonc
"functions": [
  { "source": "functions",    "codebase": "default", "runtime": "nodejs20" },  // v1 — đóng băng
  { "source": "functions-v2", "codebase": "v2",      "runtime": "nodejs22" }   // v2 — nơi viết mới
]
```

`firebase deploy --only functions:v2` không đụng tới function của v1.

**Hệ quả.**
- v1 ở trạng thái "read-only tham chiếu": chỉ được `node --check`, không sửa logic.
- App cutover từng nhóm endpoint, có thể rollback bằng một feature flag.
- Chi phí: hai bộ dependency cùng tồn tại tới khi v1 bị xoá (Sprint 9).

**Phương án đã loại.** Vá `ai.service.js` rồi refactor tại chỗ — vẫn kẹt trong
JS + Express, không dựng được zod-as-source-of-truth, và mọi lỗi trong §6 của
audit vẫn còn nguyên.

---

## ADR-002 — Transport là `onCall`, không phải REST

`firebase-functions-pro/references/callable.md` nói thẳng: *"A callable is the
default way the app talks to the server. Use `onRequest` only for webhooks and
third-party integrations."*

Cái `onCall` cho không mà REST phải tự làm:

| | `onCall` | Express REST hiện tại |
|---|---|---|
| Gắn ID token | tự động | interceptor thủ công, `currentUser!` → crash khi hết session |
| App Check | `enforceAppCheck: true` | tự verify header, hiện **không có** |
| CORS | tự xử lý | `cors({origin:true})` — mở cho mọi origin |
| Lỗi | `HttpsError` → `FirebaseFunctionsException` → sealed `ApiFailure` | `{success:false, message}` — chuỗi tiếng Anh, client parse bằng tay |
| Stream AI | `acceptsStreaming` + `sendChunk` | phải tự cài SSE |
| Cost cap | `maxInstances` từng function | 1 function cho cả API |

**Ngoại lệ dùng `onRequest`:** RevenueCat webhook và AdMob SSV callback — cả
hai do bên thứ ba gọi, không có Firebase credential.

---

## ADR-003 — Pipeline transcribe chuyển sang bất đồng bộ

v1 làm **đồng bộ**: một HTTP request ôm cả upload 200MB + ElevenLabs STT + LLM
summarize, trong function cấu hình **512MiB / 240s** (`index.js:46`), trong khi
axios timeout tới ElevenLabs là 300s và 600s. Nghĩa là function bị kill trước
khi client kịp timeout → 504, đã trả tiền STT, không ghi được gì.

**v2:**

```
App                       Cloud Functions                 Storage / Firestore
 │
 ├─ createMinute() ───────► tạo minute {status:"uploading"}
 │  ◄── {minuteId, uploadUrl}
 │
 ├─ PUT audio ────────────────────────────────────────────► gs://.../audio/...
 │     (resumable, client upload trực tiếp — không qua function)
 │
 ├─ startTranscription() ─► validate + trừ credit trong TRANSACTION
 │                          enqueue Cloud Task
 │  ◄── {minuteId}
 │
 │                          processTranscription (onTaskDispatched,
 │                            2GiB / 540s / retry 3)
 │                            → ElevenLabs STT
 │                            → convert sections
 │                            → LLM summarize
 │                            → ghi minute {status:"ready"} ──►
 │
 └─ snapshots() listener ◄──────────────────────────────── realtime update
```

Client **không polling nữa** — nó listen `users/{uid}/minutes/{minuteId}` qua
`withConverter`. Màn `AudioProcessingScreen` bỏ thanh tiến trình giả (5 bước
`0.001/50ms`, xem `02-AUDIT-APP.md` §8.6) và hiển thị `status` thật.

**Trạng thái minute:** `uploading → queued → transcribing → summarizing → ready`
và hai nhánh cuối `failed`, `cancelled`.

---

## ADR-004 — Một mô hình dữ liệu duy nhất: `users/{uid}/...`

v1 có **hai** mô hình đối chọi (audit §2): top-level `minutes`/`tags` có field
`uid` (trong `utils/firestore.js`, chết nhưng vẫn còn) và subcollection
`users/{uid}/minutes` + `tags/{uid}/tagItems` (đường chạy thật).

v2 chọn **subcollection dưới `users/{uid}`** cho mọi thứ user sở hữu. Lý do:
quyền sở hữu nằm trong *đường dẫn*, nên một callable không thể vô tình với sang
dữ liệu người khác — đúng quy tắc của `callable.md`: *"path includes uid →
cannot reach another user's note"*. `tags/{uid}/tagItems` gộp về
`users/{uid}/tags/{tagId}`. Chi tiết: `06-DATA-MODEL-V2.md`.

---

## ADR-005 — Credit trừ trong transaction, cộng chỉ qua SSV

v1 có 4 lỗi tiền (audit §6):
1. TOCTOU — `checkUserCanUseCredit` và `consumeUserCredit` cách nhau cả pipeline;
   N request song song đều qua cửa với `credit: 1`.
2. Trừ **sau khi** đã trả tiền ElevenLabs + OpenAI.
3. `postReward.js` cộng credit bằng read-modify-write, không `FieldValue.increment`.
4. Client tự gọi `POST /user/reward` sau khi xem ad — **không có xác thực gì**.

v2:
- Trừ credit **trong một `runTransaction`** ngay tại `startTranscription`, trước
  khi enqueue task. Hết credit → `HttpsError("resource-exhausted")` kèm
  `details.resetAt`.
- Task thất bại vĩnh viễn → hoàn credit trong transaction đối ứng.
- **Không còn endpoint client-credits-itself.** Reward chỉ đến từ AdMob SSV
  callback có chữ ký ECDSA P-256 (xem `08-ADS-FLOW.md`).

---

## ADR-006 — App dựng lại sạch, nhưng design thì chép nguyên si

Bản build lại **không đổi UI**. Những thứ bị đóng băng, chép nguyên si sang v2:

- Toàn bộ color scheme, typography, dimens, theme extension (`07-APP-UI-FLOW-SPEC.md` §1).
- Cây route và transition (`07` §2).
- Bố cục và luồng từng màn (`07` §3).

Cái được phép đổi: toàn bộ cách tổ chức code bên dưới — state management, tầng
data, model. Nói cách khác: **pixel giữ nguyên, code viết mới hết.**

Chốt chặn là `App/oneai_v2/test/unit/design_tokens_test.dart` — nó khẳng định
từng mã màu, từng cỡ chữ, từng bán kính khớp đúng §1 của `07`. Token trôi một
giá trị là test đỏ.

Riêng **dark theme hiện không bao giờ được áp dụng** — `main.dart` truyền
`theme: lightTheme` cứng, bỏ qua `ThemeBloc` (audit app §1.8, §8.1). Đây là bug
nhưng sửa nó **sẽ đổi giao diện**, nên nằm trong `11-OPEN-QUESTIONS.md` chờ
Toan quyết, không tự sửa.

---

## Sơ đồ tổng thể v2

```
┌─────────────────────────── Flutter app (iOS + Android) ────────────────────────────┐
│  ui/features/*        BLoC + go_router (giữ nguyên)                                │
│  domain/              models + use_cases                                            │
│  data/                                                                              │
│    ├─ OneAiFunctions       cloud_functions callables  ──┐                          │
│    ├─ MinuteStreamSource   Firestore snapshots()        │                          │
│    ├─ UploadSource         firebase_storage resumable   │                          │
│    └─ AdsGate + AdLedger   thuần, test được             │                          │
└──────────────────────────────────────────────────────────┼─────────────────────────┘
                                                           │ App Check + ID token
┌──────────────────────────────────────────────────────────▼─────────────────────────┐
│ functions-v2/  (TypeScript, Node 22, asia-southeast1)                              │
│                                                                                     │
│  minutes/    createMinute listMinutes getMinute updateMinute deleteMinute           │
│  transcribe/ startTranscription  processTranscription(task)  cancelTranscription    │
│  ai/         chat(stream) generateQuiz generateFlashcards generateMindmap           │
│              generateShortQuestions mapSpeakers renameSpeaker                       │
│  tags/       createTag listTags updateTag deleteTag                                 │
│  users/      getMe  onUserCreated  onUserDeleted                                    │
│  billing/    revenueCatWebhook(onRequest)                                           │
│  ads/        adRewardSsv(onRequest, public, ECDSA)                                  │
│  jobs/       resetDailyQuota(onSchedule)  sweepOrphanFiles(onSchedule)              │
│  lib/        admin.ts errors.ts validate.ts logging.ts llm/ storage/                │
└─────────────────────────────────────────────────────────────────────────────────────┘
        │                    │                      │                    │
    Firestore            Storage              ElevenLabs STT        OpenAI / Gemini
```

## Runtime options (theo `firebase-functions-pro/references/runtime-options.md`)

`setGlobalOptions` trong `src/index.ts`, là **câu lệnh đầu tiên**:

```ts
setGlobalOptions({
  region: "asia-southeast1",   // gần VN, cùng region với Firestore
  maxInstances: 20,            // cost cap chính
  memory: "512MiB",
  timeoutSeconds: 60,
});
```

Ghi đè theo từng function:

| Function | memory | timeout | maxInstances | Ghi chú |
|---|---|---|---|---|
| `processTranscription` | 2GiB | 540s | 10 | task worker, retry 3 |
| `chat` | 512MiB | 120s | 20 | streaming |
| `generate*` | 512MiB | 120s | 10 | |
| CRUD (minutes, tags, users) | 256MiB | 30s | 20 | |
| `adRewardSsv` | 256MiB | 30s | 10 | public, ECDSA là lớp auth |
| `revenueCatWebhook` | 256MiB | 30s | 10 | shared-secret + verify uid |

**Region của `adRewardSsv`:** skill AdMob hard-code `us-central1`, các skill
Firebase bắt `asia-southeast1`. Chọn `asia-southeast1` để cùng chỗ với Firestore
(nó chạy transaction), rồi đăng ký lại callback URL trong AdMob console.


---

## ADR-007 — App viết lại bằng Riverpod 3, không migrate BLoC

**Bối cảnh.** Quyết định ban đầu là giữ `flutter_bloc` vì chi phí migrate. Khi
đã chuyển sang dựng lại từ đầu, chi phí đó biến mất — không có gì để migrate.
Và `flutter-skill/riverpod-pro` là skill duy nhất trong repo có reference cho
state management; chọn BLoC nghĩa là agent phải tự suy luận ở mọi quyết định.

**Quyết định.** `flutter_riverpod` 3 + `riverpod_annotation` 4 + codegen.
`AsyncNotifier` cho state có I/O, `Notifier` cho state thuần, `AsyncValue` cho
loading/error, `ProviderContainer.test()` trong test. `riverpod_lint` +
`custom_lint` bật.

**Hệ quả.**
- `flutter_bloc`, `bloc`, `provider` biến mất khỏi `pubspec.yaml`.
- Navigation vẫn là go_router — nó không đụng tới state management.
- Test dùng `ProviderContainer.test()` + override, không cần `bloc_test`.
- Layering từ `riverpod-pro/architecture.md`: feature-first, mũi tên một chiều,
  Firebase type không bao giờ leo lên trên tầng `data`.

**Phương án đã loại.** Giữ BLoC — mất reference của skill, và vẫn phải viết lại
toàn bộ view model nên không tiết kiệm được gì.

---

## ADR-008 — Monorepo một repo, thư mục v2 song song với legacy

`App/oneai_v2/` và `Backend/oneai_backend/functions-v2/` nằm cạnh bản cũ.

**Vì sao không ghi đè:** trong suốt S1–S6 cần mở hai file cạnh nhau để đối chiếu
hành vi — nhất là khi chép design token và dựng lại từng màn. Git history vẫn
tra được, nhưng "mở song song hai cửa sổ" thì không.

**Vì sao không tạo repo mới:** phải set up lại CI, secrets, quyền truy cập, và
mất luôn lịch sử chung của hai nửa.

**Hệ quả.** Cả bốn nửa nằm trong **một repo duy nhất** — `doxuto/oneai`,
branch `main` (Toan gộp ngày 23/09).

| Thư mục | Vai trò | Deploy |
|---|---|---|
| `App/oneai/` | legacy, chỉ đọc | — |
| `App/oneai_v2/` | app đang viết | store |
| `Backend/oneai_backend/functions/` | legacy, đóng băng | codebase `default` |
| `Backend/oneai_backend/functions-v2/` | backend đang viết | codebase `v2` |
| `docs/` · `.claude/skills/` | tài liệu + ruleset | — |

Trước 23/09 mỗi nửa là một repo riêng (`doxutostudio/oneai`,
`doxutostudio/oneai_backend`, và `doxutostudio/oneai_v2` mới tạo). Lịch sử của
ba repo đó nằm ở `_legacy-git/` — **đổi tên chứ không xoá**, khôi phục bằng một
lệnh `mv` (xem `_legacy-git/README.md`).

**Vì sao monorepo hợp ở đây:** contract giữa app và backend đổi cùng nhau, nên
một commit sửa được cả hai nửa và CI kiểm được cả hai; `docs/` và
`.claude/skills/` phục vụ cả hai; và trong suốt S2–S7 cần mở legacy cạnh v2 để
đối chiếu hành vi.

**Cái mất:** `git log` trộn hai nửa (lọc bằng `-- App/` hoặc `-- Backend/`), và
watcher phải giới hạn `git add` vào thư mục của mình — đã làm trong
`scripts/watch-git.sh`.

Dọn ở S10-12: xoá `App/oneai/` sau khi v2 lên store và ổn định 7 ngày;
`functions/` gỡ bằng `firebase functions:delete` codebase `default`, sớm nhất
30 ngày sau phát hành khi >95% user đã lên bản mới. Cả hai thành một commit
sạch vì chúng đã được repo root theo dõi.
