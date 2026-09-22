# One AI v2 — Flutter app

**Repo:** `git@github.com:doxutostudio/oneai_v2.git` (branch `main`)

Viết lại từ đầu. `App/oneai/` (bản cũ) là repo riêng `doxutostudio/oneai`, giữ
nguyên để tra cứu, xoá sau khi ship.

Lần push đầu (agent không ra được SSH, phải chạy từ terminal của bạn):

```bash
# tạo repo rỗng doxutostudio/oneai_v2 trên GitHub trước, đừng tick README
cd App/oneai_v2 && git push -u origin main
```

| | |
|---|---|
| State management | **Riverpod 3** (`flutter-skill/riverpod-pro`) |
| Navigation | go_router |
| Backend | Cloud Functions callables (`functions-v2`), Firestore listener, Storage upload trực tiếp |
| Design | **Giữ nguyên bản cũ** — `docs/07-APP-UI-FLOW-SPEC.md` là hợp đồng, `test/unit/design_tokens_test.dart` là chốt chặn |
| Tên app | Store: **One AI: AI Note Taker & Scribe** · dưới icon: **One AI** |

## Bước bạn phải chạy một lần (agent không có flutter)

```bash
cd App/oneai_v2

# 1. Sinh khung nền tảng iOS + Android vào thư mục này
flutter create --platforms=ios,android \
  --org top.doxutostudio --project-name one_ai .

# 2. Cài dependency
flutter pub get

# 3. Sinh firebase_options cho từng flavor
dart pub global activate flutterfire_cli
flutterfire configure --project=minutesai-6715a \
  --out=lib/core/config/firebase_options_prod.dart \
  --ios-bundle-id=top.doxutostudio.one.ai \
  --android-package-name=top.doxutostudio.one.ai

# 4. Kiểm tra
flutter analyze
flutter test
```

`flutter create` sẽ **không ghi đè** `lib/`, `pubspec.yaml` hay `analysis_options.yaml`
đã có — nó chỉ thêm `ios/`, `android/`, và các file khung còn thiếu.

Sau bước 1, áp dụng **`PLATFORM-SETUP.md`** — nó có sẵn từng giá trị để dán:
Info.plist, AndroidManifest, gradle, assets cần chép, splash và launcher icon.

## Chạy

```bash
flutter run --dart-define=FLAVOR=dev --dart-define=USE_EMULATOR=true
flutter build ipa --dart-define=FLAVOR=prod
```

Không có URL hay khoá nào hardcode theo môi trường — tất cả qua `AppConfig`.

## Để agent build/test

```bash
bash scripts/watch-build.sh     # tab 1
bash scripts/watch-git.sh       # tab 2
```

Agent ghi `.build-request`, đọc `.build-done` và `reports/latest/summary.md`.

## Cấu trúc

```
lib/
  main.dart               3 dòng
  bootstrap.dart          composition root, fail loud
  app.dart                MaterialApp.router
  core/
    config/app_config.dart      flavor + hằng số mang từ v1 sang
    theme/                      màu, chữ, spacing, extension — CHÉP NGUYÊN SI
    router/                     routes.dart + app_router.dart
    errors/api_failure.dart     sealed, một file duy nhất
    l10n/                       (S8)
    widgets/                    widget dùng chung
  data/
    firebase/
      client_info.dart          khối client trên mọi request
      functions_client.dart     nơi DUY NHẤT gọi callable
      json_read.dart            reader khoan dung, tránh 3 cái bẫy cast
    models/
  features/
    auth/ minutes/ transcription/ tags/ settings/ ads/
test/
  unit/design_tokens_test.dart  giữ design khỏi trôi
  unit/json_read_test.dart
  widget/  golden/
```

## Đã bỏ so với bản cũ

| Bỏ | Lý do |
|---|---|
| `flutter_bloc`, `bloc`, `provider` | thay bằng Riverpod 3 |
| `dio` | thay bằng `cloud_functions` |
| `shared_preferences` | chỉ thêm lại khi thật sự cần |
| `logging` | `dart:developer` + Sentry |
| toàn bộ cây `demo/` | scaffolding của template |
| `codebase_ai` làm package name | thành `one_ai` |
| `meeting_minute_provider.dart` | dead code |
| `MeetingMinute` tách khỏi `Minute` | một model duy nhất |
| `example_long_init_service.dart` | dead code |
| `language_selector.dart` bản trùng | còn một |
| ~17 README template | |

## Đang chờ quyết (docs/11-OPEN-QUESTIONS.md)

- **OQ-08** dark mode: `themeMode: ThemeMode.light` cố định. Bảng màu dark đã sẵn.
- **OQ-09** font: `AppTypography.fontFamily` là `null` (font hệ thống), như hành vi thật của bản cũ.
- **OQ-10** route: giữ `/transcriptionSummary`, chưa đổi sang `/minutes/:id`.

## Đã chốt bỏ

- **YouTube ingest** (OQ-06, 23/09): không có route `/youtubeVideo`, sheet tạo
  note chỉ còn 2 lối (ghi âm / tải file).
