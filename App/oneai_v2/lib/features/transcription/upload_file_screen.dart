import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/features/credits/credit_gate_ui.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/transcription/language_selector.dart';
import 'package:one_ai/features/transcription/new_minute_request_builder.dart';
import 'package:one_ai/features/transcription/prompt_language_sheet.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// Port of v1 UploadFileScreen. PDF is now accepted too (server branch S3-08).
class UploadFileScreen extends ConsumerStatefulWidget {
  const UploadFileScreen({super.key});
  @override
  ConsumerState<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends ConsumerState<UploadFileScreen> {
  PromptSettings? _settings;
  PromptSettings get _s => _settings ??= defaultPromptSettings(ref.read(languageSettingsProvider));

  Future<void> _pick() async {
    await runWithCreditGate(context, ref, () async {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'pdf']);
      final path = result?.files.single.path;
      if (path == null || !mounted) return;
      final request = buildNewMinuteRequest(file: File(path), settings: _s);
      await context.push(Routes.audioProcessing, extra: AudioProcessingArgs(request: request));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.uploadFromFiles, style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.selectFileDescription, style: context.textTheme.bodyLarge),
            gapH32,
            _section(
              l10n.audioLanguage,
              LanguageSelector(
                selected: s.audioLanguage,
                onSelected: (l) => setState(() => _settings = s.copyWith(audioLanguage: l)),
                trigger: LanguageTriggerButton(label: LanguageSelector.nameOf(context, s.audioLanguage), tintArrows: true),
              ),
            ),
            gapH24,
            _section(
              l10n.summaryLanguage,
              LanguageSelector(
                selected: s.summaryLanguage,
                choices: TranscriptionLanguage.summaryChoices,
                onSelected: (l) => setState(() => _settings = s.copyWith(summaryLanguage: l)),
                trigger: LanguageTriggerButton(label: LanguageSelector.nameOf(context, s.summaryLanguage), tintArrows: true),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _pick();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Text(creditGateLabel(context, ref, l10n.selectFile), style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            gapH16,
          ],
        ),
      ),
    );
  }

  Widget _section(String title, Widget selector) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)), gapH16, selector],
      );
}
