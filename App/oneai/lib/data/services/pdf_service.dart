import 'dart:io';
import 'dart:ui';

import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Service for generating and sharing PDF files
class PdfService {
  final _log = Logger('PdfService');

  /// Singleton instance of PdfService
  static final PdfService instance = PdfService._();

  /// Public constructor for dependency injection
  factory PdfService() => instance;

  /// Private constructor
  PdfService._();

  /// Generate and share meeting minutes as PDF
  Future<Result<void>> shareNotesAsPdf(MeetingMinute meetingMinute, {Rect? sharePositionOrigin}) async {
    try {
      final pdf = await _generateMeetingMinutePdf(meetingMinute);
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${meetingMinute.title.replaceAll(' ', '_')}_notes.pdf';

      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          title: meetingMinute.title,
          subject: meetingMinute.title,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _log.info('PDF shared successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.severe('Error sharing PDF: $e');
      return Result.error(e);
    }
  }

  /// Generate and share transcript as PDF
  Future<Result<void>> shareTranscriptAsPdf(
    String title,
    String date,
    String duration,
    Transcript transcript, {
    Rect? sharePositionOrigin,
  }) async {
    try {
      final pdf = await _generateTranscriptPdf(title, date, duration, transcript);
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${title.replaceAll(' ', '_')}_transcript.pdf';

      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          title: '$title - Transcript',
          subject: '$title - Transcript',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _log.info('Transcript PDF shared successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.severe('Error sharing transcript PDF: $e');
      return Result.error(e);
    }
  }

  /// Generate a PDF document for meeting minutes
  Future<pw.Document> _generateMeetingMinutePdf(MeetingMinute meetingMinute) async {
    final pdf =
        pw.Document()..addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            theme: await _getPdfTheme(),
            build:
                (pw.Context context) => [
                  // Header
                  pw.Header(
                    level: 0,
                    child: pw.Paragraph(
                      text: meetingMinute.title,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                  ),

                  // Meeting info
                  pw.Paragraph(
                    text: '${meetingMinute.date} - ${meetingMinute.duration}',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),

                  pw.SizedBox(height: 16),

                  // Sections
                  ...meetingMinute.sections.expand(_buildSection),
                ],
            footer:
                (context) => pw.Container(
                  alignment: pw.Alignment.centerRight,
                  margin: const pw.EdgeInsets.only(top: 16),
                  child: pw.Paragraph(
                    text: 'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ),
          ),
        );

    return pdf;
  }

  /// Generate a PDF document for transcript
  Future<pw.Document> _generateTranscriptPdf(String title, String date, String duration, Transcript transcript) async {
    final pdf =
        pw.Document()..addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            theme: await _getPdfTheme(),
            build:
                (pw.Context context) => [
                  // Header
                  pw.Header(
                    level: 0,
                    child: pw.Paragraph(
                      text: '$title - Transcript',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                  ),

                  // Meeting info
                  pw.Paragraph(
                    text: '$date - $duration',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),

                  pw.SizedBox(height: 16),

                  // Transcript messages
                  ...transcript.messages.expand(_buildTranscriptMessage),
                ],
            footer:
                (context) => pw.Container(
                  alignment: pw.Alignment.centerRight,
                  margin: const pw.EdgeInsets.only(top: 16),
                  child: pw.Paragraph(
                    text: 'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ),
          ),
        );

    return pdf;
  }

  /// Build a section of meeting minutes in PDF document
  List<pw.Widget> _buildSection(MeetingMinuteSection section) => [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Paragraph(text: section.title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(width: 8),
        pw.Paragraph(text: section.timeRange, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
      ],
    ),
    pw.SizedBox(height: 8),
    if (section.bulletPoints.isNotEmpty)
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children:
            section.bulletPoints
                .map(
                  (point) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Bullet(bulletSize: 0, text: point, style: const pw.TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
      ),
    pw.SizedBox(height: 16),
  ];

  /// Build a transcript message in PDF document
  List<pw.Widget> _buildTranscriptMessage(TranscriptMessage message) => [
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Paragraph(text: message.speakerName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 8),
        pw.Paragraph(text: message.timestamp, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
      ],
    ),
    pw.SizedBox(height: 4),
    pw.Padding(
      padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
      child: pw.Paragraph(text: message.message, style: const pw.TextStyle(fontSize: 12)),
    ),
  ];

  /// Get the PDF theme with custom fonts
  Future<pw.ThemeData> _getPdfTheme() async => pw.ThemeData.withFont(
    base: await PdfGoogleFonts.robotoRegular(),
    bold: await PdfGoogleFonts.robotoBold(),
    italic: await PdfGoogleFonts.robotoItalic(),
    boldItalic: await PdfGoogleFonts.robotoBoldItalic(),
    icons: await PdfGoogleFonts.materialIcons(),
  );
}
