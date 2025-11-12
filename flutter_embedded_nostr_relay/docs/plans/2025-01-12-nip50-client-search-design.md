# NIP-50 Client-Side Search Support Design

**Date:** 2025-01-12
**Status:** Approved
**Scope:** Client-side search query support for external relays (e.g., relay.divine.video)

## Overview

Add NIP-50 search capability to the Flutter embedded Nostr relay client, allowing applications to send search queries to external relays that support full-text search. This implementation focuses on **client-side** support only - sending search queries to external relays and handling responses. Local embedded relay search support is deferred to future work.

## Problem Statement

Users report that relay.divine.video supports NIP-50 search, but our client cannot send search queries because the `Filter` model lacks the `search` field. This prevents applications from taking advantage of relay search capabilities for content discovery.

## Requirements

### Functional Requirements
1. Add `search` field to `Filter` model per NIP-50 specification
2. Serialize search field in REQ messages to external relays
3. Provide safe helper methods for constructing search queries with extensions
4. Detect relay search capability via NIP-11
5. Gracefully handle relays that don't support search
6. Maintain compatibility with existing divine.video extensions (`sort`, `int#*`, `cursor`)

### Non-Functional Requirements
1. Zero breaking changes to existing API
2. Minimal code complexity - favor simplicity over features
3. Type-safe query construction where practical
4. Comprehensive test coverage

## Design Decisions

### Approach: Simple String Field with Helper Extensions

We choose a minimal approach (string field + optional helpers) because:
- NIP-50 intentionally keeps search queries flexible and "human-readable"
- Different relays may implement different search syntaxes
- Over-engineering with structured classes creates coupling to specific relay implementations
- Helper methods can evolve based on actual usage patterns

### Components

#### 1. Filter Model Enhancement

Add optional `search` field to `Filter` class:

```dart
@JsonSerializable(includeIfNull: false)
class Filter extends Equatable {
  // ... existing fields ...

  /// NIP-50 search query string
  ///
  /// Human-readable search query with optional key:value extensions.
  /// Relays match against content field (and optionally other fields).
  /// Results ordered by relevance, not created_at.
  @JsonKey(includeIfNull: false)
  final String? search;

  const Filter({
    // ... existing parameters ...
    this.search,
  });
}
```

**Trade-offs:**
- ✅ Simple - just one optional field
- ✅ Flexible - any relay syntax works
- ✅ Compatible - json_serializable handles serialization
- ⚠️ No validation - clients can send malformed queries

#### 2. Safe Query Construction Helpers

Extension methods for common NIP-50 patterns:

```dart
// lib/src/models/filter_search_extensions.dart
extension FilterSearchHelpers on Filter {
  Filter withExtension(String key, String value) {
    // Auto-quotes values with spaces/special chars
  }

  // Convenience methods for standard NIP-50 extensions
  Filter withLanguage(String code);
  Filter withDomain(String domain);
  Filter withSentiment(String sentiment);
  Filter withNsfw(bool include);
  Filter withoutSpam();
}
```

**Key features:**
- Automatic quoting for values containing spaces, quotes, colons, backslashes
- Proper escaping of quotes and backslashes
- Non-invasive - raw string search still works

**Example usage:**
```dart
// Simple string
Filter(search: "bitcoin mining", kinds: [1])

// With helpers
Filter(search: "nostr apps")
  .withLanguage('en')
  .withDomain('example.com')
// → search: "nostr apps language:en domain:example.com"

// Auto-quoting
Filter().withExtension('title', 'deep dive')
// → search: 'title:"deep dive"'
```

#### 3. Relay Capability Detection

Enhance `ExternalRelayClient` to detect search support:

```dart
class ExternalRelayClient {
  RelayInfo? _relayInfo;
  bool? _supportsSearch;  // null=unknown, true/false=known

  Future<void> fetchRelayInfo() async {
    // Fetch NIP-11 via HTTP(S)
    // Parse supported_nips list
    // Cache result
  }

  Future<bool> sendRequest(String subscriptionId, List<Filter> filters) async {
    // Strip search if _supportsSearch == false
    // Send normally if true or unknown
  }
}
```

**Detection strategy:**
1. Fetch NIP-11 relay info on first connection
2. Check for `50` in `supported_nips` array
3. Cache result in `_supportsSearch` flag
4. If unknown, send once and learn from relay response

**Fallback behavior:**
- If relay sends OK false or NOTICE about search, mark unsupported
- Strip search field from future requests to that relay
- Log warnings for debugging

#### 4. Compatibility with Divine Extensions

The existing `_unknownFields` mechanism already preserves divine.video extensions:
- `sort`: Custom sorting (e.g., by loop_count)
- `int#*`: Integer range filters (e.g., int#loop_count: {gte: 1000})
- `cursor`: Pagination tokens

Search field works seamlessly with these:

```dart
Filter.fromJson({
  'kinds': [34236],
  'search': 'viral videos',
  'sort': {'field': 'loop_count', 'dir': 'desc'},
  'int#loop_count': {'gte': 1000},
})
// → All fields preserved in round-trip
```

## Implementation Plan

### Phase 1: Filter Model Enhancement
**Goal:** Add search field with serialization

**Tasks:**
1. Add `search` field to Filter model
2. Update constructor and copyWith
3. Ensure json_serializable includes field
4. Update equality/hashCode (handled by Equatable)

**Tests:**
- Serialization: search field in toJson()
- Deserialization: search field from fromJson()
- Null omission: search not in JSON when null
- Round-trip: search preserved with other fields
- Divine compatibility: search + sort + int#* + cursor

### Phase 2: Safe Query Helpers
**Goal:** Extension methods for building search queries

**Tasks:**
1. Create filter_search_extensions.dart
2. Implement withExtension with quoting logic
3. Add convenience methods (withLanguage, withDomain, etc.)

**Tests:**
- Quoting: spaces, quotes, backslashes, colons
- Escaping: proper \" and \\ sequences
- Concatenation: multiple extensions joined correctly
- Edge cases: empty strings, special Unicode

### Phase 3: Relay Capability Detection
**Goal:** Detect and respect relay search support

**Tasks:**
1. Add _supportsSearch flag to ExternalRelayClient
2. Implement fetchRelayInfo() for NIP-11
3. Strip search when unsupported in sendRequest()
4. Learn from OK/NOTICE responses

**Tests:**
- NIP-11 parsing: supported_nips detection
- Stripping: search removed when unsupported
- Learning: OK false triggers unsupported flag
- Logging: appropriate warnings logged

### Phase 4: Integration Testing
**Goal:** End-to-end validation

**Tasks:**
1. REQ message includes search field
2. Search coexists with kinds, limit, tags
3. Divine extensions preserved
4. Relay rejection handled gracefully

**Tests:**
- Wire format: REQ JSON structure correct
- Multi-filter: search in multiple filters
- Cursor pagination: works with search
- Error handling: relay rejection logged

## Testing Strategy

### Unit Tests

**Filter model (filter_test.dart):**
- search field serialization
- null search omission
- copyWith preserves search
- Equality with search

**Search extensions (filter_search_extensions_test.dart):**
- withExtension quoting logic
- Escape sequences for quotes/backslashes
- Convenience method behavior
- Empty/null handling

**Capability detection (external_relay_client_test.dart):**
- NIP-11 parsing
- Search stripping when unsupported
- Learning from relay responses

### Integration Tests

**End-to-end flow:**
1. Create filter with search
2. Send to external relay
3. Verify REQ message format
4. Handle EOSE/EVENT responses

**Divine compatibility:**
1. Search + sort + int# filters
2. Search + cursor pagination
3. Round-trip preservation

## Non-Goals (Out of Scope)

- **Embedded relay search**: Local SQLite full-text search deferred to future work
- **Search result ranking**: Relay responsibility, not client
- **Query validation**: Intentionally left to relays for flexibility
- **Auto-retry on search rejection**: Keep simple, just log and mark unsupported
- **Search syntax parsing**: Keep as opaque strings

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Relay-specific syntax differences | Medium | Keep string-based, let relays interpret |
| Query construction bugs (spaces, quotes) | High | Comprehensive quoting tests, safe helpers |
| Relay doesn't support search | Low | Capability detection + graceful degradation |
| Breaking changes to divine extensions | Medium | Extensive compatibility tests |

## Future Enhancements

1. **Embedded relay search support**: Add SQLite FTS5 for local search
2. **Search analytics**: Track which queries succeed/fail
3. **Query templates**: Common patterns as constants
4. **Advanced helpers**: If patterns emerge (e.g., date ranges, boolean operators)

## References

- [NIP-50 Specification](https://github.com/nostr-protocol/nips/blob/master/50.md)
- [NIP-11 Relay Information Document](https://github.com/nostr-protocol/nips/blob/master/11.md)
- Existing divine.video extensions in `filter_unknown_fields_test.dart`

## Approval

**Approved by:** Rabble
**Date:** 2025-01-12
**Implementation approach:** TDD with subagents
