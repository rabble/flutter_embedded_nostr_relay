// ABOUTME: Main home screen with bottom navigation and timeline functionality
// ABOUTME: Provides access to timeline, messages, profile, and relay status

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/relay_provider.dart';
import '../../providers/timeline_provider.dart';
import '../../providers/messaging_provider.dart';
import 'timeline_screen.dart';
import '../messaging/conversations_screen.dart';
import '../profile/profile_screen.dart';
import '../relay_status/relay_status_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/post_composer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const TimelineScreen(),
    const ConversationsScreen(),
    const ProfileScreen(),
    const RelayStatusScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializeProviders();
  }

  Future<void> _initializeProviders() async {
    final relayProvider = context.read<RelayProvider>();
    final timelineProvider = context.read<TimelineProvider>();
    final messagingProvider = context.read<MessagingProvider>();
    final userProvider = context.read<UserProvider>();

    // Set up provider dependencies
    timelineProvider.setRelay(relayProvider.relay);
    messagingProvider.setProviders(userProvider, relayProvider);

    // Load initial data
    if (relayProvider.isInitialized) {
      await _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    final timelineProvider = context.read<TimelineProvider>();
    final messagingProvider = context.read<MessagingProvider>();

    // Load timeline and conversations
    try {
      await Future.wait([
        timelineProvider.loadTimeline(TimelineType.global),
        messagingProvider.loadConversations(),
      ]);
    } catch (e) {
      // Handle errors silently for now
      debugPrint('Error loading initial data: $e');
    }
  }

  void _showPostComposer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: PostComposer(
            scrollController: scrollController,
            onPostPublished: () {
              Navigator.of(context).pop();
              // Refresh timeline
              if (_currentIndex == 0) {
                context.read<TimelineProvider>().refreshCurrentTimeline();
              }
            },
          ),
        ),
      ),
    );
  }

  void _showSettingsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<RelayProvider>(
        builder: (context, relayProvider, child) {
          if (!relayProvider.isInitialized) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Initializing relay...'),
                ],
              ),
            );
          }

          return IndexedStack(
            index: _currentIndex,
            children: _screens,
          );
        },
      ),
      bottomNavigationBar: Consumer2<MessagingProvider, RelayProvider>(
        builder: (context, messagingProvider, relayProvider, child) {
          return NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Timeline',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: messagingProvider.totalUnreadCount > 0,
                  label: Text('${messagingProvider.totalUnreadCount}'),
                  child: const Icon(Icons.message_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: messagingProvider.totalUnreadCount > 0,
                  label: Text('${messagingProvider.totalUnreadCount}'),
                  child: const Icon(Icons.message),
                ),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outlined),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: !relayProvider.isOnline,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  child: const Icon(Icons.hub_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: !relayProvider.isOnline,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  child: const Icon(Icons.hub),
                ),
                label: 'Relay',
              ),
            ],
          );
        },
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showPostComposer,
              child: const Icon(Icons.edit),
            )
          : null,
      appBar: AppBar(
        title: Text(_getScreenTitle()),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              onPressed: () {
                context.read<TimelineProvider>().refreshCurrentTimeline();
              },
              icon: const Icon(Icons.refresh),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _showSettingsScreen();
                  break;
                case 'sign_out':
                  _showSignOutDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'sign_out',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign Out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getScreenTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Timeline';
      case 1:
        return 'Messages';
      case 2:
        return 'Profile';
      case 3:
        return 'Relay Status';
      default:
        return 'Nostr Social';
    }
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out? Your private key will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await context.read<UserProvider>().signOut();
              // The app will automatically navigate to welcome screen due to provider changes
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}