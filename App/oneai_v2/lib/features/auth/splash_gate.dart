import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';

/// Holds a blank surface until Firebase has answered whether someone is
/// signed in, so a returning user never sees the Login screen flash by.
class SplashGate extends ConsumerWidget {
  const SplashGate({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authUserProvider);
    if (auth.isLoading && !auth.hasValue) {
      return const Scaffold(body: SizedBox.expand());
    }
    return child;
  }
}
