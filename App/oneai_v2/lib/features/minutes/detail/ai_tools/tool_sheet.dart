import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/data/models/ai_models.dart';

/// Shared chrome for the four study-tool sheets: title, close, regenerate,
/// and the loading/error/data switch over an `AsyncValue<Generated<T>>`.
class ToolSheet<T> extends ConsumerWidget {
  const ToolSheet({required this.title, required this.value, required this.onRegenerate, required this.builder, super.key});
  final String title;
  final AsyncValue<Generated<T>> value;
  final VoidCallback onRegenerate;
  final Widget Function(BuildContext context, T data) builder;

  static Future<void> present(BuildContext context, Widget sheet) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => sheet,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    if (value.hasValue)
                      TextButton(onPressed: () { HapticFeedback.lightImpact(); onRegenerate(); }, child: Text(context.l10n.regenerate, style: const TextStyle(color: AppColors.brandBlueAlt))),
                    InkWell(onTap: () => Navigator.pop(context), borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(Assets.closeIcon, width: 24, height: 24))),
                  ],
                ),
              ),
              Expanded(
                child: switch (value) {
                  AsyncData(:final value) => builder(context, value.data),
                  AsyncError(:final error, :final value) when value != null => Column(children: [Expanded(child: builder(context, value.data)), ErrorState(error: error, onRetry: onRegenerate)]),
                  AsyncError(:final error) => ErrorState(error: error, onRetry: onRegenerate),
                  _ => const LoadingState(),
                },
              ),
            ],
          ),
        ),
      );
}
