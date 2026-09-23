import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/auth/auth_controller.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:one_ai/features/auth/login_method_store.dart';
import 'package:one_ai/features/auth/login_screen.dart';

import 'harness.dart';

class MemoryLoginMethod implements LoginMethodStore {
  MemoryLoginMethod(this.value);
  AuthProviderKind? value;
  @override
  Future<AuthProviderKind?> read() async => value;
  @override
  Future<void> write(AuthProviderKind provider) async => value = provider;
}

void main() {
  testWidgets('shows Google (and Apple on iOS), the tagline, and no "previously" label on first run', (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [loginMethodStoreProvider.overrideWithValue(MemoryLoginMethod(null))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Google'), findsOneWidget);
    expect(find.textContaining('Apple'), Platform.isIOS ? findsOneWidget : findsNothing);
    expect(find.textContaining('Previously'), findsNothing);
    await expectAccessible(tester);
  });

  testWidgets('remembers the last method', (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [loginMethodStoreProvider.overrideWithValue(MemoryLoginMethod(AuthProviderKind.google))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Previously'), findsOneWidget);
  });

  testWidgets('a busy action disables the buttons and shows a spinner', (tester) async {
    await pumpScreen(tester, const LoginScreen(), overrides: [
      loginMethodStoreProvider.overrideWithValue(MemoryLoginMethod(null)),
      authControllerProvider.overrideWith(() => _BusyAuth()),
    ]);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    final buttons = [...tester.widgetList<ElevatedButton>(find.byType(ElevatedButton)), ...tester.widgetList<OutlinedButton>(find.byType(OutlinedButton))];
    expect(buttons, isNotEmpty);
    expect(buttons.every((b) => b.onPressed == null), isTrue);
  });
}

class _BusyAuth extends AuthController {
  @override
  AuthFlow build() => const AuthBusy(AuthAction.signInGoogle);
}
