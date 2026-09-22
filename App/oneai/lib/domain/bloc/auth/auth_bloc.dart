import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/auth_repository.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_event.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_state.dart';
import 'package:codebase_ai/domain/models/auth_user_model.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:codebase_ai/config/constants.dart';

/// BLoC that handles authentication logic
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final Logger _log = Logger('AuthBloc');
  final AuthRepository _authRepository;
  final SharedPreferencesService _preferencesService;
  StreamSubscription<AuthUser?>? _authSubscription;

  /// Creates new [AuthBloc] with the given repository
  AuthBloc({required AuthRepository authRepository, required SharedPreferencesService preferencesService})
    : _authRepository = authRepository,
      _preferencesService = preferencesService,
      super(const AuthState.initial()) {
    on<InitializeEvent>(_onInitialize);
    on<SignInWithGoogleEvent>(_onSignInWithGoogle);
    on<SignInWithAppleEvent>(_onSignInWithApple);
    on<SignOutEvent>(_onSignOut);

    // Initialize the bloc when created
    add(const AuthEvent.initialize());
  }

  Future<void> _onInitialize(InitializeEvent event, Emitter<AuthState> emit) async {
    _log.info('Initializing authentication');
    final currentUser = _authRepository.currentUser;
    if (currentUser != null) {
      _log.info('User is already authenticated: \\${currentUser.uid}');
      emit(AuthState.authenticated(currentUser));
    } else {
      _log.info('No authenticated user found');
      emit(const AuthState.unauthenticated());
    }

    await emit.forEach(
      _authRepository.authStateChanges,
      onData: (user) {
        if (user != null) {
          _log.info('Auth state changed: authenticated (\\${user.uid})');
          return AuthState.authenticated(user);
        } else {
          _log.info('Auth state changed: unauthenticated');
          return const AuthState.unauthenticated();
        }
      },
    );
  }

  Future<void> _onSignInWithGoogle(SignInWithGoogleEvent event, Emitter<AuthState> emit) async {
    if (state is AuthenticatedAuthState) {
      _log.info('Google sign-in attempted, but user is already authenticated');
      return;
    }

    emit(const AuthState.loading());
    try {
      _log.info('Attempting Google sign-in');
      final user = await _authRepository.signInWithGoogle();
      if (user != null) {
        _log.info('Google sign-in successful: \\${user.uid}');
        emit(AuthState.authenticated(user));
        await _preferencesService.setLoginMethod(Constants.loginMethodGoogle);
        if ((await Purchases.appUserID) != user.uid) {
          await Purchases.logIn(user.uid);
        }
      } else {
        _log.warning('Google sign-in failed: user is null');
        emit(const AuthState.error('Google sign-in failed'));
      }
    } on Exception catch (e) {
      _log.severe('Google sign-in error: \\${e.toString()}');
      emit(AuthState.error(e.toString()));
    }
  }

  Future<void> _onSignInWithApple(SignInWithAppleEvent event, Emitter<AuthState> emit) async {
    if (state is AuthenticatedAuthState) {
      _log.info('Apple sign-in attempted, but user is already authenticated');
      return;
    }

    emit(const AuthState.loading());
    try {
      _log.info('Attempting Apple sign-in');
      final user = await _authRepository.signInWithApple();
      if (user != null) {
        _log.info('Apple sign-in successful: \\${user.uid}');
        emit(AuthState.authenticated(user));
        await _preferencesService.setLoginMethod(Constants.loginMethodApple);
        if ((await Purchases.appUserID) != user.uid) {
          await Purchases.logIn(user.uid);
        }
      } else {
        _log.warning('Apple sign-in failed: user is null');
        emit(const AuthState.error('Apple sign-in failed'));
      }
    } on Exception catch (e) {
      _log.severe('Apple sign-in error: \\${e.toString()}');
      emit(AuthState.error(e.toString()));
    }
  }

  Future<void> _onSignOut(SignOutEvent event, Emitter<AuthState> emit) async {
    emit(const AuthState.loading());
    try {
      _log.info('Signing out user');
      await _authRepository.signOut();
      await Purchases.logOut();
      _log.info('Sign-out successful');
      emit(const AuthState.unauthenticated());
    } on Exception catch (e) {
      _log.severe('Sign-out error: \\${e.toString()}');
      emit(AuthState.error(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
