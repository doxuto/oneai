import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:flutter/material.dart';

/// Widget to display a section of meeting minutes
class MinuteSectionWidget extends StatelessWidget {
  final MeetingMinuteSection section;

  const MinuteSectionWidget({required this.section, super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Section title with time range
      Text(
        section.title,
        style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
      ),
      gapH12,
      // Bullet points
      ...section.bulletPoints.map(
        (point) => Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 8),
          child: Row(
            children: [
              // const Padding(
              //   padding: EdgeInsets.only(top: 6),
              //   child: Text('• ', style: TextStyle(fontSize: 16, color: Colors.black38)),
              // ),
              Expanded(child: Text(point, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black))),
            ],
          ),
        ),
      ),
      if (section.bulletPoints.isEmpty)
        Text(section.title, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black)),
      gapH24,
    ],
  );
}
