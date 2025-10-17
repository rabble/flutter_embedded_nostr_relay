// ABOUTME: Main entry point for Riverpod Nostr app with StreamProvider
// ABOUTME: Demonstrates real-time event streaming from external relays

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/timeline_view.dart';
import 'screens/identity_screen.dart';
import 'providers/relay_providers.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nostr Riverpod Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    
    // If no identity, show onboarding
    if (identity == null) {
      return const IdentityScreen();
    }
    
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          TimelineView(),
          RelayStatsView(),
          ProfileView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud),
            label: 'Relays',
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class RelayStatsView extends ConsumerWidget {
  const RelayStatsView({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relayAsync = ref.watch(relayProvider);
    final statsAsync = ref.watch(relayStatsProvider);
    final externalRelaysAsync = ref.watch(externalRelaysProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay Status'),
      ),
      body: relayAsync.when(
        data: (relay) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Embedded Relay',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    statsAsync.when(
                      data: (stats) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Events: ${stats['eventCount'] ?? 0}'),
                          Text('Subscriptions: ${stats['subscriptionCount'] ?? 0}'),
                          Text('Connected Relays: ${stats['connectedRelays'] ?? 0}'),
                        ],
                      ),
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'External Relays',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    externalRelaysAsync.when(
                      data: (relays) {
                        if (relays.isEmpty) {
                          return const Text('No external relays connected');
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: relays.map((url) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, 
                                  color: Colors.green, 
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(url),
                                ),
                              ],
                            ),
                          )).toList(),
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class ProfileView extends ConsumerWidget {
  const ProfileView({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);
    
    if (identity == null) {
      return const Center(child: Text('No identity'));
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(identityProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: ListView(
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
                  const Text('Public Key', 
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    identity.publicKey,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _showPrivateKey(context, identity);
            },
            icon: const Icon(Icons.key),
            label: const Text('Show Private Key'),
          ),
        ],
      ),
    );
  }
  
  void _showPrivateKey(BuildContext context, NostrIdentity identity) {
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
              child: SelectableText(
                identity.privateKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
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
}
