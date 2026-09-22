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
| OQ-12 | Thêm tiếng Việt? | S8 | **CHƯA CHỐT** |
| OQ-13 | Giữ `contentKind` do LLM đoán? | S3 | **CHƯA CHỐT** |
| OQ-14 | Nguồn timezone: header hay body? | S4 | **CHƯA CHỐT** |
| OQ-15 | Có làm push notification? | S8 | **CHƯA CHỐT** |

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

**Mặc định tạm:** không làm ở v1.0 của v2. → S8.
