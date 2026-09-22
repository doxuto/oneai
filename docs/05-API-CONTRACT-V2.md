# 05 — API contract v2 (callables)

Nguồn quy tắc: `03-SKILLS-RULESET.md` §1.4–1.6 và §4.
Nguồn nhu cầu: `02-AUDIT-APP.md` §5 (mọi thứ app đang gọi) và
`01-AUDIT-BACKEND-V1.md` §1 (mọi thứ v1 đang phục vụ).

---

## 1. Quy ước chung

### Envelope
Không có envelope. `{success, data, message}` của v1 **bị cấm** —
`envelope-and-naming.md`: *"Failure is an `HttpsError`, not a field."*

- Request luôn là **object**, kể cả khi rỗng (`{}`). Không bao giờ là scalar/array.
- Response luôn là **object**. Void = `{}`.
- **Không gửi `uid`** trong request. Server lấy từ `request.auth.uid`.
- Không có discriminator `action`/`type`. Một thao tác = một function.
- Ngày giờ: ISO-8601 có phần giây lẻ và `Z` (`"2026-09-22T08:41:12.345Z"`).
  **Không** còn `{_seconds, _nanoseconds}` — `FirestoreDateTimeConverter` ở app
  bị xoá (audit app §5.2).
- Field naming camelCase cả hai phía. Bool prefix `is`/`has`, id hậu tố `Id`,
  count hậu tố `Count`, timestamp hậu tố `At`, thời lượng hậu tố `Seconds`.
- Phân trang: **chỉ cursor mờ**. `nextCursor: string | null`. Cấm `page`,
  `hasMore`, `total` (v1 trả `total` = độ dài trang hiện tại, vô nghĩa).

### `ClientInfo` — bắt buộc trên mọi request

```ts
const ClientInfo = z.object({
  appVersion: z.string().max(20),
  build: z.number().int().min(0),
  platform: z.enum(["ios", "android"]),
});
```

`parse()` kiểm luôn min-version và ném
`failed-precondition` + `details.minVersion` khi app quá cũ. Đây là cơ chế
force-update duy nhất các skill chấp nhận (Remote Config bị từ chối rõ ràng).

### Helper bắt buộc

```ts
// src/lib/validate.ts
export function parse<T>(schema: ZodType<T>, data: unknown): T {
  const r = schema.safeParse(data);
  if (!r.success) {
    throw new HttpsError("invalid-argument", "Invalid input", {
      issues: r.error.issues.map(i => ({ path: i.path.join("."), message: i.message })),
    });
  }
  requireMinVersion((r.data as { client: ClientInfo }).client);
  return r.data;
}
```

Hai dòng đầu của **mọi** handler:

```ts
if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
const input = parse(SomeInput, request.data);
```

Mọi callable đều bật `enforceAppCheck: true`.

### Bảng lỗi

Dùng nguyên bảng ở `03-SKILLS-RULESET.md` §1.6. Ánh xạ nghiệp vụ của One AI:

| Tình huống | Code | `details` |
|---|---|---|
| zod fail | `invalid-argument` | `issues[]` |
| chưa đăng nhập / token hết hạn | `unauthenticated` | — |
| tài khoản anonymous | `permission-denied` | `reason: "anonymous"` |
| minute của người khác / không tồn tại | `not-found` | — |
| **hết credit** (thay cho HTTP 402 của v1) | `resource-exhausted` | `limit`, `resetAt` |
| audio > 30 phút ở gói free | `failed-precondition` | `reason: "durationLimit"`, `limitSeconds` |
| app quá cũ | `failed-precondition` | `minVersion` |
| tag trùng tên | `already-exists` | `field: "name"` |
| ElevenLabs / LLM 429 | `resource-exhausted` | `retryAfterSeconds` |
| ElevenLabs / LLM 5xx, timeout | `unavailable` / `deadline-exceeded` | — |
| LLM chặn vì safety | `failed-precondition` | `reason: "safety"` |
| transaction contention | `aborted` | — |

> **Lưu ý cutover:** app hiện bắt **HTTP 402** ở màn processing để bật dialog
> "Premium Required" (`02-AUDIT-APP.md` §5.4). Khi chuyển sang callable, điều
> kiện đó đổi thành `ApiFailure.quotaExceeded`. Không được bỏ sót, nếu không
> paywall im lặng biến mất.

---

## 2. Danh sách callable

Đặt tên theo `project-layout.md`: camelCase động-từ + danh-từ, một function một
file, tên file = tên export.

### 2.1 minutes

| Callable | Input | Output |
|---|---|---|
| `createMinute` | `{client, sourceType: "audio"\|"pdf", fileName, sizeBytes, contentType}` | `{minuteId, upload: {path, contentType, maxSizeBytes}}` — client upload thẳng bằng Firebase Storage SDK, rules kiểm size/type |
| `listMinutes` | `{client, limit: 1..50 =20, cursor?, tagIds?: string[] ≤10, sort: "createdAtDesc"\|"titleAsc" ="createdAtDesc"}` | `{items: MinuteSummary[], nextCursor: string\|null}` — không có `query` (OQ-07: lọc client-side) |
| `getMinute` | `{client, minuteId}` | `{minute: MinuteDetail}` |
| `updateMinute` | `{client, minuteId, title?, iconEmoji?, tagIds?}` | `{minute: MinuteSummary}` |
| `deleteMinute` | `{client, minuteId}` | `{}` |

```ts
interface MinuteSummary {
  id: string;
  title: string;
  iconEmoji: string | null;
  sourceType: "audio" | "pdf";
  contentKind: string | null;        // "lecture" | "team_meeting" | … (v1 gọi nhầm là contentType)
  status: "uploading" | "queued" | "transcribing" | "summarizing" | "ready" | "failed" | "cancelled";
  durationSeconds: number | null;    // v1 lưu chuỗi "MM:SS" — v2 dùng số
  tagIds: string[];
  createdAt: string;                 // ISO-8601
  updatedAt: string;
}

interface MinuteDetail extends MinuteSummary {
  summary: Summary | null;
  transcript: Transcript | null;
  sourcePath: string | null;         // path Storage; client tự lấy download URL bằng auth của mình
  speakers: { id: string; label: string }[];
  failure: { code: string; message: string } | null;
  description: string | null;
  keywords: string[];
  summaryLanguage: string | null;
}

interface Summary {
  title: string; text: string; icon: string | null;
  sections: { title: string; bullets: string[] }[];
}

interface Transcript {
  durationSeconds: number;
  languageCode: string | null;
  languageProbability: number | null;
  text: string;
  segments: { startSeconds: number; endSeconds: number; text: string; speakerId: string; speakerLabel: string }[];
}
```

> **Đổi so với v1:** `timeRange: "00:12 - 00:45"` (chuỗi) → `startSeconds` /
> `endSeconds` (số). Format hiển thị là việc của app. `duration: "15:00"` →
> `durationSeconds: 900`. App phải đổi `minute_mapper.dart` theo.

### 2.2 transcription

| Callable | Input | Output |
|---|---|---|
| `startTranscription` | `{client, minuteId, audioLanguage ="auto", summaryLanguage, keywords?: string[] ≤20, description? ≤500, timezone}` | `{minuteId, status}` |
| `cancelTranscription` | `{client, minuteId}` | `{}` |
| `processTranscription` | **task worker**, không phải callable | — |

`startTranscription` chạy đúng thứ tự: auth → parse → đọc minute (đúng chủ) →
`runTransaction` kiểm tra + trừ credit → `enqueue` Cloud Task → trả về ngay.
**Không** gọi STT/LLM trong callable.

Client theo dõi tiến trình bằng Firestore listener, không polling.
`GET /transcription/:taskId/status` và `/result` của v1 bị **xoá** — `/result`
là stub hardcode "Demo Meeting" (audit §1).

### 2.3 ai

| Callable | Input | Output |
|---|---|---|
| `chat` ⚡streaming | `{client, minuteId, question ≤2000, languageCode ="en"}` | stream `{delta}` → `{answer, messageId}` |
| `listChatMessages` | `{client, minuteId, limit, cursor?}` | `{items: ChatMessage[], nextCursor}` |
| `generateShortQuestions` | `{client, minuteId, languageCode}` | `{questions: string[]}` |
| `generateQuiz` | `{client, minuteId, languageCode}` | `{items: {question, options: string[], answerIndex: number}[]}` |
| `generateFlashcards` | `{client, minuteId, languageCode}` | `{items: {question, answer}[]}` |
| `generateMindmap` | `{client, minuteId, languageCode}` | `{root: MindmapNode}` |
| `mapSpeakers` | `{client, minuteId}` | `{speakers: {id, label}[]}` |
| `renameSpeaker` | `{client, minuteId, speakerId, name ≤60}` | `{speakers: {id, label}[]}` |

**Ba thứ phải sửa so với v1:**

1. `GET /:id/speakers` của v1 sinh bằng LLM và ghi Firestore khi cache miss — một
   GET có tác dụng phụ tính tiền. v2 tách: đọc là `getMinute`, sinh là
   `mapSpeakers` (POST-semantics).
2. Mọi `generate*` của v1 nuốt lỗi và **cache luôn kết quả rỗng**
   (`postMindMap.js` lưu `{title:"Untitled", children:[]}` rồi trả mãi).
   v2 **không bao giờ cache một lần sinh thất bại** — ném `unavailable`.
3. Chat của v1 không lưu gì. v2 lưu vào `users/{uid}/minutes/{id}/chat/{msgId}`,
   có `listChatMessages` để khôi phục hội thoại.

### 2.4 tags

| Callable | Input | Output |
|---|---|---|
| `createTag` | `{client, name ≤40}` | `{tag: {id, name}}` |
| `listTags` | `{client}` | `{items: {id, name, minuteCount}[]}` |
| `updateTag` | `{client, tagId, name}` | `{tag: {id, name}}` |
| `deleteTag` | `{client, tagId}` | `{affectedMinuteCount: number}` |

Trùng tên (so bằng `nameLower`) → `already-exists`.
Sửa luôn lỗi v1 nơi `PUT /tags/:id` trả `tagId` còn `GET`/`POST` trả `id`.

### 2.5 users

| Callable | Input | Output |
|---|---|---|
| `getMe` | `{client}` | `{user: {id, email, displayName, photoUrl, plan, quota: {used, limit, resetAt, rewardBonus}}}` |
| `deleteAccount` | `{client, confirm: true}` | `{}` |

v1 dùng ba field id khác nhau từ cùng một decoded token (`user_id`, `uid`,
`email`) tuỳ file. v2 chỉ dùng `request.auth.uid`.

### 2.6 onRequest (webhook — ngoại lệ)

| Function | Auth | Ghi chú |
|---|---|---|
| `revenueCatWebhook` | `Authorization: Bearer <secret>`, so sánh **constant-time** | v1 so bằng `!==` với `undefined` khi secret chưa set → ai gửi đúng `Bearer undefined` là nâng gói bất kỳ ai. Phải verify `app_user_id` là UID thật, và dùng `set(merge:true)` thay `update()`. |
| `adRewardSsv` | chữ ký ECDSA P-256 của Google | Public có chủ ý. Xem `08-ADS-FLOW.md`. |

### 2.7 triggers + jobs

| Function | Loại | Việc |
|---|---|---|
| `onUserCreated` | v1 auth trigger (đánh dấu rõ trong code) | tạo `users/{uid}` + quota ngày đầu |
| `onUserDeleted` | v1 auth trigger | xoá recursive Firestore + Storage, có retry, **không nuốt lỗi** |
| `resetDailyQuota` | `onSchedule` 00:00 Asia/Ho_Chi_Minh | reset quota; xem OQ-03 về việc có giữ reward hay không |
| `sweepOrphanFiles` | `onSchedule` hằng ngày | xoá file Storage không có minute tương ứng (v1 không có, rò rỉ vĩnh viễn) |

---

## 3. Bảng cutover — v1 endpoint → v2 callable

| App gọi (v1) | v2 | Ghi chú migration |
|---|---|---|
| `POST /tags` | `createTag` | |
| `PUT /tags/{id}` | `updateTag` | output đổi `tagId` → `tag.id` |
| `DELETE /tags/{id}` | `deleteTag` | |
| `GET /tags` | `listTags` | thêm `minuteCount` |
| `GET /minutes` | `listMinutes` | bỏ `total`; `data`→`items`; `nextPageCursor`→`nextCursor` |
| `GET /minutes/{id}` | `getMinute` | |
| `PATCH /minutes/{id}` | `updateMinute` | `iconAsset`→`iconEmoji`, `tags`→`tagIds`; bỏ `summaryText`/`transcription` (v1 cho client ghi đè tuỳ ý, không validate) |
| `DELETE /minutes/{id}` | `deleteMinute` | |
| `GET /minutes/{id}/transcription` | nằm trong `getMinute` | endpoint v1 luôn 404 (đọc field thay vì subcollection) |
| `POST /minutes/{id}/questions` | `generateShortQuestions` | `short_questions`→`questions` |
| `POST /minutes/{id}/chat` | `chat` (streaming) | thêm lưu lịch sử |
| `GET /minutes/{id}/speakers` | `getMinute().speakers` | không còn sinh ngầm |
| `PATCH /minutes/{id}/speakers/{sid}` | `renameSpeaker` | |
| `POST /transcription/transcribe` (multipart) | `createMinute` → upload trực tiếp → `startTranscription` | **3 bước thay 1** |
| `POST /transcription/youtube` | **XOÁ** | YouTube ingest đã bỏ hẳn (OQ-06, 23/09) |
| `GET /user/me` | `getMe` | |
| `POST /user/reward` | **XOÁ** | thay bằng AdMob SSV |
| `POST /v1/summary/pdf` | `createMinute(sourceType:"pdf")` → `startTranscription` | v1 hỏng: prompt thay `${text}` nhưng file dùng `${transcript}`, nên PDF chưa từng tóm tắt đúng |
| `POST /v1/youtube/mp3` | **XOÁ** | endpoint debug, không trừ credit, mint URL tải của bên thứ ba |
| `GET /transcription/:taskId/status` | **XOÁ** | thay bằng Firestore listener |
| `GET /transcription/:taskId/result` | **XOÁ** | stub hardcode |

---

## 4. Phía Dart

```dart
// lib/data/functions/oneai_functions.dart
final _fns = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

Future<ListMinutesResponse> listMinutes(ListMinutesRequest req) async {
  try {
    final res = await _fns.httpsCallable('listMinutes').call<Map<String, dynamic>>(req.toJson());
    return ListMinutesResponse.fromJson(res.data);
  } on FirebaseFunctionsException catch (e) {
    throw ApiFailure.fromFunctions(e);
  }
}
```

Quy tắc bắt buộc (từ `flutter-firebase-contract`):
- `call<Map<String, dynamic>>` — **không** `call<T>()` với T là model (unchecked cast).
- Số đọc qua `(json['x'] as num).toDouble()`, không cast thẳng `as double`.
- Mảng `(json['xs'] as List).map(...).toList()`, không `cast<String>()`.
- Enum đọc khoan dung: giá trị lạ → nhánh `unknown`, không ném.
- `bật strict-casts` trong `analysis_options.yaml` để những chỗ này thành lỗi biên dịch.

`ApiFailure` là sealed class, một file duy nhất:

```dart
sealed class ApiFailure implements Exception { }
final class AuthFailure      extends ApiFailure {}   // unauthenticated
final class PermissionFailure extends ApiFailure {}  // permission-denied
final class NotFoundFailure  extends ApiFailure {}
final class ValidationFailure extends ApiFailure { final List<Issue> issues; }
final class QuotaFailure     extends ApiFailure { final DateTime? resetAt; }   // ← paywall
final class PreconditionFailure extends ApiFailure { final String? reason; final String? minVersion; }
final class ConflictFailure  extends ApiFailure {}
final class TransientFailure extends ApiFailure {}   // unavailable / deadline-exceeded → retry
final class ServerFailure    extends ApiFailure {}   // internal
final class NetworkFailure   extends ApiFailure {}   // chỉ từ pre-flight connectivity
```

`isRetryable` chỉ đúng với `TransientFailure`, `ServerFailure`, `ConflictFailure`.
Không bao giờ retry một call không idempotent mà thiếu `requestId`.
