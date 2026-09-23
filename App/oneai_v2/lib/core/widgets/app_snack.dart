import 'package:flutter/material.dart';
import 'package:one_ai/core/widgets/failure_text.dart';

/// Snack bars, the v1 way (ScaffoldMessenger, default look).
abstract final class AppSnack {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static void failure(BuildContext context, Object? error) => show(context, failureText(context, error));
}
