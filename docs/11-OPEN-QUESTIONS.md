# 11 — Câu hỏi mở (chờ Toan chốt)

> ⚠️ Mã sprint (S3-05, S7-12…) trong file này là của **roadmap bản 1**.
> `09-ROADMAP.md` đã được đánh số lại cho hướng build-lại-từ-đầu.
> Tra cứu theo tên task, đừng theo mã.


Quy ước: mỗi mục có **hạn chốt** = sprint mà nó chặn. Agent **không tự quyết**
các mục `CHƯA CHỐT`; nếu buộc phải đi tiếp thì dùng "Mặc định tạm" và ghi rõ
trong commit. Khi chốt xong: đổi trạng thái, ghi ngày, ghi quyết định.

| # | Câu hỏi | Chặn | Trạng thái |
|---|---|---|---|
| OQ-01 | Migrate dữ liệu v1? | S3 | **CHƯA CHỐT** |
| OQ-02 | Hạn mức gói free là bao nhiêu? | S7 | **CHƯA CHỐT** |
| OQ-03 | Credit thưởng có sống qua đêm? | S7 | **CHƯA CHỐT** |
| OQ-04 | Premium có thực sự không giới hạn? | S7 | **CHƯA CHỐT** |
| OQ-05 | Sinh AI một lượt hay lười? | S5 | **CHƯA CHỐT** |
| OQ-06 | Giữ YouTube ingest? | — | ✅ **ĐÃ CHỐT 23/09: BỎ HẲN** |
| OQ-07 | Có cần full-text search? | S3 | **CHƯA CHỐT** |
| OQ-08 | Bật dark mode? | S8 | **CHƯA CHỐT** |
| OQ-09 | Đăng ký font Roboto? | S8 | **CHƯA CHỐT** |
| OQ-10 | Đổi route sang `/minutes/:id`? | S6 | **CHƯA CHỐT** |
| OQ-11 | Interstitial ở nhánh Congratulation | S7 | **CHƯA CHỐT** |
| OQ-12 | Thêm tiếng Việt? | S8 | ✅ đã làm sẵn `app_vi.arb` (23/09) — Toan chỉ cần rà bản dịch |
| OQ-13 | Giữ `contentKind` do LLM đoán? | S3 | **CHƯA CHỐT** |
| OQ-14 | Nguồn timezone: header hay body? | S4 | **CHƯA CHỐT** |
| OQ-15 | Có làm push notification? | S8 | ✅ **ĐÃ LÀM BE 23/09**: push khi job xong/hỏng; App đăng ký token chờ Flutter |
| OQ-16 | Section tóm tắt theo chủ đề hay theo lượt nói? | S4 | **CHƯA CHỐT** — đang dùng mặc định tạm |
| OQ-17 | Home >100 note: bỏ paging (stream cắt 100) hay thêm "Load more" bằng `listMinutes(cursor)`? | S5 | **CHƯA CHỐT** — mặc định tạm: 100 note mới nhất (20-PARITY-APP Home #13) |
| OQ-18 | Hết credit khi transcribe: mở paywall thẳng (v2) hay dialog "Premium Required" trước (v1)? | S6 | **CHƯA CHỐT** — mặc định tạm: paywall thẳng (Processing #4) |
| OQ-19 | Xử lý xong: luôn nút "Show Results" (v2) hay tự chuyển sang summary cho premium/không ad (v1)? | S6 | **CHƯA CHỐT** — mặc định tạm: luôn nút (Processing #6) |
| OQ-20 | Feedback dialog: bản gọn `StyledDialog` (v2) hay port đủ v1 (footer email, snackbar cảm ơn)? | S7 | **CHƯA CHỐT** — mặc định tạm: bản gọn (Widget #12) |
| OQ-21 | Banner: chỉ tab Summary (RC mặc định) hay cả 3 tab như v1; anchored adaptive hay inline ≤60? Gate từ chối rewarded: im lặng hay toast? | S8 | **CHƯA CHỐT** — đổi được bằng Remote Config, không cần release (Ads #8/#12) |

---

### OQ-01 — Migrate dữ liệu người dùng từ v1 sang v2?

Cấu trúc v2 khác hẳn: `tags/{uid}/tagItems` → `users/{uid}/tags`,
`metadata/*` → `artifacts/*`, `duration:"15:00"` → `durationSeconds:900`,
`timeRange:"00:12 - 00:45"` → `startSeconds`/`endSeconds`, transcript từ doc ra
Storage, `credit` → `quota/{period}`.

Ba phương án:
- **A. Migrate toàn bộ** — script một lần + dual-read trong thời gian chuyển.
  Người dùng cũ không mất gì. Tốn khoảng 1–2 tuần và cần dry-run.
- **B. Không migrate** — v2 bắt đầu từ trắng, v1 còn sống read-only 90 ngày cho
  ai muốn xem lại note cũ. Rẻ nhất.
- **C. Migrate lười** — lần đầu user mở note cũ thì chuyển ngay lúc đó.

*Cần biết:* hiện có bao nhiêu user thật và bao nhiêu minute? Nếu dưới vài trăm,
phương án A là hiển nhiên; nếu con số nhỏ xíu thì B.

**Công cụ đã có (23/09):** `cd Backend/oneai_backend/functions-v2 && npm run build &&
GOOGLE_CLOUD_PROJECT=minutesai-6715a node tools/migrate-v1.mjs inventory` — chỉ đọc,
in ra số user / minute / minute có transcript / tag. Và `plan` (dry-run) / `apply`
cho phương án A, đã test chống emulator với dữ liệu hình v1. Chi phí phương án A
giờ gần bằng 0 — chỉ còn là chạy lệnh.

**Mặc định tạm:** B. → Ảnh hưởng: S3 và S9-03.

---

### OQ-02 — Hạn mức gói free

v1 tự mâu thuẫn: `checkUserCanUseCredit` chặn ở `dailyCreditUsed >= 3`, trong
khi `resetDailyFreeCredit` set cứng `credit: 1` mỗi đêm, nên nhánh 3/ngày không
bao giờ chạy tới. Và `credit` với `dailyCreditUsed` là hai hạn mức độc lập hay
hai cách nhìn của một thứ — code không nói rõ.

Cần chốt: **`baseLimit` mỗi ngày = ?** (v2 gộp về một khái niệm duy nhất).
Kèm theo: giới hạn 30 phút/file ở gói free có giữ không?

**Mặc định tạm:** `baseLimit: 1/ngày`, giữ cap 30 phút. → S7-01.

---

### OQ-03 — Credit thưởng (rewarded ad) có sống qua đêm?

Hiện tại **không**: `resetDailyFreeCredit` *gán* `credit: 1` chứ không *cộng
thêm*, nên mọi credit kiếm được từ xem quảng cáo bị xoá sạch lúc 00:00. Có thể
là bug, cũng có thể là chống farming có chủ ý.

Thiết kế v2 (`rewardBonus` trên document quota của ngày, có TTL) mặc định là
**hết ngày là hết** — giống hành vi hiện tại, nhưng lần này là cố ý.

**Mặc định tạm:** hết ngày là hết. → S7-01.

---

### OQ-04 — Premium có thực sự không giới hạn?

v1: premium bỏ qua cả credit gate lẫn cap 30 phút, và `plan` chỉ được sửa bởi
webhook — không có kiểm tra hạn lúc dùng. Một webhook `EXPIRATION` bị miss =
premium vĩnh viễn miễn phí.

v2 đã thêm `planExpiresAt` và kiểm tra lúc dùng (S7-03). Còn lại:
premium có trần mềm nào không (ví dụ 50 lượt/ngày, 4 tiếng audio/file) để chặn
lạm dụng và chặn hoá đơn LLM?

**Mặc định tạm:** premium = trần mềm 50 lượt/ngày + 4 giờ/file, vượt thì
`resource-exhausted` với thông điệp riêng. → S7-01, S7-03.

---

### OQ-05 — Sinh AI: một lượt lúc ingest hay lười theo yêu cầu?

v1 có **cả hai** mà không dùng cái nào trọn vẹn: `summarizeFromTranscriptFull.txt`
sinh mindmap + quiz + flashcards cùng summary và `upsertMinute` đã viết sẵn chỗ
lưu — nhưng **không file nào load prompt đó**. Thực tế mỗi tính năng có endpoint
lười riêng.

Đánh đổi thẳng: một lần `gpt-4o` lúc ingest (đắt hơn, chờ lâu hơn, nhưng mở tab
nào cũng có sẵn) so với bốn lần `gpt-4o-mini` khi cần (rẻ hơn nếu user không mở,
nhưng mỗi tab lần đầu phải chờ).

**Mặc định tạm:** lười (giữ hành vi hiện tại), có cache theo `sourceHash`. → S5-05, S5-09.

---

### OQ-06 — Giữ YouTube ingest? → ✅ **BỎ HẲN** (23/09/2026)

Đường cũ: scrape `y2mate.nu` / `d.mnuu.nu` qua SOCKS proxy có credential
**commit thẳng trong repo**, và `authDetector.js` **chạy JavaScript tải về từ
trang đó bằng module `vm` của Node** để giải mã khoá auth bị obfuscate qua ba
thế hệ. Vi phạm ToS của YouTube, phụ thuộc proxy, và là lỗ RCE.

**Quyết định của Toan: bỏ hẳn.** Không feature flag, không giữ code.

Đã làm 23/09:
- Gỡ credential hardcode khỏi `functions/utils/youtube_to_mp3.js:88,129`
  (thay bằng `process.env.PROXY || ''`).
- Gỡ route `/youtubeVideo` khỏi `App/oneai_v2`.
- Gỡ `PROXY` khỏi danh sách secret cần mang sang.
- Gỡ mọi task YouTube khỏi roadmap và contract.

**Còn lại cho Toan:** credential vẫn nằm trong git history, nên **huỷ nó ở phía
nhà cung cấp proxy** — đó là cách duy nhất làm nó thật sự vô hiệu. Host
`95.164.203.157:9822`.

v1 vẫn còn các file chết (`youtubeUtils.js`, `youtube_to_mp3.js`,
`authDetector.js`, `api/v1/youtube/`, `transcribeYoutube.js`); chúng biến mất
cùng v1 ở M7.

---

### OQ-07 — Có cần full-text search?

v1 "search" là prefix-range trên `title` cộng `orderBy("createdAt")` — Firestore
không cho phép kết hợp đó nên nó luôn ném, và lỗi bị nuốt thành "200 + danh sách
rỗng".

Phương án: (A) lọc client-side trên trang đã tải — đủ cho <200 note;
(B) Typesense/Algolia extension — thêm chi phí và hạ tầng;
(C) tìm trong nội dung transcript, không chỉ tiêu đề — cần (B).

**Mặc định tạm:** A. → S3-05.

---

### OQ-08 — Bật dark mode?

Bảng màu dark đã có đủ, `ThemeBloc` + `ThemeRepository` + `ThemeSelector` đã
viết xong, nhưng `main.dart` truyền `theme: lightTheme` cứng và không set
`darkTheme`/`themeMode`, còn `ThemeSelector` thì **không màn nào mount**. Nên
dark mode chưa từng chạy.

Bật lên là **đổi giao diện** — và 3 màn đang ép nền trắng cứng
(`record_audio`, `settings`, các bottom sheet) sẽ trông vỡ trong dark. Bật thì
phải kèm S8-05 (đưa màu hardcode về token), không thì nửa vời.

**Mặc định tạm:** giữ light-only. → S8-05.

---

### OQ-09 — Đăng ký font Roboto?

`pubspec.yaml` để `assets/fonts/` dưới `assets:` nhưng thiếu mục `fonts:`, nên
`fontFamily: 'Roboto'` rơi về font hệ thống. Trên iOS đó là SF Pro — và
`bodyMedium` đang set `letterSpacing: -0.41`, đúng là giá trị của SF Pro. Có
khả năng giao diện hiện tại **được thiết kế dựa trên SF Pro**, và đăng ký Roboto
sẽ làm mọi thứ xô lệch.

**Mặc định tạm:** không đăng ký; cân nhắc xoá 2 file `.ttf` chết. → S8.

---

### OQ-10 — Đổi `/transcriptionSummary` (extra) sang `/minutes/:minuteId` (path param)?

Hiện tại `state.extra as String` không có guard → crash khi deep link hoặc khi
hệ điều hành khôi phục app nguội. Skill cũng nói ID phải nằm trong path.

Nhưng đổi path là breaking cho mọi deep link / notification đã phát hành.

**Mặc định tạm:** S6 chỉ thêm guard + fallback `context.go('/')`; đổi path để
sau. → S6-07, S7 (nếu làm push).

---

### OQ-11 — Interstitial khi thoát summary bị bỏ ở nhánh Congratulation

Người dùng lần đầu (có dialog Congratulation) không thấy interstitial
`summary_exit`. Nhiều khả năng là quên chứ không phải cố ý.

Nhưng: chính sách AdMob khuyên **không** chèn interstitial vào khoảnh khắc ăn
mừng lần đầu — có khi vô tình lại đúng.

**Mặc định tạm:** giữ nguyên hành vi (không hiện), ghi rõ là có chủ đích. → S7-12.

---

### OQ-12 — Thêm tiếng Việt vào app?

Hiện chỉ `en` và `es`, mà `es` đã thiếu key so với `en`. Toan làm việc bằng
tiếng Việt và có thể nhắm thị trường VN.

**Mặc định tạm:** thêm `vi`, và dịch đủ `es`. → S8-07.

---

### OQ-13 — Giữ `contentKind` (enum do LLM đoán)?

v1 lưu nó vào field tên `contentType` (dễ nhầm với MIME) và không có nơi nào
trong app hiển thị. Nếu không dùng thì bỏ để tiết kiệm token.

**Mặc định tạm:** giữ, đổi tên thành `contentKind`. → S3-04.

---

### OQ-14 — Nguồn timezone: header hay body?

Server đọc `req.headers['X-Timezone']`, nhưng Node hạ chữ thường mọi header
name, nên biểu thức đó **luôn `undefined`** và rơi về `req.body.timezone` hoặc
mặc định `"GMT -7"`. App thì gửi `X-Timezone: <timeZoneName>` (ví dụ `+07`,
`ICT`) — không phải IANA id. Việc này âm thầm ảnh hưởng mọi `datetime` trong
`calendarEvents`.

**Mặc định tạm:** v2 nhận `timezone` là IANA id (`"Asia/Ho_Chi_Minh"`) trong
body request, zod validate. Bỏ header. → S4.

---

### OQ-15 — Có làm push notification không?

"Transcribe xong rồi" là ứng viên rõ ràng cho push, nhất là khi pipeline v2 là
bất đồng bộ và user có thể thoát app. Skill `fcm-push-pro` đã có sẵn.

Chưa nằm trong roadmap. Nếu có thì thêm vào S8 (+1 tuần: token registry,
`onNoteReady` trigger, quyền, deep link).

**Chốt 23/09 (Toan yêu cầu):** làm. BE xong: `registerDevice`/`unregisterDevice`/
`updateNotificationPrefs`, push `minuteReady`/`minuteFailed` từ pipeline + reaper,
copy en/vi/es theo locale thiết bị, prune token chết. App: `PushRepository` +
`NotificationsController` viết sẵn (chưa compile). Còn phía Toan: upload APNs
key (.p8) vào Firebase console → Cloud Messaging; bật Push Notifications +
Background Modes › Remote notifications trong Xcode; Android không cần gì thêm.

---

### OQ-16 — Section của summary: theo chủ đề hay theo lượt nói?

Prompt v1 nói *"mỗi section tương ứng đúng một transcript segment"* — tức mỗi
lượt nói (speaker turn) là một section. Một buổi họp 1 tiếng có thể có 300
lượt nói, ra 300 section, mỗi section vài chữ. `MinuteSectionWidget` ở app chỉ
hiển thị title + bullets, không hiện timeRange, nên section kiểu đó không gắn
được với transcript và cũng không đọc nổi.

Prompt v2 (`src/prompts/summarize.ts`) chuyển sang **section theo chủ đề**:
section đầu là Overview, rồi mỗi chủ đề một section theo thứ tự xuất hiện.
Đây là hành vi tóm tắt chuẩn, nhưng là thay đổi so với bản cũ.

**Mặc định tạm:** theo chủ đề. Nếu Toan muốn giữ per-turn để làm tính năng
"nhảy tới đoạn transcript", nói lại — khi đó cần thêm `segmentIndex` vào
section và sửa prompt. → S4-08.

---

### OQ-17 → OQ-21 — Lệch parity app cần quyết (từ `20-PARITY-APP.md`)

Mỗi mục đều đã có **mặc định tạm** đang chạy trong code; Toan chỉ cần trả lời
"giữ" hay "đổi về v1". Chi tiết từng mục ở `20-PARITY-APP.md` mục "Cần Toan quyết".
OQ-21 (banner placement/size, toast khi gate từ chối) chỉ là tham số `ads_config`
trong Remote Config → đổi lúc nào cũng được, không chặn release.
