import 'package:codebase_ai/data/repositories/auth_repository.dart';
import 'package:codebase_ai/data/repositories/demo/demo_post_repository.dart';
import 'package:codebase_ai/data/repositories/demo/demo_user_repository.dart';
import 'package:codebase_ai/data/repositories/language_repository.dart';
import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/data/repositories/share_repository.dart';
import 'package:codebase_ai/data/repositories/theme_repository.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/data/services/admob/open_app_ad_service.dart';
import 'package:codebase_ai/data/services/admob/reward_ad_service.dart';
import 'package:codebase_ai/data/services/api/demo/demo_api_service.dart';
import 'package:codebase_ai/data/services/api/oneai/oneai_api_service.dart';
import 'package:codebase_ai/data/services/auth_service.dart';
import 'package:codebase_ai/data/services/pdf_service.dart';
import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_bloc.dart';
import 'package:codebase_ai/domain/use_cases/credit_usecase.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/domain/use_cases/tag_usecase.dart';
import 'package:codebase_ai/ui/core/localization/view_model/language_bloc.dart';
import 'package:codebase_ai/ui/core/themes/view_model/theme_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/single_child_widget.dart';

/// Shared providers for all configurations.
List<SingleChildWidget> _sharedProviders = [
  RepositoryProvider<RemoteConfigService>(create: (context) => FirebaseRemoteConfigService()..checkInitialization()),
  RepositoryProvider(create: (context) => SharedPreferencesService()),
  RepositoryProvider<LanguageRepository>(
    create: (context) => LanguageRepositoryImpl(preferencesService: context.read<SharedPreferencesService>()),
  ),
  RepositoryProvider<ThemeRepository>(
    create: (context) => ThemeRepositoryImpl(preferencesService: context.read<SharedPreferencesService>()),
  ),
  BlocProvider(
    create:
        (context) =>
            LanguageBloc(languageRepository: context.read<LanguageRepository>())..add(const LanguageEvent.initial()),
  ),
  BlocProvider(
    create: (context) => ThemeBloc(themeRepository: context.read<ThemeRepository>())..add(const ThemeEvent.initial()),
  ),
  // OneAI
  RepositoryProvider(create: (context) => OneAiApiService()),
  RepositoryProvider<OneAiRepository>(create: (context) => OneAiRepository(context.read<OneAiApiService>())),
  RepositoryProvider(create: (context) => DemoApiService()),
  RepositoryProvider(create: (context) => DemoUserRepository(apiService: context.read<DemoApiService>())),
  RepositoryProvider(create: (context) => DemoPostRepository(apiService: context.read<DemoApiService>())),
  RepositoryProvider(create: (context) => PdfService()),
  // Share repository and bloc
  RepositoryProvider<ShareRepository>(create: (context) => ShareRepositoryImpl(pdfService: context.read<PdfService>())),
  // BlocProvider(create: (context) => TranscriptionSummaryBloc(shareRepository: context.read<ShareRepository>())),
  // Authentication
  RepositoryProvider<AuthService>(create: (context) => FirebaseAuthService()),
  RepositoryProvider<AuthRepository>(create: (context) => AuthRepositoryImpl(authService: context.read<AuthService>())),
  BlocProvider(
    create:
        (context) => AuthBloc(
          authRepository: context.read<AuthRepository>(),
          preferencesService: context.read<SharedPreferencesService>(),
        ),
  ),
  // Use cases
  RepositoryProvider(create: (context) => TagUseCase(context.read<OneAiRepository>())),
  RepositoryProvider(create: (context) => MinuteUseCase(context.read<OneAiRepository>())),
  RepositoryProvider(create: (context) => CreditUseCase(context.read<OneAiRepository>())),
  RepositoryProvider<OpenAppAdService>(
    create:
        (context) => OpenAppAdService(context.read<RemoteConfigService>(), context.read<SharedPreferencesService>()),
  ),
  RepositoryProvider<InterstitialAdService>(
    create:
        (context) =>
            InterstitialAdService(context.read<RemoteConfigService>(), context.read<SharedPreferencesService>()),
  ),
  RepositoryProvider<RewardAdService>(
    create:
        (context) => RewardAdService(
          context.read<RemoteConfigService>(),
          context.read<SharedPreferencesService>(),
          context.read<OneAiApiService>(),
        ),
  ),
];

List<SingleChildWidget> get providersRemote => [..._sharedProviders];

List<SingleChildWidget> get providersLocal => [..._sharedProviders];
