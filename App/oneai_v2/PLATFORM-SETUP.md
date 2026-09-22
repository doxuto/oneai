# Platform setup — dán sau khi chạy `flutter create`

`flutter create` sinh ra `ios/` và `android/` với giá trị mặc định. Đây là
những chỗ phải sửa, kèm giá trị chính xác. Nguồn: `docs/13-CONFIG-INVENTORY.md`.

---

## iOS — `ios/Runner/Info.plist`

```xml
<key>CFBundleDisplayName</key>
<string>One AI</string>
<key>CFBundleName</key>
<string>One AI</string>

<!-- AdMob. ID thật của tài khoản doxutostudio, thay cho sample id
     ca-app-pub-3940256099942544~1458002511 mà bản cũ đang dùng. -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-8661297299230251~8024150974</string>

<!-- Google Sign-In -->
<key>GIDClientID</key>
<string>468402655519-7n4hnnm9rhkgova6ioumv673peo0qu8n.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.468402655519-7n4hnnm9rhkgova6ioumv673peo0qu8n</string>
      <string>oneai</string>
    </array>
  </dict>
</array>

<!-- Quyền. Chỉ khai những gì thật sự dùng. -->
<key>NSMicrophoneUsageDescription</key>
<string>One AI records audio so it can transcribe your meetings and lectures.</string>
<key>NSUserTrackingUsageDescription</key>
<string>Allows One AI to show ads that are more relevant to you. You can keep using every feature either way.</string>

<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Bỏ so với bản cũ:**
- `fb787393250278163` trong URL schemes — không có SDK Facebook nào trong app.
- `NSPhotoLibraryUsageDescription` — app chỉ chọn file audio qua `file_picker`.
  Khai quyền không dùng là một lý do bị App Review từ chối.

**Còn thiếu:** `SKAdNetworkItems` hiện trống. Lấy danh sách SKAdNetwork id từ
tài liệu AdMob và dán vào, nếu không thì attribution trên iOS không đo được.

Bundle id: `top.doxutostudio.one.ai` (đặt qua `--org top.doxutostudio` khi chạy
`flutter create`, kiểm tra lại trong `Runner.xcodeproj`).

---

## Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>

<application
    android:label="One AI"
    android:icon="@mipmap/ic_launcher">

    <meta-data
        android:name="com.google.android.gms.ads.APPLICATION_ID"
        android:value="ca-app-pub-8661297299230251~8068383004"/>
</application>
```

**Bỏ so với bản cũ:** `WRITE_EXTERNAL_STORAGE` — thừa từ API 29, và app không
ghi ra bộ nhớ ngoài.

`android/app/build.gradle.kts`:

```kotlin
namespace = "top.doxutostudio.one.ai"     // bản cũ là com.codebase.ai.codebase_ai
defaultConfig {
    applicationId = "top.doxutostudio.one.ai"
    minSdk = 24
}
ndkVersion = "27.0.12077973"
```

---

## Firebase

```bash
flutterfire configure --project=minutesai-6715a \
  --out=lib/core/config/firebase_options_prod.dart \
  --ios-bundle-id=top.doxutostudio.one.ai \
  --android-package-name=top.doxutostudio.one.ai
```

Lặp lại cho `oneai-dev` và `oneai-staging` khi hai project đó tồn tại.
`google-services.json` và `GoogleService-Info.plist` đã nằm trong `.gitignore`.

---

## Assets

Chép từ `App/oneai/assets/` sang:

- `assets/icons/` — 44 file SVG
- `assets/images/` — `app_icon.png`, `splash.png`, `like_button.png`,
  `dislike_button.png` và các biến thể 1.5x/2.0x/3.0x/4.0x

**Không chép** `assets/fonts/` — bản cũ khai nó dưới `assets:` mà không có mục
`fonts:`, nên hai file Roboto chưa bao giờ được dùng (OQ-09).

Splash + launcher icon:

```yaml
flutter_native_splash:
  color: "#ffffff"
  image: assets/images/splash.png
  android_12:
    color: "#ffffff"

flutter_launcher_icons:
  image_path: "assets/images/app_icon.png"
  android: true
  ios: true
  adaptive_icon_background: "#ffffff"
  adaptive_icon_foreground: "assets/images/app_icon.png"
  adaptive_icon_foreground_inset: 16
  min_sdk_android: 24
  remove_alpha_ios: true
  background_color_ios: "#ffffff"
```

```bash
dart run flutter_native_splash:create
dart run flutter_launcher_icons
```

---

## Tên hiển thị

| Chỗ | Giá trị |
|---|---|
| Tên trên App Store / Play Store | **One AI: AI Note Taker & Scribe** |
| Dưới icon trên máy (`CFBundleDisplayName`, `android:label`) | **One AI** |
| `MaterialApp.title` | **One AI** (lấy từ `AppConfig.appShortName`) |

Tên dài dưới icon bị cắt thành "One AI: AI No…", nên chỉ dùng cho store listing.
