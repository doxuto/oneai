import 'package:flutter/material.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// v1's SentryFeedbackDialog: a free-text box that becomes Sentry user
/// feedback. Wiring of Sentry itself is A6-06; without it the capture is a no-op.
Future<void> showFeedbackDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: ctx.l10n.giveFeedback,
      confirmLabel: ctx.l10n.done,
      content: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: dialogWidth(ctx)),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: dialogFieldDecoration(ctx, hintText: ctx.l10n.message),
        ),
      ),
      onConfirm: () async {
        final text = controller.text.trim();
        Navigator.of(ctx).pop();
        if (text.isEmpty) return;
        try {
          await Sentry.captureFeedback(SentryFeedback(message: text));
        } on Object catch (_) {
          // Sentry not initialised (dev) — nothing else to do with it.
        }
      },
    ),
  );
}
