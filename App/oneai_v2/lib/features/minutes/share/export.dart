import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/format.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/minutes/share/share_hooks.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Builds the text/Markdown once (pure, tested) and renders PDF from the same
/// structure, so both formats always say the same thing.
abstract final class MinuteExport {
  static String notesMarkdown(MinuteDetail d, {ActionItems? actionItems, Chapters? chapters}) {
    final b = StringBuffer();
    final title = d.summary?.title ?? d.summaryInfo.title;
    b.writeln('# $title');
    b.writeln();
    b.writeln('_${formatDateTime(d.summaryInfo.createdAt)}${d.summaryInfo.durationSeconds != null ? ' · ${formatDurationLong(d.summaryInfo.durationSeconds)}' : ''}_');
    b.writeln();
    for (final s in d.summary?.sections ?? const <SummarySection>[]) {
      b.writeln('## ${s.title}');
      b.writeln();
      for (final bullet in s.bullets) {
        b.writeln(_bulletToMarkdown(bullet));
      }
      b.writeln();
    }
    if (actionItems != null && (actionItems.items.isNotEmpty || actionItems.decisions.isNotEmpty)) {
      b.writeln('## Action items');
      b.writeln();
      for (final it in actionItems.items) {
        final meta = [if (it.owner != null) it.owner!, if (it.due != null) it.due!].join(', ');
        b.writeln('- [ ] ${it.text}${meta.isEmpty ? '' : ' ($meta)'}');
      }
      if (actionItems.decisions.isNotEmpty) {
        b.writeln();
        b.writeln('## Decisions');
        b.writeln();
        for (final dec in actionItems.decisions) {
          b.writeln('- $dec');
        }
      }
      b.writeln();
    }
    if (d.calendarEvents.isNotEmpty) {
      b.writeln('## Events');
      b.writeln();
      for (final e in d.calendarEvents) {
        b.writeln('- ${e.title} — ${e.datetime}${e.participants.isEmpty ? '' : ' (${e.participants.join(', ')})'}');
      }
      b.writeln();
    }
    if (chapters != null && chapters.chapters.isNotEmpty) {
      b.writeln('## Chapters');
      b.writeln();
      for (final c in chapters.chapters) {
        b.writeln('- ${formatClock(c.startSeconds)} ${c.title}');
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  static String transcriptText(MinuteDetail d) {
    final b = StringBuffer();
    b.writeln(d.summary?.title ?? d.summaryInfo.title);
    b.writeln();
    for (final s in d.transcript?.segments ?? const <TranscriptSegment>[]) {
      b.writeln('[${formatClock(s.startSeconds)}] ${d.speakerLabelFor(s.speakerId)}: ${s.text}');
    }
    return b.toString().trimRight();
  }

  /// "• x" → "- x", "    ◦ y" → "  - y".
  static String _bulletToMarkdown(String bullet) {
    final t = bullet.trimRight();
    if (t.startsWith('    ◦ ')) return '  - ${t.substring(6)}';
    if (t.startsWith('• ')) return '- ${t.substring(2)}';
    return '- $t';
  }

  static Future<List<int>> pdf(String title, String body) async {
    final doc = pw.Document();
    final lines = body.split('\n');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          for (final l in lines)
            if (l.startsWith('## '))
              pw.Padding(padding: const pw.EdgeInsets.only(top: 10, bottom: 4), child: pw.Text(l.substring(3), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)))
            else if (l.startsWith('# '))
              pw.SizedBox()
            else
              pw.Padding(padding: pw.EdgeInsets.only(left: l.startsWith('  ') ? 12 : 0, bottom: 2), child: pw.Text(l.trimLeft(), style: const pw.TextStyle(fontSize: 11))),
        ],
      ),
    );
    return doc.save();
  }
}

class ShareSheetSharer implements MinuteSharer {
  ShareSheetSharer(this._ref);
  final Ref _ref;

  @override
  Future<void> share(BuildContext context, MinuteDetail detail, ShareOption option) async {
    final l10n = context.l10n;
    try {
      final title = detail.summary?.title ?? detail.summaryInfo.title;
      switch (option) {
        case ShareOption.notesAsText:
          await SharePlus.instance.share(ShareParams(text: await _notes(detail), subject: title));
        case ShareOption.notesAsPdf:
          final bytes = await MinuteExport.pdf(title, await _notes(detail));
          await _shareFile('${_safe(title)}.pdf', bytes, title);
        case ShareOption.transcriptAsText:
          await SharePlus.instance.share(ShareParams(text: MinuteExport.transcriptText(detail), subject: title));
        case ShareOption.transcriptAsPdf:
          final bytes = await MinuteExport.pdf(title, MinuteExport.transcriptText(detail));
          await _shareFile('${_safe(title)}-transcript.pdf', bytes, title);
        case ShareOption.audioFile:
          final path = detail.sourcePath;
          if (path == null) return;
          final dir = await getTemporaryDirectory();
          final file = await _ref.read(transcriptionRepositoryProvider).downloadSource(path, File('${dir.path}/${path.split('/').last}'));
          await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: title));
      }
    } on Object catch (e) {
      if (context.mounted) AppSnack.show(context, option == ShareOption.notesAsPdf || option == ShareOption.transcriptAsPdf ? l10n.errorSharingPdf : l10n.errorSharingContent);
      debugPrint('share failed: $e');
    }
  }

  /// Include whatever artifacts are already generated (no new AI calls).
  Future<String> _notes(MinuteDetail d) async {
    ActionItems? items;
    Chapters? chapters;
    if (d.hasArtifact(ArtifactKind.actionItems)) items = (await _ref.read(actionItemsProvider(d.id).future)).data;
    if (d.hasArtifact(ArtifactKind.chapters)) chapters = (await _ref.read(chaptersProvider(d.id).future)).data;
    return MinuteExport.notesMarkdown(d, actionItems: items, chapters: chapters);
  }

  Future<void> _shareFile(String name, List<int> bytes, String subject) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: subject));
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(' ', '-').toLowerCase();
}
