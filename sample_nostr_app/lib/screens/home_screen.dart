// ABOUTME: Main home screen with timeline, navigation, and post creation
// ABOUTME: Handles identity setup and displays Nostr events

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nostr_provider.dart';
import '../providers/timeline_provider.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final timelineProvider = context.read<TimelineProvider>();
      if (context.read<NostrProvider>().isInitialized) {
        timelineProvider.startSubscription();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nostr Sample'),
        centerTitle: true,
        actions: _selectedIndex == 0 ? [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<TimelineProvider>().startSubscription();
            },
          ),
        ] : null,
      ),
      body: Consumer<NostrProvider>(
        builder: (context, nostrProvider, child) {
          if (!nostrProvider.isInitialized) {
            return _buildOnboarding(context, nostrProvider);
          }
          
          switch (_selectedIndex) {
            case 0:
              return _buildTimeline(context);
            case 1:
              return _buildProfile(context);
            case 2:
              return _buildSettings(context);
            default:
              return _buildTimeline(context);
          }
        },
      ),
      floatingActionButton: Consumer<NostrProvider>(
        builder: (context, nostrProvider, child) {
          if (!nostrProvider.isInitialized || _selectedIndex != 0) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton(
            onPressed: () => _showPostDialog(context),
            child: const Icon(Icons.add),
          );
        },
      ),
      bottomNavigationBar: Consumer<NostrProvider>(
        builder: (context, nostrProvider, child) {
          if (!nostrProvider.isInitialized) {
            return const SizedBox.shrink();
          }
          return BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Timeline',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildOnboarding(BuildContext context, NostrProvider nostrProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bolt,
              size: 80,
              color: Colors.purple,
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Nostr',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const Text(
              'Get started by creating a new identity or importing an existing one.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await nostrProvider.generateNewIdentity();
                if (mounted) {
                  context.read<TimelineProvider>().startSubscription();
                }
              },
              child: const Text('Generate New Identity'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _showImportDialog(context, nostrProvider),
              child: const Text('Import Existing'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimeline(BuildContext context) {
    return Consumer<TimelineProvider>(
      builder: (context, timelineProvider, child) {
        final events = timelineProvider.events;
        
        if (events.isEmpty) {
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
            timelineProvider.startSubscription();
          },
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return _buildAddressableEventCard(context, event);
            },
          ),
        );
      },
    );
  }
  
  Widget _buildProfile(BuildContext context) {
    final nostrProvider = context.read<NostrProvider>();
    final identity = nostrProvider.currentIdentity!;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CircleAvatar(
          radius: 50,
          child: Icon(Icons.person, size: 50),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Public Key', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  identity.publicKey,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSettings(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud),
          title: const Text('Relay Status'),
          onTap: () => _showRelayStatus(context),
        ),
        ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Export Private Key'),
          onTap: () => _showExportKey(context),
        ),
      ],
    );
  }
  
  void _showPostDialog(BuildContext context) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Post'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'What\'s on your mind?',
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isNotEmpty) {
                await context.read<NostrProvider>().publishTextNote(content);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
  
  void _showImportDialog(BuildContext context, NostrProvider nostrProvider) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Private Key'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your private key (hex format)',
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await nostrProvider.importIdentity(controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  context.read<TimelineProvider>().startSubscription();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Invalid private key: $e')),
                  );
                }
              }
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }
  
  void _showRelayStatus(BuildContext context) async {
    final nostrProvider = context.read<NostrProvider>();
    final stats = await nostrProvider.getRelayStats();
    final connectedRelays = nostrProvider.service.connectedRelays;
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relay Status'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Embedded Relay', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Events: ${stats['eventCount'] ?? 0}'),
              Text('Subscriptions: ${stats['subscriptionCount'] ?? 0}'),
              const SizedBox(height: 16),
              const Text('Connected External Relays', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (connectedRelays.isEmpty)
                const Text('No external relays connected')
              else
                ...connectedRelays.map((relay) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $relay', style: const TextStyle(fontSize: 12)),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  void _showExportKey(BuildContext context) {
    final identity = context.read<NostrProvider>().currentIdentity!;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Private Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            const Text('Keep this secret!'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                identity.privateKey,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAddressableEventCard(BuildContext context, NostrEvent event) {
    // Parse the content JSON for kind 32222 events
    Map<String, dynamic>? contentData;
    String title = 'Video Event';
    String? description;
    String? url;
    String? dTag;
    
    // Get d-tag from the event
    try {
      final dTags = event.tags.where((tag) => tag.isNotEmpty && tag[0] == 'd').toList();
      if (dTags.isNotEmpty && dTags[0].length > 1) {
        dTag = dTags[0][1];
      }
    } catch (e) {
      print('Error getting d-tag: $e');
    }
    
    try {
      contentData = json.decode(event.content);
      if (contentData != null) {
        title = contentData['title'] ?? 'Video Event';
        description = contentData['description'];
        url = contentData['url'];
      }
    } catch (e) {
      // If parsing fails, show raw content
      print('Error parsing event content: $e');
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.video_library, size: 20),
                  backgroundColor: Colors.purple.shade100,
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
                      ),
                      if (dTag != null)
                        Text(
                          'ID: $dTag',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatTimestamp(event.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (url != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        url,
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    event.pubkey.substring(0, 8) + '...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Chip(
                  label: Text('Kind ${event.kind}'),
                  labelStyle: TextStyle(fontSize: 11),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
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
}