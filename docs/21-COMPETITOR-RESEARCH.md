# 21 — Nghiên cứu đối thủ & thị trường (09/2026) → bổ sung roadmap

Ngày 24/09/2026. Bổ sung cho `17-FEATURE-RESEARCH.md` (use case) bằng góc nhìn
**đối thủ đang làm gì, thu tiền thế nào, người dùng than gì**. Nguồn ở §7, đều
đọc ngày 23–24/09/2026; mục (u) = chưa xác minh trên trang nhà cung cấp.

## 1. Bức tranh 30 giây

- Thị trường tách 3 nhóm: **họp** (Otter, Notta, Fireflies, Plaud, Fathom, tl;dv,
  Krisp, Granola), **học** (Turbo AI, Knowt, Coconote, StudyFetch, Mindgrasp,
  Quizlet), **ghi chú giọng nói cá nhân** (Voicenotes, AudioPen, Cleft). Không ai
  làm tốt **cả họp lẫn bài giảng trong một app** — đúng vị trí One AI đang đứng.
- **Nền tảng** (Apple Notes/Phone iOS 18–26, Google Recorder, Samsung Transcript
  Assist, Microsoft Copilot Record) đã cho miễn phí "ghi → transcript → tóm tắt"
  tiếng Anh, nhưng: Apple **không có tiếng Việt**, Google chỉ có VI qua cloud trên
  Pixel, Samsung chỉ Galaxy, Copilot chỉ doanh nghiệp có license. Không ai có
  speaker + action items + quiz/flashcard + đồng bộ iOS↔Android.
- **Không đối thủ nào dùng quảng cáo / rewarded ad** để cấp phút miễn phí — mô hình
  free-with-ads + rewarded credit của One AI là đất trống (nhưng eCPM VN thấp, §4).
- Than phiền lớn nhất toàn ngành 2026: (1) **hạn mức free ẩn / trải nghiệm "đụng
  tường"** (Notta 3 phút/bản ghi, Granola khoá lịch sử 30 ngày, Fathom ~5 tóm tắt),
  (2) **đoán sai người nói** khi >3 người / ồn, (3) **ghi âm bị ngắt** bởi cuộc
  gọi/khoá màn, mất bản ghi, (4) bị trừ tiền sau trial, hỗ trợ chậm, (5) consent
  (Otter, Granola bị kiện tập thể vì bot tự vào họp / ghi không xin phép).

## 2. Đối thủ họp — bảng rút gọn

| | Ghi trên mobile | Import | Live | Speaker | Action items | Chat 1 note | Hỏi xuyên note | Template | Share link | Dịch | Offline | Free | Giá (tháng / năm-quy-tháng) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Otter | ✔ | 3 file trọn đời (free) | ✔ | ✔ | ✔ | 20 câu/th | Pro+ | ✔ | ✔ | ✘ mobile (u) | ✘ | 300 ph/th, 30 ph/bản | $16.99 / $8.33 |
| Notta | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ (Brain) | ✔ | ✔ | Pro | ✘ | 120 ph/th, **3 ph/bản** | $9.99–13.99 / $8.17 |
| Fireflies | ✔ | ✔ | ✔ | ✔ | ✔ | AskFred | ✔ | 100+ app | ✔ | Pro+ | ✘ | "không giới hạn", 400 ph lưu, 20 credit AI | $18 / $10 |
| Plaud | ✔ (+ thiết bị) | ✔ | sau sync | ✔ | ✔ | Pro+ | ✔ + Memory (07/2026) | 10.000+ | ✔ có hạn | ✔ | thiết bị | 300 ph/th | $17.99 / $8.33; phần cứng $110–189 |
| Fathom | app iOS "coming soon" | ✘ | desktop | ✔ | ✔ | ✔ | Business | ✔ | ✔ | ✔ | ✘ | không giới hạn ghi, ~5 tóm tắt/th (u) | $20 / $16 |
| tl;dv | ✔ (chỉ ghi) | web | ✘ | ✔ | ✔ | web | Pro+ | ✔ | ✔ | 30+ | 5 bản ghi | ~10 tóm tắt trọn đời | $29 / $18 |
| Krisp | ✔ | (u) | ✔ 17 ngôn ngữ | ✔ | ✔ | ✔ | ✔ | theo loại họp | ✔ | ✔ | on-device EN (Ent) | trial 7 ngày | $16 / $8 |
| Granola | iOS (Android 07/2026 u) | ✘ | ẩn | yếu | ✔ | free hạn chế | ✔ | ✔ | ✔ | 10–17 ngôn ngữ | ✘ | không giới hạn, **lịch sử 30 ngày** | $14 (chỉ tháng) |
| Cleft | ✔ Apple | share sheet | on-device | ✘ | style | ✘ | ✘ | 3 style | ✔ | ✘ | **✔ on-device** | 5 ph/bản | $6.99 / $3.33 |
| Voicenotes | ✔ | Pro | Pro | — | — | ✔ | **✔ mọi note** + MCP | — | ✔ | 100+ | ghi offline | 100 ph/tuần, lịch sử 30 ngày | $9; IAP $8.99/tuần, $14.99/th, $89.99/năm |

Xu hướng 2025–26 nhóm dẫn đầu: **hỏi xuyên mọi note có trích dẫn + "memory" về
user** (Plaud Memory, Otter Knowledge Engine 04/2026, Fireflies AskFred, Zoom
ZoomMate), **MCP/connector** ra LLM ngoài (Fathom, Otter, Plaud), **agent** (Otter
Meeting Agent, Fireflies Voice Agents 09/2026), thư viện template khổng lồ, bán
**phần cứng** (Plaud 1,5 triệu máy, Notta Memo 02/2026), **credit theo lượt** chồng
lên subscription (Fireflies, Zoom). Tất cả đều đã bỏ bot, chuyển sang "bot-free
desktop capture" trong 2025–26.

## 3. Đối thủ học tập — bảng rút gọn

| | Nền tảng | Ghi lecture | Import | Chương | Quiz/FC | Spaced rep | Hỏi xuyên | Dịch | Free | Giá | Rating |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Turbo AI (Turbolearn) | iOS/Android/web | ✔ | audio, PDF, PPT, web, YouTube | mốc thời gian | ✔ | ✘ | theo note | 30+ | ~2 bản ghi rồi paywall (không công bố) | $9.99/tuần, $19.99/th, $69.99–119.99/năm | 4.7 (33K), #44 Education |
| Knowt | iOS/Android/web | ✔ | PDF, ảnh, video, PPT, audio, YouTube | ✘ | ✔ | **✔ free** | theo lecture | ? | flashcard thủ công không giới hạn; **1 tóm tắt AI/th** | $24.99/th, $149.99/năm | 4.7 (11K) |
| Coconote | iOS/Android/web/Mac/Watch | ✔ | audio, PDF (trả phí), YouTube, slide | ✔ | ✔ + podcast, game | ✘ | theo note | 33 | vài bản ghi | $9.99/tuần, $19.99/th, $99.99–129.99/năm | 4.8 (17K) |
| StudyFetch | iOS/Android/web | ✔ (1 người nói) | PDF, YouTube, audio | ✘ | ✔ | ✔ | Spark.E | 20+ | ~2 bản ghi | $19.99/th, $96/năm | 4.8 (14K) |
| Mindgrasp | web/iOS | ✔ 5–10 h/th | audio, PDF, YouTube, LMS | ✘ | ✔ | ✘ | theo doc | 30+ | **không có**, trial cần thẻ | $9.99–14.99/th | Trustpilot 2.0 |
| Quizlet | tất cả | ✘ | text, ảnh | ✘ | ✔ lõi | ✔ (trả phí) | Q-Chat | UI | ads, giới hạn vòng | $7.99/th, $35.99/năm | Play 4.7 (905K) |

Nhận xét: app học **không có** output họp (decision/owner/due), app họp **không
có** quiz/flashcard. Spaced repetition chỉ Knowt/Quizlet/StudyFetch có. Chương
theo thời gian chỉ Coconote. **Không app nào quảng bá độ chính xác tiếng Việt.**

## 4. Kiếm tiền — số liệu để chốt OQ-02/03/04 và S8

- **Giá App Store phổ biến 09/2026**: tuần $5.99–9.99 · tháng $12.99–24.99 · năm
  $44.99–149.99. RevenueCat Education median: tuần $4.99, tháng $9.99, năm $44.99
  (cao nhất mọi ngành). One AI hiện chưa có gói tuần — **thêm gói tuần** cho mùa thi
  (Turbo/Knowt/Coconote đều có).
- **Chuyển đổi** (RevenueCat 2026): tải→trial 6.5%, tải→trả ~2%; hard paywall
  trial→trả 10.7% vs freemium 2.1%; trial 17–32 ngày chuyển 42.5% vs trial <4 ngày
  25.5%; 55% huỷ trial 3 ngày xảy ra ngay ngày 0; gói năm mất ~35% trong tháng đầu;
  **31% huỷ trên Google Play là lỗi thanh toán** (rất liên quan VN → bật grace
  period + account hold); chỉ ~10% app chạy thật sự hybrid ads+subs.
- **Rewarded eCPM (AdMob 06/2026)**: US $14–22, **VN/ID/IN/PH $2–3**; interstitial VN
  $1–2; banner VN $0.06–0.14. Một lượt rewarded ở VN ≈ $0.002–0.003, trong khi 10
  phút STT cloud ≈ $0.01–0.06 → **rewarded không bù được chi phí STT ở VN**; phải
  coi rewarded là đòn bẩy giữ chân/thói quen, cấp credit nhỏ, cap/ngày, và kiếm
  tiền thật từ (a) traffic Tier-1 qua ads, (b) subscription giá địa phương ở VN.
- **Free tier trong ngành**: phút/tháng (Otter 300, Notta 120, Voicenotes 100/tuần),
  trần/bản ghi (Otter 30 ph, Notta 3 ph, Cleft 5 ph, Audionotes 1 ph), số output
  (Knowt 1 tóm tắt/th, tl;dv 10 trọn đời). One AI: 1 credit/ngày + 30 ph/bản +
  30 AI call/ngày — **rộng hơn Notta/Knowt**, và quan trọng hơn: phải **hiển thị
  hạn mức trước khi user đụng tường** (than phiền số 1 của ngành).

## 5. Đối chiếu với One AI v2 — có gì, thiếu gì

| Hạng mục | Ngành 2026 | One AI v2 (24/09) | Kết luận |
|---|---|---|---|
| Ghi trên mobile, import audio/PDF, speaker, summary, action items, chat 1 note, share link, export, template | table stakes | ✔ tất cả (A1–A6, S11-05/08) | đủ |
| Chapters, key terms, quiz, flashcard, SM-2 | chỉ app học, rời rạc | ✔ (S4-09, S11-03) | **lợi thế**: họp + học trong một app |
| Dịch summary/transcript | Pro ở đa số | ✔ (S11-04) | đủ |
| Offline recording + tự upload | hầu như không ai (Cleft on-device, tl;dv 5 bản) | ✔ hàng đợi (S11-07) | lợi thế nhỏ, cần **chống ngắt** (§6 #2) |
| Hỏi xuyên mọi note có trích dẫn | leaders 2026 | ✘ (S11-01 chưa làm) | **ưu tiên lên đầu S11** |
| Memory / cá nhân hoá (tên gọi, thuật ngữ của tôi) | Plaud, Otter | ✘ | glossary (§6 #3) |
| Live transcript khi đang ghi | phần lớn app họp có | ✘ (S12-01) | giữ S12; làm "draft on-device" trước (§6 #9) |
| Hiển thị hạn mức còn lại, paywall minh bạch | ai cũng bị chê | ✘ | **rẻ, làm ngay** (§6 #1) |
| Gói tuần, trial 7–14 ngày, giá VN, grace period | chuẩn Education | chưa cấu hình | RevenueCat + store (§6 #5) |
| Consent / thẻ thông báo ghi âm, on-device badge | đang thành vấn đề pháp lý | ✘ | (§6 #4) |
| Bilingual (transcript VI, note EN hoặc ngược lại) | Turbo chê vì đơn ngữ | một phần (`summaryLanguage` ≠ audio) | thêm toggle ở note (§6 #6) |
| MCP / connector ra Notion, Google Docs | Fathom, Otter, Plaud, Voicenotes | share sheet thôi | S12 |
| Đồng bộ slide ↔ mốc thời gian lecture | chỉ Notability/Goodnotes, không VI | ✘ | S12 |
| Ads (banner/interstitial/app-open) | **không ai** | ✔ (A6) | giữ; **rewarded đã bỏ 24/09** theo đúng kết luận §4 (eCPM VN không bù STT) — free = 10 phút/ngày cố định |

## 6. Việc bổ sung vào roadmap (theo thứ tự ưu tiên)

1. **Hạn mức minh bạch** (S6/A7): số phút/credit còn lại ngay trên nút Ghi và
   trong sheet tạo note; paywall và store listing nêu rõ hạn mức free; thông báo
   trước khi chạm trần (ví dụ còn 5 phút). BE đã có `quota` + `maxDurationSeconds`.
2. **Ghi âm chống ngắt** (A7): ghi theo từng đoạn (chunk) ghi thẳng xuống đĩa,
   tự tiếp tục sau cuộc gọi/ngắt audio session, foreground service Android với
   notification, khôi phục sau crash ("đã lưu N phút"), cảnh báo pin/dung lượng.
   Đây là than phiền #3 của ngành và là thứ Voice Memos cũng không làm.
3. **Glossary "sửa một lần, nhớ mãi"** (BE S4-11 + app): từ điển thuật ngữ theo
   user (tên người, tên sản phẩm, từ chuyên ngành) → đưa vào `keywords` khi STT và
   vào prompt summarize; sửa tên speaker/thuật ngữ trong transcript sẽ đề nghị
   thêm vào glossary. Rẻ vì `keywords`/`renameSpeaker` đã có.
4. **Consent & minh bạch dữ liệu** (A7): thẻ "Đang ghi âm — chia sẻ với người
   tham gia" (text/ảnh) 1 chạm, badge cloud/on-device, nêu rõ "không dùng để huấn
   luyện" trong onboarding + Privacy (`19-STORE-COMPLIANCE.md` §4 đã có).
5. **Gói & giá** (S8, RevenueCat — Toan cấu hình): thêm gói **tuần** (~$4.99 US),
   trial **7 ngày** cho gói năm, giá địa phương VN (tương đương 49–99k/th), bật
   grace period + account hold trên Play, gói năm là mặc định trên paywall.
   → chốt luôn OQ-02/03/04 với mặc định: free 1 credit/ngày + 30 ph/bản (giữ),
   credit thưởng **không** sống qua đêm (giống mọi đối thủ "minutes don't roll
   over"), premium 50 bản/ngày × 4 h (thực tế "không giới hạn").
6. **Song ngữ** (A7): toggle "hiện transcript VI + note EN" (hoặc ngược) ngay trong
   note; dùng `translate` (S11-04) đã có, không thêm BE.
7. **Hỏi xuyên mọi note** (S11-01/02): đẩy lên **đầu S11** — là tính năng phân biệt
   leaders với phần còn lại; kèm trích dẫn nhảy tới mốc audio.
8. **Import rộng hơn** (S11-06 mở rộng): Share Extension nhận file từ Zalo/Drive/
   Files/Voice Memos; Android intent `audio/*`, `application/pdf`.
9. **Draft STT on-device** (S12): Whisper-small/Gemini Nano tạo bản nháp ngay khi ghi
   (live-ish, offline), cloud "re-transcribe HD" là bước trả phí/rewarded — giải
   quyết cả live transcript lẫn chi phí rewarded ở VN.
10. **Đồng bộ slide** (S12): import PDF slide + audio, căn mốc thời gian theo trang.
11. **Connector** (S12): xuất thẳng Notion/Google Docs; MCP server đọc note (Fathom,
    Plaud, Voicenotes đã có).
12. **Benchmark tiếng Việt** (Ops, sau deploy dev): đo WER ElevenLabs vs Gemini trên
    10 file VI (bắc/trung/nam, lẫn thuật ngữ EN), chọn `STT_VENDOR` theo số đo;
    công bố "độ chính xác tiếng Việt" trên listing — không đối thủ nào làm.

Không làm: phần cứng (Plaud/Notta Memo), bot vào họp online (cả ngành đang bỏ),
agent tự hành động (chưa có user), team/workspace (S12, chỉ khi có tín hiệu).

## 7. Nguồn

Họp: otter.ai/pricing · otter.ai/blog (Meeting Agent 25/03/2025; Knowledge Engine
28/04/2026) · crowdverdict.ai/reviews/otter (19/08/2026) · notta.ai/en/pricing ·
finance.yahoo.com (Notta Memo 03/02/2026) · tinrec.com/en/blog/15699 (07/09/2026)
· plaud.ai/blogs/articles/notta-review (22/09/2026) · fireflies.ai/pricing ·
fireflies.ai/mobile · globenewswire (Fireflies Voice Agents 02/09/2026) ·
g2.com/products/fireflies-ai/reviews · plaud.ai/pages/plaud-ai-plan-pricing ·
plaud.ai/blogs/news/plaud-intelligence-3-0-launch (09/10/2025) ·
plaud.ai/pages/plaud-release-notes · techcrunch.com (Plaud 04/01/2026; Fathom
15/04/2026; Zoom 17/09/2025) · laxis.com/blog/plaud-note · fathom.ai/pricing ·
fathom.ai/ios-app · get-alfred.ai/blog/fathom-pricing · cleftnotes.com/pricing ·
claap.io/blog/tl-dv-pricing · intercom.help/tldv (mobile) · krisp.ai/pricing ·
krisp.ai/ai-meeting-assistant · g2.com/products/krisp/reviews · granola.ai/pricing
· usecarly.com/blog/granola-pricing (15/07/2026) · anarlog.so/blog/granola-ai-
complaints (30/08/2026) · support.microsoft.com (Record in Copilot, 18/08/2026) ·
zoom.us/pricing/aic.

Học & nền tảng: courseplatformsreview.com (Turbolearn 18/02/2026) ·
apps.apple.com (Turbo AI, Knowt, Coconote, StudyFetch, Voicenotes, Notewave) ·
help.knowt.com (free plan) · knowt.com/plans · rimo.app (Coconote 30/06/2026) ·
notegpt.io/pricing · notewise.dev/pricing · tldv.io/blog/studyfetch-review
(25/03/2026) · whisprinote.com (Mindgrasp) · turboscribe.ai/pricing ·
audionotes.app/pricing · nibble-app.com/blog/quizlet-cost (15/09/2026) ·
notion.com/help/ai-meeting-notes · macrumors.com (Notes transcription) ·
macobserver.com (ngôn ngữ call transcription, 27/09/2025) ·
support.google.com/pixelphone/answer/16267698 · 9to5google.com/guides/google-
recorder (17/08/2026) · samsung.com (Transcript Assist) · news.samsung.com
(10/04/2024) · androidheadlines.com (One UI 9 cloud STT, 10/07/2026) ·
voicenotes.com/pricing.

Tiền & chất lượng: revenuecat.com/state-of-subscription-apps-2026 (+ Education,
Productivity) · revenuelab.fyi/blog/admob-ecpm-benchmarks-2026 (17/06/2026) ·
business.mistplay.com/resources/rewarded-ads-stats · vexascribe.com/how-accurate-
is-whisper (25/08/2026) · blackboxrecorder.in (iOS recording interruption,
25/07/2026) · vbee.vn/blog (STT tiếng Việt, 30/03/2026).
