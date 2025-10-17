// ABOUTME: Widget for displaying individual timeline events/posts
// ABOUTME: Shows author info, content, interactions, and media with Material Design 3 styling

import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/timeline_provider.dart';

class TimelineEventCard extends StatelessWidget {
  final TimelineEvent timelineEvent;
  final VoidCallback? onLike;
  final VoidCallback? onReply;
  final VoidCallback? onRepost;
  final VoidCallback? onShare;
  final VoidCallback? onUserTap;

  const TimelineEventCard({
    super.key,
    required this.timelineEvent,
    this.onLike,
    this.onReply,
    this.onRepost,
    this.onShare,
    this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final event = timelineEvent.event;
    final profile = timelineEvent.authorProfile;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author header
            Row(
              children: [
                // Profile picture
                GestureDetector(
                  onTap: onUserTap,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    backgroundImage: profile?.picture != null
                        ? CachedNetworkImageProvider(profile!.picture!)
                        : null,
                    child: profile?.picture == null
                        ? Icon(
                            Icons.person,
                            color: colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Author info
                Expanded(
                  child: GestureDetector(
                    onTap: onUserTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.name ?? 'Anonymous',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        const SizedBox(height: 2),
                        
                        Row(
                          children: [
                            Text(
                              '@${event.pubkey.substring(0, 8)}...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                            
                            if (profile?.nip05 != null) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                            ],
                            
                            const SizedBox(width: 8),
                            
                            Text(
                              timeago.format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  event.createdAt * 1000,
                                ),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // More options
                IconButton(
                  onPressed: () => _showMoreOptions(context),
                  icon: const Icon(Icons.more_vert),
                  iconSize: 16,
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Content
            _buildContent(context),
            
            // Media attachments
            if (timelineEvent.hasMedia) ...[
              const SizedBox(height: 12),
              _buildMediaContent(context),
            ],
            
            const SizedBox(height: 12),
            
            // Interaction buttons
            Row(
              children: [
                // Reply button
                _InteractionButton(
                  icon: Icons.mode_comment_outlined,
                  activeIcon: Icons.mode_comment,
                  count: timelineEvent.replyCount,
                  isActive: false, // TODO: Track if user has replied
                  onPressed: onReply,
                ),
                
                const SizedBox(width: 16),
                
                // Repost button
                _InteractionButton(
                  icon: Icons.repeat,
                  activeIcon: Icons.repeat,
                  count: 0, // TODO: Track reposts
                  isActive: timelineEvent.isReposted,
                  onPressed: onRepost,
                  activeColor: Colors.green,
                ),
                
                const SizedBox(width: 16),
                
                // Like button
                _InteractionButton(
                  icon: Icons.favorite_border,
                  activeIcon: Icons.favorite,
                  count: timelineEvent.likeCount,
                  isActive: timelineEvent.isLiked,
                  onPressed: onLike,
                  activeColor: Colors.red,
                ),
                
                const Spacer(),
                
                // Share button
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined),
                  iconSize: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final content = timelineEvent.event.content;
    
    // Simple content rendering - could be enhanced with:
    // - Link detection and previews
    // - Hashtag highlighting
    // - Mention highlighting
    
    return SelectableText(
      content,
      style: theme.textTheme.bodyMedium,
    );
  }

  Widget _buildMediaContent(BuildContext context) {
    final mediaUrls = timelineEvent.mediaUrls;
    
    if (mediaUrls.isEmpty) return const SizedBox.shrink();
    
    return Column(
      children: mediaUrls.map((url) => _buildMediaItem(context, url)).toList(),
    );
  }

  Widget _buildMediaItem(BuildContext context, String url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 200,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  'Failed to load image',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Event ID'),
              onTap: () {
                Navigator.of(context).pop();
                // TODO: Copy event ID to clipboard
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy Link'),
              onTap: () {
                Navigator.of(context).pop();
                // TODO: Copy event link
              },
            ),
            ListTile(
              leading: const Icon(Icons.report),
              title: const Text('Report'),
              onTap: () {
                Navigator.of(context).pop();
                // TODO: Report functionality
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Block User'),
              onTap: () {
                Navigator.of(context).pop();
                // TODO: Block user functionality
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final int count;
  final bool isActive;
  final VoidCallback? onPressed;
  final Color? activeColor;

  const _InteractionButton({
    required this.icon,
    required this.activeIcon,
    required this.count,
    required this.isActive,
    this.onPressed,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final buttonColor = isActive 
        ? (activeColor ?? colorScheme.primary)
        : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 18,
              color: buttonColor,
            ),
            
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: buttonColor,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}