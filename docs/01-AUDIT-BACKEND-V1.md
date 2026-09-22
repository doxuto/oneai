# OneAI Firebase Backend — v1 Audit (for v2 rewrite)

> **Nguồn:** sinh tự động từ việc đọc toàn bộ source ngày 2026-09-22. Audit Backend v1 (JS + Express) — cơ sở duy nhất cho bản viết lại v2
> Đây là tài liệu *mô tả hiện trạng* — không sửa code theo nó, chỉ dùng làm input cho v2.

**Repo root:** `$HOME/mnt/oneai/Backend/oneai_backend`
**Firebase project:** `minutesai-6715a` (`.firebaserc`)
**Runtime:** Node 20, `firebase-functions` v6 (v2 API), Express 5, CommonJS.

**Deployed function exports** (`functions/index.js:46-50`): `api` (onRequest), `createUserProfile`, `updateLastLogin`, `deleteUserData`, `runDailyJobs`. Nothing else is exported.

**Routing chain:** `index.js` → `app.use("/webhooks", revenuecatWebhook)` → `app.use("/", authMiddleware, apiRouter)` → `api/index.js` mounts `/v1` → `api/v1/index.js` mounts `/minutes`, `/transcription`, `/tags`, `/user`, `/youtube`, `/summary`. **Real paths are `/v1/...`, not `/api/v1/...` as `api.yaml` claims.**

---

## 1. HTTP API inventory

`successResponse` envelope is `{ success: true, data, message }` (HTTP 200 default). `errorResponse(message)` returns `{ success: false, message }` — it is a *value*, not a sender; several handlers misuse it (see §6).

Auth: `authMiddleware` (`middlewares/auth.js`) requires `Authorization: Bearer <FirebaseIdToken>`, calls `admin.auth().verifyIdToken`, sets `req.user` = decoded token. It is applied **globally** at `index.js:41` **and again** on every sub-router — every request verifies the token twice.

### Minutes — `api/v1/minutes/index.js`

| Method + path | File | Auth | Request | Response `data` | Codes | Side effects |
|---|---|---|---|---|---|---|
| `GET /v1/minutes` | `getMinutes.js` | yes | query: `limit` (int, default 10), `sort` (str `field:order`, default `createdAt:desc`), `tags` (CSV str), `search` (str), `startDate`, `endDate` (date str), `startAfterDocId` (str) | `{ total: number, data: Minute[], nextPageCursor: string\|null }` | 200, 400 (no `req.user.email`), 500 | Firestore read `users/{uid}/minutes` |
| `GET /v1/minutes/:id` | `getMinuteById.js` | yes | — | full minute doc `{ id, ...docFields, summary?, transcription?, shortQuestions?, speakers? }` | 200, 400, 404, 500 | Firestore reads + GCS JSON download of `transcriptionUri` / `summaryUri` |
| `PATCH /v1/minutes/:id` | `updateMinute.js` | yes | body: `title` (str), `iconAsset` (str), `tags` (array), `summaryText` (str), `transcription` (any) — **no validation** | `{ minuteId, ...updatedFields, updatedAt }` | 200, 400 (no valid fields), 404, 500 | Firestore `set(merge)`; reads `tags/{uid}/tagItems` to filter tag IDs |
| `DELETE /v1/minutes/:id` | `deleteMinute.js` | yes | — | `{}` | 200, **400 returned via `successResponse`**, 404, 500 | `db.recursiveDelete` of minute + subcollections; `bucket.deleteFiles({prefix: user_uploads/{uid}/{minuteId}/})` |
| `GET /v1/minutes/:id/transcription` | `getTranscriptByMinuteId.js` | yes | — | `{ transcription }` | 200, 400, 404, 500 | Read only — reads **field** `metadata.transcription`, not the subcollection |
| `POST /v1/minutes/:id/flashcards` | `postFlashcards.js` | yes | body: `languageCode` (str, default `"en"`) | `{ flashcards: [{question, answer}] }` | 200, 400, 500; **hangs** on missing transcript | Firestore write `metadata/flashcards`; OpenAI call |
| `POST /v1/minutes/:id/quiz` | `postQuiz.js` | yes | body: `languageCode` | `{ quiz: [{question, options?, answer}] }` | 200, 400; **hangs** | Firestore write `metadata/quiz`; OpenAI call |
| `POST /v1/minutes/:id/questions` | `postShortQuestions.js` | yes | body: `languageCode` | `{ short_questions: string[] }` | 200, 400; **hangs** | Firestore write `metadata/shortQuestions`; OpenAI call |
| `POST /v1/minutes/:id/mindmap` | `postMindMap.js` | yes | body: `languageCode` | `{ mindmap: {id,title,icon,children[]}, generatedAt }` | 200, 400; **hangs** | Firestore write `metadata/mindmap`; OpenAI call |
| `POST /v1/minutes/:id/chat` | `chat.js` | yes | body: `question` (str, **required**), `languageCode` (str, default `"en-US"`) | `{ question, answer, minuteId }` | 200, 400, 500; **hangs** if no transcript | OpenAI call. **Persists nothing** — no chat history |
| `GET /v1/minutes/:id/speakers` | `getSpeakers.js` | yes | — | `{ speakers: {speaker_0: "Name", ...} }` | 200, 400, 404, 500 | **Generates on cache miss**: OpenAI call + write `metadata/speakers`. A GET with billing side effects |
| `POST /v1/minutes/:id/speakers` | `mapSpeakers.js` | yes | — | `{ speakers }` | 200, 400; **hangs** | OpenAI call + write `metadata/speakers` (+ `generatedAt`) |
| `PATCH /v1/minutes/:id/speakers/:speakerId` | `updateSpeakerName.js` | yes | body: `newName` (str, non-empty) | full speakers map | 200, 400, 500 | `set({[speakerId]: newName}, {merge:true})` — **upserts, no existence check** |
| `GET /v1/minutes/:id/calendar-events` | `getCalendarEvents.js` | yes | — | `{ calendarEvents: [{id,title,description,datetime,participants,rawText}] }` | 200, 400, 404, 500 | Read only |
| `PATCH /v1/minutes/:id/calendar-events/:eventId` | `updateCalendarEvents.js` | yes | body: **arbitrary object**, spread into the event | `{ calendarEvents }` | 200, 400, 404, 500 | Read-modify-write of the whole array + `updatedAt` |

Note: no credit is consumed by any of the AI generation endpoints above — only the ingest endpoints charge.

### Transcription — `api/v1/transcription/index.js`

| Method + path | File | Auth | Request | Response `data` | Codes | Side effects |
|---|---|---|---|---|---|---|
| `POST /v1/transcription/transcribe` | `transcribe.js` | yes | multipart (busboy): `file` (binary audio, ≤200MB); fields (all **strings**): `audioLanguage` (default `"auto-detect"`), `summaryLanguage`, `keywords`, `description`, `timezone` (default `"GMT -7"`) | `{ minuteId, transcription, keywords, description }` | 200, 401, **402** (no credit), **403** (free + >1800s), 500 | ElevenLabs STT; GCS audio upload; GCS transcription JSON upload; Firestore `upsertMinute`; `consumeUserCredit` |
| `POST /v1/transcription/youtube` | `transcribeYoutube.js` | yes | body: `youtubeUrl` (str, required), `audioLanguage`, `summaryLanguage`, `keywords`, `description`, `timezone` | `{ minuteId, transcription }` | 200, 402, 500 | y2mate/d.mnuu.nu via SOCKS proxy; MP3 download (≤5 retries); ElevenLabs STT; GCS JSON upload; `upsertMinute`; `consumeUserCredit`. **Audio is not uploaded to GCS** (`gcsUri: null`) |
| `POST /v1/transcription/file` | `transcribeFile.js` | yes | multipart: `file` (ElevenLabs JSON, ≤100MB); fields: `summaryLanguage`, `keywords`, `description`, `timezone` | `{ minuteId, transcription, keywords, description }` | 200, 400, 401, 402, 500 | Summarize; GCS JSON upload; `upsertMinute`; `consumeUserCredit`. **No duration cap** |
| `GET /v1/transcription/:taskId/status` | `getStatus.js` | yes | — | `{ status, operationId, lastCheckedAt, minuteId, resultsGcsUri }` | 200, 400, **403** (ownership), 404, 500 | Reads `speechJobs/{taskId}`. The only endpoint with an **explicit** ownership check |
| `GET /v1/transcription/:taskId/result` | `getResult.js` | yes | — | **hardcoded stub**: `{title:"Demo Meeting", date, duration:"15:00", transcript:{messages:[]}, meetingMinute:{...sections:[]}}` | 200 | None. Ignores `taskId`, no ownership check |

### Tags — `api/v1/tags/index.js`

| Method + path | File | Auth | Request | Response `data` | Codes | Side effects |
|---|---|---|---|---|---|---|
| `GET /v1/tags` | `getTags.js` → `tag.service.getAll` | yes | — | `{ tags: [{id, name, name_lower}] }` | 200, 400, 500 | Read `tags/{uid}/tagItems` |
| `POST /v1/tags` | `createTag.js` | yes | body: `name` (str, required) | `{ id, name }` | 200, 400, **409** (duplicate `name_lower`), 500 | Write `tags/{uid}/tagItems/{autoId}` = `{name, name_lower}` |
| `PUT /v1/tags/:id` | `updateTag.js` | yes | body: `name` (str, required) | `{ tagId, name }` | 200, 400, 409, 404, 500 | Update `{name, name_lower}` |
| `DELETE /v1/tags/:id` | `deleteTag.js` | yes | — | `{ tagId, affectedMinutes }` **then a second `res.json`** | 200, 400, 404, 500 | Delete tag doc; batch-update every minute containing the tag |

### User — `api/v1/user/index.js`

| Method + path | File | Auth | Request | Response `data` | Codes | Side effects |
|---|---|---|---|---|---|---|
| `GET /v1/user/me` | `getMe.js` | yes | — | `{ user: <users/{uid} doc> }` | 200, 401, 404, 500 | Read only. **Exports a Router, not a handler** — mounted as `router.get("/me", <router>)`; reads `req.user?.uid` while every minutes endpoint reads `req.user?.user_id` |
| `POST /v1/user/reward` | `postReward.js` | yes | body: `rewardAmount` (number, `>0` and `≤1_000_000`) | `{ credit: newCredit }` | 200, 401, 404, 500; **invalid input → 500** | `userRef.update({credit: current + rewardAmount})` — **read-modify-write, not atomic** |

### YouTube / Summary / Webhook

| Method + path | File | Auth | Request | Response | Codes | Side effects |
|---|---|---|---|---|---|---|
| `POST /v1/youtube/mp3` | `youtubeToMp3.js` | yes | body: `youtubeUrl` (str) | `{ success: true, downloadURL: {success, data:{downloadURL}} }` — **nested object, not a URL** | 200, 400, 500 | y2mate/d.mnuu.nu via SOCKS proxy |
| `POST /v1/summary/pdf` | `summary/pdf.js` | yes | multipart: `file` (PDF, ≤20MB, **type not enforced**); fields `summaryLanguage` (default `"en-US"`), `keywords`, `description`, `timezone` | `{ minuteId, summary, keywords, description }` | 200, 400, 401, 402, 500 | `pdf-parse`; LLM summarize; GCS PDF upload; `upsertMinute` (`sourceType:"pdf"`); `consumeUserCredit` |
| `POST /webhooks/revenuecat-webhook` | `webhooks/revenuecatWebhook.js` | **no Firebase auth** — static `Bearer ${REVENUECAT_WEBHOOK_SECRET}` | body: `{ event: { type, app_user_id, expiration_at_ms } }` | `{ success, message }` | 200, **403**, 400, 500 | `users/{app_user_id}.update({plan})` |

---

## 2. Firestore data model

### Collections actually written

**`users/{uid}`** — document ID is the Firebase Auth UID.

| Field | Type | Written at |
|---|---|---|
| `uid` | string | `triggers/user.js:10` |
| `email` | string\|null | `triggers/user.js:11` |
| `displayName` | string\|null | `triggers/user.js:12` |
| `photoURL` | string\|null | `triggers/user.js:13` |
| `createdAt` | JS `Date` | `triggers/user.js:14` |
| `role` | string `'user'` | `triggers/user.js:15` |
| `plan` | string `'free'` \| `'premium'` | `triggers/user.js:16`; `revenuecatWebhook.js:49,53,56` |
| `credit` | number (init `1`) | `triggers/user.js:17`; `postReward.js:52`; `checkAndConsumeUserCredit.js:114`; `resetDailyFreeCredit.js:20` |
| `lastLoginAt` | server Timestamp | `triggers/user.js:79` |
| `dailyCreditUsed` | number (increment) | `checkAndConsumeUserCredit.js:106`; reset at `resetDailyFreeCredit.js:21` |
| `totalCreditUsed` | number (increment) | `checkAndConsumeUserCredit.js:107` |
| `lastCreditReset` | `Timestamp` | `resetDailyFreeCredit.js:22` |

**`users/{uid}/minutes/{minuteId}`** — minuteId is a client-invisible `uuidv4()` generated server-side.

Written by `upsertMinute` (`services/minutes.service.js:37-114`), payload assembled at `transcribe.js:173-186`, `transcribeFile.js:103-122`, `transcribeYoutube.js:200-213`, `summary/pdf.js:99-118`:
`title` (string), `minuteId` (string), `gcsUri` (string\|null), `iconAsset` (string — an **emoji** from the LLM), `contentType` (string — the LLM `type` enum), `sourceType` (`"audio"`\|`"youtube"`\|`"pdf"`), `duration` (string `"MM:SS"`\|null), `transcriptionUri` (string — **but an object for PDFs**, see §6), `keywords` (string), `descriptionAudio` (string), `summaryLanguage` (string), `createdAt` (`Date`), `updatedAt` (`Date`).

Added by `updateMinute` (`minutes.service.js:334-350`): `tags` (string[] of tagItem IDs), `summaryText` (string), `transcription` (any), `updatedAt` (`Date`).

Added by `addMinutes` (`minutes.service.js:128-135`, **unrouted**): `timestamp` (string), `createdAt` as an **ISO string** rather than a `Date` — conflicts with the `Date` written elsewhere and with `orderBy("createdAt")`.

Added by `speech.service.js:215-226` (unreachable, see §6): `transcript` (string), `transcription` (raw STT JSON), `summaryText`, `completedAt`.

**`users/{uid}/minutes/{minuteId}/metadata/{docId}`** — fixed doc IDs:

| docId | Shape | Written at |
|---|---|---|
| `transcription` | `{ duration, sections: [{timeRange, title, speaker, speaker_id}], transcript, language_code, language_probability }` | `minutes.service.js:62` |
| `summary` | LLM summary minus nested blocks: `{ type, title, summaryText, sections:[{title, bullets[]}], icon }` | `minutes.service.js:78` |
| `speakers` | `{ speaker_0: "Name", ... }` (+ `generatedAt` in `mapSpeakers.js:60`) | `minutes.service.js:83`; `mapSpeakers.js:58`; `getSpeakers.js:64`; `updateSpeakerName.js:43` |
| `calendarEvents` | `{ calendarEvents: [{id,title,description,datetime,participants,rawText}], updatedAt? }` | `minutes.service.js:89`; `updateCalendarEvents.js:51` |
| `quiz` | `{ quiz: [{question, options?, answer}], generatedAt: ISO string }` | `minutes.service.js:95`; `postQuiz.js:89` |
| `flashcards` | `{ flashcards: [{question, answer}], generatedAt: ISO string }` | `minutes.service.js:101`; `postFlashcards.js:93` |
| `mindmap` | `{ mindmap: {id,title,icon,children[]}, generatedAt: ISO string }` | `minutes.service.js:107`; `postMindMap.js:67` |
| `shortQuestions` | `{ short_questions: string[], generatedAt: ISO string }` | `postShortQuestions.js:65` |

**`speechJobs/{operationId}`** (`services/speech.service.js:45-58`): `userId`, `minuteId`, `keywords`, `description`, `audioLanguage`, `summaryLanguage`, `gcsUri`, `gcOutputFolder`, `operationId` (string), `status` (`"IN_PROGRESS"`\|`"COMPLETED"`\|`"FAILED"`), `createdAt` (`Date`), `lastCheckedAt` (`Date`); updated at `:114-118` with `status`, `resultsGcsUri`, `completedAt`. **Read by `getStatus.js:25` but nothing writes it in the live code path.**

**`tags/{uid}/tagItems/{tagId}`** (`services/tag.service.js:43-46`): `name` (string), `name_lower` (string, lowercased with whitespace → `_`).

### Path inconsistencies — confirmed

1. **`minutes` vs `users/{uid}/minutes`** — confirmed.
   - Top-level `minutes` with a `uid` field: `functions/utils/firestore.js:7`, `:13`, `:23`, `:29`, `:36`, `:56`, `:61`.
   - Subcollection `users/{uid}/minutes`: `services/minutes.service.js:49-50`, `:137`, `:206-207`, `:324`, `:367-368`, `:405`, `:445-447`; `services/tag.service.js:172`; `services/speech.service.js:213-214`; `triggers/user.js:29`; and every minutes endpoint.
   - `utils/firestore.js` is required by **nothing** — it is the abandoned original model, but it still encodes a different ownership scheme (`where("uid","==",uid)` + a per-doc ownership check at `:24`) versus the path-scoped scheme used everywhere else.

2. **`tags` vs `tags/{uid}/tagItems`** — confirmed.
   - Top-level `tags` with a `uid` field: `functions/utils/firestore.js:41`, `:46`, `:51`.
   - `tags/{uid}/tagItems`: `services/tag.service.js:25-27`, `:38-40`, `:76-78`, `:91-93`, `:127-129`, `:157-159`; `services/minutes.service.js:314`; `triggers/user.js:37`, `:42`.

3. **Chat history** — `utils/firestore.js:56` and `:61` define `minutes/{id}/chat` with `{message, senderType, timestamp}`. `api/v1/minutes/chat.js` persists nothing at all, and there is no `GET .../chat` route. `api.yaml:172-191` documents both. Three mutually inconsistent stories.

4. **Transcription: field vs subcollection.** `getTranscriptByMinuteId.js:25` reads `docSnap.get('metadata.transcription')` — a **nested field on the minute document**. Every writer (`minutes.service.js:62`) writes a **subcollection document** `metadata/transcription`. This endpoint returns 404 for every minute created by the live pipeline.

5. **`users` by document ID vs by email query.** `services/user.service.js:13-18` queries `users` by `email` and, on miss, `.add()`s a new doc with an **auto-generated ID** — colliding with the UID-keyed model of `triggers/user.js:9`. (File is unreferenced, but it is the only place `getUserByEmail` exists, and `getMinutes.js:25-28` still hard-requires `req.user.email` to be present.)

6. **Minute-level `transcription` / `summaryText` fields** (`minutes.service.js:336-337`, `speech.service.js:219-220`) duplicate `metadata/transcription` and `metadata/summary`. `getMinuteById` reads the metadata docs and the GCS URIs but not these fields, so a client PATCH to `transcription` is write-only and invisible.

---

## 3. Cloud Storage layout

Bucket: `minutesai-6715a.firebasestorage.app` (`config/config-firebase.js:13`), accessed with an explicit `keyFilename: './service-account.json'` rather than ADC.

| Prefix | Contents | Written at |
|---|---|---|
| `user_uploads/{userId}/{minuteId}/audio/{Date.now()}-{uuid}` | Raw uploaded audio (only for `POST /transcription/transcribe`) | `upload.service.js:19` |
| `user_uploads/{userId}/{minuteId}/transcription/transcription.json` | Raw ElevenLabs STT response | `upload.service.js:60` (`type: 'transcription'`) |
| `user_uploads/{userId}/{minuteId}/summary/{fileName}.json` | Summary JSON — **the calls are commented out** at `transcribe.js:164-170` and `transcribeYoutube.js:191-197`; `minutes.service.js:285` still reads a `summaryUri` field that is therefore never set |
| `user_uploads/{userId}/{minuteId}/json/{fileName}.json` | Fallback when `type` is neither of the above | `upload.service.js:59` |
| `user_uploads/{userId}/{minuteId}/pdf/{Date.now()}-{fileName}` | Raw uploaded PDF | `upload.service.js:111` |
| `gs://minutesai-6715a.firebasestorage.app/user_uploads/{userId}/{minuteId}/transcription` | Google STT v2 `gcsOutputConfig` target | `speech.service.js:19` (unreachable) |

Every upload sets `metadata.metadata.firebaseStorageDownloadTokens = uuidv4()`, which mints a **rules-bypassing public download URL**. The token is generated and then discarded — never returned to the client, never stored. It is pure unused attack surface.

**Cleanup:** two paths only.
- `deleteMinuteFiles` (`minutes.service.js:15-22`) — `bucket.deleteFiles({prefix: user_uploads/{userId}/{minuteId}/})`, invoked by `deleteMinute`.
- `deleteUserData` (`triggers/user.js:51-59`) — lists and deletes `user_uploads/{userId}` on Auth user deletion.

There is **no TTL, lifecycle rule, or orphan sweep.** Any minute whose Firestore write fails after a successful upload leaves the audio in the bucket forever. YouTube and PDF minutes store `gcsUri: null` on the doc, so the only link between a minute and its bytes is the path convention.

**`storage.rules`** (3 rules, 12 lines):
```
match /user_uploads/{uid}/{allPaths=**}  → read if request.auth.uid == uid; write: false
match /{allPaths=**}                     → read, write: false
```
No client writes at all; every write goes through the Admin SDK, which bypasses rules entirely. There is no `request.resource.size` or `contentType` constraint anywhere, because no client write is permitted — meaning **all size/type enforcement lives in application code**, and most of it is missing or disabled (§6).

---

## 4. External dependencies

| Service | Called from | Env vars / secrets | Purpose |
|---|---|---|---|
| **ElevenLabs Speech-to-Text** (`https://api.elevenlabs.io/v1/speech-to-text`) | `api/v1/transcription/transcribe.js:114`, `transcribeYoutube.js:167` | `ELEVENLABS_API_KEY` | Primary transcription. `model_id=scribe_v1`, `diarize=true`, `tag_audio_events=true`, optional `language_code` (ISO-639-3, mapped from a 90-entry table duplicated in both files) |
| **OpenAI** | `utils/llm/openai.js:7,26` | `OPENAI_API_KEY`, `OPENAI_MODEL` (default `gpt-4o-mini`) | All LLM generation. `ai.service.js:50,196` hardcodes `gpt-4o` for summarization and speaker mapping |
| **Google Gemini** | `utils/llm/gemini.js:7,21` | `GEMINI_API_KEY`, `GEMINI_MODEL` (default `gemini-1.5-pro`) | Alternative provider, selectable via `LLM_VENDOR` |
| **Grok** | `utils/llm/grok.js:9,25` | `GROK_API_KEY`, `GROK_MODEL` (default `grok-1.0`) | Alternative provider. **Instantiated with the OpenAI SDK and no `baseURL` override** — it would send the Grok key to `api.openai.com` |
| **Provider selection** | `utils/llm/index.js:12` | `LLM_VENDOR` (default `openai`) | — |
| **Google Cloud Speech-to-Text v2** | `services/speech.service.js:7-9,41,68` | `./service-account.json` | Legacy async batch pipeline. Recognizer `projects/minutesai-6715a/locations/global/recognizers/my-global-recognizer`. **Unreachable in the deployed build** |
| **Google Cloud Storage** | `config/config-firebase.js:12` | `./service-account.json` | Audio/JSON/PDF storage |
| **Firebase Admin (Auth + Firestore)** | throughout | ADC | Token verification, all data |
| **RevenueCat** (inbound webhook) | `webhooks/revenuecatWebhook.js:5,28` | `REVENUECAT_WEBHOOK_SECRET` | Subscription state → `plan` field |
| **y2mate.nu + d.mnuu.nu** | `utils/youtube_to_mp3.js:92,156,162,175`; `utils/authDetector.js:74` | `PROXY` (SOCKS5) | YouTube → MP3. `authDetector.js` runs **scraped remote JavaScript through Node's `vm` module** (`:33,70,85,120`) to reverse three generations of the site's obfuscated auth-key scheme |
| **ytdl-core + ffmpeg-static** | `utils/youtubeUtils.js:1,6,25` | — | Dead alternative YouTube path (`child_process.exec` to ffmpeg) |
| **pdf-parse** | `api/v1/summary/pdf.js:4,55` | — | PDF text extraction |
| **music-metadata** | `utils/getAudioDuration.js:2,11` | — | Duration from an in-memory audio buffer, for the free-plan 30-minute cap |

**Complete list of `process.env` reads:** `GROK_API_KEY`, `GROK_MODEL`, `GEMINI_API_KEY`, `GEMINI_MODEL`, `LLM_VENDOR`, `OPENAI_API_KEY`, `OPENAI_MODEL`, `PROXY`, `ELEVENLABS_API_KEY`, `REVENUECAT_WEBHOOK_SECRET`.

**Keys present in `functions/.env`** (names only): `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `PROXY`, `REVENUECAT_WEBHOOK_SECRET`, `GEMINI_API_KEY`, `LLM_VENDOR`, `GROK_API_KEY`. Note `GEMINI_MODEL`, `GROK_MODEL`, `OPENAI_MODEL` are read but not defined — the code defaults apply.

Declared-but-unused npm dependencies: `multer`, `youtube-dl-exec`, `fluent-ffmpeg`, `cheerio` (used), `@distube/ytdl-core` (the dead file imports plain `ytdl-core`), `express-validator` (only by the unused `custom-validate.js`), `firebase-functions-test` (a **test** package in production `dependencies`), and `busy` (see §6).

---

## 5. Business logic worth preserving

### 5.1 Transcription pipeline (the live path)

The deployed pipeline is **fully synchronous** — one HTTP request does everything and returns the finished result. The `speechJobs` / poll / status machinery described by `api.yaml` is vestigial.

`POST /v1/transcription/transcribe`:
1. **Parse multipart** via busboy into an in-memory `Buffer` (`utils/uploadAudio.js`), max 200MB. Fields land on `req.body` as strings; the file on `req.file = {fieldname, originalname, encoding, mimetype, buffer}`.
2. **Credit check** — `checkUserCanUseCredit(userId)`. Fail → `402`.
3. **Duration gate** — `getAudioDurationFromBuffer` (music-metadata). If `plan === 'free'` and `duration > 1800s` → `403`. Premium is uncapped.
4. **Language mapping** — `audioLanguage` (e.g. `"en-US"`) → base code → ISO-639-3 (`"eng"`) via the 90-entry table. Unmapped → omit `language_code`, let ElevenLabs auto-detect.
5. **ElevenLabs STT** — multipart POST with `scribe_v1`, diarization and audio-event tagging on.
6. **Upload raw audio** to `user_uploads/{uid}/{minuteId}/audio/...`; keep the `gs://` URI.
7. **Convert** the word-level response into speaker-turn sections (`utils/convertTranscript.js`): walk `data.words`, filter `type === "word"`, start a new section on every `speaker_id` change, emit `{timeRange: "MM:SS - MM:SS", title: <joined words>, speaker: "Speaker N" (1-based), speaker_id: "speaker_N" (0-based)}`. Total `duration` comes from the last word's `end`. Also carries through `transcript` (full text), `language_code`, `language_probability`.
8. **Summarize** — `summarizeFromTranscript(transcript, summaryLanguage, description, timezone)` → JSON string → `JSON.parse`. Yields `{type, title, summaryText, sections, icon, calendarEvents}`.
9. **Upload transcription JSON** to GCS.
10. **`upsertMinute`** — fan the result out: base doc + `metadata/transcription` + `metadata/summary` (with `speakers`/`calendarEvents`/`quiz`/`flashcards`/`mindmap` destructured out and written to their own metadata docs).
11. **`consumeUserCredit`** — *after* all the work.
12. Return the full structured transcription inline.

`POST /v1/transcription/youtube` is the same from step 5, prefixed by: resolve a download URL through y2mate (up to 60 convert attempts at 1s, then up to 10 progress polls at 3s), then download the MP3 as an `arraybuffer` with up to 5 retries at a 20s timeout each. **No audio is retained** (`gcsUri: null`).

`POST /v1/transcription/file` skips STT entirely — the client supplies a previously-obtained ElevenLabs JSON, which is converted and summarized. This is the "re-summarize without re-paying ElevenLabs" path. It charges a credit and has **no duration cap**.

`POST /v1/summary/pdf` swaps STT for `pdf-parse` and `summarizeFromText`, storing `sourceType: "pdf"` with `duration: null` and no transcription sections.

### 5.2 Credit / quota system

Three fields on `users/{uid}`: `credit` (balance), `dailyCreditUsed` (today's count), `totalCreditUsed` (lifetime).

- **Signup** (`triggers/user.js:16-17`): `plan: 'free'`, `credit: 1`.
- **Gate** — `checkUserCanUseCredit` (`utils/checkAndConsumeUserCredit.js:53-83`): premium → always allowed, no counters consulted. Free → if `dailyCreditUsed >= 3` return `{allowed:false, reason:"daily_limit_exceeded"}`; else `allowed = credit > 0`.
- **Charge** — `consumeUserCredit` (`:93-129`): always `dailyCreditUsed += 1` and `totalCreditUsed += 1`; additionally `credit -= 1` for non-premium. Throws `"Insufficient credit."` if a free user has no credit at charge time.
- **Nightly reset** — `runDailyJobs` (`scheduled/runDailyJobs.js`) at cron `0 0 * * *` UTC, 300s / 256MiB, runs `resetDailyFreeCredit`: query `users where plan == "free"`, then batched (500/batch) `{credit: 1, dailyCreditUsed: 0, lastCreditReset: Timestamp.now()}`.
- **Reward flow** — `POST /v1/user/reward` with `rewardAmount` (0 < n ≤ 1,000,000), read-modify-write onto `credit`. This is the AdMob-rewarded-video hook.
- **Plan capability difference** beyond credits: only the 30-minute audio cap (`transcribe.js:47`), and only on that one endpoint.

Net effective free-tier behaviour: **1 transcription per day** (`credit` is hard-set to `1`, not incremented), despite a daily limit constant of `3`. Rewarded credits are **erased at midnight UTC** by the same hard-set.

### 5.3 RevenueCat webhook

Mounted **before** `authMiddleware` (`index.js:36`) so it is reachable unauthenticated; guarded only by an exact string compare of the `authorization` header against `Bearer ${REVENUECAT_WEBHOOK_SECRET}`. No HMAC, no timestamp, no replay protection.

- `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`, `SUBSCRIPTION_EXTENDED` → `plan: "premium"`.
- `CANCELLATION`, `EXPIRATION`, `REFUND` → if `expiration_at_ms > Date.now()` keep `"premium"` (grace through the paid period), else `"free"`.
- Any other event type → logged, no write.
- `app_user_id` is trusted verbatim as the Firestore document ID / Firebase UID.
- Always `200` on success; `400` if `app_user_id` is missing; `403` on bad secret; `500` on any throw.

### 5.4 Scheduled jobs

Only **one** is deployed: `runDailyJobs` (above). `triggers/speechScheduler.js` defines `scheduledCheckJobs` (an `onRequest` intended for Cloud Scheduler that calls `checkPendingSpeechJobs`) but it is **not exported from `index.js`**, so nothing ever polls `speechJobs`.

Auth triggers (v1 API, unlike everything else):
- `createUserProfile` — `auth.user().onCreate` → seed the profile doc.
- `updateLastLogin` — `beforeUserSignedIn` (v2 identity blocking function) → `set({lastLoginAt}, {merge:true})`. Note a blocking function runs on the sign-in critical path and its return value is interpreted by Identity Platform; it returns `{success:true}`.
- `deleteUserData` — `auth.user().onDelete` → delete `users/{uid}/minutes` docs, the user doc, all `tags/{uid}/tagItems`, the `tags/{uid}` doc, and all `user_uploads/{uid}` objects. **Does not recurse into `minutes/{id}/metadata`**, orphaning every metadata subcollection.

### 5.5 YouTube-to-audio flow

`utils/youtube_to_mp3.js` + `utils/authDetector.js`. All traffic goes through a SOCKS5 proxy (`PROXY`, with a hardcoded credentialed fallback) and `rejectUnauthorized = false`.

1. `extractVideoId` — regex `(?:v=|youtu\.be\/|embed\/)([\w-]{11})`.
2. `generateAuthorization` — GET `https://y2mate.nu/` with a spoofed Safari UA, then `getAuthorizationInfo(html, agent)`.
3. `authDetector` tries three strategies in order: **new inline** (inline `var gC` + `Object.defineProperty`, no `/auth/*.js` present), **legacy inline** (inline `gC` containing `LVy`), **legacy external** (inline `gC` plus a fetched `/auth/*.js` whose `eval(atob('...'))` payload is executed to recover `sH`, `sK`, `sP`). Each runs the site's script in a `vm` context, then reconstructs the key: decode a binary index string, base64-decode a secret (optionally reversed per a flag), index into it with an offset, truncate, apply a casing flag (0/1/2), and base64 the result joined to a hex-decoded salt. Returns `{authorizationKey, paramKey, headerKey?, headerVal?}`.
4. GET `https://d.mnuu.nu/api/v1/init?{paramKey}={authorizationKey}&_={random}` → `convertURL`.
5. GET `{convertURL}&v={videoId}&f=mp3&_={random}`, retried up to 60× at 1s, handling three outcomes: immediate `downloadURL`; `redirect === 1` + `redirectURL`; or a `progressURL` to poll.
6. `pollProgress` — up to 10 attempts at 3s until `downloadURL` appears or a non-zero `error` is returned.

This is scraping against an actively hostile, obfuscated third party. It is the single most fragile component in the system and **will** break without warning; §7 flags the decision.

### 5.6 AI generation features

Provider abstraction: `BaseProvider.generate({prompt, temperature, model})` (`utils/llm/base.js`), implemented by OpenAI / Gemini / Grok, selected by `getProvider(providerId ?? LLM_VENDOR ?? "openai")`. Prompts live as `.txt` templates in `utils/prompts/` and are filled by naive `String.replace` of `${placeholder}` tokens (single-occurrence replacement only). All outputs pass through `stripCodeFence` (strip ```` ```json ```` / ```` ``` ````).

| Feature | Function | Prompt file | Temp | Output shape |
|---|---|---|---|---|
| Summary from transcript | `summarizeFromTranscript` | `summarizeFromTranscript.txt` | 0.6, forced `gpt-4o` | `{type, title, summaryText, sections:[{title,bullets[]}], icon, calendarEvents[]}` |
| Summary from text (PDF) | `summarizeFromText` | **also loads `summarizeFromTranscript.txt`** | 0.6, `gpt-4o` | same |
| Chat answer | `answerQuestionFromSummary` | `answerFromSummary.txt` | 0.5 | plain text; must reply exactly `"I'm not sure based on the transcription."` when unsupported |
| Short questions | `generateShortQuestions` | `shortQuestions.txt` | 0.4 | `{short_questions: string[]}` (5 items) |
| Flashcards | `generateFlashcards` | `flashcards.txt` | 0.5 | `{flashcards:[{question,answer}]}` (5–10) |
| Quiz | `generateQuiz` | `quiz.txt` | 0.5 | `{quiz:[{question, options?, answer}]}` (5–10; MCQ / true-false / short answer) |
| Mind map | `generateMindMap` | `mindmap.txt` | 0.4 | `{mindmap:{id,title,icon,children[]}}`, every node has `children` (`[]` for leaves), unique short IDs, 2–4 levels |
| Speaker mapping | `mapSpeakers` | `mapSpeakers.txt` | default, forced `gpt-4o` | `{speaker_0:"Name", speaker_1:"speaker_1", ...}` |

**Prompt purposes and output contracts** (worth porting verbatim — the rules are hard-won):

- **`summarizeFromTranscript.txt` / `summarizeFromText.txt`** (near-identical; differ only in the `${transcript}` vs `${text}` input token and minor wording). Classify into one of `interview | podcast | team_meeting | lecture | presentation | webinar | casual_talk | other`. Produce a title, a narrative `summaryText`, one `section` per input transcript segment (explicitly *no* merging or splitting), bullets using `•` / `◦` two-level markers sized to the actual content, a leading localized "Overview" section whose single bullet is the full `summaryText`, one emoji `icon`, and `calendarEvents` with relative times resolved to absolute ISO-8601 against `${now}` / `${timezone}`. Extensive corner-case handling: short transcripts collapse to one section; ≥80% noise → `"title": "No meaningful content"` with empty bullets; greeting-only sections → empty bullets; lists preserved one item per bullet; multilingual input translated to `${summaryLanguage}` with proper nouns preserved; pseudo-hierarchy (a bullet with exactly one sub-bullet) merged. Type-aware bullet emphasis: `team_meeting` → action items/decisions/follow-ups, `lecture`/`presentation` → key points/definitions/examples, `interview` → questions and notable answers. Strict JSON, exact field order, no code fences.
- **`summarizeFromTranscriptFull.txt`** — a **superset** producing `mindmap`, `quiz` (0–5) and `flashcards` (0–5) in the *same* call as the summary, with slightly different section rules (up to three bullet levels, generic titles forbidden). **Never loaded by any code**, yet `upsertMinute:67-109` is built precisely to destructure and store those nested blocks. This is the abandoned one-pass design.
- **`mapSpeakers.txt`** — four numbered anti-hallucination rules with worked examples distinguishing *speaker* from *listener* ("Thanks, Brian" → the current speaker is Brian; "Okay, Cindy" → Cindy is the listener). Every speaker ID must appear in the output; unmappable IDs map to themselves.
- **`answerFromSummary.txt`** — answer plainly, no "Based on the transcript" preamble, exact fallback string when unsupported.
- **`shortQuestions.txt`, `flashcards.txt`, `quiz.txt`, `mindmap.txt`** — as tabulated above; each insists on raw JSON with no markdown fences.

**Caching behaviour worth preserving:** each of flashcards / quiz / questions / mindmap / speakers checks its `metadata/{doc}` first and returns the cached value without an LLM call. Summary and transcription are produced eagerly at ingest; the rest are lazy and generated on first request.

---

## 6. Defects, risks and tech debt

### Secrets

`git -C <repo> check-ignore -v functions/.env functions/service-account.json` returns:
```
.gitignore:7:functions/.env               functions/.env
.gitignore:17:functions/service-account.json  functions/service-account.json
```
and `git ls-files` returns nothing for both. **Both files are ignored and untracked — not committed.** `functions/service-account.json` is a real GCP service-account key (contains `type`, `project_id`, `private_key_id`, `client_email`, `client_id`, `auth_uri`, `token_uri`). No values are reproduced here.

However:
- **`firebase.json:8-14`'s `ignore` list does not exclude `.env` or `service-account.json`**, so both are packaged into the deployed function bundle. A private key is shipped to a runtime that already has Application Default Credentials and does not need it. `config-firebase.js:12` and `speech.service.js:8` load it by the **CWD-relative** path `./service-account.json`, which is also fragile.
- **A credentialed SOCKS5 proxy URL (`socks5h://user:pass@host:port`) is hardcoded as the `PROXY` fallback at `utils/youtube_to_mp3.js:88` and `:129`** — this *is* committed to the repo. Rotate it.
- `firestore-debug.log`, `.DS_Store` (three copies) and `.idea/` are present in the working tree.

### Fatal — the deployed `api` function cannot load

**`services/ai.service.js` uses ESM syntax (`import`/`export`) in a CommonJS package.** `functions/package.json` has no `"type": "module"`, `main` is `index.js`, and the file extension is `.js`. It is the only such file in the codebase (verified by grep). Every `require("../../../services/ai.service")` throws `SyntaxError: Cannot use import statement outside a module` at load time. Because `index.js` → `api` → `v1` → the route indexes `require()` these handlers eagerly at module scope, **the entire `api` function fails to initialize.** This must be the first thing the rewrite addresses; it also means nothing downstream of it has ever run in this state.

`ai.service.js:8` compounds it: `path.resolve("utils","prompts")` is **CWD-relative**, not `__dirname`-relative. Prompt loading will fail in the Cloud Functions runtime regardless.

### Correctness

- **`ai.service.js:78`** — `summarizeFromText` loads `summarizeFromTranscript.txt`, whose input token is `${transcript}`, then replaces `${text}`. The document text is **never substituted**; the model receives a prompt containing the literal string `'${transcript}'`. **PDF summarization is silently broken.**
- **`transcribeYoutube.js:126`** — `getAudioDurationFromBuffer(req.file.buffer)` on a JSON route where `req.file` is `undefined`. `TypeError` → caught by the outer handler → every YouTube transcription returns 500 *after* the MP3 has been downloaded.
- **`transcribeYoutube.js:40`** — calls `unauthorizedResponse(res)`, which is **not imported** (line 7 imports only `successResponse`, `errorResponse`) → `ReferenceError`.
- **`transcribeYoutube.js:36`** — `return errorResponse(res, "...")` returns a plain object and **sends nothing**. The request hangs until the platform timeout.
- **Same `errorResponse(res, msg)` misuse** (signature is `errorResponse(message)`) at `chat.js:63`, `postFlashcards.js:78,108`, `postQuiz.js:78,101`, `postShortQuestions.js:55,74`, `postMindMap.js:60,80`, `mapSpeakers.js:51,71`. Every one is a hung request that burns the full function timeout.
- **`postReward.js:33`** — `badRequestResponse` is destructured from `responseHelper` but **that helper does not exist**; invalid input produces a `TypeError` → 500 instead of 400.
- **`deleteTag.js:3-4`** — `await tagService.deleteTag(req,res)` already sent the response, then `res.json({success:true})` → `ERR_HTTP_HEADERS_SENT`.
- **`summary/pdf.js:84`** — assigns `transcriptionUri` from `uploadPDFToFolder`, which returns **`{_minuteId, gcsUri}`**, while `uploadJsonToFolder` returns a bare `gs://` **string**. The PDF minute stores an object where every reader expects a string; `readJsonFromGcsUri` (`minutes.service.js:5`) then calls `.split` on an object and fails into its swallowing catch.
- **`youtubeToMp3.js:10-11`** — `downloadURL` is set to the whole `{success, data:{downloadURL}}` wrapper, not the URL.
- **`getResult.js`** — a hardcoded demo stub still routed at `GET /v1/transcription/:taskId/result`.
- **`getTranscriptByMinuteId.js:25`** — reads `metadata.transcription` as a document field; the writer creates a subcollection doc. Always 404s.
- **`getMe.js`** — exports an Express `Router` with its own `.get("/me")`, mounted via `router.get("/me", <router>)`. Every other handler exports `(req,res)`. It also reads `req.user?.uid` while the minutes endpoints read `req.user?.user_id`, and `getMinutes.js:25` hard-fails on a missing `req.user.email` — three different identity fields across the same decoded token.
- **`convertTranscript.js:83,88`** — `speakerId.match()` assumes a string; a numeric `speaker_id` from ElevenLabs would throw.
- **`minutes.service.js:404,440`** — `sort.split(":")` is passed straight to `orderBy(field, order)` with no whitelist. `getMinutes.js:8` defaults to `createdAt:desc`, but a client-supplied field combined with the `tags`/`search`/date filters requires composite indexes that are not declared anywhere (no `firestore.indexes.json` exists).
- **`minutes.service.js:426-428`** — the "search" is a prefix range on `title`, which Firestore requires to be the first `orderBy`; combined with the default `orderBy("createdAt")` it will throw.

### Auth / ownership

- **`webhooks/revenuecatWebhook.js:28`** — if `REVENUECAT_WEBHOOK_SECRET` is unset, `SECRET` is `undefined` and the comparison becomes `authHeader !== "Bearer undefined"`; an attacker sending exactly `Bearer undefined` passes. Combined with `app_user_id` being trusted as the UID, that is **arbitrary plan escalation for any account**. There is no signature verification and no replay protection even when the secret is set.
- **`revenuecatWebhook.js:49,53,56`** — `userRef.update()` throws `NOT_FOUND` if the document is absent (RevenueCat anonymous IDs, or a purchase before `createUserProfile` lands) → 500 → RevenueCat retries indefinitely. Should be `set(..., {merge:true})` and should validate that `app_user_id` is a real Firebase UID.
- **`updateSpeakerName.js:43`** — `set(..., {merge:true})` on `users/{uid}/minutes/{arbitraryId}/metadata/speakers` with no check that the minute exists. Any authenticated user can write unbounded orphan documents under their own tree, using a **client-controlled `speakerId` as the Firestore field name** with no whitelist.
- **`updateCalendarEvents.js:48`** — `{...events[index], ...updates}` spreads the **entire request body** into the stored event; a client can overwrite `id` or inject arbitrary keys.
- **`updateMinute`** (`minutes.service.js:336-337`) — accepts arbitrary `summaryText` and `transcription` values with no type, schema or size validation and writes them straight to Firestore.
- **`getResult.js`** — no ownership check (it returns static data, so no leak today, but the shape invites one).
- `middlewares/custom-validate.js` defines `addMinutesValidation` and is **used by nothing**; `express-validator` is a dependency purely for this dead file. There is no input validation layer anywhere in the live code.
- `uploadPDF.js:19-22` — the PDF content-type check is commented out. `uploadAudio.js` has no type check at all.

### Credits — non-atomic and mis-ordered

- **TOCTOU:** `checkUserCanUseCredit` and `consumeUserCredit` are separate reads/writes separated by an entire STT + LLM pipeline (`transcribe.js:30` → `:188`; `transcribeFile.js:32` → `:124`; `transcribeYoutube.js:47` → `:215`; `pdf.js:33` → `:120`). N concurrent requests from one user all pass the gate on `credit: 1`. There is no transaction.
- **Charged last:** the credit is consumed *after* ElevenLabs and OpenAI have been paid. A crash anywhere in between means the vendor bill was incurred for free. Conversely `consumeUserCredit` throws `"Insufficient credit."` at `:117` if the balance hit zero meanwhile — in `transcribe.js` that throw lands in the outer catch and returns **500 to a user whose minute was already saved successfully**.
- **`consumeUserCredit` re-reads** the user doc (`:95`) purely to branch on `plan` and to log, then issues increments — two round-trips where one conditional transaction would do.
- **`postReward.js:46-52`** — classic read-modify-write on `credit` with no `FieldValue.increment`. Two concurrent rewarded-ad callbacks lose one. This is the *one* place a user can add credits, so it is the one place that most needs atomicity.
- **`checkAndConsumeUserCredit`** (`:10-45`) is defined but **not in `module.exports`** (`:131`) — dead, and it is the only *correct* (single-read-then-atomic-decrement) implementation in the file.
- **Policy contradiction:** `checkUserCanUseCredit:74` enforces `dailyCreditUsed >= 3`, while `resetDailyFreeCredit.js:20` hard-sets `credit: 1`. The daily-3 branch is unreachable for a user who starts each day with one credit. See §7.
- **Reward credits are destroyed nightly** because the reset *assigns* rather than *tops up*.
- The **premium plan has no expiry check at use time** — `plan` is only ever corrected by the webhook. A missed `EXPIRATION` webhook grants unlimited free usage indefinitely.

### Memory and timeout

- **Config mismatch:** `firebase.json:6-7` declares `memory: "2GB"`, `timeoutSeconds: 120` for the codebase, but `index.js:46` overrides `api` with **`timeoutSeconds: 240, memory: "512MiB"`**. The per-function option wins. So the heaviest function in the system runs in **512MiB**.
- In that 512MiB, `transcribe.js` simultaneously holds: the busboy `Buffer` (up to **200MB**, `uploadAudio.js:6`), the `form-data` copy sent to ElevenLabs, the parsed ElevenLabs JSON, the structured conversion, and `JSON.stringify(..., null, 2)` of it. OOM is close to certain for large files. The `express.raw` limits (130mb / 150mb, `index.js:30-31`) are inconsistent with busboy's 200MB and with each other, and `multipart/form-data` is not in either `type` list.
- **Timeout inversion:** the function budget is 240s, but the ElevenLabs axios timeout is **300000ms** (`transcribe.js:121`) and **600000ms** (`transcribeYoutube.js:169`). The client will never time out before the platform kills the function — so a slow STT produces a hard 504 with a consumed ElevenLabs call and no Firestore write.
- **YouTube budget:** `youtube_to_mp3.js` alone can spend ~60s (60 convert attempts) + ~30s (10 progress polls), then `transcribeYoutube.js:82-113` downloads with 5 retries × 20s, all *before* STT starts — inside 240s total.
- **`Buffer.concat` in a `data` handler** (`uploadAudio.js:22`, `uploadJson.js:20`, `uploadPDF.js:33`) reallocates and copies the whole accumulated buffer per chunk — O(n²) in both time and peak memory. Should be a chunk array with one `concat` at the end, or a stream straight to GCS.
- **`uploadAudio.js:56-57` feeds the parser twice** — both `req.pipe(busboy)` and `busboy.end(req.rawBody)` execute unconditionally. `uploadJson.js:49-53` and `uploadPDF.js:67-71` correctly branch on `req.rawBody`. `uploadAudio` is the one used by the main transcription endpoint.
- **busboy `fileSize` limits are set but the `limit` event is never handled** in all three parsers — an oversized upload is silently **truncated** and then transcribed as a partial file.
- **`transcribe.js:15`** — `uploadAudio(req, res, async function (err) {...})` never checks `err`.
- The whole synchronous design is wrong for the workload. The codebase already contains an async job model (`speechJobs`, `getStatus`, the poller) that is not wired up.

### Silently swallowed errors

- **`ai.service.js:107,138,156,174,205`** — bare `catch { return {short_questions: []} }` / `{flashcards: []}` / `{quiz: []}` / `{mindmap:{title:"Untitled",children:[]}}` / `{}`. A provider outage, a rate limit and "the transcript had no content" are indistinguishable. Worse, **`postMindMap.js:67` persists the `"Untitled"` fallback into `metadata/mindmap`**, and `:33-36` then returns that cached garbage forever. `getSpeakers.js:64` likewise caches `{}`.
- **`minutes.service.js:481-488`** — `queryCollectionWithCursorPagination` catches everything and returns `{data: [], nextPageCursor: null, hasNextPage: false}`. A missing composite index makes `GET /v1/minutes` return **HTTP 200 with an empty list**. This is the single most misleading failure mode in the API.
- **`minutes.service.js:10-13`** — `readJsonFromGcsUri` returns `null` on any error.
- **`minutes.service.js:275-277`** — per-metadata-doc catch that logs and continues.
- **`upload.service.js:43-46, 76-79, 132-136`** — every upload helper returns `null` on failure. `transcribe.js:137` then reads `uploadResult.gcsUri` → `TypeError` on a failed upload.
- **`getAudioDuration.js:13-16`** — returns `0` on a parse failure, which **silently defeats the free-plan 30-minute cap** (`0 > 1800` is false).
- **`triggers/user.js:45-47, 60-62`** — deletion errors are logged and swallowed; the user is reported deleted regardless.
- **`runDailyJobs.js:14-16`** — the daily reset's errors are caught and dropped; a partial batch failure is invisible.

### Dead code and duplicate exports

- **`utils/firestore.js`** — required by nothing. 65 lines encoding an entirely different data model (top-level `minutes`, top-level `tags`, a `chat` subcollection).
- **`utils/openai.js`** — 401 lines, **100% commented out**.
- **`utils/youtubeUtils.js`** — required by nothing. Also references an undefined `result` at `:43` (its assignment at `:33` is commented out) and shells out to ffmpeg via `child_process.exec` with an interpolated path.
- **`triggers/speechScheduler.js`** — defines `scheduledCheckJobs` but is **not exported in `index.js`**. Consequently **`services/speech.service.js` (242 lines, the entire Google STT v2 pipeline) is unreachable**, and `speechJobs` is written by nothing while `getStatus.js` still reads it.
- Inside that unreachable file, four further bugs: `:4` imports `summarizeText` but `:207` calls **`summarizeFromTranscript`** (undefined); `:21` does `keywords.map(...)` on what every HTTP path supplies as a **string**; `:186` uses `return` inside the `for` loop over jobs, aborting the whole batch instead of `continue`; `:32` places `diarizationConfig` at the request root instead of inside `config`; and `:44` stores a bare operation ID which `:68` then passes to `getOperation({name})`, which expects a full resource name.
- **`services/user.service.js`** — required by nothing, and **exports `getUserByEmail` twice** (`:5` and `:12`); the second silently shadows the first, and the two have different semantics (the second auto-creates a user).
- **`middlewares/custom-validate.js`** — `addMinutesValidation` unused.
- **`api/v1/minutes/postMinutes.js`** — entirely commented out and not routed; `minutes.service.addMinutes` (`:119-141`) is its orphaned service half.
- **`utils/prompts/summarizeFromTranscriptFull.txt`** — never loaded by any `loadPrompt` call.
- **`minutes.service.js:234-258`** — four commented-out metadata configs (`flashcards`, `quiz`, `mindmap`, `calendarEvents`), so `getMinuteById` returns summary/transcription/shortQuestions/speakers but silently omits the other four.
- **`transcribe.js:164-170`, `transcribeYoutube.js:191-197`** — commented-out summary uploads, while `minutes.service.js:285` still reads the `summaryUri` they would have written.
- **Duplicated 90-entry `languageMap`** in `transcribe.js:69-85` and `transcribeYoutube.js:15-31`.
- **Duplicated "load transcript else summary" block** copy-pasted in six handlers (`chat.js:37-60`, `postFlashcards.js:51-75`, `postQuiz.js:52-75`, `postShortQuestions.js:39-52`, `postMindMap.js:41-57`, `getSpeakers.js:44-54`), with subtle divergence — `getSpeakers.js:45` and `mapSpeakers.js:46` read `.transcript`, the other four read `.sections`.
- **`mapSpeakers.js:9`** documents itself as `POST /map-speakers` but is routed at `POST /:id/speakers` (`minutes/index.js:23`).
- **Duplicate auth:** `authMiddleware` runs globally (`index.js:41`) *and* per-route on all six sub-routers — every request performs token verification twice.

### Dependency hygiene

- **`package.json:20` declares `"busy": "^0.1.1"`, but all three parsers `require('busboy')`** (`uploadAudio.js:1`, `uploadJson.js:1`, `uploadPDF.js:1`). `busboy` resolves only **transitively via `multer`** — which is itself declared and otherwise unused. Remove `busy`, declare `busboy`.
- **`form-data` is required** (`transcribe.js:4`, `transcribeYoutube.js:4`) but **not declared** — another transitive resolution.
- **`@distube/ytdl-core` is declared**, but the (dead) consumer imports plain **`ytdl-core`**, which is not declared.
- **`firebase-functions-test` sits in production `dependencies`.**
- `youtube-dl-exec`, `fluent-ffmpeg`, `express-validator` are declared and effectively unused.
- No lockfile discipline issue observed, but `node_modules` exists at both the repo root and `functions/`.

### Observability

Every handler logs with emoji prefixes to `console`, including **full prompt and transcript bodies** (`summary/pdf.js:64` logs the entire extracted PDF text; `transcribe.js:152` logs the summary; `speech.service.js:174` logs the full transcript). That is user content in Cloud Logging. There is no request ID, no structured logging, no metrics, and no error reporting integration.

---

## 7. Things that are ambiguous — a human must decide

1. **Which data model is canonical.** Top-level `minutes` + `tags` with `uid` fields (`utils/firestore.js`) versus `users/{uid}/minutes` + `tags/{uid}/tagItems` (everything live). The dead file is the only place ownership is checked *explicitly* rather than by path; the v2 rewrite should pick one and state the ownership rule once.
2. **Is the Google Cloud STT v2 async pipeline being revived or deleted?** `speech.service.js`, `speechJobs`, `speechScheduler`, `GET /:taskId/status` and `GET /:taskId/result` all still exist and `getStatus` still reads Firestore, but ElevenLabs replaced it synchronously and the poller is not deployed. Given the 240s/512MiB reality, an async job model is almost certainly the right v2 architecture — but whether to resurrect *this* one or write a new one is a call.
3. **Free-tier policy.** Is the limit 3/day (`checkUserCanUseCredit:74`) or 1/day (`resetDailyFreeCredit:3,20`)? Are `credit` and `dailyCreditUsed` two independent quotas or two views of one? Should the reset *top up* to a floor or *assign*?
4. **Do reward credits survive the nightly reset?** Today they do not. If rewarded video is a monetization lever, this is almost certainly a bug — but it may be a deliberate anti-farming measure.
5. **Should premium be genuinely unlimited?** It bypasses the credit gate entirely *and* the 30-minute duration cap, and `plan` is never re-validated against an expiry at use time. A missed webhook grants unlimited usage forever.
6. **`keywords`: string or array?** Every HTTP path supplies a form-field string; `speech.service.js:21` calls `.map()` on it; `api.yaml:73` documents `["KPI","A1"]`. It is stored on the minute doc as whatever arrives.
7. **Should chat history be persisted?** `api.yaml:172-191` specifies `GET` and `POST /minutes/:id/chat` with a message list; `utils/firestore.js:55-64` has the storage helpers; the live `chat.js` implements POST only and stores nothing. Three answers, no decision.
8. **`GET /:id/speakers` has billing side effects** — it generates via the LLM and writes on a cache miss. Intentional (lazy generation) or should generation be POST-only, leaving GET pure?
9. **One-pass versus lazy AI generation.** `summarizeFromTranscriptFull.txt` produces mindmap + quiz + flashcards alongside the summary, and `upsertMinute:67-109` is written to store exactly those nested blocks — but nothing loads that prompt, and each feature has its own lazy endpoint instead. Which model is intended? (Cost and latency trade off directly: one `gpt-4o` call at ingest versus four `gpt-4o-mini` calls on demand.)
10. **Should summaries still be uploaded to GCS?** The upload calls are commented out in two files, yet `getMinuteById` still reads a `summaryUri`.
11. **Is the y2mate/d.mnuu.nu scraping path acceptable?** It is ToS-hostile, proxy-dependent, executes remote JavaScript in `vm`, and carries a committed credentialed proxy. A supported alternative (or dropping YouTube ingest) is a product decision, not a technical one.
12. **`POST /v1/youtube/mp3`** exposes third-party download-URL minting to any authenticated user, independent of transcription and **without consuming credit**. Is that a deliberate feature or a leftover debugging endpoint?
13. **The API contract itself.** `api.yaml` says `/api/v1/...`; the code serves `/v1/...`. It says `POST /transcription/audio`; the code has `/transcription/transcribe`. It specifies response bodies (`{taskId}`, a `transcript.messages[]` array) that no handler returns. Whoever owns the Flutter client must confirm which paths and shapes are actually in use before anything is renamed.
14. **`iconAsset`** is an emoji character from the LLM; `api.yaml:11` describes it as `"icon_id"`. Emoji or asset identifier?
15. **The timezone header.** `transcribe.js:63`, `transcribeFile.js:52` and `transcribeYoutube.js:43` read `req.headers['X-Timezone']` — Node lowercases all incoming header names, so this is **always `undefined`** and always falls through to `req.body.timezone` or `"GMT -7"`. Is the header or the body field the intended source? (This silently affects every `calendarEvents` datetime resolution.)
16. **`GET /v1/minutes` `total`** is the length of the current page, not a collection count. Is a true total expected by the client?
17. **`contentType`** on the minute doc holds the LLM's session-type enum (`lecture`, `team_meeting`, …), not a MIME type, while `sourceType` holds `audio`/`youtube`/`pdf`. The naming is inverted from the obvious reading and should be settled before the client is ported.
