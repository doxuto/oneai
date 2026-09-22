# 10 — Backlog (epic → story)

> ⚠️ Mã sprint (S3-05, S7-12…) trong file này là của **roadmap bản 1**.
> `09-ROADMAP.md` đã được đánh số lại cho hướng build-lại-từ-đầu.
> Tra cứu theo tên task, đừng theo mã.


Góc nhìn theo sản phẩm. Góc nhìn theo thời gian ở `09-ROADMAP.md`; mỗi story
đều trỏ về sprint và task ID ở đó.

Ưu tiên: **P0** chặn phát hành · **P1** cần cho v1.0 · **P2** sau phát hành.

---

## E1 — Hạ tầng backend v2 (P0)

| Story | Ai | Sprint |
|---|---|---|
| Là dev, tôi cần một codebase TS deploy được mà không đụng v1, để hỏng cái mới không làm chết cái đang chạy | dev | S1-01..03 |
| Là dev, tôi cần `parse()`, `mapError()`, `logger` dùng chung, để mọi callable hành xử giống nhau | dev | S1-05..07 |
| Là dev, tôi cần secret qua `defineSecret`, để `functions.config()` (bị gỡ từ 03/2026) không làm hỏng deploy | dev | S1-08 |
| Là dev, tôi cần emulator + seed, để test không cần project thật | dev | S1-11 |
| Là chủ sản phẩm, tôi cần App Check, để API không bị gọi từ ngoài app | PO | S1-12, S9-04 |

## E2 — Vòng đời note (P0)

| Story | Ai | Sprint |
|---|---|---|
| Là người dùng, tôi muốn xem danh sách note của mình, phân trang mượt | user | S3-05 |
| Là người dùng, tôi muốn mở một note và thấy summary + transcript | user | S3-06 |
| Là người dùng, tôi muốn sửa tiêu đề, đổi emoji, gắn tag | user | S3-07 |
| Là người dùng, tôi muốn xoá note và mọi file của nó | user | S3-08 |
| Là người dùng, tôi muốn note mới xuất hiện ngay mà không cần kéo refresh | user | S6-08 |
| Là chủ sản phẩm, tôi cần không ai đọc được note của người khác | PO | S3-01, S3-06 |

## E3 — Transcribe (P0)

| Story | Ai | Sprint |
|---|---|---|
| Là người dùng, tôi muốn ghi âm rồi nhận transcript + summary | user | S4-01..07 |
| Là người dùng, tôi muốn upload file audio có thanh tiến trình **thật** và huỷ được | user | S6-06 |
| Là người dùng, tôi muốn tóm tắt PDF | user | S4-06, S4-10 |
| Là người dùng, tôi muốn thoát app trong lúc xử lý mà vẫn không mất kết quả | user | S4-02, S6-07 |
| Là người dùng, tôi muốn biết vì sao nó hỏng, không phải một thông báo chung chung | user | S4-08 |
| Là chủ sản phẩm, tôi cần file 100MB không làm chết function | PO | S4-02 |

> YouTube ingest đã bỏ hẳn (OQ-06, 23/09) — không còn story nào cho nó.
| Là chủ sản phẩm, tôi cần job hỏng thì hoàn credit | PO | S4-08 |

## E4 — Tính năng AI (P0/P1)

| Story | Ưu tiên | Sprint |
|---|---|---|
| Chat với note, chữ chạy dần | P0 | S5-03, S6-09 |
| Lịch sử chat còn nguyên sau khi thoát app | P1 | S5-04 |
| Câu hỏi gợi ý | P1 | S5-05 |
| Quiz / flashcards / mindmap | P1 | S5-05 |
| Nhận diện và đổi tên người nói | P1 | S5-06 |
| Rút sự kiện lịch từ nội dung | P2 | S5-07 |
| Không bao giờ cache một lần sinh thất bại | P0 | S5-05 |

## E5 — Tag & tổ chức (P1)

CRUD tag, lọc theo tag, đếm số note mỗi tag, xoá tag thì gỡ khỏi mọi note.
→ S3-09, S3-10. Tìm kiếm: OQ-07.

## E6 — Tài khoản & quota (P0)

| Story | Sprint |
|---|---|
| Đăng nhập Google / Apple | có sẵn |
| Xem hạn mức còn lại và giờ reset | S7-01 |
| Xoá tài khoản và toàn bộ dữ liệu | S1-10 |
| Quota trừ trong transaction, không race | S4-01 |
| Premium không bị mất khi một webhook lỡ | S7-02, S7-03 |
| Không ai tự cộng credit cho mình được | S7-04, S7-05 |

## E7 — Monetization (P0)

| Story | Sprint |
|---|---|
| Xem quảng cáo có thưởng để lấy thêm lượt, credit do **server** cộng | S7-05, S7-06 |
| Gate quảng cáo thuần, test được, phủ đủ 12 lý do từ chối | S7-07 |
| Một key `ads_config`, mặc định an toàn (ads off) | S7-08 |
| UMP consent đúng chuẩn GDPR, ATT sau UMP trên iOS | S7-09 |
| Quảng cáo không bao giờ chặn màn hình hay làm chậm mở app | S7-10, S7-11 |
| Native ad trong danh sách note | S7-14 |
| Mua premium qua RevenueCat | có sẵn, làm cứng ở S7-02 |

## E8 — Chất lượng App (P0/P1)

| Story | Ưu tiên | Sprint |
|---|---|---|
| Giao diện không xê dịch sau rework — golden test | P0 | S2-01, S6-13 |
| Xoá toàn bộ demo scaffolding | P1 | S8-01 |
| Mọi chuỗi đi qua l10n | P1 | S8-06 |
| Tiếng Việt + hoàn thiện tiếng Tây Ban Nha | P1 | S8-07 |
| Màu đi qua token thay vì hardcode | P2 | S8-05 |
| Accessibility AA | P1 | S8-09 |
| Cold start < 2s | P1 | S8-10 |
| Integration test luồng chính | P0 | S8-11 |

## E9 — Vận hành (P0)

Staging env (S0-06) · load test (S9-02) · alert (S9-05) · runbook + rollback
(S9-06) · phased rollout (S9-11) · gỡ v1 (S9-13).

## E10 — Sau phát hành (P2)

Push khi transcribe xong (OQ-15) · full-text search (OQ-07) · dark mode (OQ-08) ·
chia sẻ / cộng tác note · widget iOS · Apple Watch · xuất sang Notion/Docs ·
nhiều ngôn ngữ transcript hơn.

---

## Nợ kỹ thuật đã xác định

Nguồn: `01-AUDIT-BACKEND-V1.md` §6 và `02-AUDIT-APP.md` §8.

### Backend — được giải quyết bằng chính việc viết lại

| Vấn đề | Cách xử lý |
|---|---|
| `ai.service.js` dùng ESM trong package CJS ⇒ **cả function `api` chết khi load** | v2 là TS thuần |
| Prompt load bằng path tương đối CWD | `__dirname` — S4-05 |
| `summarizeFromText` thay sai biến ⇒ PDF chưa từng tóm tắt đúng | S4-06 |
| `errorResponse(res, msg)` gọi sai chữ ký ở **10 chỗ** ⇒ request treo tới hết timeout | `HttpsError` |
| `transcribeYoutube` đọc `req.file.buffer` trên route JSON ⇒ luôn 500 sau khi đã tải MP3 | viết lại |
| TOCTOU credit, trừ sau khi đã trả tiền vendor | S4-01 |
| `postReward` read-modify-write | xoá hẳn — S7-04 |
| Webhook RevenueCat: `Bearer undefined` lọt khi secret chưa set | S7-02 |
| 512MiB ôm buffer 200MB; `Buffer.concat` O(n²); busboy `limit` không bắt ⇒ file bị cắt âm thầm rồi vẫn transcribe | S4-02 + upload trực tiếp |
| axios timeout 300s/600s trong function 240s | S4-03 |
| Nuốt lỗi khắp nơi, đỉnh điểm: thiếu index ⇒ **HTTP 200 + danh sách rỗng** | S3-05, S5-05 |
| Không có index, không có `firestore.indexes.json` | S3-02 |
| Code chết: `utils/firestore.js`, `utils/openai.js` (401 dòng comment hết), `youtubeUtils.js`, `speechScheduler.js` + cả `speech.service.js` 242 dòng không ai gọi tới | không port sang v2 |
| `package.json` khai `busy` nhưng code dùng `busboy`; `form-data` dùng mà không khai; `firebase-functions-test` nằm trong `dependencies` | v2 dependency sạch |
| Log cả prompt, transcript, nội dung PDF vào Cloud Logging | S1-07 |

### App

| Vấn đề | Sprint |
|---|---|
| `currentUser!` không guard ⇒ crash khi hết session | S6-02 |
| `state.extra as String` không guard ⇒ crash khi deep link | S6-07 / OQ-10 |
| Log ID token + full response body ở mức INFO | S0-09 |
| Thanh tiến trình giả, tự báo lỗi sau ~250s, nút đóng không huỷ upload | S6-07 |
| Nuốt lỗi đăng nhập (`catch (e) { return null; }`) | S6 |
| 2 test có sẵn đều hỏng; ngoài ra không có test nào | S2-03 |
| Cây `demo/` vẫn ship, 5 route, 3 provider | S8-01 |
| `Minute` vs `MeetingMinute` trùng vai | S6-10 |
| 2 file `language_selector.dart` trùng tên class | S8-03 |
| Dialog xác nhận copy-paste ≥8 lần | S8-04 |
| Xanh viết bằng 4 literal khác nhau, không lấy từ theme | S8-05 |
| ~35 nhóm chuỗi tiếng Anh cứng, trong khi ARB đã có 349 entry | S8-06 |
| Dark theme là code chết | OQ-08 |
| Font Roboto không được đăng ký | OQ-09 |
| Ads chặn first paint **hai lần** | S7-11 |
| `ad_banner_refresh_rate_seconds` đọc mà không ai dùng | S7-13 |
| `_loadAd` gọi `setState` từ trong `LayoutBuilder.builder` | S7 |
| Không có UMP | S7-09 |
| Package name vẫn là `codebase_ai` | S8-08 |
| Không tách môi trường — `providersRemote` và `providersLocal` giống hệt nhau | S0-07 |
