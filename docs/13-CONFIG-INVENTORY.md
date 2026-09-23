# 13 — Config inventory (những thứ mang sang bản build lại)

Trích từ codebase cũ ngày 2026-09-22. Đây là **danh sách duy nhất** những giá
trị được giữ lại; mọi thứ khác viết mới.

Quy tắc: giá trị **client-side** dưới đây vốn đã nằm trong file binary phát hành
nên ghi ra đây không làm lộ thêm gì. Giá trị **server-side** chỉ ghi *tên biến* —
không bao giờ ghi giá trị vào repo.

---

## 1. Firebase

| | |
|---|---|
| Project id | `minutesai-6715a` |
| Messaging sender id | `468402655519` |
| Storage bucket | `minutesai-6715a.firebasestorage.app` |
| Android app id | `1:468402655519:android:8a74bff47f1cb60d7e202a` |
| Android apiKey | `AIzaSyCpKGcArlZrTX3dewyKCZMXwd7gf1V0KJk` |
| iOS app id | `1:468402655519:ios:aa2c8efd457865047e202a` |
| iOS apiKey | `AIzaSyCxB2edI535upaZGa15pYU3manAhIkHdTk` |

> `firebase_options.dart` cũ còn một khối `web` toàn `YOUR_API_KEY` chưa cấu hình
> — bản mới không sinh platform web.
>
> **Cần bổ sung:** project `oneai-dev` và `oneai-staging` (S0-06). Bản build lại
> đọc `firebase_options` theo flavor, không hardcode một project.

## 2. Định danh app

| | |
|---|---|
| Tên trên store | **One AI: AI Note Taker & Scribe** |
| Tên dưới icon (`CFBundleDisplayName` / `android:label`) | **One AI** |

| | Android | iOS |
|---|---|---|
| Application id / bundle id | `top.doxutostudio.one.ai` | `top.doxutostudio.one.ai` |
| Store id | — | `6743523150` |
| minSdk / ndk | `24` / `27.0.12077973` | — |
| Namespace cũ | `com.codebase.ai.codebase_ai` ← **bỏ**, đổi thành `top.doxutostudio.one.ai` |

## 3. RevenueCat

| | |
|---|---|
| Public SDK key — Android | `goog_XBenIbCcAEYqjdHwxPQPRyjeEjt` |
| Public SDK key — iOS | `appl_uJKYXVJiPCraeNcbYkNytLfVxYS` |
| Entitlement id | `pro` |
| Webhook secret (server) | biến `REVENUECAT_WEBHOOK_SECRET` — **xoay lại khi dựng v2** |

`Purchases.setLogLevel(LogLevel.debug)` **không** mang sang — chỉ bật ở debug build.

## 4. Sentry

| | |
|---|---|
| DSN | `https://2ecaca4988375921fd4b32362d27a8e5@o4509008840097792.ingest.us.sentry.io/4509008848814080` |

Bản mới: `tracesSampleRate` khác nhau theo flavor, bật `beforeSend` lọc PII.

## 5. AppsFlyer

| | |
|---|---|
| Dev key | `3qD2EG45ru9SgRjw7NfcGF` |
| Android app id | `top.doxutostudio.one.ai` |
| iOS app id | `6743523150` |

`showDebug: true` **không** mang sang. `timeToWaitForATTUserAuthorization: 30`
xem lại sau khi làm UMP đúng thứ tự (`08-ADS-FLOW.md` §4).

## 6. AdMob

| | Giá trị | Trạng thái |
|---|---|---|
| Android App ID | `ca-app-pub-8661297299230251~8068383004` | ✅ |
| **iOS App ID** | `ca-app-pub-8661297299230251~8024150974` | ✅ Toan cung cấp 23/09 |

> Bản cũ để `ca-app-pub-3940256099942544~1458002511` trong Info.plist — sample
> id công khai của Google — nên iOS chưa từng thu được đồng quảng cáo nào.
> Bản mới dùng id thật ở trên. Giá trị chính xác để dán: `App/oneai_v2/PLATFORM-SETUP.md`.
>
> ⚠️ Tôi hiểu `~8024150974` là **App ID của iOS** (Android đã có `~8068383004`,
> cùng publisher id `8661297299230251`). Nếu thật ra nó là một app Android thứ
> hai thì báo lại — đặt nhầm platform là ads im lặng không chạy.

Ad unit id: **không** hardcode ở đâu cả — toàn bộ đọc từ Remote Config dạng
`{"Android": "...", "iOS": "..."}`. Bản mới gom vào một key `ads_config` (xem
`08-ADS-FLOW.md` §3) và thêm tầng debug dùng test unit id của Google.

`SKAdNetworkItems` trong Info.plist: **hiện có 0 mục.** Cần thêm danh sách
SKAdNetwork id của các mạng quảng cáo (AdMob công bố sẵn) nếu muốn đo lường
attribution trên iOS.

Android đã có `com.google.android.gms.permission.AD_ID` — giữ.

## 7. Google Sign-In

| | |
|---|---|
| iOS client id | `468402655519-7n4hnnm9rhkgova6ioumv673peo0qu8n.apps.googleusercontent.com` |
| Reversed URL scheme | `com.googleusercontent.apps.468402655519-7n4hnnm9rhkgova6ioumv673peo0qu8n` |

URL scheme khác trong Info.plist cũ: `oneai` (deep link) — giữ;
`fb787393250278163` (Facebook) — **bỏ**, không có SDK Facebook nào trong app.

## 8. Quyền hệ thống

**iOS** — giữ và viết lại cho rõ hơn:
`NSMicrophoneUsageDescription`, `NSUserTrackingUsageDescription`.
`NSPhotoLibraryUsageDescription` — **bỏ** trừ khi bản mới thật sự chọn ảnh
(hiện app chỉ dùng `file_picker` cho audio).
`ITSAppUsesNonExemptEncryption` — giữ.

**Android** — `INTERNET`, `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `AD_ID` giữ.
`WRITE_EXTERNAL_STORAGE` — **bỏ**, đã thừa từ API 29 trở lên và minSdk là 24
nhưng app không ghi ra bộ nhớ ngoài.

## 9. Liên kết pháp lý / hỗ trợ

| | |
|---|---|
| Terms | `https://doxutostudio.top/terms` |
| Privacy | `https://doxutostudio.top/privacy` |
| Email hỗ trợ | `contact@doxutostudio.top` |

Cả hai trang cần cập nhật theo UMP + dữ liệu thu thập của bản mới (S9-07).

## 10. Server-side secrets — **chỉ tên biến**

Bản v2 nạp qua `defineSecret`, không qua `.env`, không qua `functions.config()`.

| Tên | Dùng cho | Ghi chú |
|---|---|---|
| `ELEVENLABS_API_KEY` | Speech-to-text | giữ |
| `OPENAI_API_KEY` | LLM | giữ |
| `GEMINI_API_KEY` | LLM (dự phòng) | giữ |
| `REVENUECAT_WEBHOOK_SECRET` | webhook | **xoay lại** |
| `GROK_API_KEY` | — | **bỏ** — adapter cũ khởi tạo bằng SDK OpenAI mà không override `baseURL`, tức là gửi khoá Grok tới `api.openai.com` |
| `PROXY` | — | **BỎ HẲN** — YouTube ingest đã gỡ (OQ-06 chốt 23/09). Credential hardcode đã xoá khỏi working tree, nhưng **vẫn còn trong git history: huỷ nó ở phía nhà cung cấp proxy** (`95.164.203.157:9822`) |
| `LLM_VENDOR` | chọn provider | thành param thường, không phải secret |

`GEMINI_MODEL`, `GROK_MODEL`, `OPENAI_MODEL` được code cũ đọc nhưng chưa bao giờ
được khai báo — bản mới đưa vào `defineString` có default tường minh.

Param không bí mật (`functions-v2/.env`, commit có chủ ý):

| Tên | Mặc định | Ý nghĩa |
|---|---|---|
| `STT_VENDOR` | `elevenlabs` | `elevenlabs` \| `gemini` |
| `STT_FALLBACK_VENDOR` | `none` | vendor thử lại một lần khi primary sập |
| `SHARE_BASE_URL` | `""` | base URL trang share link (S11-05); rỗng = URL cloudfunctions.net của `sharePage`; đặt khi có domain riêng |
| `GEMINI_STT_MODEL` | `gemini-2.5-flash` | model khi STT là Gemini |
| `OPENAI_EMBEDDING_MODEL` / `GEMINI_EMBEDDING_MODEL` / `EMBEDDING_DIM` | `text-embedding-3-small` / `gemini-embedding-001` / 768 | embedding cho S11-01/02; vendor theo `LLM_VENDOR`; `EMBEDDING_DIM` **phải bằng** `vectorConfig.dimension` trong `firestore.indexes.json` (đổi → mọi note tự re-embed qua backfill) |
| `LLM_VENDOR` / `OPENAI_MODEL` / `OPENAI_MODEL_HEAVY` / `GEMINI_MODEL` | `openai` / `gpt-4o-mini` / `gpt-4o` / `gemini-2.0-flash` | LLM |
| `FREE_MAX_ACTIVE_JOBS` / `PREMIUM_MAX_ACTIVE_JOBS` | 1 / 3 | job transcribe đồng thời tối đa mỗi user |
| `FREE_SOURCE_RETENTION_DAYS` / `PREMIUM_SOURCE_RETENTION_DAYS` | 7 / 90 | số ngày giữ audio/PDF gốc sau khi note `ready`; `-1` giữ mãi |
| `FREE_DAILY_SECONDS` = 600, `FREE_MAX_DURATION_SECONDS` = 600, `PREMIUM_DAILY_SECONDS` = 0 (không giới hạn), `PDF_CHARGE_SECONDS` = 300, `*_AI_CALLS_DAILY` | `.env` | quota theo giây/ngày (chốt 24/09); không còn `*_DAILY_LIMIT` |

Push (FCM) không cần secret: Admin SDK dùng ADC. Cần **APNs key** upload trong
Firebase console (Project settings → Cloud Messaging → Apple app) — làm tay.

`functions/service-account.json` — **không mang sang.** Runtime Cloud Functions
đã có Application Default Credentials; file key chỉ là rủi ro.

---

## 11. Việc bạn cần làm trước khi ship

| # | Việc | Chặn |
|---|---|---|
| ~~C1~~ | ~~Lấy AdMob iOS App ID thật~~ | ✅ 23/09 — `ca-app-pub-8661297299230251~8024150974` |
| **C2** | **Huỷ SOCKS proxy credential ở phía nhà cung cấp** — đã xoá khỏi code nhưng git history vẫn giữ | **ngay hôm nay** |
| C3 | Xoay `REVENUECAT_WEBHOOK_SECRET` | S7 |
| C4 | Tạo project Firebase `oneai-dev` + `oneai-staging` | S0 |
| C5 | Thêm `SKAdNetworkItems` vào Info.plist | trước đo lường iOS |
| C6 | Cập nhật trang Terms + Privacy theo UMP | S9 |
| C7 | Bật SSV trên rewarded unit trong AdMob console sau khi deploy `adRewardSsv` | S7 |
