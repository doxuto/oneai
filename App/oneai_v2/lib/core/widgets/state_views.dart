import 'package:flutter/material.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/failure_text.dart';

/// Centered message with an optional action — v1's empty-state look
/// (icon above, title, body in onSurfaceVariant).
class EmptyState extends StatelessWidget {
  const EmptyState({required this.title, super.key, this.body, this.icon, this.action});
  final String title;
  final String? body;
  final Widget? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(height: 16)],
              Text(title, textAlign: TextAlign.center, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (body != null) ...[
                const SizedBox(height: 8),
                Text(body!, textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant)),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, super.key, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        title: failureText(context, error),
        icon: Icon(Icons.error_outline, size: 40, color: context.colorScheme.error),
        action: onRetry == null ? null : TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}
