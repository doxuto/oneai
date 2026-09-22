import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/home/widgets/sentry_feedback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';

/// Widget to collect feedback at the end of a meeting
class FeedbackWidget extends StatefulWidget {
  const FeedbackWidget({super.key});

  @override
  State<FeedbackWidget> createState() => _FeedbackWidgetState();
}

class _FeedbackWidgetState extends State<FeedbackWidget> {
  bool _showGiveFeedbackButton = false;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    decoration: BoxDecoration(color: const Color(0xFFF0F6FF), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Text(context.loc.howDidWeDo, style: context.textTheme.titleSmall),
        const Spacer(),
        if (_showGiveFeedbackButton)
          _buildGiveFeedbackButton(context)
        else ...[
          _buildFeedbackButton(
            context,
            Assets.dislikeButton,
            onPressed: () {
              // Add your dislike feedback handling logic here
              showDialog(context: context, builder: (_) => const SentryFeedbackDialog());
            },
          ),
          gapW16,
          _buildFeedbackButton(
            context,
            Assets.likeButton,
            onPressed: () {
              setState(() {
                _showGiveFeedbackButton = true;
              });
            },
          ),
        ],
      ],
    ),
  );

  Widget _buildFeedbackButton(BuildContext context, String image, {VoidCallback? onPressed}) => GestureDetector(
    onTap:
        onPressed == null
            ? null
            : () {
              HapticFeedback.lightImpact();
              onPressed();
            },
    child: Image.asset(image, width: 40, height: 40),
  );

  Widget _buildGiveFeedbackButton(BuildContext context) => ElevatedButton(
    onPressed: () async {
      await HapticFeedback.lightImpact();
      // Handle give feedback action
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      } else {
        await inAppReview.openStoreListing();
      }
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(45),
        side: const BorderSide(color: Color(0xFF2C7DF7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    child: Text(
      context.loc.giveFeedback,
      style: context.textTheme.bodyMedium?.copyWith(color: const Color(0xFF2C7DF7)),
    ),
  );
}
