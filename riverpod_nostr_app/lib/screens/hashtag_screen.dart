// ABOUTME: Hashtag screen that displays videos filtered by a specific hashtag
// ABOUTME: Uses a dedicated subscription to query both local and external relay events

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/hashtag_providers.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

class HashtagScreen extends ConsumerStatefulWidget {
  final String hashtag;
  
  const HashtagScreen({
    super.key,
    required this.hashtag,
  });

  @override
  ConsumerState<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends ConsumerState<HashtagScreen> {
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
      final notifier = ref.read(hashtagEventListProvider(widget.hashtag).notifier);
      if (!notifier.isLoadingMore && notifier.hasMoreEvents) {
        notifier.loadMoreEvents();
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final eventList = ref.watch(hashtagEventListProvider(widget.hashtag));
    final isLoadingMore = ref.watch(hashtagIsLoadingMoreProvider(widget.hashtag));
    final hasMoreEvents = ref.watch(hashtagHasMoreEventsProvider(widget.hashtag));
    
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.hashtag}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh by clearing the list
              ref.read(hashtagEventListProvider(widget.hashtag).notifier).clear();
            },
          ),
        ],
      ),
      body: eventList.isEmpty && !isLoadingMore
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.tag, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('No videos with #${widget.hashtag}'),
                const Text('Loading from relays...'),
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: () async {
              ref.read(hashtagEventListProvider(widget.hashtag).notifier).clear();
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
                            ref.read(hashtagEventListProvider(widget.hashtag).notifier).loadMoreEvents();
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
                return HashtagEventCard(
                  event: event,
                  currentHashtag: widget.hashtag,
                );
              },
            ),
          ),
    );
  }
}

class HashtagEventCard extends StatelessWidget {
  final NostrEvent event;
  final String currentHashtag;
  
  const HashtagEventCard({
    super.key,
    required this.event,
    required this.currentHashtag,
  });
  
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
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Could open video player here
        },
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
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
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // Display hashtags if any
                    if (hashtags.isNotEmpty) ...[
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: hashtags.map((tag) => InkWell(
                          onTap: tag != currentHashtag ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HashtagScreen(hashtag: tag),
                              ),
                            );
                          } : null,
                          child: Chip(
                            label: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: tag == currentHashtag ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: tag == currentHashtag 
                              ? Colors.purple.shade200 
                              : Colors.purple.shade50,
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        // Time
                        const Icon(Icons.access_time, size: 12, color: Colors.grey),
                        const SizedBox(width: 2),
                        Text(
                          _formatTimestamp(event.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        // Stats
                        if (loops != null) ...[
                          const Icon(Icons.loop, size: 12, color: Colors.grey),
                          const SizedBox(width: 2),
                          Text(
                            _formatCount(loops),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
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
      return 'now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h';
    } else {
      return '${diff.inDays}d';
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