# One AI

Ứng dụng transcribe audio cuộc họp / bài giảng, tóm tắt và hỏi đáp bằng AI.
Flutter (iOS + Android) + Firebase Cloud Functions.

**Tên trên store:** One AI: AI Note Taker & Scribe

---

## Bố cục

```
oneai/
├── App/
│   ├── oneai/              ⛔ LEGACY — app cũ, chỉ đọc để tham chiếu
│   └── oneai_v2/           ✅ app đang phát triển (Flutter + Riverpod 3)
├── Backend/
│   └── oneai_backend/
│       ├── functions/      ⛔ LEGACY — backend cũ (JS + Express), đóng băng
│       ├── functions-v2/   ✅ backend đang phát triển (TypeScript + onCall)
│       ├── firebase.json   2 codebase: `default` (v1) và `v2`
│       ├── firestore.rules · firestore.indexes.json · storage.rules
│       └── scripts/        watch-build / watch-git / build-and-test
├── docs/                   14 tài liệu — đọc docs/00-README.md trước
├── .claude/skills/         13 skill (firebase, flutter, admob) mà code phải bám theo
└── _legacy-git/            lịch sử git của 3 repo cũ (gitignore)
```

**Quy tắc:** code mới viết vào `oneai_v2` và `functions-v2`. Không sửa legacy —
nó chỉ để đối chiếu hành vi, và sẽ bị xoá sau khi v2 lên store (mốc M7).

## Bắt đầu

1. `docs/00-README.md` — chỉ mục toàn bộ tài liệu
2. `docs/11-OPEN-QUESTIONS.md` — những gì còn chờ quyết, **đọc trước mỗi sprint**
3. `docs/09-ROADMAP.md` — 11 sprint tới ngày phát hành
4. `docs/12-AGENT-WORKFLOW.md` — cách agent build/test/commit qua file

## Chạy

```bash
# Backend
cd Backend/oneai_backend/functions-v2
npm install && npm run lint && npm test && npm run build

# App — lần đầu cần sinh khung nền tảng, xem App/oneai_v2/README.md
cd App/oneai_v2
flutter create --platforms=ios,android --org top.doxutostudio --project-name one_ai .
flutter pub get && flutter analyze && flutter test
```

Deploy backend v2 mà không đụng v1:

```bash
firebase deploy --only functions:v2
```

## Watcher cho agent

Agent không có shell trên máy bạn, nên nó đặt hàng build/git qua file.
Mở 4 tab và để đó:

```bash
cd App/oneai_v2             && bash scripts/watch-build.sh
cd App/oneai_v2             && bash scripts/watch-git.sh
cd Backend/oneai_backend    && bash scripts/watch-build.sh
cd Backend/oneai_backend    && bash scripts/watch-git.sh
```

Chi tiết giao thức: `docs/12-AGENT-WORKFLOW.md`.

## Bí mật

Không có secret nào trong repo. `.gitignore` chặn `.env`, `service-account.json`,
`google-services.json`, `GoogleService-Info.plist`, `firebase_options*.dart`,
keystore và provisioning profile — chặn ở cả thư mục gốc lẫn thư mục con.

Ngoại lệ duy nhất được commit có chủ đích: `functions-v2/.env`, chỉ chứa param
không bí mật (tên model, hạn mức). Secret thật nạp qua
`firebase functions:secrets:set`.

Danh sách key cần có và những việc còn tồn: `docs/13-CONFIG-INVENTORY.md`.
