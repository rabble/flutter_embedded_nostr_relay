// ABOUTME: Profile screen that displays user information, vines, reactions, and lists
// ABOUTME: Shows cached data immediately while fetching fresh content from external relays

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/profile_provider.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'video_player_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String pubkey;
  
  const ProfileScreen({super.key, required this.pubkey});
  
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final metadata = ref.watch(profileMetadataProvider(widget.pubkey));
    
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 280,
              floating: false,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: _buildProfileHeader(metadata),
              ),
              bottom: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.video_library), text: 'Vines'),
                  Tab(icon: Icon(Icons.favorite), text: 'Reactions'),
                  Tab(icon: Icon(Icons.repeat), text: 'Reposts'),
                  Tab(icon: Icon(Icons.list), text: 'Lists'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildVinesTab(widget.pubkey),
            _buildReactionsTab(widget.pubkey),
            _buildRepostsTab(widget.pubkey),
            _buildListsTab(widget.pubkey),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProfileHeader(AsyncValue<Map<String, dynamic>?> metadata) {
    return metadata.when(
      data: (data) {
        final name = data?['name'] ?? 'Anonymous';
        final about = data?['about'] ?? '';
        final picture = data?['picture'];
        final banner = data?['banner'];
        final nip05 = data?['nip05'];
        
        return Stack(
          fit: StackFit.expand,
          children: [
            // Banner
            if (banner != null)
              Image.network(
                banner,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.purple.shade100,
                ),
              )
            else
              Container(
                color: Colors.purple.shade100,
              ),
            
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            
            // Profile info
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: picture != null ? NetworkImage(picture) : null,
                    backgroundColor: Colors.purple.shade200,
                    child: picture == null 
                      ? const Icon(Icons.person, size: 40, color: Colors.white)
                      : null,
                  ),
                  const SizedBox(width: 16),
                  // Name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (nip05 != null)
                          Row(
                            children: [
                              const Icon(Icons.verified, size: 16, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                nip05,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        if (about.isNotEmpty)
                          Text(
                            about,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Container(
        color: Colors.purple.shade100,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        color: Colors.purple.shade100,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.white),
              Text('Error loading profile: $e', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildVinesTab(String pubkey) {
    final vines = ref.watch(userVinesProvider(pubkey));
    
    return vines.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Text('No vines yet'),
          );
        }
        
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: events.length,
          itemBuilder: (context, index) {
            return VineCard(event: events[index]);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
  
  Widget _buildReactionsTab(String pubkey) {
    final reactions = ref.watch(userReactionsProvider(pubkey));
    
    return reactions.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Text('No reactions yet'),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final reaction = events[index];
            final content = reaction.content;
            final reactedTo = reaction.tags.firstWhere(
              (tag) => tag.isNotEmpty && tag[0] == 'e',
              orElse: () => [],
            );
            
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(content.isEmpty ? '👍' : content),
                ),
                title: Text('Reacted to event'),
                subtitle: reactedTo.length > 1 
                  ? Text('${reactedTo[1].substring(0, 8)}...')
                  : null,
                trailing: Text(_formatTime(reaction.createdAt)),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
  
  Widget _buildRepostsTab(String pubkey) {
    final reposts = ref.watch(userRepostsProvider(pubkey));
    
    return reposts.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Text('No reposts yet'),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final repost = events[index];
            final repostedEvent = repost.tags.firstWhere(
              (tag) => tag.isNotEmpty && tag[0] == 'e',
              orElse: () => [],
            );
            
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.repeat),
                ),
                title: const Text('Reposted'),
                subtitle: repostedEvent.length > 1 
                  ? Text('${repostedEvent[1].substring(0, 8)}...')
                  : null,
                trailing: Text(_formatTime(repost.createdAt)),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
  
  Widget _buildListsTab(String pubkey) {
    final lists = ref.watch(userListsProvider(pubkey));
    
    return lists.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(
            child: Text('No lists yet'),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final list = events[index];
            String listName = 'Untitled List';
            
            // Extract list name from d tag
            final dTag = list.tags.firstWhere(
              (tag) => tag.isNotEmpty && tag[0] == 'd',
              orElse: () => [],
            );
            if (dTag.length > 1) {
              listName = dTag[1];
            }
            
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.list),
                ),
                title: Text(listName),
                subtitle: Text('${list.tags.where((t) => t.isNotEmpty && t[0] == 'p').length} items'),
                trailing: Text(_formatTime(list.createdAt)),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
  
  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) {
      return 'now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h';
    } else if (diff.inDays < 30) {
      return '${diff.inDays}d';
    } else {
      return '${(diff.inDays / 30).round()}mo';
    }
  }
}

class VineCard extends StatelessWidget {
  final NostrEvent event;
  
  const VineCard({super.key, required this.event});
  
  @override
  Widget build(BuildContext context) {
    String? thumbnailUrl;
    String title = 'Vine';
    List<String> hashtags = [];
    
    // Extract data from tags
    for (final tag in event.tags) {
      if (tag.isEmpty) continue;
      
      switch (tag[0]) {
        case 'title':
          if (tag.length > 1) title = tag[1];
          break;
        case 'imeta':
          for (int i = 1; i < tag.length - 1; i += 2) {
            if (tag[i] == 'image' && i + 1 < tag.length) {
              thumbnailUrl = tag[i + 1];
            }
          }
          break;
        case 't':
          if (tag.length > 1) hashtags.add(tag[1]);
          break;
      }
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
        clipBehavior: Clip.antiAlias,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: thumbnailUrl != null
              ? Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image, size: 48),
                  ),
                )
              : Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.video_library, size: 48),
                ),
          ),
          // Title and hashtags
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hashtags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: hashtags.map((tag) => Chip(
                      label: Text('#$tag', style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.purple.shade50,
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}