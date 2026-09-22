import 'package:codebase_ai/domain/models/demo/demo_post_model.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DemoPostDetailScreen extends StatelessWidget {
  final DemoPostModel post;

  const DemoPostDetailScreen({required this.post, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(post.title),
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Post title in large font
          Text(post.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),

          gapH8,

          // Post metadata
          Row(
            children: [
              Chip(
                label: Text(context.loc.userId(post.userId)),
                backgroundColor: context.colorScheme.primary.withAlpha(25),
              ),
              gapW8,
              Chip(
                label: Text(context.loc.postId(post.id)),
                backgroundColor: context.appTheme.successColor.withAlpha(25),
              ),
            ],
          ),

          gapH24,

          // Post body content
          Text(post.body, style: context.textTheme.bodyLarge),

          gapH32,

          // Additional UI components can be added here
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.cardRadius)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.comments,
                    style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  gapH8,
                  Text(context.loc.commentsPlaceholder),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
