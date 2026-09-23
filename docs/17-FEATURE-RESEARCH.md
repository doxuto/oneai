# 17 — Nghiên cứu tính năng: làm app phong phú hơn theo đúng use case

Ngày 23/09/2026. Mục tiêu: liệt kê các tính năng khiến One AI hữu ích hơn cho
**hai use case lõi** (họp và bài giảng), chấm theo giá trị / công sức / độ khớp
với kiến trúc v2, rồi xếp vào roadmap. Không phải mọi ý đều làm — cột "Quyết định"
là kết luận.

## 1. Use case và khoảnh khắc người dùng cần gì

| Use case | Trước | Trong | Ngay sau | Sau vài ngày |
|---|---|---|---|---|
| **Họp** (standup, 1:1, khách hàng) | bấm ghi nhanh, không cần setup | ghi im lặng, pin, không mất khi tắt màn | ai làm gì, đến khi nào; quyết định gì; lịch hẹn | tìm lại "đã chốt gì về X", chia sẻ cho người vắng |
| **Bài giảng / lecture** | import file dài (1–3h), PDF slide | — | chương/mốc thời gian để tua, thuật ngữ, tóm tắt | ôn: quiz, flashcard lặp lại, hỏi đáp xuyên nhiều bài |
| **Phỏng vấn / podcast** (phụ) | — | — | ai nói gì, trích dẫn | tìm câu trích |

Nhận xét: v1 mạnh ở "ngay sau" (summary, chat, quiz) nhưng **trống ở "sau vài
ngày"** (tìm kiếm, ôn tập, chia sẻ) và ở "trong" (ghi âm dài, offline).

## 2. Danh sách tính năng, chấm điểm

Giá trị 1–5 · Công sức S/M/L/XL · Khớp v2 = có tái dùng hạ tầng sẵn (artifact
cache, pipeline, listener) không.

### 2.1 Làm ngay — rẻ vì tái dùng `generateArtifact` (đã implement BE 23/09)

| Tính năng | Use case | Giá trị | Công sức | Ghi chú |
|---|---|---|---|---|
| **Action items + decisions** (`generateActionItems`) | họp | 5 | S | owner/due/quote; cache theo transcript; cùng timezone với calendarEvents |
| **Chapters có mốc thời gian** (`generateChapters`) | lecture, podcast | 5 | S | transcript kèm `[start-end]`, clamp về độ dài thật; PDF từ chối `noTimeline`; app dùng để tua và highlight chương đang phát |
| **Key terms / glossary** (`generateKeyTerms`) | lecture | 4 | S | định nghĩa theo ngữ cảnh, kèm câu trích |
| **Talk-time theo người nói** (`getMinute.talkTime`) | họp, phỏng vấn | 3 | S | thuần từ transcript, **không tốn LLM**; hiện thanh % cạnh speaker |
| **Retention audio gốc** | vận hành | 5 | S | xong (`05` §2.7b) — chống đầy Storage, giữ transcript |

### 2.2 Trước phát hành — vào S6/S7 (app) vì BE đã đủ

| Tính năng | Use case | Giá trị | Công sức | Ghi chú |
|---|---|---|---|---|
| Tab **"Việc cần làm"** trong Summary (action items, tick xong, xuất Reminders) | họp | 5 | M | client-side; tick lưu local hoặc `updateArtifact` sau |
| **Thanh chương** trên player + tua theo chương | lecture | 4 | M | dữ liệu có sẵn |
| **Thêm sự kiện vào Lịch** từ `calendarEvents` | họp | 4 | S | `add_2_calendar`/EventKit, không cần BE |
| **Chia sẻ Markdown / PDF có chương + action items** | cả hai | 4 | M | S7-03 mở rộng; Notion/Docs qua share sheet |
| **Ghim / yêu thích note** | cả hai | 2 | S | `updateMinute.pinned` (+1 field) |
| **Cảnh báo "audio gốc sẽ bị xoá sau N ngày"** + nút "Tải về" | cả hai | 3 | S | từ `sourceExpiresAt` |

### 2.3 Sau phát hành — S11 (giá trị cao, cần thêm hạ tầng)

| Tính năng | Use case | Giá trị | Công sức | Cần gì |
|---|---|---|---|---|
| **Hỏi đáp xuyên nhiều note** ("tuần trước chốt gì về pricing?") | họp | 5 | L | Firestore **vector search** (embedding mỗi note khi ready, `findNearest`), callable `askAll`; cost: 1 embedding/transcript |
| **Tìm kiếm toàn văn** (OQ-07) | cả hai | 4 | M | ngắn hạn: client-side trên `transcriptPreview` + title; dài hạn: dùng chính embedding trên |
| **Ôn tập flashcard theo lịch** (spaced repetition SM-2) | lecture | 4 | M | client-side, lưu `users/{uid}/study/{cardId}`; thông báo nhắc ôn qua push đã có |
| **Dịch summary/transcript** sang ngôn ngữ khác | cả hai | 3 | S | artifact `translation_{lang}`; streaming |
| **Share link chỉ đọc** cho người vắng họp | họp | 4 | M | callable `createShareLink` → doc `shares/{token}` + trang web tĩnh (Hosting) đọc qua callable public; thu hồi được |
| **Share extension / Voice Memos import** (iOS) | cả hai | 4 | M | Share Extension + App Group; Android intent filter |
| **Ghi âm offline, tự upload khi có mạng** | cả hai | 3 | M | client queue; BE không đổi |
| **Widget / Siri "Bắt đầu ghi"** | họp | 2 | M | |
| **Meeting templates** (standup / 1:1 / interview) → prompt summary theo kiểu | họp | 3 | S | `startTranscription.template` → chọn prompt; `contentKind` đã có |

### 2.4 Xa hơn — S12+, chỉ khi có tín hiệu từ user

| Tính năng | Giá trị | Công sức | Vì sao chưa |
|---|---|---|---|
| **Live transcription** khi đang ghi (streaming STT) | 5 | XL | cần WebSocket STT vendor, UI realtime, pin; chi phí cao; làm sau khi có retention/quota ổn |
| Workspace / chia sẻ trong team, comment | 4 | XL | đổi data model (owner → members), rules, billing theo seat |
| Nhận diện giọng xuyên cuộc họp ("đây là Ana") | 3 | XL | voice profile, privacy |
| Đồng bộ lịch (Google/Outlook) để tự ghi | 3 | L | OAuth, background |
| Cắt/ghép audio trước khi upload | 2 | M | |

## 3. Không làm

- **YouTube ingest** — đã bỏ (OQ-06).
- **Sinh sẵn mọi artifact lúc ingest** — tốn LLM cho thứ user không mở; giữ lười theo yêu cầu + cache (OQ-05 nghiêng về "lười").
- **Client tự cộng credit dưới bất kỳ hình thức nào.**

## 4. Tác động lên roadmap

- S4 (BE AI): thêm S4-09 (action items, key terms, chapters, talk-time) — ✅ 23/09.
- S3: thêm S3-13 retention — ✅ 23/09.
- S6: thêm S6-12 tab Việc cần làm, S6-13 thanh chương, S6-14 thêm vào Lịch, S6-15 cảnh báo hết hạn audio.
- S7: S7-03 mở rộng xuất Markdown/PDF có chương + action items; S7-09 ghim note.
- **S11 mới (sau phát hành, 4 tuần)**: hỏi đáp xuyên note (vector), tìm kiếm, spaced repetition, dịch, share link, share extension, offline queue, templates.
- **S12 (backlog)**: live transcription, team, voice profile, calendar sync.

## 5. Bổ sung 24/09

Góc nhìn đối thủ, giá và than phiền người dùng ở `21-COMPETITOR-RESEARCH.md`; các mục mới: S8-13..15, S11-09..13, S12-06..09, app A7.
