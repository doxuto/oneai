# 07 — App UI & flow spec (ĐÓNG BĂNG)

> ⚠️ Mã sprint (S3-05, S7-12…) trong file này là của **roadmap bản 1**.
> `09-ROADMAP.md` đã được đánh số lại cho hướng build-lại-từ-đầu.
> Tra cứu theo tên task, đừng theo mã.


> Đây là **hợp đồng giao diện** cho `App/oneai_v2/`. App viết lại từ đầu
> nhưng không được làm đổi bất cứ giá trị nào trong §1, cây route trong §2, hay
> bố cục trong §3. Mọi thay đổi phải là một task riêng, được Toan duyệt riêng.
>
> **Chốt chặn tự động:** `App/oneai_v2/test/unit/design_tokens_test.dart` — nó
> khẳng định từng mã màu, cỡ chữ, bán kính trong §1 khớp với code.
>
> Bản đầy đủ từng widget: `02-AUDIT-APP.md`. File này là phần **bất biến**.

---

## 1. Design tokens — chép nguyên si

### 1.1 ColorScheme — light (đang chạy thật)

| Role | Value |
|---|---|
| `primary` | `0xFF2C7DF7` |
| `onPrimary` | `Colors.white` |
| `primaryContainer` | `0xFFE8DDFF` |
| `onPrimaryContainer` | `0xFF21005E` |
| `secondary` | `0xFF03DAC6` |
| `onSecondary` | `Colors.black` |
| `secondaryContainer` | `0xFFCEFAF8` |
| `onSecondaryContainer` | `0xFF002021` |
| `surface` | `0xFFFFFFFF` |
| `onSurface` | `0xFF1C1B1F` |
| `surfaceContainerHighest` | `0xFFE7E0EB` |
| `onSurfaceVariant` | `0xFF49454E` |
| `error` | `0xFFB00020` |
| `onError` | `0xFFFFFFFF` |
| `outline` | `0xFFBDBDBD` |
| `shadow` | `0xFF000000` |
| `inverseSurface` | `0xFF313033` |
| `onInverseSurface` | `0xFFF4EFF4` |
| `inversePrimary` | `0xFFCFBCFF` |
| `surfaceTint` | `0xFF2C7DF7` |

### 1.2 ColorScheme — dark (định nghĩa sẵn, **chưa bao giờ chạy**)

| Role | Value |
|---|---|
| `primary` | `0xFFBB86FC` |
| `onPrimary` | `Colors.black` |
| `primaryContainer` | `0xFF4F378B` |
| `onPrimaryContainer` | `0xFFE8DDFF` |
| `secondary` | `0xFF03DAC6` |
| `secondaryContainer` | `0xFF00504C` |
| `onSecondaryContainer` | `0xFFBBF5F1` |
| `surface` | `0xFF121212` |
| `onSurface` | `0xFFE6E1E5` |
| `surfaceContainerHighest` | `0xFF49454F` |
| `onSurfaceVariant` | `0xFFCAC4D0` |
| `error` | `0xFFCF6679` |
| `onError` | `0xFF000000` |
| `outline` | `0xFF938F99` |
| `inverseSurface` | `0xFFE6E1E5` |
| `onInverseSurface` | `0xFF1C1B1F` |
| `inversePrimary` | `0xFF6750A4` |
| `surfaceTint` | `0xFFBB86FC` |

> `main.dart` truyền `theme: lightTheme` cứng, không set `darkTheme`/`themeMode`.
> `ThemeBloc`, `ThemeRepository`, `ThemeSelector` và cả bảng màu dark là code
> chết lúc runtime. **Không tự sửa** — xem OQ-08.

### 1.3 AppThemeExtension

| Token | Light | Dark |
|---|---|---|
| `successColor` | `0xFF00BFA5` | `0xFF00C897` |
| `onSuccessColor` | `Colors.white` | `Colors.black` |
| `successContainerColor` | `0xFFCCF5E9` | `0xFF00513C` |
| `onSuccessContainerColor` | `0xFF00382D` | `0xFF7AEBC3` |
| `warningColor` | `0xFFFFC107` | `0xFFFFA000` |
| `onWarningColor` | `Colors.black` | `Colors.black` |
| `warningContainerColor` | `0xFFFFE082` | `0xFF653A00` |
| `onWarningContainerColor` | `0xFF332800` | `0xFFFFDDB3` |
| `buttonRadius` | `Radius.circular(8)` | `Radius.circular(8)` |
| `cardRadius` | `Radius.circular(12)` | `Radius.circular(12)` |
| `dialogRadius` | `Radius.circular(16)` | `Radius.circular(16)` |
| `animationFast` | `200ms` | `200ms` |
| `animationMedium` | `300ms` | `300ms` |
| `animationSlow` | `500ms` | `500ms` |

### 1.4 Typography (một TextTheme dùng chung, `fontFamily: 'Roboto'`)

| Style | size | weight | letterSpacing |
|---|---|---|---|
| `displayLarge` | 57 | w400 | −0.25 |
| `displayMedium` | 45 | w400 | 0 |
| `displaySmall` | 36 | w400 | 0 |
| `headlineLarge` | 32 | w400 | 0 |
| `headlineMedium` | 28 | w400 | 0 |
| `headlineSmall` | 24 | w400 | 0 |
| `titleLarge` | 22 | w500 | 0 |
| `titleMedium` | 16 | w500 | 0.15 |
| `titleSmall` | 14 | w500 | 0.1 |
| `labelLarge` | 14 | w500 | 0.1 |
| `labelMedium` | 12 | w500 | 0.5 |
| `labelSmall` | 11 | w500 | 0.5 |
| `bodyLarge` | 16 | w400 | 0.5 |
| `bodyMedium` | 14 | w400 | **−0.41** |
| `bodySmall` | 12 | w400 | 0.4 |

Không style nào set `height`.

> **Cảnh báo:** `pubspec.yaml` khai báo `assets/fonts/` dưới `assets:` nhưng
> **không có mục `fonts:`**, nên `fontFamily: 'Roboto'` rơi về font hệ thống;
> hai file `.ttf` chỉ là asset chết. Đăng ký font **sẽ đổi render trên iOS** →
> OQ-09, không tự sửa.

### 1.5 Dimens

`SizedBox` const: `gapW4/8/12/16/24/32/48/64`, `gapH4/8/12/16/24/32/48/64`.

### 1.6 Component themes

`useMaterial3: true`. AppBar `elevation 0`, bg `surface`. Card `elevation 2`,
radius 12. Buttons padding `H16/V12`, radius 8. Input `filled`, radius 8, focus
border `primary` width 2, padding `H16/V16`. Chip radius 8. Dialog radius 16.
BottomSheet **trong suốt** (light) / radius 16 + elevation 0 (dark). Divider
`outline.withAlpha(51)`. Switch/Checkbox/Slider/ProgressIndicator đều đổ về
`primary` với các alpha `128/77/51/31`.

### 1.7 Màu hardcode ngoài theme — giữ nguyên, ghi nhận nợ

UI đang viết cứng nhiều màu không đi qua ColorScheme. **Không refactor trong
đợt này** (rủi ro đổi giao diện), nhưng liệt kê để Sprint 8 xử lý có chủ đích:

- Xanh: `0xFF0767F8` (home empty, tag pill, TagChip, FAB processing, login accent,
  settings language chip), `0xFF2C7DF7` (summary appbar, tab selector, audio
  player, feedback), `0xFF4285F4` (PremiumButton), `Colors.blue` (nhãn dialog).
- `0xFFBDBDBD` (divider dialog/menu) và `0xFFE41919` (hành động phá huỷ) — ~25 chỗ.
- Nền ép trắng bất kể theme: `record_audio_screen`, `settings_screen`,
  `new_minutes_bottom_sheet`, `prompt_language_sheet`, audio player, share menu.
- Khác: `0xFFEDF4FF 0xFFE1EDFF 0xFFEBF3FF 0xFFE6F0FF 0xFFF0F6FF 0xFFF5F5F5
  0xFFF6F6F6 0xFFF2F2F2 0xFFF0F0F0 0xFFE5E5E5 0xFF8E8E93 0xFFFEA200 0xFFFFBB00
  0xFFFFB300 0xFFF8C307`.

### 1.8 Assets

44 SVG trong `assets/icons/`, ảnh trong `assets/images/` (`app_icon.png`,
`splash.png`, `like_button.png`, `dislike_button.png` + biến thể 1.5x→4.0x).
Mọi path tập trung ở `lib/config/assets.dart` (`abstract final class Assets`).
Splash `#ffffff` + `splash.png`. Launcher icon `app_icon.png`, adaptive bg
`#ffffff`, foreground inset 16, iOS `remove_alpha_ios: true`.

---

## 2. Cây route — giữ nguyên đường dẫn và transition

```
GoRouter (rootNavigatorKey, initialLocation '/')
│ redirect toàn cục: chưa auth → /login ; đã auth mà ở /login → /
│ refreshListenable: AuthStateNotifier(AuthBloc)
│ errorBuilder: _errorPage
│
├─ /login                    LoginPage                      MaterialPage
├─ /                         HomeScreen                     fade
│   ├─ /transcriptionSummary TranscriptionSummaryScreen     slideRightToLeft
│   └─ /settings             SettingsScreen                 slideRightToLeft
├─ /recordAudio              RecordAudioScreen              slideRightToLeft
├─ /uploadFile               UploadFileScreen               slideRightToLeft
│                              (v1 còn /youtubeVideo — đã bỏ, OQ-06 23/09)
├─ /audioProcessing          AudioProcessingScreen          slideRightToLeft
└─ /demoHome /demoUsers /demoPosts/:postId /demoSettings /demoCategories   ← XOÁ (Sprint 8)
```

`PageAnimationManager.createPage` trả `CupertinoPage` trên iOS/macOS, nên trên
iOS mọi `transitionBuilder` bị bỏ qua và dùng swipe-back gốc. Không đổi.

**Thay đổi bắt buộc khi rework** (route giữ nguyên, cách truyền tham số đổi):
`/transcriptionSummary` và `/demoPosts/:postId` hiện ép kiểu `state.extra as X`
không bảo vệ → crash khi deep link hoặc cold restore. Chuyển sang path param
`/minutes/:minuteId` **là breaking change về UX deeplink** → đưa vào OQ-10.
Bước an toàn trong Sprint 6: giữ `/transcriptionSummary` nhưng đọc `extra` có
guard và fallback `context.go('/')`.

---

## 3. Luồng người dùng — hành vi phải giữ

### Đăng nhập
`LoginPage` → Google hoặc Apple → `AuthBloc` → RevenueCat `logIn(uid)` →
redirect `/`. Ghi nhớ phương thức đăng nhập lần trước để hiện nhãn
"Previously signed in with …".

### Tạo note
`HomeScreen` FAB → `NewMinutesBottomSheet` → 2 lối (v1 có 3; lối YouTube đã bỏ
theo OQ-06 chốt 23/09, nên sheet và route `/youtubeVideo` không còn):

| Lối | Màn | Đầu ra |
|---|---|---|
| Ghi âm | `/recordAudio` | file `.m4a` local |
| Tải file | `/uploadFile` | file đã chọn |

Cả hai đi qua `premiumActionWrapper` → nếu `nonPremiumNoCredits` thì bật rewarded
ad, chỉ chạy tiếp khi nhận được credit → `/audioProcessing` với
`extra: {audioPath, audioLanguage, summaryLanguage, recordingContext?, keywords?}`.

**Sửa ở Sprint 6:** `/audioProcessing` hiện chạy thanh tiến trình **giả** (5
bước, `0.001/50ms`) và tự báo lỗi `'Transcription did not complete in time.'`
sau ~250s kể cả khi server vẫn đang chạy; nút đóng pop ra mà không huỷ upload.
Thay bằng `status` thật từ Firestore listener + nút huỷ gọi `cancelTranscription`.
**Bố cục, màu, chữ giữ nguyên.**

### Xem note
`HomeScreen` list → tap card → interstitial `pre_summary` → `/transcriptionSummary`.
Ba tab: Summary / Transcript / Chat, mỗi tab có banner ở trên. Share → PDF hoặc
text → interstitial `after_share`. Thoát → interstitial `summary_exit` (trừ
nhánh có dialog Congratulation — đây là bug, xem OQ-11).

### Settings
Audio/Summary language, feedback, contact, review, privacy, terms, manage
subscription, free credits, sign out, delete account. Thoát → interstitial
`settings_exit`.

---

## 4. Những gì tầng data được phép đổi

| Đổi được (viết mới hết) | Không đổi |
|---|---|
| State management: BLoC → **Riverpod 3** | Widget tree, màu, chữ, padding |
| `dio` → `cloud_functions` + `firebase_storage` | Tên route, transition |
| Model: gộp `Minute` ↔ `MeetingMinute` | Sự kiện UI → hành vi (tap gì ra gì) |
| Polling → Firestore `snapshots()` | Vị trí và loại quảng cáo |
| `Result<T>` → sealed `ApiFailure` | Thứ tự tab, nội dung dialog |

Chốt chặn: golden test viết **ngay khi một màn được dựng xong** (không viết
trước — sẽ đỏ liên tục vô ích), và phải xanh từ đó trở đi. Cộng với
`design_tokens_test.dart` chạy ngay từ bây giờ, đó là hai lớp chứng minh giao
diện không xê dịch.
