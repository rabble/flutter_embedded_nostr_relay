// ABOUTME: Timeline screen displaying Nostr events with filtering and interactions
// ABOUTME: Shows global, following, and mentions feeds with real-time updates

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/timeline_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/timeline_event_card.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    
    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final timelineProvider = context.read<TimelineProvider>();
    final newType = TimelineType.values[_tabController.index];
    timelineProvider.switchTimeline(newType);
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      // Load more events when reaching the bottom
      // TODO: Implement pagination
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Tab bar
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Global'),
              Tab(text: 'Following'),
              Tab(text: 'Mentions'),
            ],
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        
        // Timeline content
        Expanded(
          child: Consumer2<TimelineProvider, UserProvider>(
            builder: (context, timelineProvider, userProvider, child) {
              if (timelineProvider.isLoading && 
                  timelineProvider.currentTimelineEvents.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading timeline...'),
                    ],
                  ),
                );
              }

              if (timelineProvider.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading timeline',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timelineProvider.error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          timelineProvider.refreshCurrentTimeline();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final events = timelineProvider.currentTimelineEvents;
              
              if (events.isEmpty) {
                return _buildEmptyState();
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await timelineProvider.refreshCurrentTimeline();
                },
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: events.length + (timelineProvider.isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= events.length) {
                      // Loading indicator at bottom
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final timelineEvent = events[index];
                    return TimelineEventCard(
                      timelineEvent: timelineEvent,
                      onLike: () => _handleLike(timelineEvent),
                      onReply: () => _handleReply(timelineEvent),
                      onRepost: () => _handleRepost(timelineEvent),
                      onShare: () => _handleShare(timelineEvent),
                      onUserTap: () => _handleUserTap(timelineEvent),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final timelineProvider = context.read<TimelineProvider>();
    
    String title;
    String description;
    IconData icon;
    
    switch (timelineProvider.currentTimeline) {
      case TimelineType.global:
        title = 'No posts yet';
        description = 'Be the first to share something with the world!';
        icon = Icons.public;
        break;
      case TimelineType.following:
        title = 'No posts from followed users';
        description = 'Follow some users to see their posts here.';
        icon = Icons.people_outline;
        break;
      case TimelineType.mentions:
        title = 'No mentions yet';
        description = 'When someone mentions you, it will appear here.';
        icon = Icons.alternate_email;
        break;
    }
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                timelineProvider.refreshCurrentTimeline();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLike(TimelineEvent timelineEvent) async {
    try {
      final timelineProvider = context.read<TimelineProvider>();
      await timelineProvider.toggleLike(
        timelineEvent.event.id,
        timelineEvent.event.pubkey,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to like post: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _handleReply(TimelineEvent timelineEvent) {
    // TODO: Implement reply functionality
    // This would open the post composer with reply context
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reply functionality coming soon'),
      ),
    );
  }

  void _handleRepost(TimelineEvent timelineEvent) {
    // TODO: Implement repost functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Repost functionality coming soon'),
      ),
    );
  }

  void _handleShare(TimelineEvent timelineEvent) {
    // TODO: Implement share functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share functionality coming soon'),
      ),
    );
  }

  void _handleUserTap(TimelineEvent timelineEvent) {
    // TODO: Navigate to user profile
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profile view for ${timelineEvent.event.pubkey.substring(0, 8)}... coming soon'),
      ),
    );
  }
}