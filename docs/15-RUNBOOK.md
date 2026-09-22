# 15 — Runbook vận hành backend v2

## Deploy

```bash
cd Backend/oneai_backend
bash scripts/deploy.sh dev        # lint + unit + build → rules/indexes → functions:v2
bash scripts/deploy.sh staging
bash scripts/deploy.sh prod       # hỏi lại, phải gõ "prod"
```

Script từ chối chạy nếu thiếu một trong 4 secret trên project đích. v1 (codebase
`default`) không bao giờ bị đụng — muốn đụng phải gõ tay `--only functions:default`.

Sau lần deploy đầu trên mỗi project (một lần, console):

| Việc | Ở đâu |
|---|---|
| TTL policy trên `expiresAt` cho collection group `quota` và collection `adRewards` | Firestore → TTL |
| SSV URL của rewarded unit = URL `adRewardSsv` | AdMob → App → Ad units → rewarded → Server-side verification |
| Webhook URL = URL `revenueCatWebhook`, header `Authorization: Bearer <secret>` | RevenueCat → Project → Integrations → Webhooks |
| Remote Config `ads_config` + `ad_units` | `remote-config/README.md` — merge, **không** deploy thẳng |
| App Check: monitor trước, enforce ở S10-04 | Firebase → App Check |

## Rollback

Mỗi function deploy độc lập. Rollback một function = deploy lại commit trước cho
đúng function đó:

```bash
git checkout <commit-tốt> -- Backend/oneai_backend/functions-v2/src
cd Backend/oneai_backend && firebase deploy --only functions:v2:chat -P prod
git checkout main -- Backend/oneai_backend/functions-v2/src
```

Rules rollback tương tự với `--only firestore:rules`. Index không rollback được
(chỉ thêm) — xoá index thừa bằng tay trong console nếu cần.

**Tắt khẩn cấp một tính năng** không cần deploy: `ads_config.enabled=false` trong
Remote Config tắt toàn bộ quảng cáo trong ≤1h (`minimumFetchInterval`). Với AI,
hạ `FREE_AI_CALLS_DAILY` / `PREMIUM_AI_CALLS_DAILY` rồi deploy lại — tính từ
period hiện tại.

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân khả dĩ | Xem | Sửa |
|---|---|---|---|
| Note kẹt `transcribing` > 10 phút | worker chết / task mất | log `pipeline.error`, Cloud Tasks queue `processTranscription` | `sweepOrphanFiles` fail + refund sau 2h; chạy tay: `firebase functions:shell` → `sweepOrphanFiles()` |
| Mọi transcribe fail `unavailable` | ElevenLabs down hoặc key sai | log `elevenlabs.non_ok` (status) | 5xx → chờ; 401 → `secrets:set ELEVENLABS_API_KEY` rồi deploy |
| `listMinutes` trả `failed-precondition` | thiếu composite index | log `minute.list.index_missing` có URL tạo index | bấm URL, hoặc `deploy --only firestore:indexes` |
| User báo mất premium | webhook EXPIRATION tới sớm / `planExpiresAt` sai | `users/{uid}.planExpiresAt`, log `revenuecat.*` | RevenueCat → Customer → resend webhook |
| Reward xem xong không cộng | SSV chưa bật / URL sai / chữ ký sai | log `ssv.bad_signature` hoặc không có log nào | kiểm tra SSV URL trong AdMob; `adRewards/{tx}` có tồn tại không |
| Hoá đơn LLM tăng đột biến | một user spam chat | log `ai.chat` group by uid | hạ `*_AI_CALLS_DAILY`; xem `quota/{period}.aiCalls` của uid đó |
| App cũ (v1) không tải được audio | storage.rules mất nhánh `user_uploads/` | rules hiện tại | giữ nhánh đó tới M7 |

## Alert nên đặt (Cloud Monitoring, log-based)

| Tên | Điều kiện | Ngưỡng |
|---|---|---|
| pipeline-failed | `jsonPayload.message="pipeline.error"` AND `retryable=false` | > 5 / 15 phút |
| stt-5xx | `elevenlabs.non_ok` AND `status>=500` | > 3 / 5 phút |
| ssv-bad-signature | `ssv.bad_signature` | > 10 / giờ (dò tấn công) |
| revenuecat-unauthorized | `revenuecat.unauthorized` | > 0 |
| index-missing | `minute.list.index_missing` | > 0 |
| function-errors | Cloud Functions error rate | > 2 % / 5 phút |
| cost | Billing budget | 80 % dự toán tháng |

## Log

Mọi log là JSON có `message` dạng `domain.thing.event` và `uid` khi có. Lọc:

```
jsonPayload.message="pipeline.done"          # mọi note xử lý xong, có ms, tokens
jsonPayload.message=~"^ai\." AND jsonPayload.uid="<uid>"
jsonPayload.message="ssv.granted"
```

Không bao giờ có nội dung transcript, prompt, email hay token trong log — nếu thấy
là bug, sửa ngay.

## Xoá dữ liệu người dùng (GDPR / App Store yêu cầu)

`deleteAccount` phía app gọi Firebase Auth `delete()` → trigger `onUserDeleted`
xoá recursive `users/{uid}` và prefix Storage `users/{uid}/`. Thất bại → trigger
ném lỗi để platform retry, log `user.delete.*_failed`. Kiểm tra bằng tay:

```bash
gcloud firestore documents get users/<uid>   # phải 404
gsutil ls gs://<bucket>/users/<uid>/         # phải rỗng
```

Dữ liệu v1 ở `user_uploads/{uid}/` và `tags/{uid}/` **không** nằm trong trigger này
tới khi migration xong — xoá tay nếu có yêu cầu trước M7.
