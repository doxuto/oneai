import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';

/// v1 sheet minus the YouTube entry (OQ-06). Two ways in: record, upload.
class NewMinutesBottomSheet extends StatelessWidget {
  const NewMinutesBottomSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => const NewMinutesBottomSheet(),
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.newNote, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(Assets.closeIcon, width: 24, height: 24)),
                ),
              ],
            ),
            gapH16,
            _Option(
              icon: Assets.voiceIcon,
              label: context.l10n.startAudioRecording,
              onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); context.push(Routes.recordAudio); },
            ),
            gapH12,
            _Option(
              icon: Assets.galleryIcon,
              label: context.l10n.uploadFromFiles,
              onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); context.push(Routes.uploadFile); },
            ),
            gapH24,
          ],
        ),
      );
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFEBF3FF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [SvgPicture.asset(icon, width: 26, height: 26), gapW16, Text(label, style: context.textTheme.bodyMedium)]),
          ),
        ),
      );
}
