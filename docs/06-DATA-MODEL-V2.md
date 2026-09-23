# 06 — Data model v2 (Firestore + Storage)

Nguyên tắc: **quyền sở hữu nằm trong đường dẫn.** Mọi thứ user sở hữu ở dưới
`users/{uid}/`. Không còn field `uid` để lọc, không còn hai mô hình song song
như v1 (`01-AUDIT-BACKEND-V1.md` §2).

---

## 1. Collections

```
users/{uid}
  ├─ minutes/{minuteId}
  │    ├─ chat/{messageId}
  │    └─ artifacts/{kind}          kind ∈ quiz|flashcards|mindmap|shortQuestions|speakers|calendarEvents
  ├─ tags/{tagId}
  └─ quota/{periodId}               periodId = "2026-09-22" (ngày, Asia/Ho_Chi_Minh)

adRewards/{transactionId}           idempotency ledger cho AdMob SSV, có TTL
transcriptionJobs/{jobId}           trạng thái task worker (chỉ server đọc/ghi)
```

### `users/{uid}`

| Field | Type | Ghi chú |
|---|---|---|
| `email` | `string \| null` | |
| `displayName` | `string \| null` | |
| `photoUrl` | `string \| null` | |
| `plan` | `"free" \| "premium"` | chỉ `revenueCatWebhook` ghi |
| `planExpiresAt` | `Timestamp \| null` | **mới** — v1 không có, nên một webhook `EXPIRATION` bị miss = premium vĩnh viễn |
| `createdAt` / `updatedAt` / `lastSeenAt` | `Timestamp` | |
| `minuteCount` | `number` | denormalize, cập nhật bằng trigger |
| `notifications` | `{transcriptionDone: boolean}` | thiếu = `true`; chỉ `updateNotificationPrefs` ghi |

Bỏ `role` (không dùng ở đâu), bỏ `credit` / `dailyCreditUsed` / `totalCreditUsed`
/ `lastCreditReset` — chuyển hết vào `quota/{periodId}`.

### `users/{uid}/quota/{periodId}` — **mới**

| Field | Type | Ghi chú |
|---|---|---|
| `periodId` | `string` | `"2026-09-22"` |
| `used` | `number` | số lần transcribe đã dùng trong ngày |
| `baseLimit` | `number` | hạn mức gói (free: xem OQ-02) |
| `rewardBonus` | `number` | do AdMob SSV cộng vào, **chỉ nâng trần** |
| `expiresAt` | `Timestamp` | TTL → hết ngày tự biến mất, không cần job dọn |

Ngữ nghĩa (theo `rewarded-ssv.md`): *"Grant raises the ceiling, it doesn't lower
usage"* — đang 3/5, thưởng 2 → thành **3/7**, không phải 1/5.

Hiệu lực: `allowed = used < baseLimit + rewardBonus`. Premium bỏ qua kiểm tra
nhưng **vẫn ghi `used`** để có số liệu.

Đây là chỗ sửa mâu thuẫn của v1: `checkUserCanUseCredit` chặn ở
`dailyCreditUsed >= 3` trong khi `resetDailyFreeCredit` set cứng `credit: 1`,
khiến nhánh 3/ngày không bao giờ chạy tới, và reward bị xoá sạch mỗi đêm.

### `users/{uid}/minutes/{minuteId}`

| Field | Type | Ghi chú |
|---|---|---|
| `title` | `string` | |
| `iconEmoji` | `string \| null` | v1 đặt tên `iconAsset` nhưng chứa emoji |
| `sourceType` | `"audio" \| "pdf"` | YouTube đã bỏ (OQ-06) |
| `contentKind` | `string \| null` | enum do LLM đoán; v1 gọi là `contentType`, dễ nhầm MIME |
| `status` | enum | `uploading\|queued\|transcribing\|summarizing\|ready\|failed\|cancelled` |
| `statusUpdatedAt` | `Timestamp` | |
| `failure` | `{code, message} \| null` | |
| `durationSeconds` | `number \| null` | v1 lưu chuỗi `"MM:SS"` |
| `audioPath` | `string \| null` | path trong bucket, **không** phải `gs://` URL |
| `languageCode` / `languageProbability` | | |
| `summaryLanguage` | `string` | |
| `keywords` | `string[]` | v1 lưu chuỗi ở chỗ này, mảng ở chỗ kia (OQ đã đóng: **mảng**) |
| `description` | `string \| null` | ngữ cảnh user nhập |
| `tagIds` | `string[]` ≤10 | |
| `summary` | map nhúng | nhỏ, đọc kèm luôn |
| `transcriptPath` | `string` | transcript đầy đủ nằm ở Storage, không nhồi vào doc |
| `transcriptPreview` | `string` ≤2000 | để hiển thị nhanh và search |
| `createdAt` / `updatedAt` | `Timestamp` | |

**Vì sao transcript ra Storage:** doc Firestore tối đa 1 MiB. Một buổi họp 2
tiếng vượt ngưỡng đó. v1 ghi cả `metadata/transcription` lẫn field
`transcription` trên doc gốc — vừa trùng vừa rủi ro.

**Retention:** `sourceState` (`available`|`expired`), `sourceExpiresAt`
(`Timestamp|null`), `sourceExpiredAt`. Index collection-group
`(sourceState, sourceExpiresAt)` cho bước xoá hằng ngày. Xem `05` §2.7b.

### `users/{uid}/minutes/{minuteId}/artifacts/{kind}`

| Field | Type |
|---|---|
| `kind` | `"quiz"\|"flashcards"\|"mindmap"\|"shortQuestions"\|"speakers"\|"calendarEvents"` |
| `data` | map, shape tuỳ `kind` |
| `model` | `string` — model nào sinh ra |
| `generatedAt` | `Timestamp` |
| `sourceHash` | `string` — hash của transcript lúc sinh |

`sourceHash` cho phép invalidate cache khi transcript đổi (v1 không có → sửa
speaker xong quiz vẫn là quiz cũ). **Không bao giờ ghi artifact khi sinh thất bại.**

### `users/{uid}/minutes/{minuteId}/chat/{messageId}`

`role: "user"|"assistant"`, `text`, `createdAt`, `model?`, `tokenCount?`.
Mới hoàn toàn — v1 không lưu chat.

### `users/{uid}/tags/{tagId}`

`name`, `nameLower` (unique key), `minuteCount`, `createdAt`.
Gộp từ `tags/{uid}/tagItems` của v1.

### `adRewards/{transactionId}`

`uid`, `amount`, `adUnit`, `at`, `expiresAt` (now + 30 ngày, có TTL policy).
`transaction_id` của Google làm document id ⇒ idempotency miễn phí bằng
`tx.create()`, ném code 6 nếu trùng.

### `users/{uid}/devices/{deviceId}` — **mới**

`deviceId = sha256(token)[:40]`. `token`, `platform`, `locale`, `appVersion`,
`createdAt`, `lastSeenAt`. Server-only (rules chặn cả owner). Một token chỉ nằm
dưới một uid: `registerDevice` xoá bản ghi cùng token ở uid khác (collection-group
query trên `token` — field override trong `firestore.indexes.json`). Token chết
bị xoá khi FCM báo.

### `transcriptionJobs/{jobId}`

`uid`, `minuteId`, `requestId`, `state` (queued|running|done|failed|cancelled),
`attempt`, `periodId`, `quotaRefunded: boolean`, `options{audioLanguage,
summaryLanguage, keywords, description, timezone}`, `createdAt`, `startedAt`,
`finishedAt`, `error`, và khi `done`: `stt: {vendor, model}`, `durationMs`.
Chỉ Admin SDK truy cập; rules chặn client hoàn toàn. `reapStaleJobs` (15 phút)
đọc theo `(state, startedAt)` / `(state, createdAt)`; trần đồng thời đọc
`(uid, state)`.

---

## 2. Indexes (`firestore.indexes.json`)

v1 **không có file index nào** và
`queryCollectionWithCursorPagination` nuốt mọi lỗi rồi trả mảng rỗng — thiếu
index biểu hiện thành "HTTP 200, danh sách trống", kiểu hỏng khó chịu nhất.

v2 khai báo trước:

| Collection | Fields | Phục vụ |
|---|---|---|
| `minutes` (CG) | `status ASC, createdAt DESC` | list mặc định |
| `minutes` (CG) | `tagIds ARRAY, createdAt DESC` | lọc theo tag |
| `minutes` (CG) | `status ASC, title ASC` | sort theo tên |
| `chat` (CG) | `createdAt ASC` | lịch sử chat |

**Search:** v1 làm prefix-range trên `title` cộng với `orderBy("createdAt")` —
Firestore không cho phép, luôn ném. v2 **không** làm full-text trong Firestore.
Phase 1: lọc client-side trên trang đã tải. Phase 2 (nếu cần): xem OQ-07.

---

## 3. Security rules

Nguyên tắc từ `firebase-security-pro`: **client không ghi gì trực tiếp.** Mọi
mutation đi qua callable. Client chỉ đọc, để dùng được `snapshots()`.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn()   { return request.auth != null; }
    function isOwner(uid) { return signedIn() && request.auth.uid == uid; }

    match /users/{uid} {
      allow get: if isOwner(uid);
      allow write: if false;                  // callable + trigger only

      match /minutes/{minuteId} {
        allow get, list: if isOwner(uid);
        allow write: if false;
        match /{sub=**} { allow get, list: if isOwner(uid); allow write: if false; }
      }
      match /tags/{tagId}  { allow get, list: if isOwner(uid); allow write: if false; }
      match /quota/{p}     { allow get: if isOwner(uid);       allow write: if false; }
    }

    match /adRewards/{txId}          { allow read, write: if false; }
    match /transcriptionJobs/{jobId} { allow read, write: if false; }
    match /{document=**}             { allow read, write: if false; }
  }
}
```

Bắt buộc có rules unit test (`@firebase/rules-unit-testing`) cho: chủ đọc được,
người khác không, và mọi write từ client đều bị từ chối.

---

## 4. Cloud Storage

```
users/{uid}/minutes/{minuteId}/source/{fileName}        audio hoặc pdf gốc
users/{uid}/minutes/{minuteId}/transcript.json          transcript đầy đủ
users/{uid}/minutes/{minuteId}/exports/{fileName}.pdf   PDF xuất ra
```

Đổi so với v1 (`user_uploads/{uid}/{minuteId}/...`): đồng nhất tiền tố với
Firestore, và **bỏ `firebaseStorageDownloadTokens`**. v1 sinh token cho mọi file
— token này tạo URL tải công khai bỏ qua rules — rồi vứt đi không dùng. Thuần
tuý bề mặt tấn công.

### storage.rules

```js
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{uid}/minutes/{minuteId}/source/{fileName} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if request.auth != null
                   && request.auth.uid == uid
                   && request.resource.size < 300 * 1024 * 1024
                   && (request.resource.contentType.matches('audio/.*')
                       || request.resource.contentType == 'application/pdf');
    }
    match /users/{uid}/{allPaths=**} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if false;                 // chỉ Admin SDK
    }
    match /{allPaths=**} { allow read, write: if false; }
  }
}
```

Đây là thay đổi lớn: v2 cho client **upload thẳng** vào `source/`, nên rules
phải chặn size và content-type. v1 chặn mọi write từ client và nhận file qua
busboy vào RAM 512MiB — chính là chỗ OOM.

### Vòng đời file

1. `createMinute` tạo doc `status: "uploading"` + trả path để upload.
2. Client upload resumable (progress thật, có thể huỷ, có thể tiếp tục).
3. `startTranscription` kiểm tra file tồn tại, đúng size, đúng type.
4. `deleteMinute` xoá prefix `users/{uid}/minutes/{minuteId}/`.
5. `sweepOrphanFiles` (hằng ngày) xoá prefix không còn minute, và minute kẹt
   `status: "uploading"` quá 24h. **v1 không có bước này** — mọi lần Firestore
   ghi hỏng sau khi upload xong là rò rỉ file vĩnh viễn.
6. Lifecycle rule trên bucket: `exports/` xoá sau 7 ngày.
