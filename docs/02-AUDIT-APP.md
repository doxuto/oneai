# One AI — Flutter App Documentation (as-built)

> **Nguồn:** sinh tự động từ việc đọc toàn bộ source ngày 2026-09-22. Audit App Flutter as-built — design tokens, flow, contract, ads
> Đây là tài liệu *mô tả hiện trạng* — không sửa code theo nó, chỉ dùng làm input cho v2.

Source root: `/Users/<you>/mnt/oneai/App/oneai` (device path `$HOME/mnt/oneai/App/oneai`)
Dart package name: **`codebase_ai`** (all imports are `package:codebase_ai/...`) — the pubspec `name`/`description` are still the template's (`"A new Flutter codebase project."`).
Version: `1.0.4+16`. SDK `^3.7.2`.

---

## 1. Design system

### 1.1 Color schemes

`lib/ui/core/themes/color_schemes/light_color_scheme.dart` and `.../dark_color_scheme.dart` each define a static palette class plus a `ColorScheme` factory. Values below are verbatim.

**Palette classes (`LightColorScheme` / `DarkColorScheme` static consts)**

| Static const name | Light (`LightColorScheme`) | Dark (`DarkColorScheme`) |
|---|---|---|
| `primary` | `Color(0xFF2C7DF7)` | `Color(0xFFBB86FC)` |
| `primaryContainer` | `Color(0xFFE8DDFF)` | `Color(0xFF4F378B)` |
| `onPrimaryContainer` | `Color(0xFF21005E)` | `Color(0xFFE8DDFF)` |
| `secondary` | `Color(0xFF03DAC6)` | `Color(0xFF03DAC6)` |
| `secondaryContainer` | `Color(0xFFCEFAF8)` | `Color(0xFF00504C)` |
| `onSecondaryContainer` | `Color(0xFF002021)` | `Color(0xFFBBF5F1)` |
| `background` | `Color(0xFFFFFFFF)` | `Color(0xFF121212)` |
| `onBackground` | `Color(0xFF1C1B1F)` | `Color(0xFFE6E1E5)` |
| `surface` | `Color(0xFFFFFFFF)` | `Color(0xFF121212)` |
| `onSurface` | `Color(0xFF1C1B1F)` | `Color(0xFFE6E1E5)` |
| `surfaceVariant` | `Color(0xFFE7E0EB)` | `Color(0xFF49454F)` |
| `onSurfaceVariant` | `Color(0xFF49454E)` | `Color(0xFFCAC4D0)` |
| `error` | `Color(0xFFB00020)` | `Color(0xFFCF6679)` |
| `onError` | `Color(0xFFFFFFFF)` | `Color(0xFF000000)` |
| `errorContainer` | `Color(0xFFFFDAD4)` | `Color(0xFF8C0009)` |
| `onErrorContainer` | `Color(0xFF410001)` | `Color(0xFFFFDAD4)` |
| `outline` | `Color(0xFFBDBDBD)` | `Color(0xFF938F99)` |
| `shadow` | `Color(0xFF000000)` | `Color(0xFF000000)` |
| `scrim` | `Color(0xFF000000)` | `Color(0xFF000000)` |

**`ColorScheme` roles actually wired into `ThemeData` (`createLightColorScheme()` / `createDarkColorScheme()`)**

| ColorScheme role | Light | Dark |
|---|---|---|
| `primary` | `0xFF2C7DF7` | `0xFFBB86FC` |
| `onPrimary` | `Colors.white` | `Colors.black` |
| `primaryContainer` | `0xFFE8DDFF` | `0xFF4F378B` |
| `onPrimaryContainer` | `0xFF21005E` | `0xFFE8DDFF` |
| `secondary` | `0xFF03DAC6` | `0xFF03DAC6` |
| `onSecondary` | `Colors.black` | `Colors.black` |
| `secondaryContainer` | `0xFFCEFAF8` | `0xFF00504C` |
| `onSecondaryContainer` | `0xFF002021` | `0xFFBBF5F1` |
| `surface` | `0xFFFFFFFF` | `0xFF121212` |
| `onSurface` | `0xFF1C1B1F` | `0xFFE6E1E5` |
| `surfaceContainerHighest` | `0xFFE7E0EB` | `0xFF49454F` |
| `onSurfaceVariant` | `0xFF49454E` | `0xFFCAC4D0` |
| `error` | `0xFFB00020` | `0xFFCF6679` |
| `onError` | `0xFFFFFFFF` | `0xFF000000` |
| `outline` | `0xFFBDBDBD` | `0xFF938F99` |
| `shadow` | `0xFF000000` | `0xFF000000` |
| `inverseSurface` | `Color(0xFF313033)` | `Color(0xFFE6E1E5)` |
| `onInverseSurface` | `Color(0xFFF4EFF4)` | `Color(0xFF1C1B1F)` |
| `inversePrimary` | `Color(0xFFCFBCFF)` | `Color(0xFF6750A4)` |
| `surfaceTint` | `0xFF2C7DF7` (= primary) | `0xFFBB86FC` (= primary) |
| `brightness` | `Brightness.light` | `Brightness.dark` |

Note: `background`, `onBackground`, `errorContainer`, `onErrorContainer`, `scrim` are defined in the palette classes but **not** passed into the `ColorScheme` constructor — they are dead constants.

### 1.2 Theme extension — `lib/ui/core/themes/theme_extension.dart`

`class AppThemeExtension extends ThemeExtension<AppThemeExtension>` with two static instances, `AppThemeExtension.light` and `AppThemeExtension.dark`:

| Token | Light | Dark |
|---|---|---|
| `successColor` | `Color(0xFF00BFA5)` | `Color(0xFF00C897)` |
| `onSuccessColor` | `Colors.white` | `Colors.black` |
| `successContainerColor` | `Color(0xFFCCF5E9)` | `Color(0xFF00513C)` |
| `onSuccessContainerColor` | `Color(0xFF00382D)` | `Color(0xFF7AEBC3)` |
| `warningColor` | `Color(0xFFFFC107)` | `Color(0xFFFFA000)` |
| `onWarningColor` | `Colors.black` | `Colors.black` |
| `warningContainerColor` | `Color(0xFFFFE082)` | `Color(0xFF653A00)` |
| `onWarningContainerColor` | `Color(0xFF332800)` | `Color(0xFFFFDDB3)` |
| `buttonRadius` | `Radius.circular(8)` | `Radius.circular(8)` |
| `cardRadius` | `Radius.circular(12)` | `Radius.circular(12)` |
| `dialogRadius` | `Radius.circular(16)` | `Radius.circular(16)` |
| `animationFast` | `Duration(milliseconds: 200)` | same |
| `animationMedium` | `Duration(milliseconds: 300)` | same |
| `animationSlow` | `Duration(milliseconds: 500)` | same |

`lerp()` interpolates colors with `Color.lerp` and snaps `Radius`/`Duration` at `t < 0.5`.

Same file exposes `extension AppThemeContextExtension on BuildContext`: `context.theme`, `context.textTheme`, `context.colorScheme`, `context.appTheme` (falls back to `AppThemeExtension.light` if the extension is absent).

Only `buttonRadius` and `cardRadius` are actually consumed in the UI (`premium_button.dart`, `theme_selector.dart`, `transcription_summary_screen.dart`). The success/warning tokens, `dialogRadius` and the three animation durations are unused anywhere in `lib/`.

### 1.3 Theme helpers — `lib/ui/core/themes/theme_helpers.dart`

Pure utilities, no tokens: `getBrightness(context)`, `isDarkMode(context)`, `updateSystemUiOverlayDirect({isDark, themeData, statusBarColor, navigationBarColor})` (defaults status bar to `Colors.transparent`, nav bar to `colorScheme.surface`), `withOpacity(color, opacity)`, `darken(color, [amount=0.1])`, `lighten(color, [amount=0.1])`, `adaptiveColor(context, lightColor, darkColor)`, `primaryShade(context, {opacity=0.1})`.

### 1.4 Typography — `lib/ui/core/themes/typography.dart`

`AppTypography.createTextTheme()` returns one `TextTheme` shared by **both** themes. No `height` is set on any style. Font family is applied at `ThemeData` level, not per-style.

| Style | size | weight | letterSpacing | height |
|---|---|---|---|---|
| `displayLarge` | 57 | `w400` | `-0.25` | — |
| `displayMedium` | 45 | `w400` | `0` | — |
| `displaySmall` | 36 | `w400` | `0` | — |
| `headlineLarge` | 32 | `w400` | `0` | — |
| `headlineMedium` | 28 | `w400` | `0` | — |
| `headlineSmall` | 24 | `w400` | `0` | — |
| `titleLarge` | 22 | `w500` | `0` | — |
| `titleMedium` | 16 | `w500` | `0.15` | — |
| `titleSmall` | 14 | `w500` | `0.1` | — |
| `labelLarge` | 14 | `w500` | `0.1` | — |
| `labelMedium` | 12 | `w500` | `0.5` | — |
| `labelSmall` | 11 | `w500` | `0.5` | — |
| `bodyLarge` | 16 | `w400` | `0.5` | — |
| `bodyMedium` | 14 | `w400` | **`-0.41`** | — |
| `bodySmall` | 12 | `w400` | `0.4` | — |

Also `AppTypography.applyFontFamily(TextTheme, String?)` — defined but never called.

### 1.5 Dimens — `lib/ui/core/themes/dimens.dart`

All are top-level `const SizedBox` widgets (no numeric constants, no radius constants here):

- Width: `gapW4` (4), `gapW8` (8), `gapW12` (12), `gapW16` (16), `gapW24` (24), `gapW32` (32), `gapW48` (48), `gapW64` (64)
- Height: `gapH4` (4), `gapH8` (8), `gapH12` (12), `gapH16` (16), `gapH24` (24), `gapH32` (32), `gapH48` (48), `gapH64` (64)

### 1.6 ThemeData (light and dark) — `light_theme.dart` / `dark_theme.dart`

Both: `useMaterial3: true`, `fontFamily: 'Roboto'`, `extensions: [AppThemeExtension.light|dark]`.

Shared component themes (identical values in both files unless noted):
- `appBarTheme`: `backgroundColor: colorScheme.surface`, `foregroundColor: colorScheme.onSurface`, `elevation: 0`, `systemOverlayStyle: SystemUiOverlayStyle.dark` (light theme) / `.light` (dark theme), status bar transparent.
- `cardTheme`: elevation `2`, radius `12`, color `colorScheme.surface`.
- `elevatedButtonTheme`: elevation `2`, padding `H16/V12`, radius `8`, bg `primary`, fg `onPrimary`.
- `textButtonTheme`: padding `H16/V12`, radius `8`, fg `primary`.
- `outlinedButtonTheme`: padding `H16/V12`, radius `8`, fg `primary`, side `colorScheme.outline`.
- `inputDecorationTheme`: `filled: true`, fill `surface`, all borders radius `8`, focused border `primary` width `2`, error border `error`, contentPadding `H16/V16`.
- `chipTheme`: bg `surface`, label `labelLarge` in `onSurfaceVariant`, padding `H16/V12`, radius `8`.
- `dialogTheme`: bg `surface`, radius `16`.
- `bottomSheetTheme`: **light** = `backgroundColor: Colors.transparent`, `modalBackgroundColor: Colors.transparent`, `constraints: tightFor(width: infinity)`. **dark** additionally has `modalElevation: 0` and `shape: RoundedRectangleBorder(radius 16)`.
- `scaffoldBackgroundColor: colorScheme.surface`.
- `dividerColor: colorScheme.outline.withAlpha(51)`.
- `switchTheme`: thumb `primary` when selected else `outline`; track `primary.withAlpha(128)` when selected else `surface`.
- `checkboxTheme`: fill `primary` when selected, radius `4`.
- `sliderTheme`: active `primary`, inactive `primary.withAlpha(77)`, thumb `primary`, overlay `primary.withAlpha(31)`.
- `progressIndicatorTheme`: color `primary`, circular/linear track `primary.withAlpha(51)`.

**Dark-theme-only extras:** `snackBarTheme` (bg `inverseSurface`, text `onInverseSurface`, floating, radius `8`), `tooltipTheme` (bg `inverseSurface`, radius `4`), `iconTheme` (`onSurface`, size `24`).

### 1.7 Fonts and assets

`pubspec.yaml` `flutter:` block declares:
```yaml
assets:
  - assets/icons/
  - assets/images/
  - assets/fonts/
```
**There is no `fonts:` declaration.** `assets/fonts/Roboto-Bold.ttf` and `assets/fonts/Roboto-Regular.ttf` ship as raw assets only, so `fontFamily: 'Roboto'` resolves to the platform default, not the bundled file. (See §8.)

`assets/` contents:
- `assets/fonts/`: `Roboto-Bold.ttf`, `Roboto-Regular.ttf`
- `assets/images/`: `app_icon.png`, `splash.png`, `like_button.png`, `dislike_button.png` + 1.5x/2.0x/3.0x/4.0x variants of the like/dislike buttons
- `assets/icons/` (44 SVGs): `ant-design_tags-outlined.svg`, `bx_smile.svg`, `circular_complication.svg`, `flat-color-icons_google.svg`, `fluent-color_premium-20.svg`, `fluent-emoji-flat_waving-hand.svg`, `fluent_delete-16-regular.svg`, `ic_baseline-apple.svg`, `ic_clock_bg.svg`, `ic_contact.svg`, `ic_delete_account.svg`, `ic_enter.svg`, `ic_feedback.svg`, `ic_free.svg`, `ic_gallery.svg`, `ic_gift_fill.svg`, `ic_policy.svg`, `ic_review.svg`, `ic_signout.svg`, `ic_subscription.svg`, `ic_terms.svg`, `ic_voice.svg`, `ic_youtube_video.svg`, `iconamoon_arrow-up-2-light.svg`, `iconamoon_close-light.svg`, `iconamoon_comment-light.svg`, `ion_flash-sharp.svg`, `lets-icons_add-round.svg`, `lets-icons_comment-light.svg`, `lineicons_message-2-question.svg`, `lsicon_paste-outline.svg`, `lucide_audio-lines.svg`, `material-symbols-light_text-ad-outline-rounded.svg`, `material-symbols_list.svg`, `mdi-light_clock.svg`, `mdi-light_note-text.svg`, `mdi_edit.svg`, `mdi_tick-all.svg`, `mi_share.svg`, `mynaui_danger-triangle-solid.svg`, `proicons_pdf-2.svg`, `solar_play-bold.svg`, `tabler_microphone-filled.svg`, `weui_setting-outlined.svg`

All paths are centralised as `static const` in `lib/config/assets.dart` (`abstract final class Assets`). Splash: `flutter_native_splash` color `#ffffff`, image `assets/images/splash.png`. Launcher icon: `assets/images/app_icon.png`, adaptive bg `#ffffff`, foreground inset 16, iOS bg `#ffffff`, `remove_alpha_ios: true`.

### 1.8 Theme mode selection and persistence

- `ThemeType` enum: `system`, `light`, `dark` — `lib/domain/models/theme_type_model.dart`.
- `ThemeBloc` (`lib/ui/core/themes/view_model/theme_bloc.dart`): events `ThemeEvent.initial()`, `ThemeEvent.changed({themeType})`; state `ThemeState({themeType, themeData, isDarkMode})`. `ThemeState.initial()` defaults to `ThemeType.system` and picks `darkTheme`/`lightTheme` from `SchedulerBinding.instance.platformDispatcher.platformBrightness`. On `changed` it resolves `themeData`, calls `ThemeHelpers.updateSystemUiOverlayDirect(...)` with a transparent status bar, persists via repository, and only emits if the save returned `Ok`. It early-returns if `state.themeType == themeType`.
- `ThemeRepositoryImpl` → `SharedPreferencesService.getTheme()/setTheme()` → key `'APP_THEME'`, stored as `ThemeType.name`, default `system`.
- Registered in `lib/config/dependencies.dart` as `BlocProvider(create: ... ThemeBloc(...)..add(const ThemeEvent.initial()))`.
- UI: `lib/ui/core/themes/widgets/theme_selector.dart` — a `PopupMenuButton<ThemeType>` (icon `Icons.dark_mode`/`Icons.light_mode`) with System / Light / Dark items. **This widget is never mounted by any screen.**
- **Critical:** `lib/main.dart` wraps the app in `BlocSelector<ThemeBloc, ThemeState, ThemeData>` but then passes `theme: lightTheme` (hardcoded) to `MaterialApp.router` and sets no `darkTheme`/`themeMode`. Dark mode is therefore never applied at runtime. The dark palette is dead code today. **Preserve `lightTheme` exactly; do not "fix" this during the rework unless the user asks.**

---

## 2. Navigation map

`lib/routing/routes.dart` — `abstract final class Routes`:

| Constant | Path string |
|---|---|
| `root` | `'/'` |
| `login` | `'/login'` |
| `demoHome` | `'/demoHome'` |
| `demoUsers` | `'/demoUsers'` |
| `demoPosts` | `'/demoPosts'` |
| `postDemoWithId(int id)` | `'$demoPosts/$id'` (helper) |
| `demoSettings` | `'/demoSettings'` |
| `demoCategories` | `'/demoCategories'` |
| `transcriptionSummary` | `'/transcriptionSummary'` |
| `recordAudio` | `'/recordAudio'` |
| `uploadFile` | `'/uploadFile'` |
| `youtubeVideo` | `'/youtubeVideo'` |
| `audioProcessing` | `'/audioProcessing'` |
| `settings` | `'/settings'` |

`lib/routing/router.dart` — `GoRouter createAppRouter(AuthBloc authBloc)`:
- `navigatorKey: rootNavigatorKey` (a top-level `GlobalKey<NavigatorState>(debugLabel: 'root')`, also read by `OpenAppAdService` for warm-start ads).
- `debugLogDiagnostics: true`, `initialLocation: Routes.root`.
- `errorBuilder: _errorPage` — `Scaffold` + `AppBar(context.loc.pageNotFound)`, `Icon(Icons.error_outline, size: 64, color: colorScheme.error)`, `gapH16`, `context.loc.pageNotFoundMessage(state.uri.path)` in `titleMedium` bold, `gapH16`, `ElevatedButton(context.loc.goHome)` → `context.go(Routes.root)`.
- `refreshListenable: AuthStateNotifier(authBloc)` — a `ChangeNotifier` subscribing to `AuthBloc.stream` and calling `notifyListeners()` on every state.
- `redirect: _authGuard` — **global**, applies to every route. Reads `context.read<AuthRepository>().isAuthenticated`. If not authenticated and not already at `/login` → `Routes.login`. If authenticated and at `/login` → `Routes.root`. Else `null`.

**Route tree** (indentation = `GoRoute.routes` nesting; there are no `ShellRoute`s anywhere):

```
GoRouter (rootNavigatorKey, initialLocation '/')
│  global redirect: _authGuard  (unauthenticated → /login ; authenticated on /login → /)
│  refreshListenable: AuthStateNotifier(AuthBloc)
│  errorBuilder: _errorPage
│
├─ /login                          → LoginPage()
│     page: MaterialPage<void>   (no custom transition)
│
├─ /                               → BlocProvider(HomeBloc(tagUseCase, minuteUseCase)..add(HomeEvent.onInit())) → HomeScreen()
│     page: PageAnimationManager.createPage, transition: fadeTransition
│     │
│     ├─ /transcriptionSummary     → BlocProvider(TranscriptionSummaryBloc(shareRepository, minuteUseCase, oneAiRepository)
│     │                                ..add(TranscriptionSummaryEvent.loadMinute(minuteId: state.extra as String)))
│     │                              → TranscriptionSummaryScreen()
│     │     extra: String minuteId (REQUIRED — unguarded `as String` cast)
│     │     page: PageAnimationManager.createPage, transition: slideRightToLeftTransition
│     │
│     └─ /settings                 → BlocProvider(SettingsBloc(authRepository)) → SettingsScreen()
│           page: PageAnimationManager.createPage, transition: slideRightToLeftTransition
│
├─ /demoHome                       → DemoHomeScreen()            [demo scaffolding]
│     builder: (plain MaterialPage, no animation)
│
├─ /demoUsers                      → BlocProvider(DemoUserBloc(...)) → DemoUserScreen()   [demo]
│     transition: fadeTransition
│
├─ /demoPosts/:postId              → DemoPostDetailScreen(post: state.extra as DemoPostModel)  [demo]
│     transition: slideRightToLeftTransition
│
├─ /demoSettings                   → inline Scaffold placeholder (context.loc.settingsComingSoon)   [demo]
│
├─ /demoCategories                 → inline Scaffold placeholder (context.loc.categoriesComingSoon) [demo]
│
├─ /recordAudio                    → RecordAudioScreen()
│     transition: slideRightToLeftTransition
│
├─ /uploadFile                     → UploadFileScreen()
│     transition: slideRightToLeftTransition
│
├─ /youtubeVideo                   → YouTubeVideoScreen()
│     transition: slideRightToLeftTransition
│
└─ /audioProcessing                → AudioProcessingScreen()
      extra: Map {audioPath|youtubeLink, audioLanguage, summaryLanguage, recordingContext?, keywords?}
      transition: slideRightToLeftTransition
```

**Transitions** — `lib/ui/core/ui/animation/page_animation_manager.dart`:
- `PageAnimationManager.createPage(...)` returns a **`CupertinoPage` on iOS/macOS** (so every `transitionBuilder` above is ignored on iOS; you get the native swipe-back slide) and a `CustomTransitionPage` with the given builder on other platforms.
- Available builders: `fadeTransition` (`FadeTransition` with `CurveTween(Curves.easeInOut)`), `slideRightToLeftTransition` (`Tween<Offset>(begin: Offset(1,0), end: Offset.zero)`), `slideBottomToTopTransition` (`Offset(0,1) → zero`, **unused**), `scaleTransition` (`ScaleTransition` + `Curves.easeInOut`, **unused**).

Navigation calls in the app: `context.go(Routes.settings)` (home header), `context.push(Routes.transcriptionSummary, extra: item.id)` (minute card), `context.go(Routes.transcriptionSummary, extra: _minuteId)` (after processing), `context.push(Routes.recordAudio | uploadFile | youtubeVideo)` (new-minute sheet), `context.push(Routes.audioProcessing, extra: {...})` (record/upload/youtube), `context.push(Routes.uploadFile)` (YouTube "unsupported formats" link), `context.pop()` (back from summary/settings/processing).

---

## 3. Screen-by-screen flow spec

### 3.1 `login_page.dart` — `LoginPage` (`/login`)
- **Purpose:** unauthenticated entry point. `StatefulWidget`.
- **Consumes:** `BlocConsumer<AuthBloc, AuthState>`. Also constructs its own `SharedPreferencesService()` directly (not DI) to read the previous login method.
- **Displays:** `Scaffold` → `SafeArea` → `Padding(all 16)` → centered `Column`:
  - `Spacer`
  - Row: `SvgPicture.asset(Assets.circularComplicationIcon, 50×50)` + `gapW12` + `Text(context.loc.oneAi)` at `fontSize: 28, FontWeight.bold`
  - `gapH12`, `RichText` centered: `TextStyle(w600, 24, Colors.black)` with `context.loc.instantNotesFromAudio` then `context.loc.doneWithAi` in `Color(0xFF0767F8)`
  - `Spacer`
  - Google button: `OutlinedButton`, `backgroundColor: Colors.white`, `side: BorderSide(Colors.black)`, radius `24`, padding `vertical 14`, contents `SvgPicture(Assets.googleIcon, 17×17)` + `gapW4` + `context.loc.signInWithGoogle` (16, black, w600), plus a 16×16 `CircularProgressIndicator(strokeWidth: 2)` while that button is loading.
  - **iOS only** (`if (Platform.isIOS)`): `gapH12` + Apple button: `ElevatedButton`, bg `Colors.black`, fg `Colors.white`, radius `24`, padding `vertical 14`, `Assets.appleIcon` 17×17 + `context.loc.signInWithApple`; then `gapH12`, and if `_previousLoginMethod != null` a 12px black w400 line `'(Previously signed in with Google)'` / `'(Previously signed in with Apple)'`; then `gapH24`.
- **Actions:** Google tap → `HapticFeedback.lightImpact()`, `_loadingButton = 'google'`, `AuthBloc.add(AuthEvent.signInWithGoogle())`. Apple tap → same with `'apple'` / `signInWithApple()`.
- **Loading:** per-button spinner driven by `state is LoadingAuthState && _loadingButton == <method>`.
- **Error:** listener shows a `SnackBar(state.message)` on `ErrorAuthState` and clears `_loadingButton`.
- **Navigates:** nowhere explicitly — the router's `_authGuard` redirects to `/` when `AuthBloc` emits authenticated.
- **Note:** the Apple button and the "previously signed in" hint are both inside the `Platform.isIOS` block, so the hint never shows on Android.

### 3.2 `home_screen.dart` — `HomeScreen` (`/`)
- **Purpose:** notes list + tag filtering + entry to creation flows.
- **Consumes:** `HomeBloc` (provided by the route). Also directly: `Purchases` (RevenueCat) via a `CustomerInfoUpdateListener`, `RemoteConfigService`, `SharedPreferencesService`, and `isPremium()`.
- **initState:** `_checkEntitlement()`, `Purchases.addCustomerInfoUpdateListener(_customerInfoListener)`, `ScrollController` + `_onMinutesScroll`, `Future.microtask(_showIntroBasicPopup)`.
- **Layout:** `Scaffold(backgroundColor: colorScheme.surface)` → `SafeArea` → `Padding(horizontal 16)` → `Stack`:
  - Header row (`Padding(top: 16)`): `PremiumButton(state: premium|upgrade)`, `Spacer`, feedback icon button (`Assets.messageIcon`, 24×24), `gapW16`, settings icon button (`Assets.settingsIcon`, 24×24). Each is an `InkWell(borderRadius: 8, padding: 8)`.
  - `gapH16`, title `Text('My Notes')` in `headlineMedium` bold — **hardcoded English string, not localized**.
  - `gapH24`, tag row: `SizedBox(height: 44)` with a horizontal `ListView.separated` (8px separators). Item 0 = "create tag" pill (`height 40`, bg `Color(0xFFEDF4FF)`, radius `20`, `Icons.add_circle_rounded` in `Color(0xFF0767F8)` size 18 + `context.loc.createTag` in `labelLarge` w500 `0xFF0767F8`). If `tags.length > 2`, item 1 = an "All" `TagChip` (`Tag(id: '', name: 'All')`) selected when `selectedTagIds.isEmpty`. Remaining items = one `TagChip` per tag.
  - `gapH24`, `Expanded(RefreshIndicator(onRefresh → HomeEvent.loadMinuteItems(isRefresh: true, isLoadMore: false)) → _buildMinutesList())`.
  - Overlay: when `state.isLoading`, `Positioned.fill(ColoredBox(Colors.transparent, Center(CircularProgressIndicator())))`.
- **Minutes list:** filters `state.minutes` by `selectedTagIds.every((id) => m.tags?.contains(id) ?? false)`.
  - **Empty state** (filtered empty and not loading): a `CustomScrollView`/`SliverFillRemaining` aligned at `Alignment(0, -0.4)` with a 60×60 circle `Color(0xFFE1EDFF)` containing `Assets.clockIcon` 32×32 tinted `Color(0xFF0767F8)`, `gapH16`, `context.loc.noNotesYet` (`titleMedium` w500), `gapH8`, `context.loc.tapButtonBelowToStart` (`bodyMedium`, `onSurfaceVariant`).
  - Otherwise `ListView.builder` (`padding: EdgeInsets.only(bottom: 80)`), each item `Padding(bottom: 16) → MinuteItemCard(item:)`; when `state.isLoadingMore` an extra trailing `Padding(vertical: 24) → Center(LoadingDots())`.
- **Infinite scroll:** `_onMinutesScroll` fires `HomeEvent.loadMinuteItems(isRefresh: false, isLoadMore: true)` when within 200px of the bottom, with a `_isLoadMoreTriggered` latch reset at 400px from the bottom.
- **FAB:** `FloatingActionButtonLocation.centerFloat`. An `AnimatedSlide`(250ms, `Curves.ease`) + `AnimatedOpacity`(200ms) that hides the FAB (`Offset(0, 1.2)`, opacity 0) whenever `MediaQuery.viewInsets.bottom > 0` (keyboard open). The button itself: full-width, `height 56`, bg `Color(0xFF0767F8)`, radius `28`, `Icons.add` white + `gapW8` + `context.loc.newNote` (`labelLarge`, white, w600). Tap → `showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent, shape: vertical top Radius 20) → NewMinutesBottomSheet()`.
- **Premium button tap:** if not premium → `RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId)`; if premium → the button is disabled (`onPressed: null`), though `_onPremiumButtonPressed()` would call `RevenueCatUI.presentCustomerCenter()`.
- **Feedback icon:** `showDialog(builder: (_) => const SentryFeedbackDialog())`.
- **Settings icon:** `context.go(Routes.settings)`.
- **Create-tag dialog:** `AlertDialog` radius `16`, title `context.loc.createNewTag` (`titleLarge`, centered), body `context.loc.enterTagName` + a `TextField` constrained to `getDialogWidth(context)` with hint `context.loc.tagName`, borders radius 8 `Colors.grey.shade300` (focused = `colorScheme.primary`). Actions = full-width `Divider(Color(0xFFBDBDBD))` then a split `Cancel` / `Create` row divided by a `VerticalDivider(Color(0xFFBDBDBD))`, both `labelLarge` in `Colors.blue`, bottom corners radius 16. `Create` → `HomeEvent.createTag(name:)` when text non-empty.
- **Delete-tag dialog** (tag long-press): same shell, title `'Delete Tag'` (hardcoded), body `'Are you sure you want to delete the tag "<name>"?'` (hardcoded), right action `'Delete'` in `Color(0xFFE41919)` → `HomeEvent.deleteTag(tagId:)`.
- **Intro-basic popup** (`_showIntroBasicPopup`, fired once from `initState`): skipped if `await isPremium()`; skipped if `!remoteConfig.popupIntroBasicEnabled`; if a previous `INTRO_BASIC_LAST_SHOWN_TIME` exists then skipped when `popupIntroBasicFrequencyHours == 0` (show-once) or when `now.difference(lastShown).inHours < freqHours`. Renders `AlertDialog` titled `'Basic Plan Overview'` (hardcoded) with body = `remoteConfig.popupIntroBasicText`. Both buttons call `_requestTrackingAuthorization()` (iOS ATT prompt, only if `TrackingStatus.notDetermined`); left = `Cancel`, right = `'Go Premium'` in `Color(0xFFE41919)` → `_onPremiumButtonPressed()`. Afterwards persists `setIntroBasicLastShownTime(now)`. **This is also the flag that gates cold-start App Open ads** (see §6).

### 3.3 `record_audio_screen.dart` — `RecordAudioScreen` (`/recordAudio`)
- **Purpose:** in-app recording via `package:record`.
- **State:** local `StatefulWidget` only (`TickerProviderStateMixin`) — no bloc. `RecordingState { initial, recording, paused }`, `_recordingSeconds`, `AudioRecorder`, `_audioPath`, `_audioLanguage`, `_summaryLanguage`, `_recordingContext`, `_keywords`. Instantiates its own `SharedPreferencesService()`.
- **initState:** creates `AudioRecorder`, an `AnimationController(3000ms)..repeat()` for the ripple, loads the saved audio/summary languages from prefs.
- **AppBar:** white bg, elevation 0, `IconButton(Icons.arrow_back)`, title = `Assets.circularComplicationIcon` 32×32 + `gapW8` + `Text('One AI')` (`titleMedium` bold) — **hardcoded string**, `centerTitle: false`.
- **Body:** `Scaffold(backgroundColor: Colors.white)`. Centered 220×220 `Stack`:
  - 4 ripple rings generated from the controller: size `120 + value*100`, opacity `(1.0 - value) * _waveOpacities[i]` where `_waveOpacities = [1.0, 0.8, 0.6, 0.4]`, staggered by `index * 0.2`, border `colorScheme.primary.withAlpha(128)` width `1.5`. Opacity forced to `0.0` when not recording.
  - Center button: 120×120 circle, fill `primary` while recording else `Colors.white`, border `primary` width `2` when paused else `1`, child `Assets.microphoneFilledIcon` 36×36 tinted white while recording else `primary`.
  - `gapH24`, status text (`bodyLarge`, `Colors.grey[600]`): `context.loc.tapToStartRecording` / `tapToStopRecording` / `recordingPaused`.
  - Timer `Padding(top: 8)`, `Opacity(0.0)` while initial, text `mm:ss` in `bodyMedium`, colored `primary` while recording else `Colors.grey[500]`.
  - `SizedBox(height: 60)`, then a `TextButton.icon` (`height 48`, `iconAlignment: IconAlignment.end`) with `Assets.settingsIcon` 24×24 tinted `primary` and label `context.loc.promptAndLanguage` → opens `PromptLanguageSheet` and writes the returned map back into local state.
- **Transcribe button:** `Padding(H24/V16)` → `Visibility(visible: _recordingState == paused, maintainSize/Animation/State: true)` → `PremiumStatusBuilder` → `ElevatedButton` (bg `primary`, fg white, `minimumSize: Size.fromHeight(56)`, radius `28`). Label = `context.loc.transcribeAndSummarize`, or the hardcoded `'Watch Ad to Transcribe'` when `status == PremiumStatus.nonPremiumNoCredits`. Tap → `premiumActionWrapper(context, status, ...)` → `_audioRecorder.stop()` then `context.push(Routes.audioProcessing, extra: {audioPath, audioLanguage, summaryLanguage, recordingContext, keywords})`.
- **Recording config:** `RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100)`, file at `${getApplicationDocumentsDirectory()}/minutes_ai_${millisecondsSinceEpoch}.m4a`. Guarded by `await _audioRecorder.hasPermission()` — if permission is denied nothing happens and no message is shown.
- **Exit guard:** `PopScope(canPop: _recordingState == RecordingState.initial)`; otherwise `_showExitWarningDialog` — `AlertDialog` radius 16, title row with `Assets.warningTriangleIcon` 18×18 tinted `Color(0xFFF8C307)` + `context.loc.warning` (`titleLarge`), body `context.loc.exitRecordingWarning`, actions `Cancel` (blue) / `context.loc.exit` in `Color(0xFFE41919)` → `_stopAndClearRecording()` then two `Navigator.pop`s.

### 3.4 `upload_file_screen.dart` — `UploadFileScreen` (`/uploadFile`)
- **Purpose:** pick a local audio file.
- **State:** local only; `Language _audioLanguage = Language.autodetect`, `_summaryLanguage = Language.autodetect`, loaded from prefs in `initState`. Own `SharedPreferencesService()`.
- **Layout:** `AppBar(backgroundColor: Colors.transparent, elevation: 0, title: context.loc.uploadFromFiles in titleLarge bold)`. Body `Padding(all 24)` → Column: `context.loc.selectFileDescription` (`bodyLarge`), `gapH32`, Audio-language section, `gapH24`, Summary-language section, `Spacer`, select-file button, `gapH16`.
- **Language section:** title in `titleMedium` w600, `gapH16`, `LanguageSelector` whose trigger is a 40-high `Container` bg `Color(0xFFF5F5F5)` radius `8` padding `horizontal 12`, containing the language name in `bodyMedium` colored `colorScheme.primary` plus a stacked up/down chevron pair built by rotating `Assets.arrowUpIcon` 12×12 by `0.5π` and `1.5π`, tinted `primary`.
- **Select-file button:** full width `height 56`, `PremiumStatusBuilder` → `ElevatedButton` (bg `primary`, fg white, radius `28`). Label `context.loc.selectFile` or hardcoded `'Watch Ad to Transcribe'` when `nonPremiumNoCredits`; text style `titleMedium` bold white. Tap → `premiumActionWrapper(...)` → `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3','wav','m4a','aac'])`; on a non-null path → `context.push(Routes.audioProcessing, extra: {audioPath, audioLanguage, summaryLanguage})`.
- **No loading/error state.** A cancelled picker or a null path is silently ignored. The selected languages are **not** persisted back to prefs here (only Settings writes them).

### 3.5 `youtube_video_screen.dart` — `YouTubeVideoScreen` (`/youtubeVideo`)
- **State:** local; `_linkController` (a listener calls empty `setState` to re-evaluate `_canTranscribe = _linkController.text.trim().isNotEmpty`), two `Language`s loaded from prefs.
- **AppBar:** transparent, elevation 0, `context.loc.youtubeVideoNotes` in `titleLarge` bold.
- **Body:** `SafeArea` → `Padding(H24/V16)` → Column with a scrollable top area:
  - `'Paste a YouTube link for transcript & notes:'` in `bodyMedium` `Colors.black87` — **hardcoded string**.
  - `gapH16`, link field: 56-high `Container` bg `Color(0xFFF6F6F6)` radius `8`; a borderless `TextField` (hint `'https://...'` hardcoded, `bodyMedium` grey, filled `0xFFF6F6F6`, contentPadding horizontal 16) and a paste chip — white bg, radius `8`, border `Color(0xFFE5E5E5)`, `Assets.pasteOutlineIcon` 16×16 tinted `primary` + `gapW8` + `context.loc.tapToPaste` (`bodyMedium`, `primary`, w500). Paste tap → `Clipboard.getData(Clipboard.kTextPlain)` into the controller.
  - `gapH24` Audio language, `gapH24` Summary language — same pattern as upload, **except the trigger button here uses `Colors.blue` for both the label and the chevron tint instead of `colorScheme.primary`**.
  - `gapH48`.
  - Footer note (`_buildUnsupportedFormatsNote`): centered `RichText` of `context.loc.youtubeShortsPrefixText` (grey `bodySmall`) + `context.loc.youtubeUnsupportedFormatsLinkText` (`primary`, w500, `TapGestureRecognizer` → `context.push(Routes.uploadFile)`) + `context.loc.youtubeUnsupportedFormatsPeriod` (grey).
  - `gapH24`, transcribe button: full width `height 56`, `PremiumStatusBuilder` → `ElevatedButton` (bg `primary`, radius `28`), disabled (`onPressed: null`) when `!_canTranscribe`. Label = `context.loc.transcribeAndSummarize` or `'Watch Ad to Transcribe'`. Tap → `premiumActionWrapper(...)` → `context.push(Routes.audioProcessing, extra: {youtubeLink: trimmed, audioLanguage, summaryLanguage})`.
- **No client-side URL validation** beyond non-empty.

### 3.6 `audio_processing_screen.dart` — `AudioProcessingScreen` (`/audioProcessing`)
- **Purpose:** run the transcribe call while showing a simulated 5-step progress animation, and upsell a rewarded ad during the wait.
- **State:** local `StatefulWidget`, no bloc of its own. Reads `MinuteUseCase`, `OneAiRepository`, `RewardAdService` from context; `isPremium()` on init.
- **Route extras parsed in `didChangeDependencies`** (once, guarded by `_transcribeStarted`): `audioPath`, `audioLanguage`, `summaryLanguage`, `recordingContext`, `keywords`, `youtubeLink`.
- **Steps** (`_initializeSteps`, localized): `context.loc.processingAudio`, `transcribing`, `identifyingSpeakers`, `takingNotes`, `finishingTouches`. Each has `state ∈ {loading=0, completed=1, error=2}` and a `progress` double.
- **Progress simulation:** `Timer.periodic(50ms)`; per tick `progress += 0.001` normally, `+= 0.01` once `_shouldSpeedUp` (set when the API returns Ok). So the bar takes ~250s to fill on its own — the "did not complete in time" fallback fires only if the API hasn't answered by then.
- **API call (`_startTranscription`):** language `name`s are mapped to ISO codes via `Language.values.byName(x).languageCode`. If `youtubeLink` non-empty → `minuteUseCase.transcribeYoutube(youtubeUrl, audioLanguage, summaryLanguage)`. Else if `audioPath` non-empty → `minuteUseCase.transcribe(filePath, audioLanguage, summaryLanguage, keywords, description: recordingContext)`. Else returns silently.
  - **Ok:** `_minuteId = transcription.minuteId!` (unguarded `!`), then `OneAiRepository.getSpeakers(minuteId:)` (result discarded — a warm-up call), then `_shouldSpeedUp = true`.
  - **Error:** marks the first still-loading step as `error`, cancels the timer, and:
    - `DioException` with `response.statusCode == 402` → `AlertDialog` `'Premium Required'` / `'You have no free credits left. Please upgrade your plan.'` (both hardcoded), actions `Cancel` / `'Go Premium'` in `Color(0xFFE41919)`; on confirm `RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId)`.
    - any other status or any other error → `SnackBar('Something went wrong, please try later')` with `backgroundColor: colorScheme.error` (hardcoded string).
- **Completion:** when all steps finish, if `_shouldSpeedUp && _error == null`: if `_isPremium || !context.isFullscreenAdInProgress()` → after `Duration(microseconds: 200)` call `navigateToSummary()` (`context.go(Routes.transcriptionSummary, extra: _minuteId)`). Otherwise set `_isProcessSucceeded = true` and show a "Show Results" FAB instead (so navigation waits for the ad).
- **Layout:** `Scaffold(backgroundColor: colorScheme.surface)`, `AppBar` with `Assets.circularComplicationIcon` 32×32 + `gapW8` + `context.loc.appName` (`titleMedium` bold) and a trailing `IconButton(Icons.close)` → `context.pop()`. Body `SafeArea` → `Padding(horizontal 16)` → `SingleChildScrollView`:
  - `gapH16`, **processing card:** `Card(elevation: 0, radius 12, side: colorScheme.outline.withAlpha(25))`, `Padding(16)`, `ListView.separated` (shrinkWrap, `gapH16` separators). Each row: a 24×24 icon slot (empty `SizedBox` until `progress > 0`), `gapW12`, the label in `bodyMedium` w500, and a right-aligned `'<n>%'` in `bodyMedium` `primary` w500 while loading. Icon = filled `primary` circle with white `Icons.check` (16) when completed; filled `error` circle with `Icons.close` (16) when errored; else a 24×24 `CircularProgressIndicator(strokeWidth: 2, backgroundColor: surfaceContainerHighest, valueColor: primary)`.
  - `gapH16`, **reward-ad card** — only `if (!_isPremium)`: `Card(elevation 0, radius 12, outline.withAlpha(25))` with `Assets.giftFillIcon` 48×48, `gapH12`, `'Earn a Free Credit While You Wait!'` (`titleMedium` bold, centered), `gapH12`, the long hardcoded blurb `'Your audio is being processed. This might take a minute or two depending on its duration. While you wait, would you like to watch a short ad to earn 1 free credit?'` (`bodyMedium`, centered), `gapH12`, a 52-high `ElevatedButton` bg `Color(0xFFFEA200)` radius `82` labelled `'🔥 Watch Ad & Earn Credit'` (`titleMedium` w600) → `RewardAdService.showWhenWaitingTranscribeProcess(context:)`. All four strings are hardcoded English.
  - `Padding(horizontal 24)` → `context.loc.recordingProcessingMessage` (`bodyMedium`, `onSurfaceVariant`, centered), `gapH24`.
- **FAB:** `!_isPremium && _isProcessSucceeded` → full-width 56-high `ElevatedButton` bg `Color(0xFF0767F8)` radius `28` labelled `'Show Results'` (hardcoded, `labelLarge` white w600) → `navigateToSummary()`. `FloatingActionButtonLocation.centerFloat`.
- The close button pops without cancelling the in-flight upload.

### 3.7 `transcription_summary_screen.dart` — `TranscriptionSummaryScreen` (`/transcriptionSummary`)
- **Purpose:** the note detail — Summary / Transcript / Chat tabs, sharing, audio playback.
- **Consumes:** `TranscriptionSummaryBloc` (route-provided, already dispatched `loadMinute`), plus `InterstitialAdService`, `SharedPreferencesService`, `MinuteUseCase` from context.
- **Route extra:** the `minuteId` `String`; `didChangeDependencies` pops if `extra is! String`.
- **AppBar:** transparent, elevation 0, leading `IconButton(Icons.arrow_back, color: Color(0xFF2C7DF7))`, title `context.loc.back` in `titleMedium` `Color(0xFF2C7DF7)`, `titleSpacing: 0`. Action: a `PopupMenuButton<ShareOption>` (`position: under`, `offset: Offset(0, 8)`, shape radius = `context.appTheme.cardRadius`, `color: Colors.white`, `elevation: 4`, icon `Assets.shareIcon` 24×24 tinted `primary`). Items, each 44 high with a 20×20 `Colors.black87`-tinted SVG on the right and `Divider(Color(0xFFBDBDBD), height: 1)` between them:
  - `notesAsPdf` — `context.loc.shareNotesAsPdf`, `Assets.pdfIcon`
  - `notesAsText` — `context.loc.shareNotesAsText`, `Assets.textIcon`
  - `transcriptAsPdf` — `context.loc.shareTranscriptAsPdf`, `Assets.pdfIcon`
  - `transcriptAsText` — `context.loc.shareTranscriptAsText`, `Assets.noteTextIcon`
  - `audioFile` (only `if (showFAB)`, i.e. `minute.gcsUri != null`) — `context.loc.shareAudioFile`, `Assets.audioLinesIcon`
- **Body header:** `Padding(horizontal 16)` → title in `headlineMedium` bold, `gapH8`, `'<date> • <duration>'` in `bodyMedium` `Colors.grey[600]`, `gapH16`, `TranscriptTabSelector`, `gapH16`, `Expanded(tab content)`.
- **Loading / empty / error:** `state.isLoading` → centered `CircularProgressIndicator`. `state.errorMessage != null` → a post-frame `SnackBar(errorMessage, backgroundColor: Colors.red)` (clears previous snackbars first). If `minute == null || _meetingMinute == null || _transcript == null` → `SizedBox.shrink()`.
- **Minutes/Summary tab:** scroll view with the shared `InlineAdaptiveBannerAd` at the top (`Padding(bottom: 16)`), then one `MinuteSectionWidget` per `_meetingMinute.sections`, then `SafeArea(minimum: bottom 16) → FeedbackWidget()`.
- **Transcript tab:** the banner ad, then one `TranscriptMessageWidget` per `_transcript.messages`.
- **Chat tab:** the banner ad, the message list, a `ChatTypingIndicator` while `isChatLoading`, then `gapH16` and `SafeArea(minimum: bottom 16) → ChatInputWidget(onMessageSent, focusNode, suggestedQuestions)`. Selecting the chat tab dispatches `TranscriptionSummaryEvent.initChat()` if the conversation is empty and auto-scrolls to the bottom (300ms `Curves.easeOut`).
- **Sharing:** each option dispatches the matching `TranscriptionSummaryEvent.share*` with `sharePositionOrigin()` (the screen's `RenderBox` rect, needed for iPad) and opens `_showLoadingDialog()` — a barrier-non-dismissible `Dialog` (bg `colorScheme.surface`, radius 12) with a `CircularProgressIndicator` + `gapH16` + `context.loc.preparingContent`. Its `BlocListener`: on success → **`InterstitialAdService.showAfterShare(context:, showLoading: false)`**, then pop the dialog; on error → pop and `SnackBar(context.loc.errorSharingContent, backgroundColor: colorScheme.error)`.
- **Share audio special-case:** if `state.isAudioDownloading` → `SnackBar(context.loc.audioIsDownloading)` and return; if `state.audioSource == null` → dispatch `downloadAudio()` + `SnackBar(context.loc.audioIsStartingDownload)` and return.
- **Audio player:** FAB only on the Summary tab and only when `showFAB` (`gcsUri != null`). Two visual forms:
  - Collapsed: `Padding(bottom: 100)`, 42×42 `FloatingActionButton(mini: true, backgroundColor: Color(0xFF2C7DF7), elevation: 2, CircleBorder)`, showing a white 24×24 `CircularProgressIndicator(strokeWidth: 2.2)` while initial/loading/downloading, else `Assets.playIcon` 24×24 white. Tap (`_onPlayPressed`) → if downloading or not downloaded, shows the corresponding snackbar and sets `_playerShowingState = waitForControlDashboard`; if not ready, `SnackBar(context.loc.audioIsNotReady, backgroundColor: colorScheme.error)`; else expands.
  - Expanded dashboard (`_buildAudioPlayerUI`): `Padding(bottom: 100, left: 32)` → white `DecoratedBox` radius `16` with `BoxShadow(Colors.black12, blurRadius: 8, offset: Offset(0, 2))`. Row of controls all in `Color(0xFF2C7DF7)`: speed `TextButton` cycling `[0.5, 1.0, 1.5, 2.0]` shown as `'1.0x'` (bold), `Icons.replay_10`, play/pause (`Icons.pause`/`Icons.play_arrow`, size 32), `Icons.forward_10`, `Icons.close` (pauses and collapses). Below: current position, a `Slider` (drag tracked in `_sliderPosition`, seek on `onChangeEnd`), and total duration, both `fontSize: 12, Colors.black54`, in `mm:ss`.
  - `just_audio` `AudioPlayer` created in `_initAudioPlayer`, listening to `positionStream` and `playerStateStream`; `AudioPlayerLoadingState { initial, loading, notDownloaded, ready }`, `AudioPlayerShowingState { playButton, waitForControlDashboard, controlDashboard }`.
- **Back / exit (`PopScope(canPop: false)` → `_showCongratulationDialog`):**
  - If **not** (`getShowCongratulationDialog()` is true **and** `MinuteUseCase.minutes.length == 1`) → `InterstitialAdService.showBeforeSummaryExit(context:)` then `context.pop()`.
  - Otherwise show the `'Congratulation'` dialog (title hardcoded, body the hardcoded "Congratulations on transcribing your first audio!…" blurb). Left button `"Sure, I'll rate it"` (blue) → `InAppReview.requestReview()` or `openStoreListing()`, then `markShowCongratulationDialog()` and two pops. Right button `'Not now'` in `Color(0xFFE41919)` → `markShowCongratulationDialog()` and two pops. **Note the interstitial is skipped on this branch.**

### 3.8 `settings_screen.dart` — `SettingsScreen` (`/settings`)
- **Consumes:** `SettingsBloc` (route-provided), `AuthBloc`, `CreditUseCase`, `InterstitialAdService`; own `SharedPreferencesService()`; RevenueCat `Purchases` listener.
- **Hardcoded URLs/email:** `_termsOfServiceUrl = 'https://doxutostudio.top/terms'`, `_privacyPolicyUrl = 'https://doxutostudio.top/privacy'`, `_contactUsEmail = 'contact@doxutostudio.top'`.
- **AppBar:** `BackButton` (custom `onPressed`), title `const Text('Settings')` (hardcoded), `centerTitle: true`, elevation 0, transparent bg, `foregroundColor: Colors.black`. Scaffold bg `Color(0xFFFFFFFF)`.
- **Exit guard:** `PopScope(canPop: false)`; `_onWillPop()` awaits `InterstitialAdService.showBeforeSettingsExit(context:)` and then always returns `true` → `context.pop()`.
- **Sections** (`_sectionLabel` = 13px, `Color(0xFFBDBDBD)`, w600, letterSpacing 1, padding top 24 / bottom 8 / left 4; `_card` = white `Container`, radius 14, `BoxShadow(Colors.black.withOpacity(0.03), blurRadius: 8, offset: Offset(0,2))`; `_divider` = `Divider(height 1, thickness 1, Color(0xFFF0F0F0), indent 16, endIndent 16)`; `_iconRow` = 30×30 SVG + 16 gap + 14px black w400 label + `Icons.chevron_right` in `Color(0xFFBDBDBD)`, padding `H16/V14`):
  - **`NOTES`**: `'Audio Language'` row → `LanguageSelector` → `setAudioLanguage(lang.name)` in prefs; `'Summary Language'` row → `setSummaryLanguage(...)`. Trigger chip: `Color(0xFFF5F5F5)` radius 8, label in `Color(0xFF0767F8)`, `Icons.expand_more` `Colors.grey[600]` size 20. **These are the only writes to the language prefs in the app.**
  - **`SUPPORT`**: `'Give feedback'` (`Assets.feedbackIcon`) → `SentryFeedbackDialog`; `'Contact us'` (`Assets.contactIcon`) → `launchUrl('mailto:contact@doxutostudio.top?subject=Support Request&body=…My ID: <uid>\nApp version: <version>')` using `PackageInfo.fromPlatform()`; `'Leave a review'` (`Assets.reviewIcon`) → `InAppReview`.
  - **`LEGAL`**: `'Privacy policy'` (`Assets.policyIcon`), `'Terms of service'` (`Assets.termsIcon`) → `launchUrl(...)`, each with a try/catch → `SnackBar('Failed to open … Please try again later.')`.
  - **`ACCOUNT`**: a plain row `'Email: <FirebaseAuth.instance.currentUser?.email>'` (15px `Colors.black87`); `'Manage subscription'` (`Assets.subscriptionIcon`) → paywall or customer center; `'Free credits'` (`Assets.freeIcon`) via `_creditsRow` showing `_credits`, which is `'Unlimited'` when `credit >= 888` else the number (RevenueCat premium users get the sentinel `888` from `CreditUseCase`); `'Sign out'` (`Assets.signoutIcon`) → `AuthBloc.add(AuthEvent.signOut())`.
  - **`DANGER ZONE`** (label color `Color(0xFFFFB300)`): `'Delete account'` (`Assets.deleteAccountIcon`) → confirmation `AlertDialog` (`'Delete Account'` / `'Are you sure you want to delete your account? This action cannot be undone.'`, right action `'Delete'` in `Color(0xFFE41919)`) → `SettingsEvent.deleteAccount()`.
- **Bloc reactions:** `SettingsLoading` → barrier-non-dismissible `showDialog` with a bare `CircularProgressIndicator`; `SettingsDeleteAccountSuccess` → hide dialog + `SnackBar('Account deleted successfully.')` (the navigation back is commented out; the router's auth guard handles it); `SettingsError(message)` → hide dialog + `SnackBar(message)`.
- Every label in this screen is a hardcoded English literal except the shared `context.loc.cancel`.

### 3.9 `new_minutes_bottom_sheet.dart` — `NewMinutesBottomSheet`
- Triggered from HomeScreen's FAB. `Container` bg `Colors.white`, `BorderRadius.vertical(top: Radius.circular(20))`, `padding: all 16`, `Column(mainAxisSize: min, crossAxisAlignment: stretch)`.
- Header row: `context.loc.newNote` in `titleMedium` bold, and a close `InkWell(borderRadius: 20, padding: 8)` with `Assets.closeIcon` 24×24 → `Navigator.pop`. (A `LanguageSelector` in the header is present but fully commented out; the unused field `Language _selectedLanguage = Language.autodetect` remains.)
- `gapH16`, then three option buttons separated by `gapH12`, each a `Material(color: Color(0xFFEBF3FF), borderRadius: 12)` → `InkWell` → `Padding(16)` → 26×26 SVG + `gapW16` + label in `bodyMedium`. Each first pops the sheet, then pushes:
  - `Assets.voiceIcon` / `context.loc.startAudioRecording` → `context.push(Routes.recordAudio)`
  - `Assets.galleryIcon` / `context.loc.uploadFromFiles` → `context.push(Routes.uploadFile)`
  - `Assets.youtubeVideoIcon` / `context.loc.youTubeVideo` → `context.push(Routes.youtubeVideo)`
- Trailing `gapH24`. All taps fire `HapticFeedback.lightImpact()`.

### 3.10 `prompt_language_sheet.dart` — `PromptLanguageSheet`
- Opened from RecordAudioScreen only. Takes `initialAudioLanguage`, `initialSummaryLanguage`, `initialRecordingContext`, `initialKeywords`; returns a `Map<String, dynamic>` with keys `'audioLanguage'`, `'summaryLanguage'`, `'recordingContext'`, `'keywords'` via `Navigator.pop`.
- `SizedBox(height: MediaQuery.size.height * 0.9)` → transparent `Scaffold(resizeToAvoidBottomInset: true)` → white `DecoratedBox` with top corners `Radius.circular(16)`.
- Header `Padding(16,16,16,8)`: centered `context.loc.promptAndLanguage` (`titleMedium` bold) with a right-aligned `TextButton(context.loc.done)` in `labelLarge` `colorScheme.primary` that pops the map.
- Scroll body `Padding(16,0,16,24)`, `keyboardDismissBehavior: onDrag`:
  - `context.loc.whatAreYouRecording` (`titleMedium` w600), `gapH8`, `context.loc.recordingContextHint` (`bodyMedium` `Colors.grey[600]`), `gapH16`, `TextField` filled `Color(0xFFF5F5F5)`, all borders radius 8 `BorderSide.none`, contentPadding `H16/V16`, hint `context.loc.meetingTypeHint`.
  - `gapH24`, `context.loc.keywords` + `context.loc.keywordsHint` + a `TextField` with hint `context.loc.keywordsPlaceholder`, identical styling.
  - `gapH24`, `Divider(Color(0xFFBDBDBD))`, `gapH24`, audio-language selector, `gapH24`, summary-language selector — both `titleMedium` w600 titles + `gapH16` + `LanguageSelector` with the `Color(0xFFF5F5F5)` trigger chip (label in `colorScheme.primary`; **the chevrons here are untinted**, unlike the upload screen).
- The sheet has **no Cancel**: dismissing by swipe returns `null` and the caller keeps its previous values. Values are only kept in RecordAudioScreen's local state — never persisted.

### 3.11 Key supporting widgets
- **`minute_item_card.dart` — `MinuteItemCard`**: `InkWell` → `Card(margin: zero, elevation: 0, radius 12, side: colorScheme.surfaceContainerHighest)`, `Padding(16)`, row of: `CircleAvatar(radius: 24, backgroundColor: Color(0xFFEDF4FF))` showing `item.iconAsset ?? '😊'` at 24pt; `gapW16`; title (`item.title ?? 'Untitled'`, `titleMedium` w600) over an info row of `formatDateTimeToString(createdAt)` · a 4×4 dot · `item.duration ?? '0:00'`, all `bodySmall` in `onSurface.withAlpha(153)`; and a `PopupMenuButton<String>` (`offset: Offset(0,40)`, radius 12, `Icons.more_horiz`). **Card tap → `InterstitialAdService.showBeforeSummaryEnter(context:)` and only then `context.push(Routes.transcriptionSummary, extra: item.id)`.** Menu (dividers `Color(0xFFBDBDBD)` between): `edit_name` (`context.loc.editName`, `Assets.editIcon`), `edit_icon` (`Assets.smileIcon`), `manage_tags` (`Assets.tagsIcon`), `delete` (`Assets.deleteIcon`, label in `Color(0xFFE41919)`). Edit-name → `HomeEvent.updateMinuteName`; edit-icon → validates a single emoji by regex, error text `'Please enter a single emoji.'`, then `HomeEvent.updateMinuteIcon`; manage-tags → a `Dialog` hosting its own `MinuteItemBloc` with a `Wrap` of `TagChip`s, an empty state `'No tags created yet'` in a `Color(0xFFF5F5F5)` 48-high box, and a `Done` button dispatching `MinuteItemEvent.saveTags()`; delete → confirm dialog → `HomeEvent.deleteMinuteItem`. `_buildIconOption(...)` is dead code.
- **`tag_chip.dart` — `TagChip`**: 40-high pill, radius 20, bg `Color(0xFF0767F8)` when selected else `Color(0xFFEDF4FF)`, label `Colors.white` / `Color(0xFF0767F8)`, `fontWeight.w500`, `fontSize: 15`, horizontal padding 16, outer `Padding(horizontal 4)`, `onTap`/`onLongPress` both with haptics.
- **`transcript_tab_selector.dart`**: three `Expanded` `ElevatedButton`s, radius `24`, `padding: vertical 10`, elevation 0, bg `Color(0xFF2C7DF7)` when selected else `Color(0xFFE6F0FF)`, text white / `Color(0xFF2C7DF7)` at `fontSize: 14, w500`, each with a 16×16 tinted SVG + 6px gap. Labels: `'Summary'` (**hardcoded**, `Assets.listIcon`), `context.loc.transcript` (`Assets.commentIcon`), `context.loc.chat` (`Assets.commentLightIcon`).
- **`minute_section_widget.dart`**: section title in `titleSmall` bold `Colors.black`, `gapH12`, each bullet `Padding(bottom: 8, left: 8)` in `bodyMedium` `Colors.black`; if there are no bullets, the title is repeated as body text; trailing `gapH24`. `section.timeRange` is carried in the model but **never rendered**.
- **`transcript_message_widget.dart`**: 28×28 circular avatar whose color rotates by `speakerId % 5` over `Colors.purple, red, blue, green, orange` (default grey) with the numeric speaker id in white bold 14; `gapW12`; speaker name as a compact `TextButton` (`titleSmall` bold) that opens an edit-name dialog dispatching `TranscriptionSummaryEvent.updateSpeakers(speakerId: message.speakerIdRaw, newName:)`, replaced by `LoadingDots(dotCount: 3)` while that speaker id is in `state.speakerIdsLoading`; timestamp in `bodySmall` `Colors.grey[600]`; message in `bodyMedium`. Outer `Padding(bottom: 24)`.
- **`chat_input_widget.dart`**: a 38-high horizontal `ListView` of suggested-question `TagChip`s (tapping one sends it immediately and unfocuses), then a 43-high input `Container` (white, border `Colors.grey[300]`, radius 45) with a borderless `TextField` (hint `'Message...'` **hardcoded**, hint color `Color(0xFF8E8E93)`, `isDense`, zero contentPadding) and an `Assets.enterIcon` 33×33 send button. `onSubmitted` also sends.
- **`chat_message_widget.dart`**: bot messages render as an 8×8 `primary` dot + plain `Text` at `fontSize: 16` in `onSurface`; user messages render right-aligned in a `Color(0xFFF2F2F2)` bubble, radius 18, padding `H16/V12`. `ChatTypingIndicator` shows the same bubble with three `Color(0xFFBDBDBD)` 8×8 dots fading on a 1200ms controller staggered 0/200/400ms.
- **`feedback_widget.dart`**: `Color(0xFFF0F6FF)` container radius 12, padding `V12/H16`, `context.loc.howDidWeDo` in `titleSmall`, then two 40×40 `Image.asset` buttons (`Assets.dislikeButton` → `SentryFeedbackDialog`; `Assets.likeButton` → swaps to a white `ElevatedButton` radius 45 outlined `Color(0xFF2C7DF7)` labelled `context.loc.giveFeedback` → `InAppReview`).
- **`loading_dots.dart` — `LoadingDots`**: defaults `color: Colors.blue, size: 10.0, dotCount: 5, spacing: 8.0`; each dot fades `0.3 → 1.0` on a 1200ms repeating controller with a `delay = i * 120` ms `Interval`.
- **`sentry_feedback_dialog.dart`**: full-width `Dialog` (insetPadding `H8/V32`, white, radius 14). Header row `Cancel` / `'Feedback & Support'` (bold 18) / `Submit`, both `TextButton`s in `Colors.blue`. A 6-line-min autofocused `TextField` (`OutlineInputBorder` radius 8, contentPadding 12). Footer: `'Be as detailed as possible. We'll get back to you within\n1 business day to:'` then the user's Firebase email in bold (or `'No email provided'`). Submit → `Sentry.captureFeedback(SentryFeedback(associatedEventId: SentryId.newId(), message, contactEmail: <firebase email>, name: ''))`, pops with `true` and shows `SnackBar('Thank you for your feedback!')`; on throw sets `_submitError = 'Failed to send feedback. Please try again.'` shown in red. All strings hardcoded.
- **`premium_button.dart` — `PremiumButton`**: `PremiumButtonState { premium, upgrade }`. `premium` → bg `Color(0xFFFFBB00)`, `Assets.premiumIcon`, `context.loc.premium`. `upgrade` → bg `Color(0xFF4285F4)`, `Assets.flashIcon`, `context.loc.upgrade`. Both: `ElevatedButton`, `padding: H16/V8`, radius = `context.appTheme.buttonRadius` (8), elevation 0, 16×16 SVG + `gapW4` + label `TextStyle(color: Colors.white, w500, 14)`. Note `disabledBackgroundColor` is set to the same color so the disabled premium state looks identical.
- **`app_button.dart` — `AppButton`**: a generic `ElevatedButton` wrapper (`borderRadius` default 8.0, padding `V12/H16`, bg `colorScheme.primary`, fg `colorScheme.onPrimary`). **Never used anywhere.**
- **`keyboard_dismiss_on_tap.dart`**: wraps the whole `MaterialApp` in `main.dart`.
- **`utils/dialog.dart` — `getDialogWidth(context)`**: 90% of screen width below 600, 80% below 1200, else 60%.

---

## 4. State management inventory

Providers are all registered in `lib/config/dependencies.dart` under `_sharedProviders` (exposed as both `providersRemote` and `providersLocal`, which are identical). App-level blocs: `LanguageBloc`, `ThemeBloc`, `AuthBloc`. Route-level blocs: `HomeBloc`, `TranscriptionSummaryBloc`, `SettingsBloc`. Widget-level: `MinuteItemBloc`, `DemoUserBloc`.

| Bloc | File | Events | States | Depends on |
|---|---|---|---|---|
| `AuthBloc` | `lib/domain/bloc/auth/auth_bloc.dart` (+ `auth_event.dart`, `auth_state.dart`) | `AuthEvent.initialize()` (`InitializeEvent`), `.signInWithGoogle()`, `.signInWithApple()`, `.signOut()` — **no `deleteAccount` event here** | `AuthState.initial()`, `.loading()`, `.authenticated(AuthUser)`, `.unauthenticated()`, `.error(String)` | `AuthRepository`, `SharedPreferencesService`; also calls `Purchases.logIn/logOut` and persists `LOGIN_METHOD`. Self-dispatches `initialize()` in its constructor and then `emit.forEach(authRepository.authStateChanges)`. |
| `ThemeBloc` | `lib/ui/core/themes/view_model/theme_bloc.dart` | `ThemeEvent.initial()` (`_Initial`), `.changed({ThemeType themeType})` (`_Changed`) | single `ThemeState({ThemeType themeType, ThemeData themeData, bool isDarkMode})` + `ThemeState.initial()` | `ThemeRepository`, `ThemeHelpers`, `lightTheme`/`darkTheme` |
| `LanguageBloc` | `lib/ui/core/localization/view_model/language_bloc.dart` | `LanguageEvent.initial()`, `.changed({Locale locale})` | single `LanguageState({Locale locale})` + `.initial()` = `Locale('en')` | `LanguageRepository`, `AppLocalizations.load` |
| `HomeBloc` | `lib/ui/features/home/view_model/home_bloc.dart` | `HomeEvent.onInit()`, `.loadMinuteItems({bool isRefresh, bool isLoadMore})`, `.createTag({String name})`, `.updateMinuteName({String id, String newName})`, `.updateMinuteIcon({String id, String iconAsset})`, `.deleteMinuteItem({String id})`, `.loadTags()`, `.selectTags({List<String> tagIds})`, `.deleteTag({String tagId})` | single `HomeState({bool isLoading=false, String? errorMessage, List<Minute> minutes=[], List<Tag> tags=[], List<String> selectedTagIds=[], bool isLoadingMore=false})` | `TagUseCase`, `MinuteUseCase`; concurrency via `LoadingManager<HomeOperation>` with `enum HomeOperation { loadMinutes, loadTags, createTag, updateMinuteName, updateMinuteIcon, deleteMinuteItem, deleteTag }` |
| `MinuteItemBloc` | `lib/ui/features/home/view_model/minute_item_bloc.dart` | `MinuteItemEvent.loadTags()`, `.toggleTag(String tagId)`, `.saveTags()` | single `MinuteItemState({bool isLoading=false, String? errorMessage, List<Tag> tags=[], List<String> selectedTagIds=[]})` | `TagUseCase`, `MinuteUseCase`, plus the `Minute` it edits. `saveTags` no-ops when the sorted id lists are equal. |
| `SettingsBloc` | `lib/ui/features/settings/view_model/settings_bloc.dart` (+ `settings_event.dart`, `settings_state.dart`) | `SettingsEvent.deleteAccount()` (`DeleteAccountEvent`) | `SettingsState.initial()`, `.loading()`, `.deleteAccountSuccess()`, `.error(String)` | `AuthRepository`. Uses a single untyped `on<SettingsEvent>` handler with an `if (event is DeleteAccountEvent)` check rather than typed handlers. |
| `TranscriptionSummaryBloc` | `lib/ui/features/transcription/view_model/transcription_summary_bloc.dart` | `.loadMinute({String minuteId})`, `.shareNotesAsPdf({MeetingMinute, Rect?})`, `.shareNotesAsText({...})`, `.shareTranscriptAsPdf({String title, date, duration, Transcript, Rect?})`, `.shareTranscriptAsText({...})`, `.shareAudioFile({String audioPath, Rect?})`, `.sendChatMessage({String message})`, `.initChat()`, `.downloadAudio()`, `.updateSpeakers({String speakerId, String newName})` | single `TranscriptionSummaryState({bool isLoading=false, String? errorMessage, Minute? minute, bool isShareLoading=false, bool isChatLoading=false, ChatConversation chatConversation=ChatConversation(messages: []), List<String> suggestedQuestions=[], bool isAudioDownloading=false, File? audioSource=null, Set<String> speakerIdsLoading={}})` | `ShareRepository`, `MinuteUseCase`, `OneAiRepository`; also `FirebaseStorage` + `Dio` for audio download and `path_provider` for the cache path |
| `DemoUserBloc` | `lib/ui/features/demo/view_model/demo_user_bloc.dart` | demo scaffolding | — | `DemoUserRepository`, `DemoPostRepository` |

**Use cases** (`lib/domain/use_cases/`), all plain classes registered as `RepositoryProvider`s and all wrapping `OneAiRepository`:
- `TagUseCase` — `createTag`, `updateTag`, `deleteTag`, `getAllTags`; caches `_tagsCache` and broadcasts `tagsStream`. Mutations re-fetch the full list.
- `MinuteUseCase` — `loadMinutes({isRefresh, isLoadMore})` with cursor paging (`_pageSize = 10`, `_startAfterDocId` where `''` = start and `null` = exhausted), `getMinuteById`, `updateMinuteById`, `deleteMinuteById`, `transcribe`, `transcribeYoutube`, `updateSpeakers`; caches `_minutesCache` and broadcasts `minutesStream`. After a successful transcribe it re-fetches page 1 with `limit: 1` and prepends.
- `CreditUseCase` — `getUserCredit()` returns `888` as a **sentinel for premium** (short-circuits the API for entitled users), otherwise `OneAiRepository.getUserInfo().credit`; caches and broadcasts `creditStream`.

**Non-bloc state also in play:** `PremiumStatusBuilder` (a `StatefulWidget` holding `_isPremium`/`_hasCredits`), `MeetingMinuteProvider` (static sample data, see §8), and per-screen `setState` in `HomeScreen`, `RecordAudioScreen`, `UploadFileScreen`, `YouTubeVideoScreen`, `AudioProcessingScreen`, `SettingsScreen`, `TranscriptionSummaryScreen`.

**Result type:** `lib/utils/result.dart` — a freezed sealed `Result<T>` with `Ok(value)` / `Error(error)`, pattern-matched throughout.

---

## 5. Data layer → backend contract

**File:** `lib/data/services/api/oneai/oneai_api_service.dart` — `class OneAiApiService`.

**Base URL (hardcoded, single environment):**
```
https://us-central1-minutesai-6715a.cloudfunctions.net/api/v1
```
Set in the constructor default: `Dio(BaseOptions(baseUrl: '…'))`. A `Dio` instance can be injected for tests but nothing does. There is **no env/flavor switch and no baseUrl override anywhere in `lib/`.**

**Auth + headers** — every call awaits `_optionsWithAuth()`, which does:
```dart
final token = await FirebaseAuth.instance.currentUser!.getIdToken();
```
(note the unguarded `!` — a signed-out user throws) and returns:

| Header | Value |
|---|---|
| `Authorization` | `Bearer <Firebase ID token>` |
| `X-Timezone` | `DateTime.now().timeZoneName` (e.g. `+07`, `ICT`) |
| `X-Timezone-Offset` | `±HH:MM` from `DateTime.now().timeZoneOffset` |
| `X-Language` | **`'en-US'` — hardcoded constant, never reflects the app locale** |
| `X-Platform` | `'iOS'` \| `'Android'` \| `'Unknown'` |

The token is fetched fresh per request (no caching, no refresh interceptor). The full token is logged at `INFO` level (`_log.info('Token: $token')`), as are request bodies and full response bodies.

**Envelope contract:** every endpoint is expected to return `{ "success": bool, "data": ..., "message": String? }`. The service checks `response.data['success'] == true` and that `data` (and sometimes a named sub-key) is non-null; otherwise it returns `Result.error(Exception('… ${response.data['message'] ?? 'No data'}'))`.

### 5.1 Endpoint table

| Dart method | HTTP | Path | Request | Response shape read | Returns |
|---|---|---|---|---|---|
| `createTag(String name)` | `POST` | `/tags` | body `{ "name": name }` | `data` → tag object | `Result<TagDto>` |
| `updateTag(String tagId, String name)` | `PUT` | `/tags/{tagId}` | body `{ "name": name }` | `data.tagId` (String), `data.name` (String) — **built manually, not via `TagDto.fromJson`; key is `tagId`, not `id`** | `Result<TagDto>` |
| `deleteTag(String tagId)` | `DELETE` | `/tags/{tagId}` | — | `success` only | `Result<void>` |
| `getAllTags()` | `GET` | `/tags` | — | `data.tags` → `List<TagDto>` | `Result<List<TagDto>>` |
| `getMinuteById(String minuteId)` | `GET` | `/minutes/{minuteId}` | — | `data` → `MinuteDto` | `Result<MinuteDto>` |
| `getMinutes({String? startAfterDocId, int limit = 10})` | `GET` | `/minutes` | query `limit` (**string**), optional `startAfterDocId` | `data.data` → `List<MinuteDto>`, `data.total` (int, required), `data.nextPageCursor` (String?) | `Result<MinuteResponseDto>` |
| `updateMinuteById(String minuteId, {String? title, String? iconAsset, List<String>? tags})` | `PATCH` | `/minutes/{minuteId}` | body with only the non-null of `title`, `iconAsset`, `tags`; errors locally if all are null | `success` only | `Result<void>` |
| `deleteMinuteById(String minuteId)` | `DELETE` | `/minutes/{minuteId}` | — | `success` only | `Result<void>` |
| `transcribe({required String filePath, String? audioLanguage, String? summaryLanguage, String? keywords, String? description})` | `POST` | `/transcription/transcribe` | **`multipart/form-data`**: `file` (`MultipartFile.fromFile(filePath)`) + optional `audioLanguage`, `summaryLanguage`, `keywords`, `description` | `data` → `TranscriptionDto` | `Result<TranscriptionDto>` |
| `transcribeYoutube({required String youtubeUrl, String? audioLanguage, String? summaryLanguage, String? keywords, String? description})` | `POST` | `/transcription/youtube` | JSON body `{youtubeUrl, audioLanguage?, summaryLanguage?, keywords?, description?}` with nulls stripped | `data` → `TranscriptionDto` | `Result<TranscriptionDto>` |
| `transcriptById(String minuteId)` | `GET` | `/minutes/{minuteId}/transcription` | — | `data` → `TranscriptionDto` | `Result<TranscriptionDto>` |
| `postShortQuestions({required String minuteId, required String languageCode})` | `POST` | `/minutes/{minuteId}/questions` | body `{ "languageCode": languageCode }` | `data.short_questions` must be non-null; `data` → `QuestionDto` | `Result<QuestionDto>` |
| `postChat({required String minuteId, required String question, String? languageCode, String? summaryText})` | `POST` | `/minutes/{minuteId}/chat` | body `{question}` plus `languageCode` / `summaryText` when non-null | `data` → `ChatDto` | `Result<ChatDto>` |
| `getUserInfo()` | `GET` | `/user/me` | — | `data.user` → `OneAiUserDto` | `Result<OneAiUserDto>` |
| `getSpeakers(String minuteId)` | `GET` | `/minutes/{minuteId}/speakers` | — | `data.speakers` → `Map<String, String>` | `Result<Map<String, String>>` |
| `updateSpeakerById(String minuteId, String speakerId, String name)` | `PATCH` | `/minutes/{minuteId}/speakers/{speakerId}` | body `{ "newName": name }` | `success` only | `Result<void>` |
| `postRewardedAdCredit({int reward = 1})` | `POST` | `/user/reward` | body `{ "rewardAmount": reward }` | `data.credit` (int) — falls back to `0` if absent | `Result<int>` (new credit balance) |

### 5.2 DTOs (`lib/data/services/model/oneai/`)

- **`TagDto`** — `{ String id, String name, @JsonKey(name: 'name_lower') String? nameLower }`
- **`MinuteDto`** — `{ required String minuteId, SummaryDto? summary, String? summaryLanguage, String? keywords, TranscriptionDetailsDto? transcription, String? title, String? descriptionAudio, String? gcsUri, DateTime? createdAt (via FirestoreDateTimeConverter), List<String>? tags, String? type, String? iconAsset, List<String>? shortQuestions, String? duration, Map<String,String>? speakers }`
- **`MinuteResponseDto`** — `{ required int total, required List<MinuteDto> data, String? nextPageCursor }`
- **`SummaryDto`** — `{ String? summaryText, String? icon, String? title, String? type, List<SummarySectionDto>? sections }`; **`SummarySectionDto`** — `{ String? title, String? timeRange, List<String>? bullets }`
- **`TranscriptionDetailsDto`** — `{ String? duration, String? language_code, String? transcript, double? language_probability, List<TranscriptionSectionDto>? sections }` (note the two snake_case Dart field names — the JSON keys are literally `language_code` / `language_probability`); **`TranscriptionSectionDto`** — `{ String? timeRange, String? title, String? speaker, @JsonKey(name: 'speaker_id') String? speakerId }`
- **`TranscriptionDto`** — `{ String? minuteId, TranscriptionDetailsDto? transcription, String? description, String? keywords, String? title }`
- **`QuestionDto`** — `{ @JsonKey(name: 'short_questions') @Default([]) List<String> shortQuestions }`
- **`ChatDto`** — `{ required String question, required String answer, String? minuteId }`
- **`OneAiUserDto`** — `{ required String uid, required String? email, required String? displayName, required String? photoURL, required String role, required String plan, required int credit, DateTime? createdAt (FirestoreDateTimeConverter) }`

**`FirestoreDateTimeConverter`** (in `minute_dto.dart`) decodes raw Firestore timestamps of the form `{"_seconds": int, "_nanoseconds": int}` (also accepting `double`) and encodes back to the same shape. **The v2 server must keep emitting `_seconds`/`_nanoseconds` for `createdAt`, or send a real `DateTime`-parseable value — any other format silently becomes `null`, and the note list then shows a blank date.**

### 5.3 Repository layer

`lib/data/repositories/oneai_repository.dart` — `class OneAiRepository(OneAiApiService)` is a thin 1:1 façade that maps DTO → domain model: `createTag`, `updateTag`, `deleteTag`, `getAllTags`, `getMinuteById`, `getMinutes`, `updateMinuteById`, `deleteMinuteById`, `transcribe`, `transcribeYoutube`, `transcriptById`, `postShortQuestions`, `postChat`, `getUserInfo`, `getSpeakers({minuteId})`, `updateSpeakers({minuteId, speakerId, newName})`. Private mappers: `_mapTranscriptionDtoToModel`, `_mapMinuteResponseDtoToModel`, `_mapMinuteDtoToModel`, `_mapSummaryDtoToModel`, `_mapOneAiUserDtoToModel`. Note `_mapTranscriptionDtoToModel` **drops `speakerId`** from transcription sections (the minute mapper keeps it), and `_mapOneAiUserDtoToModel` drops `displayName`, `photoURL` and `createdAt`.

Other repositories:
- `auth_repository.dart` — `AuthRepository` / `AuthRepositoryImpl` over `AuthService`: `authStateChanges`, `currentUser`, `signInWithGoogle`, `signInWithApple`, `signOut`, `deleteAccount`, `isAuthenticated`. Maps Firebase `User` → `AuthUser(uid, displayName, email, photoURL, isAnonymous, isEmailVerified)`. **Both sign-in methods swallow every exception and return `null`.**
- `theme_repository.dart`, `language_repository.dart` — thin wrappers over `SharedPreferencesService`.
- `share_repository.dart` — `ShareRepository`/`ShareRepositoryImpl` over `PdfService` + `share_plus`: `shareNotesAsPdf`, `shareNotesAsText`, `shareTranscriptAsPdf`, `shareTranscriptAsText`, `shareAudioFile`. Text exports are written to `getTemporaryDirectory()` as `<title_with_underscores>_notes.txt` / `_transcript.txt`.
- `demo/demo_post_repository.dart`, `demo/demo_user_repository.dart` — scaffolding over `DemoApiService` (JSONPlaceholder-style), still wired into DI.

**Audio download** does **not** go through `OneAiApiService`: `TranscriptionSummaryBloc._getAudioSource` calls `FirebaseStorage.instance.refFromURL(minute.gcsUri).getDownloadURL()` and then a bare `Dio().download(...)` to `${getTemporaryDirectory()}/audio/<title-lowercased-hyphenated>.mp3`. So **`gcsUri` must remain a `gs://`/Firebase-Storage URL that `refFromURL` accepts.**

**Other network/SDK endpoints outside the API service:** `hasInternetConnection()` in `lib/utils/extensions.dart` does a bare `Dio().get('https://www.google.com')` with 3s timeouts as a connectivity probe.

### 5.4 Contract checklist for the v2 server

Paths that must exist: `POST /tags`, `PUT /tags/{id}`, `DELETE /tags/{id}`, `GET /tags`, `GET /minutes`, `GET /minutes/{id}`, `PATCH /minutes/{id}`, `DELETE /minutes/{id}`, `GET /minutes/{id}/transcription`, `POST /minutes/{id}/questions`, `POST /minutes/{id}/chat`, `GET /minutes/{id}/speakers`, `PATCH /minutes/{id}/speakers/{speakerId}`, `POST /transcription/transcribe` (multipart), `POST /transcription/youtube`, `GET /user/me`, `POST /user/reward`.

Behaviours the client depends on beyond shape:
- `{success, data, message}` envelope on **every** response, including errors the client should surface.
- `HTTP 402` on the transcribe endpoints is the specific trigger for the "Premium Required / no free credits" paywall dialog.
- `GET /minutes` paging is cursor-based: `data.nextPageCursor` `null`/absent means "last page" and the client stops paging forever until refresh.
- `PUT /tags/{id}` returns `tagId` while `GET /tags` and `POST /tags` return `id`.
- `POST /minutes/{id}/questions` must include a non-null `data.short_questions`, or the chat tab silently gets no suggestions.
- `POST /user/reward` must return `data.credit > 0` — `RewardAdService` treats `credit <= 0` as a failure and retries up to 3 times (500ms apart).

---

## 6. Monetization + ads

### 6.1 Formats and services

| Format | Service | Registered as |
|---|---|---|
| App Open | `lib/data/services/admob/open_app_ad_service.dart` — `OpenAppAdService with WidgetsBindingObserver` | `RepositoryProvider<OpenAppAdService>(RemoteConfigService, SharedPreferencesService)` |
| Interstitial | `lib/data/services/admob/interstitial_ad_service.dart` — `InterstitialAdService` | `RepositoryProvider<InterstitialAdService>(RemoteConfigService, SharedPreferencesService)` |
| Rewarded | `lib/data/services/admob/reward_ad_service.dart` — `RewardAdService` | `RepositoryProvider<RewardAdService>(RemoteConfigService, SharedPreferencesService, OneAiApiService)` |
| Inline adaptive Banner | `lib/data/services/admob/banner_ad_widget.dart` — `InlineAdaptiveBannerAd` (a `StatefulWidget`) | instantiated directly in `TranscriptionSummaryScreen` |

`MobileAds.instance.initialize()` is called in `main()`. **No UMP/consent flow** — the only consent-adjacent call is iOS ATT (`AppTrackingTransparency.requestTrackingAuthorization()`), triggered from either button of the HomeScreen intro-basic popup.

### 6.2 Ad unit IDs — all remote-config driven, none hardcoded

Each id key holds a JSON string `{"Android": "...", "iOS": "..."}`; `FirebaseRemoteConfigService.getStringValueFromPlatformMap(key)` parses it and picks by platform, returning `''` on any failure. **Defaults are empty strings**, so with no remote config fetched no ad can load.

| Getter | Remote Config key |
|---|---|
| `adUnitBanner` | `ad_unit_banner` |
| `adUnitInterstitialPreSummary` | `ad_unit_interstitial_pre_summary` |
| `adUnitInterstitialAfterShare` | `ad_unit_interstitial_after_share` |
| `adUnitInterstitialSettingsExit` | `ad_unit_interstitial_settings_exit` |
| `adUnitInterstitialSummaryExit` | `ad_unit_interstitial_summary_exit` |
| `adUnitOpenApp` | `ad_unit_open_app` |
| `adUnitRewarded` | `ad_unit_rewarded` |

### 6.3 Placements

| Trigger point | Call | File |
|---|---|---|
| Cold start, from `MaterialApp.builder` after remote config resolves | `OpenAppAdService.showAtColdStart(context:)` (`showLoading: false`) | `lib/main.dart` |
| App resumed from background | `OpenAppAdService.showAtWarmStart(context:)` via `didChangeAppLifecycleState` | `open_app_ad_service.dart` |
| Tapping a note card, **before** navigating to the summary | `InterstitialAdService.showBeforeSummaryEnter(context:)` → `ad_unit_interstitial_pre_summary` | `minute_item_card.dart` |
| Leaving the summary screen (only on the branch that skips the congratulation dialog) | `showBeforeSummaryExit(context:)` → `ad_unit_interstitial_summary_exit` | `transcription_summary_screen.dart` |
| After a successful share completes, before the loading dialog closes | `showAfterShare(context:, showLoading: false)` → `ad_unit_interstitial_after_share` | `transcription_summary_screen.dart` |
| Leaving the Settings screen (back button or gesture) | `showBeforeSettingsExit(context:)` → `ad_unit_interstitial_settings_exit` | `settings_screen.dart` |
| Starting a transcribe with zero credits (all three creation screens) | `RewardAdService.showBeforeTranscribeProcess(context:)` via `premiumActionWrapper` | `premium_status_builder.dart` |
| "🔥 Watch Ad & Earn Credit" card while processing | `RewardAdService.showWhenWaitingTranscribeProcess(context:)` | `audio_processing_screen.dart` |
| Top of each of the three tabs on the summary screen | `InlineAdaptiveBannerAd` (one shared instance reused across tabs) | `transcription_summary_screen.dart` |

### 6.4 Gating logic

All three fullscreen services share the same `_show()` skeleton, in this order:
1. `isLocked()` — this service already has an ad in flight → skip.
2. `context.isFullscreenAdInProgress()` (from `lib/utils/extensions.dart`) — true if **any** of OpenApp/Interstitial/Reward is locked → skip.
3. `_lock()`, optionally showing a barrier-blocking, non-poppable `CircularProgressIndicator` dialog (`showLoading`, default `true`; cold-start App Open and after-share Interstitial pass `false`).
4. `await isPremium()` — RevenueCat `Purchases.getCustomerInfo().entitlements.active.containsKey('pro')` → skip.
5. Per-format remote flag: `adOpenAppEnabled` / `adInterstitialEnabled` / `adRewardedEnabled` → skip.
6. **Global fullscreen frequency cap:** skip if `now - FULL_SCREEN_AD_LAST_SHOWN_TIME < ad_fullscreen_global_freq_seconds` (default **120s**). The timestamp is written on both `onAdShowedFullScreenContent` and `onAdDismissedFullScreenContent`.
7. **Rewarded only:** `checkAndResetDailyCounter()` (resets `REWARDED_AD_SHOWN_TODAY` when the calendar day changed), then skip if `ad_rewarded_daily_limit != 0 && shownToday >= limit` (default limit **5**; `0` means unlimited).
8. `hasInternetConnection()` → skip.
9. Load with a timeout of `ad_load_timeout_seconds` (default **5**; rewarded uses `× 2`), show with the same value as the show timeout.
10. Preload the next ad 1s after dismissal. A preloaded ad is reused only while `now - _lastAdPreloadTime < ad_preload_timeout_minutes` (default **60**).

Format-specific extras:
- **App Open cold start:** skipped entirely when `INTRO_BASIC_LAST_SHOWN_TIME` is null, i.e. on the very first app open (the intro popup owns that first session).
- **App Open warm start:** requires a recorded `_lastBackgroundTime` and `timeInBackground >= ad_open_app_background_threshold_minutes` (default **30**). `_lastBackgroundTime` is reset to null after each check. Uses `rootNavigatorKey.currentState?.overlay?.context`.
- **Banner:** checks `adBannerEnabled` and `isPremium()` on every `_loadAd`, guarded by an `isJobLoading` flag and an orientation/width memo. Size is `AdSize.getInlineAdaptiveBannerAdSize(width.truncate(), 60)` — max height 60. Renders `Container()` (nothing) until loaded. **`ad_banner_refresh_rate_seconds` is exposed by `RemoteConfigService` but never read by the widget — there is no refresh timer.**

### 6.5 Rewarded reward flow

`RewardAdService._showAd` sets `rewarded = true` and `rewardAmount = reward.amount.toInt()` in `onUserEarnedReward`. On `onAdDismissedFullScreenContent`:
- If `rewarded`: `_callRewardApiWithRetry(reward: rewardAmount)` → `OneAiApiService.postRewardedAdCredit(reward:)` → `POST /user/reward {rewardAmount}`. Up to **3** attempts, 500ms apart; an attempt counts as success only when the returned `credit > 0`. On success it increments `REWARDED_AD_SHOWN_TODAY`, toasts `'✅ You received $rewardAmount free credit!'` and completes with the amount. On failure it toasts `'✅ Ad completed! We will add your credit soon...'` and completes with `null`.
- If not rewarded: `'⚠️ Ad not completed. No credit awarded.'`, completes `null`.

Other rewarded toasts (all hardcoded `SnackBar`s except the freq-cap one): `'⚠️ Reward ad is already in loading, please wait.'`, `'⚠️ A fullscreen ad is already in progress, please try again later.'`, `'⚠️ No rewarded ads available at the moment. Please try again later.'`, `"⚠️ You have reached today's reward ad limit."`, `'📡 Please connect to the internet...'`, and `remoteConfig.adToastFreqLimitMessage` for the frequency cap.

There is **no server-side verification (SSV)** — the client asserts the reward by calling `/user/reward` itself.

### 6.6 RevenueCat / paywall

`main.dart` → `initPurchasesSdk()`: `Purchases.setLogLevel(LogLevel.debug)` then `Purchases.configure(PurchasesConfiguration(<key>))` with hardcoded public SDK keys — Android `'goog_XBenIbCcAEYqjdHwxPQPRyjeEjt'`, iOS `'appl_uJKYXVJiPCraeNcbYkNytLfVxYS'`; unsupported platforms throw `UnsupportedError`. If a Firebase user is already signed in and `Purchases.appUserID != uid`, it calls `Purchases.logIn(uid)`. `AuthBloc` repeats that `logIn` after each successful sign-in and calls `Purchases.logOut()` on sign-out.

Entitlement id: `Constants.entitlementId = 'pro'` (`lib/config/constants.dart`).

Paywall surfaces: `RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId)` from HomeScreen's upgrade button, the intro-basic popup's "Go Premium", Settings → "Manage subscription", and the 402 "Premium Required" dialog on the processing screen. `RevenueCatUI.presentCustomerCenter()` for already-premium users in Settings.

`premium_status_builder.dart`:
- `enum PremiumStatus { premium, nonPremiumHasCredits, nonPremiumNoCredits }`.
- `PremiumStatusBuilder` listens to `Purchases.addCustomerInfoUpdateListener` and to `CreditUseCase.creditStream`, and resolves `premium` → `nonPremiumHasCredits` (credit > 0) → `nonPremiumNoCredits`.
- `premiumActionWrapper(context, status, action)`: if `status != nonPremiumNoCredits`, run `action()` then refresh credits. Otherwise show `RewardAdService.showBeforeTranscribeProcess(context:)` and only run `action()` if `amount != null && amount > 0`. **This is the gate on all three transcribe entry points.**

`isPremium()` (`lib/utils/extensions.dart`) is the shared entitlement check used by the ad services; it returns `false` on any exception.

Other monetization-adjacent SDKs in `main()`: AppsFlyer (`afDevKey: '3qD2EG45ru9SgRjw7NfcGF'`, Android appId `top.doxutostudio.one.ai`, iOS appId `6743523150`, `showDebug: true`, iOS `timeToWaitForATTUserAuthorization: 30`) and Sentry (DSN hardcoded in `main.dart`).

### 6.7 Every Remote Config key read

Defaults are from `FirebaseRemoteConfigService.performInitialization()`. Fetch settings: `fetchTimeout: 1 minute`, `minimumFetchInterval: 1 hour`, `fetchAndActivate()` plus a live `onConfigUpdated` subscription that re-activates.

| Key | Getter | Type | Default |
|---|---|---|---|
| `ad_unit_banner` | `adUnitBanner` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_interstitial_pre_summary` | `adUnitInterstitialPreSummary` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_interstitial_after_share` | `adUnitInterstitialAfterShare` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_interstitial_settings_exit` | `adUnitInterstitialSettingsExit` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_interstitial_summary_exit` | `adUnitInterstitialSummaryExit` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_open_app` | `adUnitOpenApp` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_unit_rewarded` | `adUnitRewarded` | platform-map JSON | `{"Android":"","iOS":""}` |
| `ad_banner_enabled` | `adBannerEnabled` | bool | `'true'` |
| `ad_interstitial_enabled` | `adInterstitialEnabled` | bool | `'true'` |
| `ad_rewarded_enabled` | `adRewardedEnabled` | bool | `'true'` |
| `ad_open_app_enabled` | `adOpenAppEnabled` | bool | `'true'` |
| `ad_banner_refresh_rate_seconds` | `adBannerRefreshRateSeconds` | int | `'60'` — **read by no one** |
| `ad_load_timeout_seconds` | `adLoadTimeoutSeconds` | int | `'5'` |
| `ad_open_app_background_threshold_minutes` | `adOpenAppBackgroundThresholdMinutes` | int | `'30'` |
| `ad_fullscreen_global_freq_seconds` | `adFullscreenGlobalFreqSeconds` | int | `'120'` |
| `ad_rewarded_daily_limit` | `adRewardedDailyLimit` | int | `'5'` (`0` = unlimited) |
| `ad_preload_timeout_minutes` | `adPreloadTimeoutMinutes` | int | `'60'` |
| `ad_toast_freq_limit_message` | `adToastFreqLimitMessage` | String (`\n` unescaped) | `'You just watched an ad. Please try again in a moment.'` |
| `popup_intro_basic_enabled` | `popupIntroBasicEnabled` | bool | `'true'` |
| `popup_intro_basic_frequency_hours` | `popupIntroBasicFrequencyHours` | int | `'0'` (= show once) |
| `popup_intro_basic_text` | `popupIntroBasicText` | String (`\n` unescaped) | the long "Welcome to the One AI Basic Plan!…" blurb |

`RemoteConfigService` extends `BaseLongInitService` (`lib/data/services/base/base_long_init_service.dart`); `MaterialApp.builder` blocks the whole UI behind `waitForInitialization()` with a full-screen `CircularProgressIndicator`, then blocks again behind the cold-start App Open ad.

**SharedPreferences keys used by ads/monetization:** `FULL_SCREEN_AD_LAST_SHOWN_TIME`, `REWARDED_AD_SHOWN_TODAY`, `REWARDED_AD_LAST_RESET_DATE`, `INTRO_BASIC_LAST_SHOWN_TIME`, `SHOW_CONGRATULATION_DIALOG`.

---

## 7. Localization

- **Tooling:** `flutter_intl` (`pubspec.yaml` → `flutter_intl: {enabled: true, class_name: AppLocalizations, main_locale: en, arb_dir: lib/ui/core/localization/l10n, output_dir: lib/ui/core/localization/generated}`) plus `flutter: generate: true`.
- **Supported locales** (from the generated `AppLocalizationDelegate.supportedLocales`): **`en` and `es` only** — `Locale.fromSubtags(languageCode: 'en')`, `Locale.fromSubtags(languageCode: 'es')`.
- **Source strings:** `lib/ui/core/localization/l10n/intl_en.arb` and `intl_es.arb`.
- **Key counts:** `intl_en.arb` has **349** entries (message keys plus their `@key` metadata blocks); `intl_es.arb` has **305**. Since roughly half of the English entries are `@`-metadata, that is on the order of **~175 translatable keys in English**, and Spanish is measurably behind (no metadata blocks means the gap is larger than 44 keys in practice — Spanish is incomplete).
- **Generated:** `lib/ui/core/localization/generated/l10n.dart` (`class AppLocalizations`), `generated/intl/messages_en.dart`, `messages_es.dart`, `messages_all.dart`. Excluded from analysis via `analysis_options.yaml`.
- **Access:** `lib/ui/core/localization/localization_extension.dart` → `extension LocalizationExtension on BuildContext { AppLocalizations get loc => AppLocalizations.of(this); }`. Used everywhere as `context.loc.<key>`.
- **Wiring:** `main.dart` passes `locale` from `BlocSelector<LanguageBloc, LanguageState, Locale>`, `localizationsDelegates: [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]`, `supportedLocales: AppLocalizations.delegate.supportedLocales`, `onGenerateTitle: (context) => context.loc.appTitle`.
- **Persistence:** `LanguageBloc` → `LanguageRepositoryImpl` → `SharedPreferencesService` key `'APP_LOCALE'`, stored as `'<languageCode>_<countryCode>'`, defaulting to `Locale('en', '')`. Note `setLocale` writes `'en_null'` when `countryCode` is null, and `getLocale` splits on `_` and takes part[1] verbatim — so a round-trip can produce `Locale('en', 'null')`.
- **The UI-language switcher (`lib/ui/core/localization/widgets/language_selector.dart`) is never mounted by any screen.** In practice the app runs in whatever locale the device reports, and the per-note transcription languages (the `Language` enum in `lib/ui/core/widgets/language_selector.dart`, 51 values) are an entirely separate concept.
- There is a large amount of hardcoded English bypassing l10n — see §8.

---

## 8. Defects, risks and tech debt

**Blocking / correctness**

1. **Dark theme is never applied.** `lib/main.dart` selects `ThemeData` from `ThemeBloc` into the variable `themeData`, then passes `theme: lightTheme` and no `darkTheme`/`themeMode` to `MaterialApp.router`. `ThemeBloc`, `ThemeRepository`, `darkTheme` and the whole dark palette are dead at runtime. `ThemeSelector` is never mounted either, so the user can't change it anyway.
2. **Fonts are not registered.** `pubspec.yaml` lists `assets/fonts/` under `assets:` but has no `fonts:` section, while both themes set `fontFamily: 'Roboto'`. The bundled `Roboto-Regular.ttf`/`Roboto-Bold.ttf` are dead weight and typography falls back to the platform default. Fixing this **will change the rendering**, so decide deliberately before the rework.
3. **Unguarded `!` on the auth token.** `OneAiApiService._optionsWithAuth()` does `FirebaseAuth.instance.currentUser!.getIdToken()` — throws if the session lapsed mid-flight.
4. **Unguarded route-extra casts.** `router.dart`: `state.extra as String` for `/transcriptionSummary` and `state.extra as DemoPostModel` for `/demoPosts/:postId` throw on a deep link or a cold restore with no extra. `audio_processing_screen.dart`: `transcription.minuteId!`.
5. **Full Firebase ID token and full response bodies are logged at INFO.** `oneai_api_service.dart`: `_log.info('Token: $token')`, plus `Request data:` and `Response data:` interceptors. `lints` has `avoid_print: true` but `main.dart` still calls `print('🔗 Deeplink: …')` and `print('🧲 Click Event: …')` in `initAppsFlyer`, and `home_screen.dart` uses `debugPrint('ATT status: $result')`.
6. **Progress simulation can outrun or lag the real call.** `AudioProcessingScreen` advances 5 fake steps at `0.001/50ms`; a transcription that finishes fast still waits for the bar, and one that exceeds ~250s produces a fake `'Transcription did not complete in time.'` error even though the server may still succeed. The close button pops without cancelling the upload.
7. **Sign-in errors are swallowed.** `AuthRepositoryImpl.signInWithGoogle/signInWithApple` `catch (e) { return null; }` with no logging, so the UI can only report the generic `'Google sign-in failed'`.
8. **Broken test.** `test/widget_test.dart` is the unmodified Flutter counter template (`pumpWidget(const MainApp())`, taps `Icons.add`, expects `'0'`/`'1'`) — it cannot pass; `MainApp` requires the whole provider tree and Firebase.
9. **`record_audio_screen_test.dart` is stale.** It expects `find.text('Recording continue')` and `find.text('Prompt & Language')` / `'Transcribe & Summarize'` as literals, but the screen now renders localized `context.loc.*` strings and there is no `'Recording continue'` text. It also pumps a bare `MaterialApp(home: RecordAudioScreen())` with no localization delegates, which will throw on `context.loc`.
10. **Test coverage is otherwise zero.** `test/` contains exactly those two files. No bloc tests, no repository tests, no API-service tests, no golden tests — which is the main risk to "preserve the look verbatim" during a backend rework.

**Leftover scaffolding**

11. **The `demo/` tree is still shipped and still wired into DI.** Files: `lib/data/repositories/demo/demo_post_repository.dart`, `demo_user_repository.dart`; `lib/data/services/api/demo/demo_api_service.dart`; `lib/data/services/model/demo/demo_post_dto.dart`, `demo_user_dto.dart`; `lib/domain/models/demo/demo_post_model.dart`, `demo_user_model.dart`; `lib/ui/features/demo/view_model/demo_user_bloc.dart`; `lib/ui/features/demo/widgets/demo_home_screen.dart`, `demo_post_detail_screen.dart`, `demo_user_screen.dart`. Five live routes point at it (`/demoHome`, `/demoUsers`, `/demoPosts/:postId`, `/demoSettings`, `/demoCategories`) and three `RepositoryProvider`s construct it at startup. Two of those routes are inline "coming soon" `Scaffold`s built directly inside `router.dart`.
12. **`lib/ui/features/transcription/view_model/meeting_minute_provider.dart`** — a `MeetingMinuteProvider` with a single `static getSampleChatConversation()` returning hardcoded demo chat messages. It sits next to `transcription_summary_bloc.dart`, is referenced by nothing, and is the "mixed state approaches" artifact you flagged. (The pubspec still depends on `provider:` — it is used only for `single_child_widget` in `dependencies.dart` and the `read<T>()` extension in `utils/extensions.dart`.)
13. **`lib/data/services/base/example_long_init_service.dart`** — an unused example subclass of `BaseLongInitService`.
14. **Package name is still `codebase_ai`** with the template pubspec description. Every import path carries it.
15. **README placeholders:** `lib/config/README.md`, `lib/data/README.md`, `lib/domain/README.md`, `lib/ui/README.md`, plus ~15 more `README.md`/`.gitkeep` template files under `lib/`, and `assets/README.md`.

**Duplication**

16. **Two `language_selector.dart` files, different concepts, same class name `LanguageSelector`.**
    - `lib/ui/core/widgets/language_selector.dart` — the transcription-language dropdown, plus the 51-value `enum Language` (`autodetect('auto-detect', 'Auto Detect')` … `vietnamese('vie','Vietnamese')`) with `languageCode`/`displayName`. Used by upload, YouTube, settings, prompt sheet, and `audio_processing_screen`.
    - `lib/ui/core/localization/widgets/language_selector.dart` — the **app UI** locale switcher (en/es). Imported by nothing.
    Its `getLanguageName(context, language)` takes a `BuildContext` but just returns `language.displayName`, so the 51 language names are never localized.
17. **Two overlapping minute models.** `lib/domain/models/minute_model.dart` (`Minute`, `MinuteResponse` — the API-facing model) and `lib/domain/models/meeting_minute_model.dart` (`MeetingMinute`, `MeetingMinuteSection` — the presentation/PDF model), bridged one-way by `lib/domain/mappers/minute_mapper.dart` (`minuteToMeetingMinute`, `minuteToTranscript`, `formatDateTimeToString`, `_formatDuration`). `MeetingMinuteSection.timeRange` is carried through the mapper and the PDF but **never rendered** by `MinuteSectionWidget`.
18. **Two animated-dot implementations.** `_AnimatedDot` in `lib/ui/features/home/widgets/loading_dots.dart` and a second private `_AnimatedDot` in `lib/ui/features/transcription/widgets/chat_message_widget.dart`, with near-identical 1200ms controllers.
19. **The confirm-dialog shell is copy-pasted at least eight times** (`Divider(Color(0xFFBDBDBD))` + `IntrinsicHeight(Row(Expanded TextButton / VerticalDivider / Expanded TextButton))` with bottom-corner radius 16): `home_screen.dart` ×3, `minute_item_card.dart` ×3, `record_audio_screen.dart`, `settings_screen.dart`, `transcription_summary_screen.dart`, `audio_processing_screen.dart`, `transcript_message_widget.dart`. There is no shared dialog widget.
20. **The `Color(0xFFF5F5F5)` language-trigger chip is duplicated four times** with divergent tints — `upload_file_screen.dart` (`primary`), `youtube_video_screen.dart` (`Colors.blue`), `prompt_language_sheet.dart` (`primary` label, **untinted** chevrons), `settings_screen.dart` (`Color(0xFF0767F8)` + `Icons.expand_more`).
21. **The RevenueCat entitlement check is re-implemented four times:** `isPremium()` in `utils/extensions.dart`, `_checkEntitlement()` in `HomeScreen`, `_checkEntitlement()` in `SettingsScreen`, `_checkEntitlement()` in `PremiumStatusBuilder`.

**Theme bypass / hardcoded design values**

22. **Blue is expressed as three different literals that never come from the theme.** `colorScheme.primary` is `0xFF2C7DF7`, but the UI hardcodes `Color(0xFF0767F8)` (home empty state, create-tag pill, `TagChip`, processing FAB, login accent, settings language chip), `Color(0xFF2C7DF7)` (summary app bar, tab selector, audio player, feedback widget), `Color(0xFF4285F4)` (`PremiumButton` upgrade) and bare `Colors.blue` (every dialog "cancel/confirm" label, YouTube language chip).
23. **`Color(0xFFBDBDBD)` (dialog/menu dividers) and `Color(0xFFE41919)` (destructive actions) are hardcoded in ~25 places** across `home_screen.dart`, `minute_item_card.dart`, `settings_screen.dart`, `record_audio_screen.dart`, `transcription_summary_screen.dart`, `audio_processing_screen.dart`, `transcript_message_widget.dart`, `prompt_language_sheet.dart`, `core/widgets/language_selector.dart`. `0xFFBDBDBD` happens to equal `LightColorScheme.outline` but is never referenced as such.
24. **Three screens force a white background regardless of theme:** `record_audio_screen.dart` (`Scaffold(backgroundColor: Colors.white)` + white `AppBar`), `settings_screen.dart` (`backgroundColor: const Color(0xFFFFFFFF)`, `foregroundColor: Colors.black`), `new_minutes_bottom_sheet.dart` / `prompt_language_sheet.dart` / the audio-player dashboard / the share popup menu (`color: Colors.white`). Several widgets also hardcode `Colors.black`/`Colors.black87`/`Colors.grey[600]` for text — `minute_section_widget.dart`, `youtube_video_screen.dart`, `settings_screen.dart`, the share menu items.
25. **Other hardcoded palette values not in any token:** `0xFFEDF4FF`, `0xFFE1EDFF`, `0xFFEBF3FF`, `0xFFE6F0FF`, `0xFFF0F6FF`, `0xFFF5F5F5`, `0xFFF6F6F6`, `0xFFF2F2F2`, `0xFFF0F0F0`, `0xFFE5E5E5`, `0xFF8E8E93`, `0xFFFEA200`, `0xFFFFBB00`, `0xFFFFB300`, `0xFFF8C307`.
26. **Radii bypass `appTheme`.** `buttonRadius`/`cardRadius` are used in exactly three files; everything else writes `BorderRadius.circular(8|12|14|16|18|20|24|28|45|82)` inline. `dialogRadius` (16) is duplicated as a literal in every dialog. The `animationFast/Medium/Slow` durations are never used — animations use inline `Duration(milliseconds: 200|250|300|1200|3000)`.
27. **`ThemeHelpers.withOpacity`/`darken`/`lighten`/`adaptiveColor`/`primaryShade` and the entire success/warning token set are dead.** Meanwhile `settings_screen.dart` calls the deprecated `Colors.black.withOpacity(0.03)`.
28. **`lib/ui/core/widgets/app_button.dart` (`AppButton`) is unused** — every screen builds its own `ElevatedButton`.
29. **`AppTypography.applyFontFamily` is unused**; `bodyMedium`'s `letterSpacing: -0.41` (an iOS system-font value) applied to a generic text theme is unusual and worth flagging as intentional-or-not before any font change.

**Hardcoded English bypassing l10n** (with 349 ARB entries already present, this is the inconsistency to watch when re-testing)

30. `home_screen.dart`: `'My Notes'`, `'All'`, `'Delete Tag'`, `'Are you sure you want to delete the tag "…"?'`, `'Delete'`, `'Basic Plan Overview'`, `'Go Premium'`.
31. `settings_screen.dart`: **every** label — `'Settings'`, `'NOTES'`, `'SUPPORT'`, `'LEGAL'`, `'ACCOUNT'`, `'DANGER ZONE'`, `'Audio Language'`, `'Summary Language'`, `'Give feedback'`, `'Contact us'`, `'Leave a review'`, `'Privacy policy'`, `'Terms of service'`, `'Email: …'`, `'Manage subscription'`, `'Free credits'`, `'Unlimited'`, `'Sign out'`, `'Delete account'`, plus all four failure snackbars and the mailto subject/body.
32. `audio_processing_screen.dart`: `'Premium Required'`, `'You have no free credits left. Please upgrade your plan.'`, `'Go Premium'`, `'Something went wrong, please try later'` (×2), `'Earn a Free Credit While You Wait!'`, the "Your audio is being processed…" paragraph, `'🔥 Watch Ad & Earn Credit'`, `'Show Results'`, `'Transcription did not complete in time.'`.
33. `transcription_summary_screen.dart`: `'Congratulation'`, the congratulations paragraph, `"Sure, I'll rate it"`, `'Not now'`.
34. `transcript_tab_selector.dart`: `'Summary'`. `chat_input_widget.dart`: `'Message...'`. `record_audio_screen.dart`: `'One AI'`, `'Watch Ad to Transcribe'`. `upload_file_screen.dart` / `youtube_video_screen.dart`: `'Watch Ad to Transcribe'`; YouTube also `'Paste a YouTube link for transcript & notes:'`, `'https://...'`. `minute_item_card.dart`: `'Untitled'`, `'No tags created yet'`, `'e.g. 😊'`, `'Please enter a single emoji.'`. `login_page.dart`: `'Previously signed in with Google'` / `'…with Apple'`. `sentry_feedback_dialog.dart`: all of it. `reward_ad_service.dart`: all six toasts. `transcription_summary_bloc.dart`: `"I'm here to help you with your note. What would you like to know?"` and `'Failed to update speaker name'`.
35. `home_screen.dart` `_showIntroBasicPopup` contains a Vietnamese comment (`// Tần suất (giờ) hiển thị lại popup. (0 = chỉ 1 lần)`) in an otherwise English codebase.

**Ads / config risks**

36. **Ads block first paint twice.** `MaterialApp.builder` shows a bare full-screen `CircularProgressIndicator` until remote config resolves (`fetchTimeout` 1 min) **and then** until `OpenAppAdService.showAtColdStart` returns. A slow network can hold a blank loading screen for a long time.
37. **`ad_banner_refresh_rate_seconds` is read from Remote Config but never used** — the banner never refreshes.
38. **`InlineAdaptiveBannerAd._loadAd` is called from inside `LayoutBuilder.builder`**, i.e. during build, and it calls `setState` — guarded only by the `isJobLoading` flag and the orientation/width memo.
39. **The interstitial on summary exit is skipped** on the congratulation-dialog branch (first-note users), which is probably unintentional.
40. **No UMP/consent flow** despite shipping AdMob; the only consent-adjacent call is iOS ATT, fired from the intro popup's buttons (including "Cancel").
41. **Secrets/config in source:** RevenueCat public keys, AppsFlyer dev key, Sentry DSN, the Cloud Functions base URL, and the support/legal URLs are all literal in `main.dart` / `oneai_api_service.dart` / `settings_screen.dart`. `Purchases.setLogLevel(LogLevel.debug)` and `AppsFlyerOptions(showDebug: true)` are on in release builds.
42. **No environment separation.** `providersRemote` and `providersLocal` in `dependencies.dart` are byte-identical (`[..._sharedProviders]`), so the local/remote split the architecture implies does not exist. There is exactly one hardcoded backend URL — **this is the single point you will need to change for the v2 backend.**

**Lint / analyzer**

43. `analysis_options.yaml` enables a very strict rule set (`strict-casts`, `strict-raw-types`, ~200 lints including `always_use_package_imports`, `prefer_expression_function_bodies`, `avoid_print`, `use_build_context_synchronously`, `prefer_final_locals`, `unawaited_futures`, `cascade_invocations`), but the code violates many of them: `settings_bloc.dart` uses a relative import (`import 'settings_event.dart';`), the ad services carry `// ignore: use_build_context_synchronously` comments in ~15 places, `main.dart` and `home_screen.dart` call `print`/`debugPrint`, `transcription_summary_screen.dart` declares local functions `_changeSpeed`/`_seekRelative` with leading underscores (`no_leading_underscores_for_local_identifiers`), `minute_item_card.dart` uses `Function(String)` (`avoid_dynamic_calls`-adjacent), several `then`-less futures are unawaited. Running `flutter analyze` before the rework will give you a concrete baseline.
44. `dependency_overrides: freezed_annotation: ^3.0.0` is pinned, and `intl: any` / `bloc: any` / `provider: any` are unconstrained.
45. `AuthBloc` declares `StreamSubscription<AuthUser?>? _authSubscription` and cancels it in `close()`, but never assigns it — the actual subscription lives in `emit.forEach` inside `_onInitialize`.
46. `CreditUseCase.dispose()`, `TagUseCase.dispose()`, `MinuteUseCase.dispose()` and `OpenAppAdService.dispose()` are never called (they are `RepositoryProvider`s that live for the app's lifetime).
47. `MinuteItemBloc` declares and cancels `StreamSubscription<List<Tag>>? _tagSub` but never assigns it.
48. `MinuteUseCase.updateMinuteById` calls `_minutesCache.firstWhere(...)` with no `orElse` — throws if the minute isn't in the cache (e.g. after a refresh dropped it).
