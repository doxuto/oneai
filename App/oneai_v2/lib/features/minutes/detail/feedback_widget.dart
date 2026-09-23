import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/features/minutes/detail/feedback_dialog.dart';

/// v1 FeedbackWidget: thumbs down → feedback dialog; thumbs up → review button.
class FeedbackWidget extends StatefulWidget {
  const FeedbackWidget({super.key});
  @override
  State<FeedbackWidget> createState() => _FeedbackWidgetState();
}

class _FeedbackWidgetState extends State<FeedbackWidget> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(color: const Color(0xFFF0F6FF), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Text(context.l10n.howDidWeDo, style: context.textTheme.titleSmall),
            const Spacer(),
            if (_liked)
              ElevatedButton(
                onPressed: () async {
                  await HapticFeedback.lightImpact();
                  final review = InAppReview.instance;
                  if (await review.isAvailable()) {
                    await review.requestReview();
                  } else {
                    await review.openStoreListing();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(45), side: const BorderSide(color: AppColors.brandBlueAlt)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(context.l10n.giveFeedback, style: context.textTheme.bodyMedium?.copyWith(color: AppColors.brandBlueAlt)),
              )
            else ...[
              GestureDetector(onTap: () { HapticFeedback.lightImpact(); showFeedbackDialog(context); }, child: Image.asset(Assets.dislikeButton, width: 40, height: 40)),
              gapW16,
              GestureDetector(onTap: () { HapticFeedback.lightImpact(); setState(() => _liked = true); }, child: Image.asset(Assets.likeButton, width: 40, height: 40)),
            ],
          ],
        ),
      );
}
