// ABOUTME: Profile provider that manages user data fetching from local and remote sources
// ABOUTME: Combines cached data with fresh content from external relays for complete profiles

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'relay_providers.dart';
import 'dart:convert';
import 'dart:async';

// Profile data provider that manages all profile-related data
final profileDataProvider = Provider.family<ProfileData, String>((ref, pubkey) {
  return ProfileData(ref, pubkey);
});

// Provider for user metadata (kind 0)
final profileMetadataProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, pubkey) async* {
  final relay = await ref.watch(relayProvider.future);
  
  // Subscribe to metadata events
  final filter = Filter(
    kinds: [0],
    authors: [pubkey],
    limit: 1,
  );
  
  // First, get cached data
  final cached = await relay.queryEvents([filter]);
  if (cached.isNotEmpty) {
    final latest = cached.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    try {
      yield json.decode(latest.content) as Map<String, dynamic>;
    } catch (e) {
      yield null;
    }
  }
  
  // Then subscribe for updates
  final controller = StreamController<Map<String, dynamic>?>();
  
  relay.subscribe(
    filters: [filter], 
    onEvent: (event) {
      try {
        controller.add(json.decode(event.content) as Map<String, dynamic>);
      } catch (e) {
        // Invalid JSON, ignore
      }
    },
  );
  
  yield* controller.stream;
});

// Provider for user's vines (kind 32222)
final userVinesProvider = StreamProvider.family<List<NostrEvent>, String>((ref, pubkey) async* {
  final relay = await ref.watch(relayProvider.future);
  
  final filter = Filter(
    kinds: [32222],
    authors: [pubkey],
    limit: 50,
  );
  
  // Get cached vines first
  final cached = await relay.queryEvents([filter]);
  yield cached..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  
  // Subscribe for new vines
  final vines = List<NostrEvent>.from(cached);
  final controller = StreamController<List<NostrEvent>>();
  
  relay.subscribe(
    filters: [filter],
    onEvent: (event) {
      // Add new vine if not already in list
      if (!vines.any((v) => v.id == event.id)) {
        vines.add(event);
        vines.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(List<NostrEvent>.from(vines));
      }
    },
  );
  
  yield* controller.stream;
});

// Provider for user's reactions (kind 7)
final userReactionsProvider = StreamProvider.family<List<NostrEvent>, String>((ref, pubkey) async* {
  final relay = await ref.watch(relayProvider.future);
  
  final filter = Filter(
    kinds: [7],
    authors: [pubkey],
    limit: 100,
  );
  
  // Get cached reactions
  final cached = await relay.queryEvents([filter]);
  yield cached..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  
  // Subscribe for new reactions
  final reactions = List<NostrEvent>.from(cached);
  final controller = StreamController<List<NostrEvent>>();
  
  relay.subscribe(
    filters: [filter],
    onEvent: (event) {
      if (!reactions.any((r) => r.id == event.id)) {
        reactions.add(event);
        reactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(List<NostrEvent>.from(reactions));
      }
    },
  );
  
  yield* controller.stream;
});

// Provider for user's reposts (kind 6)
final userRepostsProvider = StreamProvider.family<List<NostrEvent>, String>((ref, pubkey) async* {
  final relay = await ref.watch(relayProvider.future);
  
  final filter = Filter(
    kinds: [6],
    authors: [pubkey],
    limit: 100,
  );
  
  // Get cached reposts
  final cached = await relay.queryEvents([filter]);
  yield cached..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  
  // Subscribe for new reposts
  final reposts = List<NostrEvent>.from(cached);
  final controller = StreamController<List<NostrEvent>>();
  
  relay.subscribe(
    filters: [filter],
    onEvent: (event) {
      if (!reposts.any((r) => r.id == event.id)) {
        reposts.add(event);
        reposts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(List<NostrEvent>.from(reposts));
      }
    },
  );
  
  yield* controller.stream;
});

// Provider for user's lists (kind 30000-30009)
final userListsProvider = StreamProvider.family<List<NostrEvent>, String>((ref, pubkey) async* {
  final relay = await ref.watch(relayProvider.future);
  
  final filter = Filter(
    kinds: List.generate(10, (i) => 30000 + i), // 30000-30009
    authors: [pubkey],
    limit: 50,
  );
  
  // Get cached lists
  final cached = await relay.queryEvents([filter]);
  yield cached..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  
  // Subscribe for list updates
  final lists = List<NostrEvent>.from(cached);
  final controller = StreamController<List<NostrEvent>>();
  
  relay.subscribe(
    filters: [filter],
    onEvent: (event) {
      // For lists, replace existing ones with same d tag
      final dTag = event.tags.firstWhere(
        (tag) => tag.isNotEmpty && tag[0] == 'd',
        orElse: () => [],
      );
      
      if (dTag.isNotEmpty && dTag.length > 1) {
        // Remove old version of this list
        lists.removeWhere((list) {
          final listDTag = list.tags.firstWhere(
            (tag) => tag.isNotEmpty && tag[0] == 'd',
            orElse: () => [],
          );
          return listDTag.length > 1 && listDTag[1] == dTag[1];
        });
      }
      
      lists.add(event);
      lists.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(List<NostrEvent>.from(lists));
    },
  );
  
  yield* controller.stream;
});

// Helper class to manage profile data
class ProfileData {
  final Ref ref;
  final String pubkey;
  
  ProfileData(this.ref, this.pubkey);
  
  // Request fresh data from external relays
  Future<void> refreshFromExternalRelays() async {
    final relay = await ref.read(relayProvider.future);
    
    // Create filters for all profile data
    final filters = [
      Filter(kinds: [0], authors: [pubkey], limit: 1), // Metadata
      Filter(kinds: [32222], authors: [pubkey], limit: 50), // Vines
      Filter(kinds: [7], authors: [pubkey], limit: 100), // Reactions
      Filter(kinds: [6], authors: [pubkey], limit: 100), // Reposts
      Filter(kinds: List.generate(10, (i) => 30000 + i), authors: [pubkey], limit: 50), // Lists
    ];
    
    // Request from external relays
    // The embedded relay will automatically fetch from external relays
    // and store the results locally
    for (final filter in filters) {
      relay.subscribe(
        filters: [filter],
        onEvent: (_) {}, // Just trigger fetching
      );
    }
  }
  
  // Get hashtags used by this user in their vines
  Future<Set<String>> getUserHashtags() async {
    final vines = await ref.read(userVinesProvider(pubkey).future);
    final hashtags = <String>{};
    
    for (final vine in vines) {
      for (final tag in vine.tags) {
        if (tag.isNotEmpty && tag[0] == 't' && tag.length > 1) {
          hashtags.add(tag[1]);
        }
      }
    }
    
    return hashtags;
  }
}