import 'dart:io' show Platform;

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:codebase_ai/config/dependencies.dart';
import 'package:codebase_ai/data/services/admob/open_app_ad_service.dart';
import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_bloc.dart';
import 'package:codebase_ai/firebase_options.dart';
import 'package:codebase_ai/routing/router.dart';
import 'package:codebase_ai/ui/core/localization/generated/l10n.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/localization/view_model/language_bloc.dart';
import 'package:codebase_ai/ui/core/themes/light_theme.dart';
import 'package:codebase_ai/ui/core/themes/view_model/theme_bloc.dart';
import 'package:codebase_ai/ui/core/ui/keyboard_dismiss_on_tap.dart';
import 'package:codebase_ai/utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';



Future<void> initAppsFlyer() async {
  AppsflyerSdk appsflyerSdk;
  AppsFlyerOptions options;

  if (Platform.isAndroid) {
    options = AppsFlyerOptions(
      afDevKey: '3qD2EG45ru9SgRjw7NfcGF',
      appId: 'top.doxutostudio.one.ai',
      showDebug: true,
      manualStart: false,
    );
  } else if (Platform.isIOS) {
    options = AppsFlyerOptions(
      afDevKey: '3qD2EG45ru9SgRjw7NfcGF',
      appId: '6743523150',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 30,
      manualStart: false,
    );
  } else {
    throw UnsupportedError('Unsupported platform');
  }

  appsflyerSdk = AppsflyerSdk(options);

  await appsflyerSdk.initSdk(
    registerConversionDataCallback: true,
    registerOnDeepLinkingCallback: true,
    registerOnAppOpenAttributionCallback: true,
  );

  appsflyerSdk.onDeepLinking((deepLink) {
    print('🔗 Deeplink: ${deepLink.deepLink?.deepLinkValue}');
    print('🧲 Click Event: ${deepLink.deepLink?.clickEvent}');
  });
}

/// Default main method
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure logging
  configureLogging();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize AdMob
  // Note: Replace 'ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy' with your actual AdMob App ID
  await MobileAds.instance.initialize();

  // Initialize Purchases
  await initPurchasesSdk();

  await initAppsFlyer();

  // Initialize Sentry
  await SentryFlutter.init((options) {
    options.dsn = 'https://2ecaca4988375921fd4b32362d27a8e5@o4509008840097792.ingest.us.sentry.io/4509008848814080';
    // options.tracesSampleRate = 1.0; // Optional: adjust production sampling
  }, appRunner: () => runApp(MultiRepositoryProvider(providers: providersRemote, child: const MainApp())));
}

/// Main application widget that sets up the MaterialApp with proper routing and theming
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => BlocSelector<LanguageBloc, LanguageState, Locale>(
    selector: (state) => state.locale,
    builder:
        (context, locale) => KeyboardDismissOnTap(
          child: BlocSelector<ThemeBloc, ThemeState, ThemeData>(
            selector: (state) => state.themeData,
            builder:
                (context, themeData) => MaterialApp.router(
                  locale: locale,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.delegate.supportedLocales,
                  onGenerateTitle: (context) => context.loc.appTitle,
                  theme: lightTheme,
                  routerConfig: createAppRouter(context.read<AuthBloc>()),
                  builder:
                      (context, child) => FutureBuilder(
                        future: context.read<RemoteConfigService>().waitForInitialization(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Scaffold(body: Center(child: CircularProgressIndicator()));
                          }
                          return FutureBuilder(
                            future: context.read<OpenAppAdService>().showAtColdStart(context: context),
                            // future: Future.value(true), // Replace with actual cold start handling),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState != ConnectionState.done) {
                                return const Scaffold(body: Center(child: CircularProgressIndicator()));
                              }
                              return child ?? const SizedBox.shrink();
                            },
                          );
                        },
                      ),
                ),
          ),
        ),
  );
}

Future<void> initPurchasesSdk() async {
  await Purchases.setLogLevel(LogLevel.debug);
  final Logger log = Logger('initPurchasesSdk');

  PurchasesConfiguration configuration;
  if (Platform.isAndroid) {
    configuration = PurchasesConfiguration('goog_XBenIbCcAEYqjdHwxPQPRyjeEjt');
  } else if (Platform.isIOS) {
    configuration = PurchasesConfiguration('appl_uJKYXVJiPCraeNcbYkNytLfVxYS');
  } else {
    throw UnsupportedError('Unsupported OS');
  }
  await Purchases.configure(configuration);

  final uid = FirebaseAuth.instance.currentUser?.uid;

  if (uid != null && (await Purchases.appUserID) != uid) {
    log.info('Logging in to Purchases: $uid');
    await Purchases.logIn(uid);
  }
}
