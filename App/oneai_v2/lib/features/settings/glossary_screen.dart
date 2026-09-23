import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/glossary_models.dart';

/// S11-10 — "fix it once, remembered forever": names, products and jargon
/// the STT and the summariser must spell exactly. Live list from Firestore;
/// writes go through the callables.
final glossaryProvider = StreamProvider<List<GlossaryTerm>>(
  (ref) => ref.watch(glossaryRepositoryProvider).watch(ref.watch(currentUidProvider)),
);

class GlossaryActions extends Notifier<Object?> {
  @override
  Object? build() => null;

  Future<bool> add(String term, {String? hint}) async {
    final t = term.trim();
    if (t.isEmpty) return false;
    state = null;
    try {
      await ref.read(glossaryRepositoryProvider).upsert(t, hint: hint?.trim());
      return true;
    } on Object catch (e) {
      dev.log('glossary upsert failed', name: 'glossary', error: e);
      state = e;
      return false;
    }
  }

  Future<bool> remove(String termId) async {
    state = null;
    try {
      await ref.read(glossaryRepositoryProvider).delete(termId);
      return true;
    } on Object catch (e) {
      state = e;
      return false;
    }
  }
}

final glossaryActionsProvider = NotifierProvider<GlossaryActions, Object?>(GlossaryActions.new);

/// Offered after a speaker rename or from anywhere a name is corrected.
Future<void> offerAddToGlossary(BuildContext context, WidgetRef ref, String term) async {
  final l10n = context.l10n;
  AppSnack.showAction(context, l10n.addToGlossaryPrompt(term), actionLabel: l10n.add, onAction: () async {
    final ok = await ref.read(glossaryActionsProvider.notifier).add(term);
    if (context.mounted) AppSnack.show(context, ok ? l10n.addedToGlossary(term) : l10n.somethingWentWrong);
  });
}

class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});
  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen> {
  final _term = TextEditingController();
  final _hint = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _term.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_term.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(glossaryActionsProvider.notifier).add(_term.text, hint: _hint.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _term.clear();
      _hint.clear();
    } else {
      AppSnack.failure(context, ref.read(glossaryActionsProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = ref.watch(glossaryProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: context.colorScheme.surface,
        elevation: 0,
        title: Text(l10n.glossary),
        leading: IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(l10n.glossaryExplain, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _term,
                  textInputAction: TextInputAction.next,
                  maxLength: 60,
                  decoration: dialogFieldDecoration(context, hintText: l10n.glossaryTermHint),
                ),
                gapH8,
                Row(children: [
                  Expanded(child: TextField(controller: _hint, maxLength: 120, onSubmitted: (_) => _add(), decoration: dialogFieldDecoration(context, hintText: l10n.glossaryHintHint))),
                  gapW8,
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () { HapticFeedback.lightImpact(); _add(); },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                      child: Text(l10n.add, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ]),
            ),
            Expanded(
              child: switch (items) {
                AsyncData(:final value) when value.isEmpty => EmptyState(title: l10n.glossaryEmpty),
                AsyncData(:final value) => ListView.separated(
                    itemCount: value.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF0F0F0)),
                    itemBuilder: (context, i) => _TermRow(term: value[i]),
                  ),
                AsyncError(:final error) => ErrorState(error: error, onRetry: () => ref.invalidate(glossaryProvider)),
                _ => const LoadingState(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TermRow extends ConsumerWidget {
  const _TermRow({required this.term});
  final GlossaryTerm term;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey(term.id),
        direction: DismissDirection.endToStart,
        background: Container(color: AppColors.destructiveRed, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline, color: Colors.white)),
        confirmDismiss: (_) async => (await showDialog<bool>(
              context: context,
              builder: (ctx) => StyledDialog(
                title: ctx.l10n.delete,
                content: Text(ctx.l10n.deleteGlossaryTermConfirm(term.term), textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
                cancelLabel: ctx.l10n.cancel,
                confirmLabel: ctx.l10n.delete,
                destructive: true,
                onCancel: () => Navigator.of(ctx).pop(false),
                onConfirm: () => Navigator.of(ctx).pop(true),
              ),
            )) ??
            false,
        onDismissed: (_) => ref.read(glossaryActionsProvider.notifier).remove(term.id),
        child: ListTile(
          title: Text(term.term, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: term.hint == null ? null : Text(term.hint!, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
        ),
      );
}
