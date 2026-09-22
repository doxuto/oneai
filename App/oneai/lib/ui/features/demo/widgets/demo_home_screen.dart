import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/localization/widgets/language_selector.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/themes/widgets/theme_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DemoHomeScreen extends StatelessWidget {
  const DemoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.loc.mvvmBlocDemo), actions: const [ThemeSelector(), LanguageSelector()]),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.loc.flutterMvvmBlocDemo,
              style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            gapH32,

            // Users & Posts Feature Card
            _buildFeatureCard(
              context,
              icon: Icons.people_alt_outlined,
              title: context.loc.usersAndPosts,
              description: context.loc.usersAndPostsDesc,
              route: Routes.demoUsers,
            ),

            gapH16,

            // Future feature card (can be expanded later)
            _buildFeatureCard(
              context,
              icon: Icons.settings_outlined,
              title: context.loc.settings,
              description: context.loc.settingsDesc,
              route: Routes.demoSettings,
              isEnabled: false,
            ),

            gapH16,

            // Another potential feature
            _buildFeatureCard(
              context,
              icon: Icons.category_outlined,
              title: context.loc.categories,
              description: context.loc.categoriesDesc,
              route: Routes.demoCategories,
              isEnabled: false,
            ),

            gapH16,
          ],
        ),
      ),
    ),
  );

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String route,
    bool isEnabled = true,
  }) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: InkWell(
      borderRadius: BorderRadius.all(context.appTheme.cardRadius),
      onTap: () {
        HapticFeedback.lightImpact();
        isEnabled
            ? () => context.go(route)
            : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.loc.featureComingSoon(title)), duration: const Duration(seconds: 2)),
              );
            };
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              size: 48,
              color: isEnabled ? context.colorScheme.primary : context.colorScheme.onSurface.withAlpha(97),
            ),
            gapW16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? context.colorScheme.onSurface : context.colorScheme.onSurface.withAlpha(97),
                    ),
                  ),
                  gapH4,
                  Text(
                    description,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color:
                          isEnabled
                              ? context.colorScheme.onSurface.withAlpha(153)
                              : context.colorScheme.onSurface.withAlpha(97),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color:
                  isEnabled ? context.colorScheme.onSurface.withAlpha(97) : context.colorScheme.onSurface.withAlpha(38),
            ),
          ],
        ),
      ),
    ),
  );
}
