# 16 — Checklist parity backend v1 → v2 (S9-02)

Đối chiếu **từng endpoint** v1 (`01-AUDIT-BACKEND-V1.md` §1) với callable v2,
kèm bằng chứng test. Trạng thái: ✅ có + test · ➕ v2 mở rộng · ✂️ bỏ có chủ ý.

| # | v1 endpoint | v2 | Test (unit / integration) | Trạng thái |
|---|---|---|---|---|
| 1 | `GET /user/me` | `getMe` | `users.test.ts` / `getMe.test.ts` | ✅ ➕ `notifications`, `planExpiresAt` |
| 2 | `POST /user/reward` | — (AdMob SSV `adRewardSsv`) | `ssv.test.ts` / `ssv.test.ts` | ✂️ client không tự cộng credit |
| 3 | `DELETE /user` (app gọi `user.delete()` trực tiếp) | `deleteAccount` + `onUserDeleted` | `users.test.ts` / `getMe.test.ts`, `lifecycle.test.ts` | ✅ ➕ xoá Storage, không nuốt lỗi |
| 4 | `POST /tags` | `createTag` | `tags.test.ts` / `tags.test.ts` | ✅ |
| 5 | `GET /tags` | `listTags` | — / `tags.test.ts`, `migrate.test.ts` | ✅ ➕ `minuteCount` |
| 6 | `PUT /tags/:id` | `updateTag` | `tags.test.ts` / `tags.test.ts` | ✅ (sửa `tagId`→`tag.id`) |
| 7 | `DELETE /tags/:id` | `deleteTag` | `tags.test.ts` / `tags.test.ts` | ✅ ➕ gỡ khỏi minutes theo batch |
| 8 | `GET /minutes` | `listMinutes` | `minutes.test.ts`, `cursor.test.ts` / `minutes.test.ts` | ✅ (thiếu index → lỗi, không rỗng) |
| 9 | `GET /minutes/:id` | `getMinute` | `minutes.test.ts`, `contract.test.ts` / `minutes.test.ts` | ✅ ➕ `calendarEvents`, `availableArtifacts`, `stt` |
| 10 | `PATCH /minutes/:id` | `updateMinute` | `minutes.test.ts` / `minutes.test.ts` | ✅ (bỏ ghi đè `summaryText`/`transcription`) |
| 11 | `DELETE /minutes/:id` | `deleteMinute` | `minutes.test.ts` / `minutes.test.ts` | ✅ ➕ xoá prefix Storage |
| 12 | `GET /minutes/:id/transcription` | trong `getMinute.transcript` | — / `minutes.test.ts` | ✅ (v1 luôn 404) |
| 13 | `POST /minutes/:id/questions` | `generateShortQuestions` | `ai.test.ts` / `ai.test.ts` | ✅ ➕ cache `sourceHash` |
| 14 | `POST /minutes/:id/chat` | `chat` (streaming) + `listChatMessages` | `ai.test.ts` / `ai.test.ts` | ✅ ➕ lịch sử |
| 15 | `GET /minutes/:id/speakers` | `getMinute.speakers` + `mapSpeakers` | — / `ai.test.ts` | ✅ (không sinh ngầm khi đọc) |
| 16 | `PATCH /minutes/:id/speakers/:sid` | `renameSpeaker` | `ai.test.ts` / `ai.test.ts` | ✅ |
| 17 | `POST /transcription/transcribe` (multipart) | `createMinute` → upload Storage → `startTranscription` → `processTranscription` | `transcribe.test.ts`, `stt.test.ts` / `transcribe.test.ts` | ✅ ➕ resumable, quota transaction, cancel, refund, push |
| 18 | `GET /transcription/:taskId/status` | Firestore listener trên minute | — / `transcribe.test.ts` (máy trạng thái) | ✂️ polling |
| 19 | `GET /transcription/:taskId/result` | `getMinute` | — | ✂️ stub v1 |
| 20 | `POST /transcription/youtube` | — | — | ✂️ OQ-06 |
| 21 | `POST /v1/youtube/mp3` | — | — | ✂️ OQ-06 |
| 22 | `POST /v1/summary/pdf` | `createMinute(sourceType:"pdf")` → pipeline nhánh PDF | `stt.test.ts` (pdf) / `transcribe.test.ts` | ✅ (v1 chưa từng tóm tắt đúng) |
| 23 | metadata `quiz` / `flashcards` / `mindmap` (v1 sinh ngầm ở GET) | `generateQuiz` / `generateFlashcards` / `generateMindmap` | `ai.test.ts` / `ai.test.ts` | ✅ (đọc không tính tiền) |
| 24 | metadata `calendarEvents` (v1 chỉ ghi) | rút lúc summarize + `generateCalendarEvents` | `ai.test.ts` / `ai.test.ts`, `minutes.test.ts` | ✅ ➕ lộ ra API |
| 25 | RevenueCat webhook | `revenueCatWebhook` | `revenuecat.test.ts` / `revenuecat.test.ts` | ✅ (constant-time, uid thật, `set(merge)`) |
| 26 | `resetDailyCredit` (cron v1) | không cần — quota theo ngày + TTL | `quota.test.ts` / `quota.test.ts` | ✂️ |
| 27 | — | `registerDevice` / `unregisterDevice` / `updateNotificationPrefs` + push | `push.test.ts` / `push.test.ts` | ➕ mới (OQ-15) |
| 28 | — | `sweepOrphanFiles`, `reapStaleJobs`, `onMinuteWritten` | — / `sweep.test.ts`, `transcribe.test.ts`, `tags.test.ts` | ➕ mới |

**Kết luận:** 0 tính năng v1 rơi ngoài 4 mục bỏ có chủ ý (reward tự cộng, YouTube ×2,
stub result). Chốt S9-02 phía backend.

Phía app (S9-01) đối chiếu `02-AUDIT-APP.md` §3/§5 làm khi màn hình dựng xong.
