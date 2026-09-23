/// Build-time configuration. Nothing here is hardcoded per environment —
/// values arrive via --dart-define so one codebase serves dev/staging/prod.
///
///   flutter run --dart-define=FLAVOR=dev
///   flutter build ipa --dart-define=FLAVOR=prod
enum Flavor { dev, staging, prod }

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.appName,
    required this.appShortName,
    required this.admobAppIdIos,
    required this.admobAppIdAndroid,
    required this.functionsRegion,
    required this.useEmulator,
    required this.emulatorHost,
    required this.sentryDsn,
    required this.sentryTracesSampleRate,
    required this.revenueCatKeyAndroid,
    required this.revenueCatKeyIos,
    required this.entitlementId,
    required this.appsFlyerDevKey,
    required this.appsFlyerAppIdIos,
    required this.appsFlyerAppIdAndroid,
    required this.termsUrl,
    required this.privacyUrl,
    required this.supportEmail,
    this.legalBaseUrl,
  });

  /// [projectId] (from the Firebase options) lets the legal pages served by
  /// the `legal` function be linked before a website exists.
  factory AppConfig.fromEnvironment({String? projectId}) {
    const name = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
    final flavor = switch (name) {
      'prod' => Flavor.prod,
      'staging' => Flavor.staging,
      _ => Flavor.dev,
    };
    return AppConfig(
      flavor: flavor,
      // Store listing name. The home-screen label uses appShortName so it is
      // not truncated to "One AI: AI No…" under the icon.
      appName: 'One AI: AI Note Taker & Scribe',
      appShortName: 'One AI',
      admobAppIdIos: 'ca-app-pub-8661297299230251~8024150974',
      admobAppIdAndroid: 'ca-app-pub-8661297299230251~8068383004',
      functionsRegion: 'asia-southeast1',
      useEmulator: const bool.fromEnvironment('USE_EMULATOR'),
      emulatorHost: const String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: 'localhost',
      ),
      // Carried over from v1 (docs/13-CONFIG-INVENTORY.md).
      sentryDsn:
          'https://2ecaca4988375921fd4b32362d27a8e5@o4509008840097792.ingest.us.sentry.io/4509008848814080',
      sentryTracesSampleRate: flavor == Flavor.prod ? 0.2 : 1.0,
      revenueCatKeyAndroid: 'goog_XBenIbCcAEYqjdHwxPQPRyjeEjt',
      revenueCatKeyIos: 'appl_uJKYXVJiPCraeNcbYkNytLfVxYS',
      entitlementId: 'pro',
      appsFlyerDevKey: '3qD2EG45ru9SgRjw7NfcGF',
      appsFlyerAppIdIos: '6743523150',
      appsFlyerAppIdAndroid: 'top.doxutostudio.one.ai',
      termsUrl: 'https://doxutostudio.top/terms',
      privacyUrl: 'https://doxutostudio.top/privacy',
      supportEmail: 'contact@doxutostudio.top',
      legalBaseUrl: projectId == null ? null : 'https://asia-southeast1-$projectId.cloudfunctions.net/legal',
    );
  }

  final Flavor flavor;
  final String appName;
  final String appShortName;

  /// Declared in Info.plist / AndroidManifest too — these are here so code can
  /// assert the native value matches and fail loudly if someone edits one half.
  final String admobAppIdIos;
  final String admobAppIdAndroid;

  final String functionsRegion;
  final bool useEmulator;
  final String emulatorHost;
  final String sentryDsn;
  final double sentryTracesSampleRate;
  final String revenueCatKeyAndroid;
  final String revenueCatKeyIos;
  final String entitlementId;
  final String appsFlyerDevKey;
  final String appsFlyerAppIdIos;
  final String appsFlyerAppIdAndroid;
  final String termsUrl;
  final String privacyUrl;
  final String supportEmail;
  /// Base of the `legal` function (S10-07); null → fall back to the website URLs.
  final String? legalBaseUrl;

  /// Localised legal page: `privacy` | `terms` | `delete-account`, in the
  /// user's language (en/vi; everything else → en).
  String legalUrl(String doc, String languageCode) {
    final base = legalBaseUrl;
    if (base == null) return doc == 'terms' ? termsUrl : privacyUrl;
    final lang = languageCode == 'vi' ? 'vi' : 'en';
    return '$base?doc=$doc&lang=$lang';
  }

  bool get isProd => flavor == Flavor.prod;

  /// Debug logging for third-party SDKs is on everywhere EXCEPT prod.
  /// v1 shipped RevenueCat and AppsFlyer debug logging in release builds.
  bool get verboseSdkLogging => !isProd;
}
