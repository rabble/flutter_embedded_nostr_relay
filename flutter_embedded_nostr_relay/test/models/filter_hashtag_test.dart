// Test for Filter.matches() with hashtag filtering

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';

void main() {
  test('Filter.matches should match events with hashtag tags', () {
    final filter = Filter(
      kinds: [34236],
      tags: {
        '#t': ['lol'],
      },
    );

    final event = {
      'id': 'test_event_1',
      'pubkey': 'test_pubkey',
      'created_at': 1234567890,
      'kind': 34236,
      'tags': [
        ['t', 'lol'],
        ['t', 'funny'],
      ],
      'content': 'Test video',
      'sig': 'test_sig',
    };

    expect(filter.matches(event), true);
  });

  test('Filter.matches should NOT match events without matching hashtag', () {
    final filter = Filter(
      kinds: [34236],
      tags: {
        '#t': ['lol'],
      },
    );

    final event = {
      'id': 'test_event_2',
      'pubkey': 'test_pubkey',
      'created_at': 1234567890,
      'kind': 34236,
      'tags': [
        ['t', 'music'],
      ],
      'content': 'Test video',
      'sig': 'test_sig',
    };

    expect(filter.matches(event), false);
  });

  test('Filter.matches should match events with multiple hashtag values (OR logic)', () {
    final filter = Filter(
      kinds: [34236],
      tags: {
        '#t': ['lol', 'music'],
      },
    );

    final eventWithLol = {
      'id': 'test_event_1',
      'pubkey': 'test_pubkey',
      'created_at': 1234567890,
      'kind': 34236,
      'tags': [
        ['t', 'lol'],
      ],
      'content': 'Test video',
      'sig': 'test_sig',
    };

    final eventWithMusic = {
      'id': 'test_event_2',
      'pubkey': 'test_pubkey',
      'created_at': 1234567890,
      'kind': 34236,
      'tags': [
        ['t', 'music'],
      ],
      'content': 'Test video',
      'sig': 'test_sig',
    };

    final eventWithNeither = {
      'id': 'test_event_3',
      'pubkey': 'test_pubkey',
      'created_at': 1234567890,
      'kind': 34236,
      'tags': [
        ['t', 'funny'],
      ],
      'content': 'Test video',
      'sig': 'test_sig',
    };

    expect(filter.matches(eventWithLol), true);
    expect(filter.matches(eventWithMusic), true);
    expect(filter.matches(eventWithNeither), false);
  });
}
