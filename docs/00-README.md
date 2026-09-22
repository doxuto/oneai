# One AI — tài liệu rework

Cập nhật 2026-09-22 (bản 2 — đổi sang **build lại từ đầu**).

## Bộ tài liệu

| File | Nội dung | Đọc khi |
|---|---|---|
| [`01-AUDIT-BACKEND-V1.md`](01-AUDIT-BACKEND-V1.md) | Audit toàn bộ backend JS hiện tại: từng endpoint, data model, lỗi, bug | cần biết v1 *thực sự* làm gì |
| [`02-AUDIT-APP.md`](02-AUDIT-APP.md) | Audit app Flutter: design token, route, từng màn, contract, ads | cần biết app *thực sự* làm gì |
| [`03-SKILLS-RULESET.md`](03-SKILLS-RULESET.md) | Ruleset chắt lọc từ `.claude/skills` (13 skill) | khi viết code mới — đây là luật |
| [`04-ARCHITECTURE-V2.md`](04-ARCHITECTURE-V2.md) | 6 ADR + sơ đồ hệ thống + runtime options | trước khi viết dòng đầu tiên |
| [`05-API-CONTRACT-V2.md`](05-API-CONTRACT-V2.md) | Toàn bộ callable, zod, bảng lỗi, bảng cutover v1→v2 | khi làm BE hoặc tầng data App |
| [`06-DATA-MODEL-V2.md`](06-DATA-MODEL-V2.md) | Firestore collection, index, rules, Storage | khi đụng dữ liệu |
| [`07-APP-UI-FLOW-SPEC.md`](07-APP-UI-FLOW-SPEC.md) | **ĐÓNG BĂNG** — màu, chữ, route, luồng | trước mọi thay đổi ở App |
| [`08-ADS-FLOW.md`](08-ADS-FLOW.md) | AdMob v2: gate, ledger, UMP, SSV | khi làm monetization |
| [`09-ROADMAP.md`](09-ROADMAP.md) | 10 sprint, 6 mốc, từng task có tiêu chí hoàn thành | lập kế hoạch, theo tiến độ |
| [`10-BACKLOG.md`](10-BACKLOG.md) | 10 epic + story + danh sách nợ kỹ thuật | ưu tiên công việc |
| [`11-OPEN-QUESTIONS.md`](11-OPEN-QUESTIONS.md) | 15 câu chờ Toan chốt, mỗi câu có hạn và mặc định tạm | **đọc trước mỗi sprint** |
| [`12-AGENT-WORKFLOW.md`](12-AGENT-WORKFLOW.md) | Giao thức watch-build / watch-git | trước khi để agent làm việc |
| [`13-CONFIG-INVENTORY.md`](13-CONFIG-INVENTORY.md) | Mọi key/id mang sang bản mới + 7 việc bạn phải làm | khi dựng môi trường |
| [`14-EXECUTION-PLAN.md`](14-EXECUTION-PLAN.md) | Sổ cái task-level, agent tự cập nhật | theo tiến độ từng file |
| [`15-RUNBOOK.md`](15-RUNBOOK.md) | Deploy, rollback, sự cố, alert, xoá dữ liệu | khi vận hành |

## Quyết định đã chốt (22/09/2026)

| | |
|---|---|
| **Cách làm** | **Build lại từ đầu cả hai phía.** Bỏ hết thư viện và code cũ; chỉ mang sang config (xem `13-CONFIG-INVENTORY.md`) |
| **Vị trí** | Một repo `doxuto/oneai`. Code mới ở `App/oneai_v2/` và `Backend/oneai_backend/functions-v2/`; legacy giữ nguyên để tra cứu, xoá ở M7 |
| **Backend** | TypeScript + Cloud Functions v2 `onCall` + zod, codebase `v2` deploy độc lập |
| **Backend v1** | Đóng băng, không sửa. Gỡ sớm nhất 30 ngày sau phát hành |
| **App state** | **Riverpod 3** (theo `flutter-skill/riverpod-pro`). Bỏ `flutter_bloc`, `provider`, `dio` |
| **App UI** | **Giữ nguyên design hiện tại** — `07-APP-UI-FLOW-SPEC.md` là hợp đồng, `test/unit/design_tokens_test.dart` là chốt chặn |
| **Phạm vi** | Parity đầy đủ với bản cũ trước khi ship, **trừ YouTube ingest — đã bỏ hẳn** (OQ-06, 23/09) |
| **Ads** | Port `ios-admob-ads-skill` sang Flutter, rewarded chuyển sang SSV |

> Bản 1 của tài liệu này chọn "giữ BLoC, rework tại chỗ". Toan đổi hướng ngày
> 22/09: dựng lại sạch. Mọi chỗ còn nói "giữ BLoC" là tàn dư — báo lại nếu thấy.

## Bắt đầu từ đâu

1. Đọc `11-OPEN-QUESTIONS.md` — chốt **OQ-01** (migrate dữ liệu?) và **OQ-02**
   (hạn mức free?). Hai câu này chặn S2–S3. *(OQ-06 YouTube: đã chốt bỏ hẳn 23/09.)*
2. Mở 4 tab watcher theo `12-AGENT-WORKFLOW.md`.
3. Chạy S0: **huỷ SOCKS proxy credential ở phía nhà cung cấp** (**S0-03 — làm
   ngay**; code đã gỡ nhưng git history vẫn giữ).
4. Chạy `flutter create` trong `App/oneai_v2/` theo README ở đó, rồi áp dụng
   `App/oneai_v2/PLATFORM-SETUP.md`.
5. Vào S1.

## Điều quan trọng nhất

Backend v1 hiện **không load được**: `functions/services/ai.service.js` dùng cú
pháp ESM trong một package CommonJS, và vì `index.js` require toàn bộ route
eagerly, cả function `api` chết ngay lúc khởi tạo. Đó chính là "deploy lên chết
api". Chi tiết: `01-AUDIT-BACKEND-V1.md` §6 "Fatal".

Không vá nó. Viết v2 song song, cutover, rồi gỡ.
