import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/data/repositories/shares_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Deep-link target for a shared note (`/s?t=…`, universal / app link or
/// `oneai://s?t=…`). Read-only viewer with "Open PDF" and "Save to my notes"
/// (S11-05 + deep links, 24/09). A revoked link shows the not-found state.
final sharedNoteProvider = FutureProvider.autoDispose.family<SharedNote, String>(
  (ref, token) => ref.watch(sharesRepositoryProvider).fetch(token),
);

class SharedNoteScreen extends ConsumerStatefulWidget {
  const SharedNoteScreen({required this.token, super.key});
  final String token;
  @override
  ConsumerState<SharedNoteScreen> createState() => _SharedNoteScreenState();
}

class _SharedNoteScreenState extends ConsumerState<SharedNoteScreen> {
  bool _importing = false;

  Future<void> _save() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final r = await ref.read(sharesRepositoryProvider).import(widget.token);
      if (!mounted) return;
      AppSnack.show(context, r.duplicate ? context.l10n.alreadyInYourNotes : context.l10n.savedToYourNotes);
      context.pushReplacement(Routes.transcriptionSummary, extra: SummaryArgs(minuteId: r.minuteId));
    } on Object catch (e) {
      if (mounted) AppSnack.failure(context, e);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = ref.watch(sharedNoteProvider(widget.token));
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: context.colorScheme.surface,
        elevation: 0,
        leading: IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go(Routes.root)),
        title: Text(l10n.sharedNote),
        actions: [
          if (note.valueOrNull case final n?)
            IconButton(
              tooltip: l10n.openPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.brandBlueAlt),
              onPressed: () async { await HapticFeedback.lightImpact(); await launchUrl(Uri.parse(n.pdfUrl), mode: LaunchMode.externalApplication); },
            ),
        ],
      ),
      body: switch (note) {
        AsyncData(:final value) => _Body(note: value),
        AsyncError(:final error) => ErrorState(error: error, onRetry: () => ref.invalidate(sharedNoteProvider(widget.token))),
        _ => const LoadingState(),
      },
      bottomNavigationBar: note.hasValue
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _importing ? null : () { HapticFeedback.lightImpact(); _save(); },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                  icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bookmark_add_outlined, color: Colors.white),
                  label: Text(l10n.saveToMyNotes, style: context.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            )
          : null,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.note});
  final SharedNote note;
  @override
  Widget build(BuildContext context) {
    final s = note.summary;
    final t = note.transcript;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${note.iconEmoji == null ? '' : '${note.iconEmoji} '}${note.title}', style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          gapH4,
          Text(note.createdAt, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          gapH16,
          if (s != null) ...[
            if (s.text.isNotEmpty) ...[Text(s.text, style: context.textTheme.bodyMedium?.copyWith(height: 1.5)), gapH16],
            for (final sec in s.sections)
              if (sec.bullets.isNotEmpty) ...[
                Text(sec.title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.brandBlue)),
                gapH8,
                for (final b in sec.bullets)
                  Padding(padding: EdgeInsets.only(left: b.startsWith('    ◦') ? 24 : 4, bottom: 4), child: Text(b.trimLeft(), style: context.textTheme.bodyMedium)),
                gapH16,
              ],
          ],
          if (t != null) ...[
            Text(context.l10n.transcript, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.brandBlue)),
            gapH8,
            for (final seg in t.segments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RichText(text: TextSpan(style: context.textTheme.bodyMedium?.copyWith(color: Colors.black), children: [
                  TextSpan(text: '${note.speakerLabelFor(seg.speakerId)}: ', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.brandBlue)),
                  TextSpan(text: seg.text),
                ])),
              ),
          ],
          gapH24,
          Text(context.l10n.sharedReadOnlyFooter, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[500])),
        ],
      ),
    );
  }
}
