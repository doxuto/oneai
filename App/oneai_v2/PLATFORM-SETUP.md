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

✅ Đã chép sẵn (23/09): `assets/icons/` 44 SVG, `assets/images/` 12 PNG.

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

## Ghi âm nền & chống ngắt (A7-02 / S11-09)

- **iOS**: `UIBackgroundModes` phải có `audio` (đã liệt kê ở trên) để ghi tiếp khi khoá màn;
  cuộc gọi đến làm AVAudioSession bị ngắt → `record` báo `RecordState.pause`,
  `RecorderController` đánh dấu `interrupted` và tự `resume()` khi app active lại.
- **Android 14+**: ghi khi app ở nền cần foreground service với
  `android:foregroundServiceType="microphone"` + permission
  `FOREGROUND_SERVICE_MICROPHONE` và `FOREGROUND_SERVICE`. `record` **không** tự tạo
  service; bước tiếp theo (sau khi compile) là thêm `flutter_foreground_task` hoặc
  service native nhỏ bọc quanh `AudioRecorder` — cho tới lúc đó, ghi âm chỉ chắc
  chắn khi app ở foreground hoặc màn hình khoá trong thời gian ngắn.
- **Khôi phục sau crash**: marker `UNFINISHED_RECORDING_V2` (SharedPreferences) được
  ghi 15 s/lần; Home hiện banner "Khôi phục". Lưu ý: file m4a bị cắt giữa chừng có
  thể không mở được (moov atom ghi lúc stop) — nếu server báo lỗi đọc audio thì
  khuyên user bỏ; giải pháp triệt để là ghi theo chunk (S11-09 phần còn lại).

## Deep link / Universal Link / App Link (24/09)

Host: Firebase Hosting của project (`https://<project>.web.app`, hoặc domain riêng
trỏ vào Hosting). `Backend/oneai_backend/hosting/.well-known/` đã có
`apple-app-site-association` và `assetlinks.json` — **[Toan]** thay `TEAMID` (Apple
Team ID) và 2 SHA-256 (Play App Signing + upload key, lấy ở Play Console › App
integrity) rồi `firebase deploy --only hosting`.

Đường dẫn app nhận: `/s?t=<token>` (ghi chú chia sẻ → màn xem + Lưu vào ghi chú),
`/n/<minuteId>` (note của mình → màn Summary). Scheme dự phòng: `oneai://s?t=…`,
`oneai://n/<id>` (đã có `oneai` trong `CFBundleURLSchemes`).

### iOS — `Runner/Runner.entitlements`
```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:<project>.web.app</string>
  <!-- thêm domain riêng nếu có: applinks:share.doxutostudio.top -->
</array>
```
`Info.plist` thêm `<key>FlutterDeepLinkingEnabled</key><true/>` (go_router nhận
link qua kênh Flutter mặc định, không cần plugin).

### Android — `AndroidManifest.xml` trong `<activity android:name=".MainActivity">`
```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="true" />
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="<project>.web.app" android:pathPrefix="/s" />
  <data android:scheme="https" android:host="<project>.web.app" android:pathPrefix="/n/" />
</intent-filter>
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="oneai" />
</intent-filter>
```
Kiểm tra: `adb shell pm verify-app-links --re-verify top.doxutostudio.one.ai` (Android 12+),
iOS: cài app từ TestFlight rồi mở link trong Notes/Messages (Safari nhập tay không kích hoạt).

Sau khi Hosting chạy, đặt `SHARE_BASE_URL=https://<project>.web.app/s` trong
`functions-v2/.env` để link chia sẻ dùng domain này (link cũ dạng cloudfunctions.net
vẫn mở được — cùng function).

## Nhận file từ app khác — Share Extension iOS + ACTION_SEND Android (S11-06)

Plugin `receive_sharing_intent` (pubspec). App nhận audio/video/PDF từ share
sheet (Voice Memos, Files, Zalo, Drive…) → mở `UploadFileScreen` với file đã
chọn sẵn; chỉ mất quota khi bấm Bắt đầu như upload thường. Chưa đăng nhập thì
file chờ qua màn Login (`pendingIncomingShareProvider`).

### iOS — Share Extension target (Xcode, sau `flutter create`)
1. File › New › Target › **Share Extension**, tên `ShareExtension`, bundle id
   `top.doxutostudio.one.ai.ShareExtension`, không dùng SwiftUI/storyboard.
2. Cả Runner và ShareExtension: Signing & Capabilities › **App Groups** →
   `group.top.doxutostudio.one.ai`.
3. `ShareExtension/ShareViewController.swift`:
   ```swift
   import receive_sharing_intent
   class ShareViewController: RSIShareViewController {
     override func shouldAutoRedirect() -> Bool { true }
   }
   ```
4. `ShareExtension/Info.plist`:
   ```xml
   <key>AppGroupId</key><string>group.top.doxutostudio.one.ai</string>
   <key>NSExtension</key>
   <dict>
     <key>NSExtensionAttributes</key>
     <dict>
       <key>NSExtensionActivationRule</key>
       <dict>
         <key>NSExtensionActivationSupportsFileWithMaxCount</key><integer>1</integer>
         <key>NSExtensionActivationSupportsMovieWithMaxCount</key><integer>1</integer>
       </dict>
     </dict>
     <key>NSExtensionPointIdentifier</key><string>com.apple.share-services</string>
     <key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
   </dict>
   ```
5. `Runner/Info.plist`: thêm `AppGroupId` như trên và một URL scheme nữa
   `ShareMedia-top.doxutostudio.one.ai` (plugin dùng scheme này để nhảy về app).
6. `ios/Podfile`: khối `target 'ShareExtension' do inherit! :search_paths end`
   trong `target 'Runner'`; `pod install`.
Deployment target của extension ≥ iOS 13; extension không có Firebase.

### Android — `AndroidManifest.xml`, trong `<activity android:name=".MainActivity">`
```xml
<intent-filter>
  <action android:name="android.intent.action.SEND" />
  <category android:name="android.intent.category.DEFAULT" />
  <data android:mimeType="audio/*" />
  <data android:mimeType="video/*" />
  <data android:mimeType="application/pdf" />
</intent-filter>
```
(Nếu muốn nhận nhiều file: thêm `SEND_MULTIPLE` — app hiện chỉ lấy file đầu.)
`android:launchMode="singleTask"` đã cần cho deep link, dùng chung.

Kiểm tra: Voice Memos › … › Share › One AI (iOS); Files › chia sẻ .m4a (Android).

## Ghi âm chống ngắt — chunk + foreground service Android (S11-09)

App ghi theo **chunk 5 phút** (`recordingChunk`): mỗi chunk là một file m4a hoàn
chỉnh ngay khi đóng, crash/kill chỉ mất tối đa chunk đang mở; Home khôi phục các
chunk còn nguyên. Các chunk upload lên `source/parts/part-NNN.m4a`, server ghép
bằng ffmpeg (`partCount` trong `startTranscription`) — không cần gì ở app.

### Android — `AndroidManifest.xml` (plugin `flutter_foreground_task`)
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<!-- trong <application> -->
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```
Không có mục này thì app vẫn ghi được khi ở foreground; `RecordingService`
nuốt lỗi. Android 13+: xin quyền thông báo (đã có luồng push) để thấy
notification "Đang ghi âm".

### iOS
`UIBackgroundModes` đã có `audio` (mục ghi âm nền ở trên) — đủ; không dùng
foreground service.

