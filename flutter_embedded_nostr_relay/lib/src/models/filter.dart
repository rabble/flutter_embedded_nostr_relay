// ABOUTME: Nostr filter model for querying events according to NIP-01
// ABOUTME: Supports filtering by ids, authors, kinds, tags, and time ranges

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'filter.g.dart';

/// Represents a Nostr filter for querying events according to NIP-01.
/// 
/// Filters are used in REQ messages to specify which events a client wants
/// to receive. Multiple filters in a single subscription work with OR logic,
/// meaning an event matches if it satisfies ANY of the filters.
/// 
/// ## Basic Usage
/// 
/// ```dart
/// // Get text notes from specific users
/// final filter = Filter(
///   kinds: [1],
///   authors: ['pubkey1', 'pubkey2'],
///   limit: 50,
/// );
/// 
/// // Get recent events mentioning me
/// final mentionsFilter = Filter(
///   pTags: [myPubkey],
///   since: DateTime.now().subtract(Duration(hours: 24))
///       .millisecondsSinceEpoch ~/ 1000,
/// );
/// 
/// final subscription = relay.subscribe(
///   filters: [filter, mentionsFilter],
///   onEvent: (event) => processEvent(event),
/// );
/// ```
/// 
/// ## Filter Criteria
/// 
/// All filter criteria use AND logic within a single filter:
/// - [ids]: Match specific event IDs
/// - [authors]: Match events from specific public keys
/// - [kinds]: Match specific event kinds
/// - [since]/[until]: Match events in time range
/// - [limit]: Maximum number of events to return
/// - Tag filters ([eTags], [pTags], etc.): Match events with specific tags
/// 
/// ## Tag Filtering
/// 
/// Common tag filters are provided as dedicated fields:
/// - [eTags]: Filter by referenced event IDs (#e tags)
/// - [pTags]: Filter by mentioned public keys (#p tags)  
/// - [aTags]: Filter by coordinate references (#a tags)
/// - [dTags]: Filter by identifier tags (#d tags)
/// 
/// For custom tags, use the [tags] map:
/// ```dart
/// final filter = Filter(
///   tags: {
///     '#t': ['bitcoin', 'nostr'],  // Topic tags
///     '#r': ['wss://relay.com'],   // Relay references
///   },
/// );
/// ```
/// 
/// ## Performance Considerations
/// 
/// - Use [limit] to avoid retrieving too many events
/// - Prefer filtering by indexed fields ([authors], [kinds]) when possible
/// - Be specific with time ranges using [since] and [until]
/// - Tag filters may be slower than other criteria
@JsonSerializable(includeIfNull: false)
class Filter extends Equatable {
  /// List of event IDs to match (exact matches only).
  /// 
  /// When specified, only events with IDs in this list will be returned.
  /// This is useful for fetching specific events by their IDs.
  final List<String>? ids;
  
  /// List of author public keys to match.
  /// 
  /// When specified, only events created by authors whose public keys
  /// are in this list will be returned. Uses OR logic between multiple authors.
  final List<String>? authors;
  
  /// List of event kinds to match.
  /// 
  /// When specified, only events with kinds in this list will be returned.
  /// Common kinds: 0 (metadata), 1 (text note), 3 (contacts), 4 (DM), etc.
  final List<int>? kinds;
  
  /// Generic tag filters using a map of tag names to value lists.
  /// 
  /// The key should include the # prefix (e.g., '#t' for topic tags).
  /// Use the dedicated tag fields ([eTags], [pTags], etc.) when available
  /// as they're more convenient.
  final Map<String, List<String>>? tags;
  
  /// Unix timestamp - only return events created at or after this time.
  /// 
  /// Used to filter events by creation date. Combine with [until] to
  /// specify a time range.
  final int? since;
  
  /// Unix timestamp - only return events created at or before this time.
  /// 
  /// Used to filter events by creation date. Combine with [since] to
  /// specify a time range.
  final int? until;
  
  /// Maximum number of events to return.
  /// 
  /// Relays should return the most recent events (highest created_at values)
  /// up to this limit. Always use a reasonable limit to avoid overwhelming
  /// clients and relays.
  final int? limit;
  
  /// Filter by events that reference other events (e-tags).
  /// 
  /// Only returns events that have an 'e' tag with a value in this list.
  /// Useful for finding replies, reactions, or other references to specific events.
  @JsonKey(name: '#e')
  final List<String>? eTags;
  
  /// Filter by events that mention users (p-tags).
  /// 
  /// Only returns events that have a 'p' tag with a pubkey in this list.
  /// Useful for finding mentions, replies, or other references to specific users.
  @JsonKey(name: '#p')
  final List<String>? pTags;
  
  /// Filter by coordinate-style references (a-tags).
  /// 
  /// Only returns events that have an 'a' tag with a value in this list.
  /// Coordinates have the format "kind:pubkey:d-tag" and are used to reference
  /// parameterized replaceable events.
  @JsonKey(name: '#a')
  final List<String>? aTags;
  
  /// Filter by identifier tags (d-tags).
  /// 
  /// Only returns events that have a 'd' tag with a value in this list.
  /// D-tags are used as identifiers for parameterized replaceable events.
  @JsonKey(name: '#d')
  final List<String>? dTags;

  /// Unknown/custom fields (e.g., divine extensions: sort, int#*, cursor)
  /// Preserved for relay vendor extensions and future NIPs
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Map<String, dynamic>? _unknownFields;

  /// Get unknown fields (for NIP-50 search, divine extensions, etc.)
  Map<String, dynamic>? get unknownFields => _unknownFields;

  const Filter({
    this.ids,
    this.authors,
    this.kinds,
    this.tags,
    this.since,
    this.until,
    this.limit,
    this.eTags,
    this.pTags,
    this.aTags,
    this.dTags,
    Map<String, dynamic>? unknownFields,
  }) : _unknownFields = unknownFields;

  factory Filter.fromJson(Map<String, dynamic> json) {
    // Handle custom tag filters
    final Map<String, dynamic> processedJson = Map.from(json);
    final Map<String, List<String>> tagFilters = {};
    final Map<String, dynamic> unknownFields = {};

    // Known NIP-01 filter fields
    const knownFields = {
      'ids', 'authors', 'kinds', 'tags', 'since', 'until', 'limit',
      '#e', '#p', '#a', '#d', 'eTags', 'pTags', 'aTags', 'dTags',
    };

    // Extract all #<single-letter> tags and collect unknown fields
    json.forEach((key, value) {
      if (key.startsWith('#') && key.length == 2) {
        if (value is List) {
          tagFilters[key] = value.cast<String>();
          processedJson.remove(key);
        }
      } else if (!knownFields.contains(key)) {
        // Preserve unknown fields (divine extensions, future NIPs)
        unknownFields[key] = value;
        processedJson.remove(key);
      }
    });

    if (tagFilters.isNotEmpty) {
      processedJson['tags'] = tagFilters;
    }

    // Create filter with unknown fields preserved
    final filter = _$FilterFromJson(processedJson);
    return Filter(
      ids: filter.ids,
      authors: filter.authors,
      kinds: filter.kinds,
      tags: filter.tags,
      since: filter.since,
      until: filter.until,
      limit: filter.limit,
      eTags: filter.eTags,
      pTags: filter.pTags,
      aTags: filter.aTags,
      dTags: filter.dTags,
      unknownFields: unknownFields.isNotEmpty ? unknownFields : null,
    );
  }

  Map<String, dynamic> toJson() {
    final json = _$FilterToJson(this);

    // Add custom tag filters back to JSON
    if (tags != null) {
      tags!.forEach((key, value) {
        json[key] = value;
      });
      json.remove('tags');
    }

    // Add unknown fields back (divine extensions, etc.)
    if (_unknownFields != null) {
      json.addAll(_unknownFields!);
    }

    return json;
  }

  /// Check if an event matches this filter.
  /// 
  /// Tests all filter criteria against the provided event using AND logic.
  /// All specified criteria must match for the method to return true.
  /// 
  /// Parameters:
  /// - [event]: Event data as a JSON map (not NostrEvent object)
  /// 
  /// Returns `true` if the event matches all filter criteria, `false` otherwise.
  /// 
  /// Example:
  /// ```dart
  /// final filter = Filter(kinds: [1], limit: 10);
  /// final eventJson = myEvent.toJson();
  /// 
  /// if (filter.matches(eventJson)) {
  ///   print('Event matches filter');
  /// }
  /// ```
  /// 
  /// Note: This method expects event data in JSON format, not a NostrEvent object.
  /// Use `event.toJson()` to convert a NostrEvent to the required format.
  bool matches(Map<String, dynamic> event) {
    // Check IDs
    if (ids != null && ids!.isNotEmpty) {
      if (!ids!.contains(event['id'])) return false;
    }
    
    // Check authors
    if (authors != null && authors!.isNotEmpty) {
      if (!authors!.contains(event['pubkey'])) return false;
    }
    
    // Check kinds
    if (kinds != null && kinds!.isNotEmpty) {
      if (!kinds!.contains(event['kind'])) return false;
    }
    
    // Check time range
    final createdAt = event['created_at'] as int?;
    if (createdAt == null) return false; // Invalid event without timestamp
    if (since != null && createdAt < since!) return false;
    if (until != null && createdAt > until!) return false;
    
    // Check tags
    if (tags != null && tags!.isNotEmpty) {
      final eventTags = event['tags'] as List<dynamic>;
      
      for (final entry in tags!.entries) {
        final tagName = entry.key.startsWith('#') ? entry.key.substring(1) : entry.key;
        final tagValues = entry.value;
        
        bool foundMatch = false;
        for (final eventTag in eventTags) {
          if (eventTag is List && 
              eventTag.isNotEmpty && 
              eventTag[0] == tagName &&
              eventTag.length > 1 &&
              tagValues.contains(eventTag[1])) {
            foundMatch = true;
            break;
          }
        }
        
        if (!foundMatch) return false;
      }
    }
    
    // Check specific tag filters
    if (eTags != null && !_matchesTags(event, 'e', eTags!)) return false;
    if (pTags != null && !_matchesTags(event, 'p', pTags!)) return false;
    if (aTags != null && !_matchesTags(event, 'a', aTags!)) return false;
    if (dTags != null && !_matchesTags(event, 'd', dTags!)) return false;
    
    return true;
  }

  bool _matchesTags(Map<String, dynamic> event, String tagName, List<String> values) {
    final eventTags = event['tags'] as List<dynamic>;
    
    // OR logic: if any filter value matches any event tag, return true
    for (final value in values) {
      for (final tag in eventTags) {
        if (tag is List && 
            tag.isNotEmpty && 
            tag[0] == tagName &&
            tag.length > 1 &&
            tag[1] == value) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// Create a copy with updated fields
  Filter copyWith({
    List<String>? ids,
    List<String>? authors,
    List<int>? kinds,
    Map<String, List<String>>? tags,
    int? since,
    int? until,
    int? limit,
    List<String>? eTags,
    List<String>? pTags,
    List<String>? aTags,
    List<String>? dTags,
    Map<String, dynamic>? unknownFields,
  }) {
    return Filter(
      ids: ids ?? this.ids,
      authors: authors ?? this.authors,
      kinds: kinds ?? this.kinds,
      tags: tags ?? this.tags,
      since: since ?? this.since,
      until: until ?? this.until,
      limit: limit ?? this.limit,
      eTags: eTags ?? this.eTags,
      pTags: pTags ?? this.pTags,
      aTags: aTags ?? this.aTags,
      dTags: dTags ?? this.dTags,
      unknownFields: unknownFields ?? this._unknownFields,
    );
  }

  @override
  List<Object?> get props => [
        ids,
        authors,
        kinds,
        tags,
        since,
        until,
        limit,
        eTags,
        pTags,
        aTags,
        dTags,
        _unknownFields,
      ];

  @override
  String toString() {
    return 'Filter(kinds: $kinds, authors: ${authors?.take(3)}, limit: $limit)';
  }
}