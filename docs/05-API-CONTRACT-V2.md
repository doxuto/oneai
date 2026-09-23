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
| `updateMinute` | `{client, minuteId, title?, iconEmoji?, tagIds?, pinned?}` | `{minute: MinuteSummary}` — `pinned` chỉ là cờ; client xếp note ghim lên đầu theo `pinnedAt` mới nhất trước |
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
  pinned: boolean;
  pinnedAt: string | null;           // ISO khi ghim; null khi bỏ ghim
  createdAt: string;                 // ISO-8601
  updatedAt: string;
}

interface MinuteDetail extends MinuteSummary {
  summary: Summary | null;
  transcript: Transcript | null;
  sourcePath: string | null;         // path Storage; client tự lấy download URL bằng auth của mình
  sourceState: "none" | "available" | "expired";   // "expired": audio gốc đã bị xoá theo retention, transcript/summary còn
  sourceExpiresAt: string | null;    // khi nào audio gốc bị xoá; null = giữ vô hạn (retention -1)
  speakers: { id: string; label: string }[];
  failure: { code: string; message: string } | null;
  description: string | null;
  keywords: string[];
  summaryLanguage: string | null;
  template: string;                  // "auto" | "standup" | "one_on_one" | "interview" | "lecture" | "brainstorm"
  share: {url, includeTranscript, createdAt, views} | null;   // link chia sẻ đang sống (S11-05)
  calendarEvents: CalendarEvent[];   // rút lúc summarize; sinh lại bằng generateCalendarEvents
  availableArtifacts: ("shortQuestions"|"quiz"|"flashcards"|"mindmap"|"speakers"|"calendarEvents"|"actionItems"|"keyTerms"|"chapters")[];
                                     // artifact đã tồn tại — app hiện tab mà không cần gọi generate*
  talkTime: { speakerId, label, seconds, share: 0..1, turns }[];   // tính từ transcript, không gọi LLM; [] với PDF
}

interface CalendarEvent {
  id: string; title: string; description: string;
  datetime: string;                  // ISO-8601 khi resolve được, không thì nguyên văn
  participants: string[]; rawText: string;
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
| `startTranscription` | `{client, minuteId, requestId: uuid, audioLanguage ="auto", summaryLanguage, keywords: string[] ≤20 =[], description? ≤500, template: "auto"\|"standup"\|"one_on_one"\|"interview"\|"lecture"\|"brainstorm" ="auto", timezone: IANA, durationSeconds?, partCount? 2–300}` — **`partCount`** (S11-09): bản ghi tải lên theo chunk `source/parts/part-NNN.<ext>` (cùng ext với `upload.path`); server kiểm tra đủ mọi part (`noSource` kèm `missingPart`), tổng ≤300 MB, rồi worker ghép bằng ffmpeg (`-c copy`) thành `sourcePath`, xoá parts, `sourceParts` về null — retry/player/retention thấy một file thường. `template` chỉ đổi hướng dẫn section cho prompt summarize (S11-08), không đổi schema. **Keyterms**: `keywords` + glossary (≤60, keywords trước, bỏ trùng) được lưu vào `job.options.keyterms`, đưa vào prompt STT (Gemini) và prompt summarize ("spell these exactly"). **Quota**: đặt cọc `max(60, durationSeconds)` giây (PDF: `PDF_CHARGE_SECONDS` = 300) trong transaction; worker đo độ dài thật rồi **settle** (trả thừa / thu thêm); free vượt phần còn lại → `resource-exhausted reason:"quota"` với `{limitSeconds, usedSeconds, remainingSeconds, requestedSeconds, resetAt}` ngay lúc start, hoặc note `failed` reason `quota` trước khi tốn STT nếu file thật dài hơn khai báo | `{minuteId, status, duplicate: boolean}` — cùng `requestId` gọi lại → `duplicate:true`, không trừ quota lần 2 |
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
| `chat` ⚡streaming | `{client, minuteId, question ≤2000, languageCode ="en"}` | stream `{delta}` → `{answer, messageId}`. Lưu cả 2 lượt; 8 lượt gần nhất làm ngữ cảnh |
| `listChatMessages` | `{client, minuteId, limit ≤100 =50, cursor?}` | `{items: {id, role, text, createdAt}[], nextCursor}` |
| `generateShortQuestions` | `{client, minuteId, languageCode ="en", force =false}` | `{data: {questions: string[]}, cached: boolean}` |
| `generateQuiz` | như trên | `{data: {items: {question, options: string[2..4], answerIndex}[]}, cached}` |
| `generateFlashcards` | như trên | `{data: {items: {question, answer}[]}, cached}` |
| `generateMindmap` | như trên | `{data: {root: {id, title, icon, children: [{id, title, children: [{id, title, children: [{id,title}]}]}]}}, cached}` — sâu tối đa 4 |
| `generateCalendarEvents` | `{client, minuteId, languageCode ="en", force =false, timezone?: IANA}` | `{data: {events: CalendarEvent[]}, cached}` — `timezone` mặc định là zone đã gửi ở `startTranscription`, rồi UTC. Sự kiện đã được rút sẵn lúc summarize và nằm trong `getMinute().calendarEvents`; gọi cái này chỉ khi muốn sinh lại (đổi ngôn ngữ) |
| `generateActionItems` | như `generateCalendarEvents` (có `timezone?`) | `{data: {items: {id, text, owner\|null, due: ISO\|null, quote, done}[], decisions: string[]}, cached}` — họp: ai làm gì đến khi nào, đã chốt gì; `done` do user tick (mặc định false) |
| `listGlossary` | `{client}` | `{items: {id, term, hint\|null, createdAt}[]}` — ≤200, cũ nhất trước (S11-10) |
| `upsertGlossaryTerm` | `{client, term ≤60, hint? ≤120}` | `{term}` — id = hash(term thường/gọn) nên cùng từ khác hoa-thường là một mục; đầy (200) → `resource-exhausted reason:"glossaryFull"` |
| `deleteGlossaryTerm` | `{client, termId}` | `{}` |
| `createShareLink` | `{client, minuteId, includeTranscript =false}` | `{share: {url, includeTranscript, createdAt, views}}` — 1 link sống/note; gọi lại cùng option → trả link cũ; đổi `includeTranscript` → thu hồi token cũ, cấp token mới. Note chưa `ready` → `failed-precondition` |
| `revokeShareLink` | `{client, minuteId}` | `{}` — không có link → no-op |
| `sharePage` (HTTP GET `?t=token[&format=pdf]`) | public, không auth/App Check | HTML chỉ đọc có nút **Download PDF**; `format=pdf` trả `application/pdf` (attachment, Noto Sans nhúng — đủ dấu tiếng Việt) — **chốt 24/09: note chia sẻ là PDF**. `noindex`, `no-store`; token hỏng/thu hồi/note đã xoá → 404. Base URL = `SHARE_BASE_URL` hoặc URL cloudfunctions.net của chính function |
| `sharePage?format=json` | public | `{token, title, iconEmoji, createdAt, sourceType, summary, transcript\|null, speakers, pdfUrl}` — cho màn xem trong app khi mở deep link `/s?t=`; 404 JSON khi thu hồi |
| `importSharedNote` | `{client, token}` | `{minuteId, duplicate}` — "Lưu vào ghi chú của tôi": copy summary (+ transcript nếu chủ chia sẻ) thành note `ready` không audio trong tài khoản người gọi; **không trừ quota**; cùng token lần 2 → `duplicate:true`; chủ note → trả `minuteId` của chính họ; link thu hồi → `not-found` |
| Hosting `/s`, `/legal`, `/n/**` | `firebase.json` hosting | rewrite `/s` → `sharePage`, `/legal` → `legal`, `/n/**` → `open.html` (trang "Open in One AI" + store badge); `.well-known/apple-app-site-association` + `assetlinks.json` cho universal/app link (Toan điền TEAMID + SHA-256) |
| `legal` (HTTP GET `?doc=privacy\|terms\|delete-account&lang=en\|vi`) | public | Trang Chính sách / Điều khoản / Xoá tài khoản **EN + VI** phục vụ từ `assets/legal/*.html` (S10-07); app link theo ngôn ngữ máy; trỏ domain riêng hoặc copy HTML lên web sau |
| `askAll` | `{client, question, languageCode ='en', history: {role, text}[] ≤8 =[]}` | **streaming** như `chat`: chunk `{delta}` rồi `{answer, sources: {minuteId, title, iconEmoji, createdAt, startSeconds?}[]}` (S11-01). Server embed câu hỏi → **chunk transcript** (`minutes/{id}/chunks/{order}`: ~350 từ, `startSeconds/endSeconds`, vector; collection-group index) `findNearest` ≤12 đoạn, gom theo note, bù bằng note-level `findNearest` cho note cũ chưa có chunk, tối đa 6 note → prompt gồm title/ngày/summary + các đoạn `[t=SECONDS]`; model trích `[[note:ID]]` hoặc `[[note:ID@SECONDS]]`; `sources` chỉ gồm note thật sự được trích, theo thứ tự trích, `startSeconds` khi trích theo đoạn (app mở tab Transcript và tua tới đó). Không lưu lịch sử server; 1 AI call |
| `searchNotes` | `{client, query ≤500, limit 1–30 =20}` | `{items: {minuteId, title, iconEmoji, createdAt, score 0–1}[]}` — tìm theo nghĩa (S11-02), chỉ note `ready` có vector, khoảng cách COSINE ≤0.75; **không** tính AI call |
| `translate` | `{client, minuteId, part: "summary"\|"transcript", languageCode, force =false}` | **streaming** như `chat`: chunk `{delta}` rồi kết quả `{part, languageCode, text, cached}` — cache ở `minutes/{id}/translations/{part}_{lang}` theo hash transcript; transcript dịch theo từng khối ≤6.000 ký tự nối lại; 1 AI call/lần dù nhiều khối; chưa có summary → `failed-precondition reason:"noSummary"` |
| `setActionItemDone` | `{client, minuteId, itemId, done}` | như trên (`cached: true`) — không gọi model, không trừ quota; cờ nằm trong artifact nên đồng bộ mọi máy; `force` sinh lại sẽ **xoá tick**. Chưa sinh → `failed-precondition reason:"noActionItems"`; `itemId` lạ → `not-found` |
| `generateKeyTerms` | `{client, minuteId, languageCode ="en", force =false}` | `{data: {terms: {term, definition, quote}[]}, cached}` — glossary theo ngữ cảnh |
| `generateChapters` | như trên | `{data: {chapters: {title, startSeconds, endSeconds, summary}[]}, cached}` — chương theo chủ đề, mốc thời gian clamp về độ dài thật; PDF → `failed-precondition reason:"noTimeline"` |
| `mapSpeakers` | `{client, minuteId, force =false}` | `{data: {speakers: {id, label}[]}, cached}` — mọi `speaker_N` có mặt đúng 1 lần |
| `renameSpeaker` | `{client, minuteId, speakerId: /^speaker_\d+$/, name ≤60}` | `{data: {speakers}, cached:false}` — không gọi LLM |

Mọi tính năng AI yêu cầu minute `status:"ready"`; ngược lại `failed-precondition` + `reason:"notReady"`.
`cached:true` nghĩa là artifact có `sourceHash` khớp transcript hiện tại; transcript đổi → tự sinh lại.

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
| `getMe` | `{client}` | `{user: {id, email, displayName, photoUrl, plan, planExpiresAt, minuteCount, createdAt, notifications: {transcriptionDone}}, quota: {usedSeconds, limitSeconds, maxDurationSeconds, resetAt}}` — **hạn mức tính bằng giây audio/ngày** (chốt 24/09: free 600 = 10 phút, premium `limitSeconds: 0` = không giới hạn); không còn `rewardBonus` |
| `deleteAccount` | `{client, confirm: true}` | `{}` |

v1 dùng ba field id khác nhau từ cùng một decoded token (`user_id`, `uid`,
`email`) tuỳ file. v2 chỉ dùng `request.auth.uid`.

### 2.5b push (FCM)

| Callable | Input | Output |
|---|---|---|
| `registerDevice` | `{client, token: FCM ≤4096, locale?: BCP-47}` | `{}` — upsert `users/{uid}/devices/{sha256(token)}`; **token đang thuộc uid khác thì chuyển sang uid này** (cùng máy, đổi tài khoản) |
| `unregisterDevice` | `{client, token}` | `{}` — gọi khi sign out; idempotent |
| `updateNotificationPrefs` | `{client, transcriptionDone?: boolean, reviewReminders?: boolean}` (ít nhất một key; chỉ key gửi lên đổi) | `{notifications: {transcriptionDone, reviewReminders}}` — mặc định đều `true` |
| `syncReviewSchedule` | `{client, minuteId, timezone: IANA, cards: {[question ≤500]: {r: int, i: int, e ≥1.3, d: ISO\|null}} ≤200}` (S11-03b) | `{cardCount, dueCount, nextDueAt\|null, remindAt\|null}` — app là bộ lập lịch SM-2, gửi **cả map** sau mỗi phiên ôn (last-write-wins giữa máy); server lưu `minutes/{id}/study/review`, `remindAt` = 19:00 giờ máy đầu tiên sau `max(now, nextDueAt)`; map rỗng → xoá doc (ngừng theo dõi); note không tồn tại → `not-found` |

Server gửi push khi job kết thúc (từ pipeline hoặc reaper), **không** khi user
tự huỷ. Payload `data: {type: "minuteReady" \| "minuteFailed", minuteId}` để app
deep-link; title/body theo `locale` của thiết bị (en/vi/es, mặc định en);
`collapseKey = minute:{id}` nên nhiều push cho cùng note gộp một. Token FCM
báo chết (`registration-token-not-registered`, …) bị xoá ngay. Client **không
bao giờ** đọc/ghi `devices/` trực tiếp (rules chặn).

### 2.6 onRequest (webhook — ngoại lệ)

| Function | Auth | Ghi chú |
|---|---|---|
| `revenueCatWebhook` | `Authorization: Bearer <secret>`, so sánh **constant-time** | v1 so bằng `!==` với `undefined` khi secret chưa set → ai gửi đúng `Bearer undefined` là nâng gói bất kỳ ai. Phải verify `app_user_id` là UID thật, và dùng `set(merge:true)` thay `update()`. |
| ~~`adRewardSsv`~~ | — | **Bỏ 24/09**: không còn rewarded ad cộng phút miễn phí. Code đã xoá. |

### 2.7 triggers + jobs

| Function | Loại | Việc |
|---|---|---|
| `onUserCreated` | v1 auth trigger (đánh dấu rõ trong code) | tạo `users/{uid}` + quota ngày đầu |
| `onUserDeleted` | v1 auth trigger | xoá recursive Firestore + Storage, có retry, **không nuốt lỗi** |
| ~~`resetDailyQuota`~~ | — | **không cần**: quota là doc theo ngày + TTL |
| `onMinuteWritten` | Firestore trigger | recount `minuteCount` user + tag (aggregation, idempotent) |
| `processTranscription` | `onTaskDispatched` 2GiB/540s, retry 3, ≤10 song song | worker nặng; ghi `stt: {vendor, model}` lên note + job |
| `reapStaleJobs` | `onSchedule` mỗi 15 phút | job `running` > 30 phút hoặc `queued` > 60 phút → fail + hoàn credit + push `minuteFailed` |
| `remindReviews` | `onSchedule` mỗi giờ (phút :05, UTC) | collection-group `study` có `remindAt ≤ now` → gộp theo user, **một** push `{type: "reviewDue", minuteId?}` ("N thẻ đến hạn trong \"T\"" khi 1 note, "N thẻ trong M ghi chú" khi nhiều; theo locale máy), rồi `remindAt = null` + `remindedAt` — không nhắc lại tới khi app sync (không nag); pref `reviewReminders=false` hoặc không có device → bỏ qua nhưng vẫn clear |
| `backfillEmbeddings` | `onSchedule` 03:30 VN hằng ngày | embed note `ready` chưa có vector / hash lệch (note v1 migrate, lỗi provider, đổi `EMBEDDING_DIM`), ≤500/lần |
| `sweepOrphanFiles` | `onSchedule` 03:00 VN hằng ngày | upload bỏ dở > 24h, note kẹt > 2h (backstop), prefix Storage mồ côi, job cũ > 7 ngày |

**Trần đồng thời theo user:** `startTranscription` từ chối `resource-exhausted`
`reason:"tooManyActiveJobs"` khi user đã có ≥ `maxActiveJobs` job queued/running
(free 1, premium 3 — param `FREE_MAX_ACTIVE_JOBS`/`PREMIUM_MAX_ACTIVE_JOBS`),
kiểm tra **trước** khi trừ quota.

### 2.7b Retention file gốc (chống đầy Storage)

File âm thanh/PDF gốc là object nặng duy nhất một note sở hữu (transcript vài KB).
Khi note `ready`, server đóng dấu `sourceExpiresAt = now + retention` theo plan
(`FREE_SOURCE_RETENTION_DAYS=7`, `PREMIUM_SOURCE_RETENTION_DAYS=90`, `-1` = giữ
mãi). Bước 5 của `sweepOrphanFiles` (hằng ngày) xoá `source/` đã quá hạn và đặt
`sourceState:"expired"`, `sourcePath:null` — note, transcript, summary, artifact
**không đổi**; app ẩn player và hiện "Audio gốc đã hết hạn lưu trữ". Trước khi
xoá server đọc lại plan **hiện tại** của chủ note: user vừa lên premium được kéo
hạn theo cửa sổ 90 ngày, không mất audio theo lịch cũ. Backstop độc lập plan:
`storage.lifecycle.json` (xoá mọi source > 180 ngày, abort multipart > 2 ngày),
`deploy.sh` áp bằng `gsutil lifecycle set`. Upload bỏ dở > 24h đã bị dọn ở bước 1.

### 2.8 Speech-to-text — đổi vendor bằng config

`Services.stt` là một `SttClient { vendor, model, transcribe(req) → SttResult }`
trả về **cùng một `Transcript`** bất kể vendor. Có sẵn hai adapter:

| Vendor | File | Ghi chú |
|---|---|---|
| `elevenlabs` (Scribe) | `lib/stt/elevenlabs.ts` | mặc định; timestamp chính xác theo word, có `language_probability` |
| `gemini` | `lib/stt/gemini.ts` | audio ≤14MB gửi inline, lớn hơn qua Files API (upload → poll ACTIVE → xoá); JSON theo `responseSchema`; timestamp là ước lượng của model |

Chọn bằng param `STT_VENDOR`; `STT_FALLBACK_VENDOR` (mặc định `none`) bật
fallback **một lần** khi primary trả `unavailable`/`resource-exhausted`/`internal`
(không fallback cho `deadline-exceeded` — ngân sách worker đã cạn — hay lỗi mô tả
input như `safety`). Thêm vendor mới = 1 file adapter + 1 `case` trong
`lib/stt/index.ts`. Note ghi `stt.vendor/model` để so sánh chất lượng sau này.

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
