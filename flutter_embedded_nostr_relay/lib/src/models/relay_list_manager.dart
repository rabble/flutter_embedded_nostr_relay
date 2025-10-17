// ABOUTME: RelayListManager implementing NIP-65 relay list management and outbox model routing
// ABOUTME: Parses kind:10002 events, caches relay lists, and provides intelligent relay selection

import '../models/nostr_event.dart';
import '../models/relay_list.dart';
import '../models/relay_metadata.dart';
import '../models/filter.dart';
import '../utils/logger.dart';

/// Manages relay lists according to NIP-65 and implements outbox model routing.
///
/// This class is responsible for:
/// - Parsing kind:10002 relay list events
/// - Caching parsed relay lists for performance
/// - Providing intelligent relay selection for queries and publishing
/// - Implementing the outbox model routing algorithm
///
/// ## Basic Usage
///
/// ```dart
/// final manager = RelayListManager();
///
/// // Parse a kind:10002 event
/// final relayList = manager.parseRelayList(event);
/// 
/// // Cache it for later use
/// manager.cacheRelayList(relayList);
///
/// // Select optimal relays for a query
/// final relays = manager.selectRelaysForQuery(
///   Filter(authors: ['user-pubkey']),
///   'user-pubkey',
/// );
///
/// // Select write relays for publishing
/// final writeRelays = manager.selectWriteRelaysForAuthor('user-pubkey');
/// ```
///
/// ## Outbox Model Implementation
///
/// The outbox model defines that:
/// - When querying events **from** a user, use their **write** relays
/// - When querying events **about** a user (mentions), use their **read** relays
/// - When publishing events, use the author's **write** relays and mentioned users' **read** relays
class RelayListManager {
  final Map<String, RelayList> _cache = {};

  /// Parse a kind:10002 event into a RelayList.
  ///
  /// Extracts relay URLs and their read/write permissions from the event tags.
  /// Each 'r' tag represents a relay with optional permissions:
  /// - ['r', 'wss://relay.com'] - both read and write (default)
  /// - ['r', 'wss://relay.com', 'read'] - read only
  /// - ['r', 'wss://relay.com', 'write'] - write only
  /// - ['r', 'wss://relay.com', 'write', '10'] - with priority
  ///
  /// Throws [ArgumentError] if the event is not kind:10002.
  RelayList parseRelayList(NostrEvent event) {
    if (event.kind != 10002) {
      throw ArgumentError('Event must be kind:10002, got ${event.kind}');
    }

    final relays = <RelayMetadata>[];

    for (final tag in event.tags) {
      if (tag.isEmpty || tag[0] != 'r') continue;
      if (tag.length < 2 || tag[1].isEmpty) continue;

      final url = tag[1];
      
      // Validate URL format before adding
      try {
        RelayMetadata.validateUrl(url);
      } catch (e) {
        RelayLogger.warning('Skipping invalid relay URL: $url - $e');
        continue;
      }

      String? permission = tag.length >= 3 ? tag[2] : null;
      int? priority;
      
      // Parse priority if present (4th element)
      if (tag.length >= 4) {
        try {
          priority = int.parse(tag[3]);
        } catch (e) {
          RelayLogger.warning('Invalid priority for relay $url: ${tag[3]}');
        }
      }
      
      bool read = true;
      bool write = true;
      
      // Parse permission marker
      if (permission != null) {
        switch (permission.toLowerCase()) {
          case 'read':
            read = true;
            write = false;
            break;
          case 'write':
            read = false;
            write = true;
            break;
          default:
            // Unknown permission, treat as read-write
            RelayLogger.warning('Unknown permission marker for relay $url: $permission');
            break;
        }
      }

      relays.add(RelayMetadata(
        url: url,
        read: read,
        write: write,
        priority: priority,
      ));
    }

    return RelayList(
      authorPubkey: event.pubkey,
      relays: relays,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
    );
  }

  /// Select optimal relays for querying events based on the filter and outbox model.
  ///
  /// For author-specific queries, selects the authors' read relays according to NIP-65.
  /// Returns relays sorted by priority (highest first).
  ///
  /// Parameters:
  /// - [filter]: The query filter to analyze
  /// - [authorHint]: Optional hint about the primary author being queried
  /// - [maxRelays]: Maximum number of relays to return (default: 5)
  List<String> selectRelaysForQuery(
    Filter filter, 
    String? authorHint, {
    int maxRelays = 5,
  }) {
    // For queries with specific authors, use their read relays
    final authors = filter.authors;
    if (authors != null && authors.isNotEmpty) {
      final selectedRelays = <String>[];
      final seenUrls = <String>{};

      for (final author in authors) {
        final relayList = _cache[author];
        if (relayList == null) continue;

        final readRelays = relayList.readRelays;
        final sortedRelays = _sortRelaysByPriority(readRelays);

        for (final relay in sortedRelays) {
          if (!seenUrls.contains(relay.url)) {
            selectedRelays.add(relay.url);
            seenUrls.add(relay.url);
          }
          
          if (selectedRelays.length >= maxRelays) break;
        }
        
        if (selectedRelays.length >= maxRelays) break;
      }

      return selectedRelays;
    }

    // For other queries, use the hint if provided
    if (authorHint != null) {
      final relayList = _cache[authorHint];
      if (relayList != null) {
        final readRelays = relayList.readRelays;
        final sortedRelays = _sortRelaysByPriority(readRelays);
        return sortedRelays
            .take(maxRelays)
            .map((relay) => relay.url)
            .toList();
      }
    }

    // No relevant relay lists found
    return [];
  }

  /// Select write relays for publishing events by a specific author.
  ///
  /// Returns the author's write relays sorted by priority (highest first).
  List<String> selectWriteRelaysForAuthor(String authorPubkey, {int maxRelays = 5}) {
    final relayList = _cache[authorPubkey];
    if (relayList == null) return [];

    final writeRelays = relayList.writeRelays;
    final sortedRelays = _sortRelaysByPriority(writeRelays);
    
    return sortedRelays
        .take(maxRelays)
        .map((relay) => relay.url)
        .toList();
  }

  /// Cache a relay list for future use.
  ///
  /// Updates existing cache entries with newer relay lists.
  void cacheRelayList(RelayList relayList) {
    final existing = _cache[relayList.authorPubkey];
    
    // Only cache if this is newer than what we have
    if (existing == null || relayList.updatedAt.isAfter(existing.updatedAt)) {
      _cache[relayList.authorPubkey] = relayList;
      RelayLogger.debug('Cached relay list for ${relayList.authorPubkey.substring(0, 8)}... (${relayList.relays.length} relays)');
    }
  }

  /// Get a cached relay list for an author.
  ///
  /// Returns null if no relay list is cached for the author.
  RelayList? getCachedRelayList(String authorPubkey) {
    return _cache[authorPubkey];
  }

  /// Clear all cached relay lists.
  void clearCache() {
    _cache.clear();
    RelayLogger.debug('Cleared relay list cache');
  }

  /// Get the number of cached relay lists.
  int get cacheSize => _cache.length;

  /// Sort relays by priority (highest first), with null priorities last.
  List<RelayMetadata> _sortRelaysByPriority(List<RelayMetadata> relays) {
    final sorted = List<RelayMetadata>.from(relays);
    sorted.sort((a, b) {
      // Put null priorities at the end
      if (a.priority == null && b.priority == null) return 0;
      if (a.priority == null) return 1;
      if (b.priority == null) return -1;
      
      // Sort by priority descending (highest first)
      return b.priority!.compareTo(a.priority!);
    });
    return sorted;
  }
}