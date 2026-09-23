# 19 — Store listing, privacy labels, Data Safety, Terms/Privacy (S10-07, S10-08)

Ngày 23/09/2026. Chuẩn bị sẵn để khi build được (T1) là nộp được. Mọi mục
**[Toan]** là việc phải làm trong console/website, agent không làm được.
Nguồn sự thật về SDK: `App/oneai_v2/pubspec.yaml`; về dữ liệu server:
`06-DATA-MODEL-V2.md`, `05-API-CONTRACT-V2.md` §2.7b (retention).

## 1. Dữ liệu app thu thập — bảng gốc (dùng cho cả Apple lẫn Google)

| Dữ liệu | Ai thu | Mục đích | Liên kết danh tính | Dùng tracking | Bắt buộc/tuỳ chọn |
|---|---|---|---|---|---|
| Email, tên, ảnh đại diện (Google/Apple Sign-In) | Firebase Auth | Đăng nhập, quản lý tài khoản | Có | Không | Bắt buộc |
| **Audio ghi âm / file tải lên** | Firebase Storage → ElevenLabs hoặc Gemini (STT) | Chức năng chính (transcribe) | Có (uid) | Không | Bắt buộc để dùng tính năng |
| Transcript, summary, chat, artifact AI | Firestore; OpenAI/Gemini xử lý | Chức năng chính | Có | Không | — |
| Tài liệu PDF tải lên | Storage → Gemini | Chức năng chính | Có | Không | Tuỳ chọn |
| Lịch sử mua, trạng thái subscription | RevenueCat | Thanh toán, quyền premium | Có | Không | — |
| User ID (uid), device token push | Firebase (FCM), Firestore `devices/` | Thông báo "ghi chú xong" | Có | Không | Tuỳ chọn (xin quyền) |
| Crash log, thiết bị, OS | Sentry | Ổn định app | Không (`sendDefaultPii=false`) | Không | — |
| Advertising ID (IDFA/GAID), tương tác quảng cáo, thiết bị | Google Mobile Ads | Quảng cáo (chỉ free) | Có nếu user đồng ý ATT/UMP | **Có** (khi ATT cho phép) | — |
| Install attribution, IDFA/GAID, sự kiện app | AppsFlyer | Phân tích marketing | Có | **Có** (khi ATT cho phép) | — |
| Usage events (màn hình, sự kiện) | Firebase Analytics | Phân tích sản phẩm | Có (uid) | Không | — |
| Tên tag, tiêu đề note, ngôn ngữ, múi giờ | Firestore | Chức năng | Có | Không | — |

**Không thu:** vị trí, danh bạ, ảnh, sức khoẻ, dữ liệu tài chính (RevenueCat/Apple/Google giữ thẻ), tin nhắn.

Lưu ý quan trọng cho cả hai form: audio và transcript là **User Content** (Apple) /
**Audio files** + **Other user-generated content** (Google) — phải khai, và
khai rõ có gửi cho bên xử lý thứ ba (ElevenLabs/Google/OpenAI).

## 2. App Store — Privacy Nutrition Labels (App Privacy)

Khai theo nhóm Apple, dựa trên §1. **[Toan]** điền trong App Store Connect → App Privacy.

| Nhóm Apple | Loại | Dùng cho | Linked to user | Tracking |
|---|---|---|---|---|
| Contact Info | Email Address, Name | App Functionality | ✔ | ✘ |
| User Content | **Audio Data**, Other User Content (transcript/notes/chat), Photos or Videos ✘ | App Functionality | ✔ | ✘ |
| Identifiers | User ID | App Functionality, Analytics | ✔ | ✘ |
| Identifiers | Device ID (IDFA qua GMA + AppsFlyer) | Third-Party Advertising, Analytics | ✔ | **✔** |
| Purchases | Purchase History | App Functionality | ✔ | ✘ |
| Usage Data | Product Interaction, Advertising Data | Analytics, Third-Party Advertising | ✔ | ✔ (Advertising Data) |
| Diagnostics | Crash Data, Performance Data | App Functionality | ✘ | ✘ |

- Vì có Tracking = ✔ → app **phải** hiện ATT prompt (đã có: `ConsentGate`, sau UMP) và
  `NSUserTrackingUsageDescription` (PLATFORM-SETUP.md). Nếu Toan muốn tránh nhãn
  Tracking: tắt AppsFlyer + bật `MobileAds` ở chế độ non-personalized — quyết định
  ở OQ mới, mặc định giữ như v1.
- Apple 5.1.1(v) **xoá tài khoản trong app**: đã có (Settings → Delete account →
  `deleteAccount` callable → `onUserDeleted` dọn sạch). Ghi vào Review Notes.
- Review Notes nên kèm: tài khoản test (Google), 1 file audio mẫu ngắn, giải thích
  gói free = 10 phút audio/ngày, không có rewarded ad (24/09).
- Export compliance: chỉ dùng HTTPS chuẩn → `ITSAppUsesNonExemptEncryption = false`.

## 3. Google Play — Data safety form

**[Toan]** Play Console → App content → Data safety. Trả lời:

- Thu thập hay chia sẻ dữ liệu người dùng: **Có**.
- Mã hoá khi truyền: **Có** (TLS). Cho phép yêu cầu xoá: **Có** (xoá tài khoản trong app + email `contact@doxutostudio.top`).
- Theo nhóm:

| Nhóm Play | Loại | Thu thập | Chia sẻ | Mục đích |
|---|---|---|---|---|
| Personal info | Name, Email address, User IDs | ✔ | ✘ | Account management, App functionality |
| Audio files | Voice or sound recordings | ✔ | **✔** (STT provider) | App functionality |
| Files and docs | Files and docs (PDF) | ✔ | ✔ (LLM provider) | App functionality |
| Messages | Other in-app messages (chat với AI) | ✔ | ✔ (LLM provider) | App functionality |
| Financial info | Purchase history | ✔ | ✘ | App functionality |
| App activity | App interactions, Other user-generated content | ✔ | ✔ (AppsFlyer) | Analytics, Advertising |
| App info and performance | Crash logs, Diagnostics | ✔ | ✘ | Analytics |
| Device or other IDs | Device or other IDs (GAID) | ✔ | ✔ (Google Ads, AppsFlyer) | Advertising, Analytics |

- Families policy: **không** nhắm trẻ em → target audience 18+ (v1 cũng vậy).
- Ads declaration: **Có quảng cáo** (AdMob). Kèm `AD_ID` permission (GMA tự thêm).
- Account deletion URL (bắt buộc từ 2024): đã có sẵn ở function `legal`:
  `https://asia-southeast1-<project>.cloudfunctions.net/legal?doc=delete-account&lang=en`
  (nội dung §5, EN + VI). Trỏ `doxutostudio.top/delete-account` về đó nếu muốn domain riêng.

## 4. Terms & Privacy — điều khoản phải có (S10-07, C6)

✅ **Đã viết EN + VI** trong `functions-v2/assets/legal/` và phục vụ tại
`…/legal?doc=privacy|terms&lang=en|vi`; app mở đúng ngôn ngữ máy. **[Toan]** rà lại nội
dung (tên pháp nhân, luật áp dụng, tuổi tối thiểu) rồi trỏ domain hoặc copy lên web.
Danh sách điều khoản dưới đây là checklist đã được phủ:

1. **Dữ liệu thu thập** — bảng §1 diễn giải thành văn.
2. **Bên xử lý thứ ba** — liệt kê đích danh: Google (Firebase, Gemini, AdMob),
   ElevenLabs (STT), OpenAI (LLM), RevenueCat (thanh toán), AppsFlyer (attribution),
   Sentry (crash). Nêu rõ audio/transcript được gửi đến nhà cung cấp STT/LLM để xử
   lý và **không dùng để huấn luyện** (đúng với điều khoản API của họ — Toan xác nhận
   lại bản hiện hành).
3. **Lưu trữ & thời hạn** — audio gốc: 7 ngày (free) / 90 ngày (premium) rồi tự xoá
   (`FREE/PREMIUM_SOURCE_RETENTION_DAYS`); transcript/summary giữ đến khi user xoá note
   hoặc tài khoản; xoá tài khoản → xoá toàn bộ trong 30 ngày (thực tế: ngay qua
   `onUserDeleted`). Nếu Toan đổi tham số retention thì sửa trang này.
4. **Quảng cáo & consent** — UMP/GDPR cho EEA/UK, CCPA "Do not sell", ATT trên iOS; user
   đổi lựa chọn ở Settings → Privacy options. Quảng cáo chỉ hiển thị (banner/interstitial/app-open); không có ad đổi lấy phút.
5. **Thanh toán** — subscription qua App Store/Google Play, tự gia hạn, huỷ ở store;
   RevenueCat xử lý biên lai.
6. **Quyền của người dùng** — xem/xuất (share Markdown/PDF trong app), xoá (trong app),
   liên hệ `contact@doxutostudio.top`.
7. **Trẻ em** — không dành cho dưới 18 (hoặc 13 nếu Toan muốn hạ; khi đó cần
   COPPA-safe ads → `tagForChildDirectedTreatment`; **không khuyến nghị**).
8. **Thay đổi điều khoản, luật áp dụng, ngày hiệu lực.**

## 5. Trang "Xoá tài khoản" (Play yêu cầu)

Nội dung tối thiểu: (a) mở app → Settings → Delete account → xác nhận; (b) không
còn app: gửi email từ địa chỉ đã đăng ký tới `contact@doxutostudio.top`, xử lý trong
30 ngày; (c) dữ liệu bị xoá: tài khoản, note, audio, transcript, lịch sử chat, token
thiết bị; dữ liệu giữ lại: biên lai mua hàng (nghĩa vụ kế toán) — theo store.

## 6. Listing (giữ tên v1)

- Tên: `One AI: AI Note Taker & Scribe` (`AppConfig.appName`), tên ngắn `One AI`.
- Subtitle (iOS, ≤30): `Transcribe, summarize, ask AI`.
- Mô tả: viết từ use-case matrix `17-FEATURE-RESEARCH.md` §1 — họp (action items,
  decisions, calendar events) và bài giảng (chapters, key terms, quiz, flashcards);
  nêu rõ "audio processed by AI providers", "10 free minutes every day, unlimited with Premium".
- Từ khoá iOS (≤100 ký tự): `transcribe,meeting notes,lecture,summary,ai notes,voice memo,speech to text,study`.
- Ảnh: Login, Home, Record, Summary (3 tab), Study tools — chụp từ golden (A6-07).
- Rating: 4+ (iOS) / Everyone (Play) nhưng target 18+ vì có quảng cáo cá nhân hoá.
- Bản dịch listing: en, vi, es (đúng 3 ngôn ngữ app).

## 7. Checklist nộp

- [ ] T1/T2 build xanh; golden ≥30 (A6-07).
- [ ] PLATFORM-SETUP.md áp xong: `GADApplicationIdentifier`, `SKAdNetworkItems`, ATT string, mic string, Push capability (T8).
- [ ] App Privacy (§2) và Data safety (§3) điền đúng bảng §1.
- [ ] Privacy/Terms/Delete-account pages live (§4, §5); link trong Settings trỏ đúng (`AppConfig.privacyUrl/termsUrl`).
- [ ] AdMob: app-ads.txt trên `doxutostudio.top` (rewarded unit không dùng nữa — có thể tắt trong console).
- [ ] RevenueCat: products/entitlement `pro` khớp 2 store; sandbox test mua + restore.
- [ ] App Check enforce (S10-04) **sau** khi có traffic thật 1 tuần ở monitor.
- [ ] Review Notes + tài khoản test + audio mẫu.
