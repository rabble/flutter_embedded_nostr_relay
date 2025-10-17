// ABOUTME: Timeline view that displays kind 32222 events using Riverpod StreamProvider
// ABOUTME: Shows real-time updates from external relays through the embedded proxy

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/relay_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'hashtag_screen.dart';
import 'profile_screen.dart';
import 'video_player_screen.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  final _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 500) {
      // Load more when within 500 pixels of the bottom
      final notifier = ref.read(eventListProvider.notifier);
      if (!notifier.isLoadingMore && notifier.hasMoreEvents) {
        notifier.loadMoreEvents();
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final eventStream = ref.watch(addressableEventStreamProvider);
    final eventList = ref.watch(eventListProvider);
    final isLoadingMore = ref.watch(isLoadingMoreProvider);
    final hasMoreEvents = ref.watch(hasMoreEventsProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Events (Kind 32222)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh by clearing the list
              ref.read(eventListProvider.notifier).clear();
            },
          ),
        ],
      ),
      body: eventStream.when(
        data: (_) {
          // Use the accumulated event list instead of individual stream items
          if (eventList.isEmpty && !isLoadingMore) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_library, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No video events yet'),
                  Text('Waiting for kind 32222 events...'),
                ],
              ),
            );
          }
          
          return RefreshIndicator(
            onRefresh: () async {
              ref.read(eventListProvider.notifier).clear();
              // Wait a bit for new events to come in
              await Future.delayed(const Duration(seconds: 1));
            },
            child: GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: eventList.length + (isLoadingMore || hasMoreEvents ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == eventList.length) {
                  // Show loading indicator at the bottom
                  if (isLoadingMore) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  } else if (hasMoreEvents) {
                    // Show a button to load more manually if scroll doesn't trigger
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ref.read(eventListProvider.notifier).loadMoreEvents();
                          },
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Load More'),
                        ),
                      ),
                    );
                  } else {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No more events'),
                      ),
                    );
                  }
                }
                
                final event = eventList[index];
                return AddressableEventCard(event: event);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              ElevatedButton(
                onPressed: () => ref.refresh(relayProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddressableEventCard extends StatelessWidget {
  final NostrEvent event;
  
  const AddressableEventCard({super.key, required this.event});
  
  @override
  Widget build(BuildContext context) {
    // Parse OpenVine kind 32222 event data
    String title = 'Video Event';
    String? description;
    String? videoUrl;
    String? thumbnailUrl;
    String? dTag;
    String? vineId;
    String? loops;
    String? likes;
    List<String> hashtags = [];
    
    // Extract data from tags
    for (final tag in event.tags) {
      if (tag.isEmpty) continue;
      
      switch (tag[0]) {
        case 'd':
          if (tag.length > 1) dTag = tag[1];
          break;
        case 'title':
          if (tag.length > 1) title = tag[1];
          break;
        case 'imeta':
          // Parse imeta tags which contain url, image, blurhash, etc.
          for (int i = 1; i < tag.length - 1; i += 2) {
            final key = tag[i];
            final value = tag[i + 1];
            if (key == 'url') {
              videoUrl = value;
            } else if (key == 'image') {
              thumbnailUrl = value;
            }
          }
          break;
        case 'vine_id':
          if (tag.length > 1) vineId = tag[1];
          break;
        case 'loops':
          if (tag.length > 1) loops = tag[1];
          break;
        case 'likes':
          if (tag.length > 1) likes = tag[1];
          break;
        case 't':
          if (tag.length > 1) hashtags.add(tag[1]);
          break;
      }
    }
    
    // Use content as description if not empty
    if (event.content.isNotEmpty) {
      description = event.content;
    }
    
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(vineEvent: event),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail section
          if (thumbnailUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 64,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade200,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                  // Play button overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.3),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.black54,
                          child: Icon(
                            Icons.play_arrow,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 180,
              color: Colors.grey.shade200,
              child: const Center(
                child: Icon(
                  Icons.video_library,
                  size: 64,
                  color: Colors.grey,
                ),
              ),
            ),
          
          // Content section
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(pubkey: event.pubkey),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.purple.shade100,
                        child: const Icon(Icons.video_library, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (vineId != null || dTag != null)
                              Text(
                                'ID: ${vineId ?? dTag}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                // Display hashtags if any
                if (hashtags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: hashtags.map((tag) => InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HashtagScreen(hashtag: tag),
                          ),
                        );
                      },
                      child: Chip(
                        label: Text('#$tag'),
                        labelStyle: const TextStyle(fontSize: 11),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.purple.shade50,
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    // Loops count
                    if (loops != null) ...[
                      const Icon(Icons.loop, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(loops),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Likes count
                    if (likes != null) ...[
                      const Icon(Icons.favorite, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatCount(likes),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Time
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      _formatTimestamp(event.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    // Author - clickable
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfileScreen(pubkey: event.pubkey),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${event.pubkey.substring(0, 6)}...',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
  
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
  
  String _formatCount(String count) {
    try {
      final num = int.parse(count);
      if (num >= 1000000) {
        return '${(num / 1000000).toStringAsFixed(1)}M';
      } else if (num >= 1000) {
        return '${(num / 1000).toStringAsFixed(1)}K';
      }
      return count;
    } catch (e) {
      return count;
    }
  }
}