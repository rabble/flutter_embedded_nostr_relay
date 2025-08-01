// ABOUTME: Nostr filter model for querying events according to NIP-01
// ABOUTME: Supports filtering by ids, authors, kinds, tags, and time ranges

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'filter.g.dart';

@JsonSerializable(includeIfNull: false)
class Filter extends Equatable {
  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final Map<String, List<String>>? tags;
  final int? since;
  final int? until;
  final int? limit;
  
  // Custom tags support - #e, #p, #a, etc.
  @JsonKey(name: '#e')
  final List<String>? eTags;
  
  @JsonKey(name: '#p')
  final List<String>? pTags;
  
  @JsonKey(name: '#a')
  final List<String>? aTags;
  
  @JsonKey(name: '#d')
  final List<String>? dTags;

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
  });

  factory Filter.fromJson(Map<String, dynamic> json) {
    // Handle custom tag filters
    final Map<String, dynamic> processedJson = Map.from(json);
    final Map<String, List<String>> tagFilters = {};
    
    // Extract all #<single-letter> tags
    json.forEach((key, value) {
      if (key.startsWith('#') && key.length == 2) {
        if (value is List) {
          tagFilters[key] = value.cast<String>();
          processedJson.remove(key);
        }
      }
    });
    
    if (tagFilters.isNotEmpty) {
      processedJson['tags'] = tagFilters;
    }
    
    return _$FilterFromJson(processedJson);
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
    
    return json;
  }

  /// Check if an event matches this filter
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
      ];

  @override
  String toString() {
    return 'Filter(kinds: $kinds, authors: ${authors?.take(3)}, limit: $limit)';
  }
}