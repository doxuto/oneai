import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/home/widgets/loading_dots.dart';
import 'package:codebase_ai/ui/features/transcription/view_model/transcription_summary_bloc.dart';
import 'package:codebase_ai/utils/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Widget that displays a single transcript message
class TranscriptMessageWidget extends StatelessWidget {
  final TranscriptMessage message;

  const TranscriptMessageWidget({required this.message, super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpeakerAvatar(),
        gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_buildSpeakerInfo(context), gapH8, _buildMessageContent(context)],
          ),
        ),
      ],
    ),
  );

  Widget _buildSpeakerAvatar() => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(color: _getSpeakerColor(), shape: BoxShape.circle),
    child: Center(
      child: Text(
        message.speakerId.toString(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      ),
    ),
  );

  Widget _buildSpeakerInfo(BuildContext context) =>
      BlocSelector<TranscriptionSummaryBloc, TranscriptionSummaryState, bool>(
        selector: (state) => state.speakerIdsLoading.contains(message.speakerIdRaw),
        builder: (context, isSpeakerLoading) => Row(
          children: [
            if (isSpeakerLoading)
              const LoadingDots(dotCount: 3)
            else
              TextButton(
                onPressed: () {
                  _showEditNameDialog(context);
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  message.speakerName,
                  style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            gapW8,
            Text(message.timestamp, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
          ],
        ),
      );

  Widget _buildMessageContent(BuildContext context) => Text(message.message, style: context.textTheme.bodyMedium);

  Color _getSpeakerColor() {
    // Return different colors based on speaker ID
    switch (message.speakerId % 5) {
      case 0:
        return Colors.purple;
      case 1:
        return Colors.red;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.green;
      case 4:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showEditNameDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController(text: message.speakerName);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(context.loc.editName, textAlign: TextAlign.center, style: context.textTheme.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.loc.enterNewName, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: getDialogWidth(context)),
              child: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                autofocus: true,
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        actionsPadding: EdgeInsets.zero,
        actions: [
          const Divider(height: 1, color: Color(0xFFBDBDBD)),
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(dialogContext).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                      ),
                    ),
                    child: Text(context.loc.cancel, style: context.textTheme.labelLarge?.copyWith(color: Colors.blue)),
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      // Update name using the bloc
                      final newName = nameController.text.trim();
                      if (newName.isNotEmpty) {
                        context.read<TranscriptionSummaryBloc>().add(
                          TranscriptionSummaryEvent.updateSpeakers(speakerId: message.speakerIdRaw, newName: newName),
                        );
                      }
                      Navigator.of(dialogContext).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                      ),
                    ),
                    child: Text(context.loc.save, style: context.textTheme.labelLarge?.copyWith(color: Colors.blue)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
