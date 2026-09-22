import 'dart:io';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/home/view_model/home_bloc.dart';
import 'package:codebase_ai/ui/features/home/widgets/minute_item_card.dart';
import 'package:codebase_ai/ui/features/home/widgets/loading_dots.dart';
import 'package:codebase_ai/ui/features/home/widgets/new_minutes_bottom_sheet.dart';
import 'package:codebase_ai/ui/features/home/widgets/premium_button.dart';
import 'package:codebase_ai/ui/features/home/widgets/sentry_feedback_dialog.dart';
import 'package:codebase_ai/ui/features/home/widgets/tag_chip.dart';
import 'package:codebase_ai/utils/dialog.dart';
import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Home screen that displays the main content of the application
class HomeScreen extends StatefulWidget {
  /// Creates a new [HomeScreen] instance
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isPremium = false;
  late final ScrollController _minutesScrollController;
  bool _isLoadMoreTriggered = false;

  final _log = Logger('HomeScreen');

  @override
  void initState() {
    super.initState();
    _checkEntitlement();
    Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
    _minutesScrollController = ScrollController()..addListener(_onMinutesScroll);
    Future.microtask(_showIntroBasicPopup);
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_customerInfoListener);
    _minutesScrollController
      ..removeListener(_onMinutesScroll)
      ..dispose();
    super.dispose();
  }

  void _onMinutesScroll() {
    final controller = _minutesScrollController;
    if (controller.position.pixels >= controller.position.maxScrollExtent - 200 && !_isLoadMoreTriggered) {
      // Trigger load more
      _isLoadMoreTriggered = true;
      context.read<HomeBloc>().add(const HomeEvent.loadMinuteItems(isRefresh: false, isLoadMore: true));
    }
    // Reset trigger when user scrolls up
    if (controller.position.pixels < controller.position.maxScrollExtent - 400) {
      _isLoadMoreTriggered = false;
    }
  }

  Future<void> _requestTrackingAuthorization() async {
  if (!Platform.isIOS) return;

  final status = await AppTrackingTransparency.trackingAuthorizationStatus;
  if (status == TrackingStatus.notDetermined) {
    final result = await AppTrackingTransparency.requestTrackingAuthorization();
    debugPrint('ATT status: $result');
  }
}

  Future<void> _checkEntitlement() async {
    final info = await Purchases.getCustomerInfo();
    setState(() {
      _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
    });
  }

  void _customerInfoListener(CustomerInfo info) {
    if (mounted) {
      setState(() {
        _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
      });
    }
  }

  Future<void> _onPremiumButtonPressed() async {
    if (!_isPremium) {
      await RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId);
    } else {
      await RevenueCatUI.presentCustomerCenter();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colorScheme.surface,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                gapH16,
                _buildTitle(context),
                gapH24,
                BlocBuilder<HomeBloc, HomeState>(
                  builder: (context, state) => _buildTagList(context, state.tags, state.selectedTagIds),
                ),
                gapH24,
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      context.read<HomeBloc>().add(const HomeEvent.loadMinuteItems(isRefresh: true, isLoadMore: false));
                    },
                    child: _buildMinutesList(),
                  ),
                ),
              ],
            ),
            BlocSelector<HomeBloc, HomeState, bool>(
              selector: (state) => state.isLoading,
              builder:
                  (context, isLoading) =>
                      isLoading
                          ? const Positioned.fill(
                            child: ColoredBox(
                              color: Colors.transparent,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          )
                          : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
    floatingActionButton: Builder(
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
          offset:
              bottomInset > 0
                  ? const Offset(0, 1.2) // Move FAB down and hide when keyboard is open
                  : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: bottomInset > 0 ? 0.0 : 1.0,
            child: _buildNewMinutesButton(context),
          ),
        );
      },
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
  );

  Widget _buildMinutesList() => BlocBuilder<HomeBloc, HomeState>(
    builder: (context, state) {
      final filteredMinutes =
          state.selectedTagIds.isEmpty
              ? state.minutes
              : state.minutes
                  .where((m) => state.selectedTagIds.every((tagId) => m.tags?.contains(tagId) ?? false))
                  .toList();

      if (filteredMinutes.isEmpty && !state.isLoading) {
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: const Alignment(0, -0.4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(color: Color(0xFFE1EDFF), shape: BoxShape.circle),
                      child: Center(
                        child: SvgPicture.asset(
                          Assets.clockIcon,
                          width: 32,
                          height: 32,
                          colorFilter: const ColorFilter.mode(Color(0xFF0767F8), BlendMode.srcIn),
                        ),
                      ),
                    ),
                    gapH16,
                    Text(
                      context.loc.noNotesYet,
                      style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    gapH8,
                    Text(
                      context.loc.tapButtonBelowToStart,
                      style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return ListView.builder(
        controller: _minutesScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80), // Add bottom padding to avoid overlap with FAB
        itemCount: filteredMinutes.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < filteredMinutes.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MinuteItemCard(item: filteredMinutes[index]),
            );
          } else {
            // Loading more indicator
            return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: LoadingDots()));
          }
        },
      );
    },
  );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      children: [
        PremiumButton(
          state: _isPremium ? PremiumButtonState.premium : PremiumButtonState.upgrade,
          onPressed:
              _isPremium
                  ? null
                  : () async {
                    await HapticFeedback.lightImpact();
                    await _onPremiumButtonPressed();
                  },
        ),
        const Spacer(),
        _buildActionButton(
          context,
          icon: Assets.messageIcon,
          onTap: () async {
            await HapticFeedback.lightImpact();
            await showDialog(context: context, builder: (_) => const SentryFeedbackDialog());
          },
        ),
        gapW16,
        _buildActionButton(
          context,
          icon: Assets.settingsIcon,
          onTap: () {
            HapticFeedback.lightImpact();
            context.go(Routes.settings);
          },
        ),
      ],
    ),
  );

  Widget _buildActionButton(BuildContext context, {required String icon, required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(icon, width: 24, height: 24)),
  );

  Widget _buildTitle(BuildContext context) =>
      Text('My Notes', style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold));

  Widget _buildCreateTagButton(BuildContext context) => Container(
    height: 40,
    decoration: BoxDecoration(color: const Color(0xFFEDF4FF), borderRadius: BorderRadius.circular(20)),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _showCreateTagDialog(context);
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_circle_rounded, color: Color(0xFF0767F8), size: 18),
              gapW8,
              Text(
                context.loc.createTag,
                style: context.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF0767F8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _showCreateTagDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(context.loc.createNewTag, textAlign: TextAlign.center, style: context.textTheme.titleLarge),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.enterTagName, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: getDialogWidth(context)),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: context.loc.tagName,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.colorScheme.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
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
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          if (controller.text.isNotEmpty) {
                            context.read<HomeBloc>().add(HomeEvent.createTag(name: controller.text));
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.create,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildTagList(BuildContext context, List<Tag> tags, List<String> selectedTagIds) {
    final allTagSlot = tags.length > 2 ? 1 : 0;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length + 1 + allTagSlot,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            // First item: create tag button
            return _buildCreateTagButton(context);
          } else if (index <= allTagSlot) {
            // Second item: All button
            final isSelected = selectedTagIds.isEmpty;
            return TagChip(
              tag: const Tag(id: '', name: 'All'),
              selected: isSelected,
              onTap: () => context.read<HomeBloc>().add(const HomeEvent.selectTags(tagIds: [])),
            );
          }
          final tag = tags[index - 1 - allTagSlot];
          final isSelected = selectedTagIds.contains(tag.id);
          return TagChip(
            tag: tag,
            selected: isSelected,
            onTap: () {
              final bloc = context.read<HomeBloc>();
              final current = List<String>.from(selectedTagIds);
              if (isSelected) {
                current.remove(tag.id);
              } else {
                current.add(tag.id);
              }
              bloc.add(HomeEvent.selectTags(tagIds: current));
            },
            onLongPress: () {
              _showDeleteTagDialog(context, tag);
            },
          );
        },
      ),
    );
  }

  void _showDeleteTagDialog(BuildContext context, Tag tag) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('Delete Tag', style: context.textTheme.titleLarge)],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Are you sure you want to delete the tag "${tag.name}"?',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium,
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
                          Navigator.of(ctx).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.read<HomeBloc>().add(HomeEvent.deleteTag(tagId: tag.id));
                          Navigator.of(ctx).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          'Delete',
                          style: context.textTheme.labelLarge?.copyWith(color: const Color(0xFFE41919)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildNewMinutesButton(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) => const NewMinutesBottomSheet(),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0767F8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Colors.white),
            gapW8,
            Text(
              context.loc.newNote,
              style: context.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showIntroBasicPopup() async {
    // Only show for non-premium
    if (await isPremium()) {
      _log.info('Not showing popup intro basic for premium user');
      return;
    }
    if (!mounted) return;
    final remoteConfig = context.read<RemoteConfigService>();
    final prefs = context.read<SharedPreferencesService>();
    if (!remoteConfig.popupIntroBasicEnabled) {
      _log.info('Not showing popup intro basic for disabled');
      return;
    }

    // Frequency check
    final freqHours = remoteConfig.popupIntroBasicFrequencyHours;
    final now = DateTime.now();
    final lastShownStr = await prefs.getIntroBasicLastShownTime();
    if (lastShownStr != null) {
      // Tần suất (giờ) hiển thị lại popup. (0 = chỉ 1 lần)
      if (freqHours == 0) {
        _log.info('Not showing popup intro basic for frequency 0');
        return;
      }
      final lastShown = DateTime.tryParse(lastShownStr);
      if (lastShown != null && now.difference(lastShown).inHours < freqHours) {
        _log.info('Popup intro basic frequency not met');
        return;
      }
    }

    if (!mounted) return;
    _log.info('Showing popup intro basic');
    await showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text('Basic Plan Overview', textAlign: TextAlign.center, style: context.textTheme.titleLarge),
            content: Text(
              remoteConfig.popupIntroBasicText,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
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
                          _requestTrackingAuthorization();
                          HapticFeedback.lightImpact();
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          _requestTrackingAuthorization();
                          HapticFeedback.lightImpact();
                          _onPremiumButtonPressed();
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          'Go Premium',
                          style: context.textTheme.labelLarge?.copyWith(color: const Color(0xFFE41919)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );

    await prefs.setIntroBasicLastShownTime(now.toIso8601String());
  }
}
