import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/demo/view_model/demo_user_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class DemoUserScreen extends StatelessWidget {
  const DemoUserScreen({super.key});

  // Load users
  void _loadUsers(BuildContext context) {
    context.read<DemoUserBloc>().add(const UserEvent.getUsers());
  }

  // Load posts for a specific user
  void _loadUserPosts(BuildContext context, int userId) {
    context.read<DemoUserBloc>().add(UserEvent.getUserPosts(userId: userId));
  }

  // Reset loading states
  void _resetLoading(BuildContext context) {
    context.read<DemoUserBloc>().resetLoadingStates();
  }

  // Show loading statistics
  void _showLoadingStats(BuildContext context) {
    final stats = context.read<DemoUserBloc>().loadingManager.getStatistics();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.loc.loadingStatistics),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.loc.totalOperations(stats['total'] as int)),
                Text(context.loc.completed(stats['completed'] as int)),
                Text(context.loc.inProgress(stats['inProgress'] as int)),
                Text(context.loc.averageDuration((stats['averageDurationMs'] as int).toString())),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.loc.close))],
          ),
    );
  }

  // Display loading status for an operation
  Widget _buildLoadingIndicator(BuildContext context, DemoUserOperation operation) {
    final opState = context.read<DemoUserBloc>().loadingManager.getOperationState(operation);

    if (opState == null || !opState.isLoading) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        gapW8,
        SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            // Show different colors for repeated attempts
            color: opState.attemptCount > 1 ? context.appTheme.warningColor : null,
          ),
        ),
        if (opState.attemptCount > 1)
          Row(
            children: [
              gapW4,
              Text(
                context.loc.attempt(opState.attemptCount),
                style: context.textTheme.labelSmall?.copyWith(color: context.appTheme.warningColor),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Load initial data when widget builds for the first time
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers(context);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.usersAndPosts),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: context.loc.loadingStatisticsTooltip,
            onPressed: () => _showLoadingStats(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.loc.resetLoadingStatesTooltip,
            onPressed: () => _resetLoading(context),
          ),
        ],
        // Add leading back button and ensure it navigates to home
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(Routes.demoHome)),
      ),
      body: BlocBuilder<DemoUserBloc, UserState>(
        builder: (context, state) {
          // Show error if any
          if (state.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.loc.error(state.errorMessage!),
                    style: context.textTheme.bodyLarge?.copyWith(color: context.colorScheme.error),
                  ),
                  gapH16,
                  ElevatedButton(onPressed: () => _loadUsers(context), child: Text(context.loc.retry)),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Users section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text(
                            context.loc.users,
                            style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          _buildLoadingIndicator(context, DemoUserOperation.fetchUsers),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          state.users.isEmpty && !state.isOperationLoading(DemoUserOperation.fetchUsers)
                              ? Center(child: Text(context.loc.noUsersFound))
                              : ListView.builder(
                                itemCount: state.users.length,
                                itemBuilder: (context, index) {
                                  final user = state.users[index];
                                  return ListTile(
                                    title: Text(user.name),
                                    subtitle: Text(user.email),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _loadUserPosts(context, user.id);
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Posts section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text(
                            context.loc.posts,
                            style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          _buildLoadingIndicator(context, DemoUserOperation.fetchPosts),
                        ],
                      ),
                    ),
                    Expanded(
                      child:
                          state.posts.isEmpty && !state.isOperationLoading(DemoUserOperation.fetchPosts)
                              ? Center(child: Text(context.loc.selectUserToViewPosts))
                              : ListView.builder(
                                itemCount: state.posts.length,
                                itemBuilder: (context, index) {
                                  final post = state.posts[index];
                                  return ListTile(
                                    title: Text(post.title),
                                    subtitle: Text(post.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      // Navigate to post details when tapped
                                      context.push(Routes.postDemoWithId(post.id), extra: post);
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Refresh all data
          _loadUsers(context);
          final state = context.read<DemoUserBloc>().state;
          if (state.posts.isNotEmpty) {
            _loadUserPosts(context, state.posts.first.userId);
          }
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
