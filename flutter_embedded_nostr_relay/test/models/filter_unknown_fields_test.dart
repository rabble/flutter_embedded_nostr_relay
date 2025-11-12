// Test for Filter preservation of unknown fields (divine extensions, future NIPs)
// Verifies that Filter.fromJson() and Filter.toJson() preserve fields not in NIP-01 spec

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';

void main() {
  group('Filter unknown field preservation', () {
    test('fromJson should preserve unknown scalar fields', () {
      final json = {
        'kinds': [34236],
        'limit': 100,
        'customField': 'customValue',
        'numericField': 42,
        'boolField': true,
      };

      final filter = Filter.fromJson(json);

      // Verify filter was created with known fields
      expect(filter.kinds, [34236]);
      expect(filter.limit, 100);

      // Verify unknown fields are preserved in toJson()
      final outputJson = filter.toJson();
      expect(outputJson['customField'], 'customValue');
      expect(outputJson['numericField'], 42);
      expect(outputJson['boolField'], true);
    });

    test('fromJson should preserve divine sort extension', () {
      final json = {
        'kinds': [34236],
        'limit': 100,
        'sort': {
          'field': 'loop_count',
          'dir': 'desc',
        },
      };

      final filter = Filter.fromJson(json);
      final outputJson = filter.toJson();

      // Verify divine sort extension is preserved
      expect(outputJson['sort'], isA<Map>());
      expect(outputJson['sort']['field'], 'loop_count');
      expect(outputJson['sort']['dir'], 'desc');
    });

    test('fromJson should preserve divine int# filters', () {
      final json = {
        'kinds': [34236],
        'limit': 100,
        'int#loop_count': {'gte': 1000},
        'int#likes': {'gte': 100, 'lte': 1000},
      };

      final filter = Filter.fromJson(json);
      final outputJson = filter.toJson();

      // Verify int# filters are preserved
      expect(outputJson['int#loop_count'], {'gte': 1000});
      expect(outputJson['int#likes'], {'gte': 100, 'lte': 1000});
    });

    test('fromJson should preserve divine cursor pagination', () {
      final json = {
        'kinds': [34236],
        'limit': 50,
        'cursor': 'cursor_token_12345',
      };

      final filter = Filter.fromJson(json);
      final outputJson = filter.toJson();

      // Verify cursor is preserved
      expect(outputJson['cursor'], 'cursor_token_12345');
    });

    test('fromJson should preserve multiple divine extensions simultaneously', () {
      final json = {
        'kinds': [34236],
        'limit': 100,
        'sort': {'field': 'loop_count', 'dir': 'desc'},
        'int#loop_count': {'gte': 1000},
        'cursor': 'page_2',
      };

      final filter = Filter.fromJson(json);
      final outputJson = filter.toJson();

      // Verify all divine extensions are preserved
      expect(outputJson['sort'], {'field': 'loop_count', 'dir': 'desc'});
      expect(outputJson['int#loop_count'], {'gte': 1000});
      expect(outputJson['cursor'], 'page_2');
    });

    test('toJson should not include unknown fields if none were provided', () {
      final filter = Filter(
        kinds: [1],
        limit: 50,
      );

      final outputJson = filter.toJson();

      // Verify only known NIP-01 fields are present
      expect(outputJson.keys, containsAll(['kinds', 'limit']));
      expect(outputJson.containsKey('sort'), false);
      expect(outputJson.containsKey('cursor'), false);
    });

    test('round-trip preserves all unknown fields exactly', () {
      final originalJson = {
        'kinds': [34236],
        'authors': ['pubkey1', 'pubkey2'],
        'limit': 100,
        'sort': {'field': 'loop_count', 'dir': 'desc'},
        'int#loop_count': {'gte': 500},
        'int#likes': {'gte': 10},
        'cursor': 'next_page_token',
        'custom_nip_99': {'data': 'future_nip'},
      };

      final filter = Filter.fromJson(originalJson);
      final roundTripJson = filter.toJson();

      // Verify all unknown fields survived round-trip
      expect(roundTripJson['sort'], originalJson['sort']);
      expect(roundTripJson['int#loop_count'], originalJson['int#loop_count']);
      expect(roundTripJson['int#likes'], originalJson['int#likes']);
      expect(roundTripJson['cursor'], originalJson['cursor']);
      expect(roundTripJson['custom_nip_99'], originalJson['custom_nip_99']);

      // Verify known fields also survived
      expect(roundTripJson['kinds'], [34236]);
      expect(roundTripJson['authors'], ['pubkey1', 'pubkey2']);
      expect(roundTripJson['limit'], 100);
    });

    test('copyWith should preserve unknown fields', () {
      final originalJson = {
        'kinds': [34236],
        'limit': 100,
        'sort': {'field': 'loop_count', 'dir': 'desc'},
        'int#loop_count': {'gte': 1000},
      };

      final filter = Filter.fromJson(originalJson);
      final copied = filter.copyWith(limit: 200);

      final copiedJson = copied.toJson();

      // Verify unknown fields survived copyWith
      expect(copiedJson['sort'], {'field': 'loop_count', 'dir': 'desc'});
      expect(copiedJson['int#loop_count'], {'gte': 1000});
      expect(copiedJson['limit'], 200); // New limit
      expect(copiedJson['kinds'], [34236]); // Original kinds
    });

    test('unknown fields do not interfere with filter matching', () {
      final json = {
        'kinds': [1],
        'authors': ['test_pubkey'],
        'sort': {'field': 'created_at', 'dir': 'desc'},
        'custom_field': 'should_not_affect_matching',
      };

      final filter = Filter.fromJson(json);

      final matchingEvent = {
        'id': 'event1',
        'pubkey': 'test_pubkey',
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Test',
        'sig': 'sig',
      };

      final nonMatchingEvent = {
        'id': 'event2',
        'pubkey': 'other_pubkey',
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Test',
        'sig': 'sig',
      };

      // Unknown fields should not affect matching logic
      expect(filter.matches(matchingEvent), true);
      expect(filter.matches(nonMatchingEvent), false);
    });

    test('should preserve unknown fields with complex nested structures', () {
      final json = {
        'kinds': [34236],
        'limit': 100,
        'sort': {
          'field': 'loop_count',
          'dir': 'desc',
          'nested': {
            'deeply': {
              'nested': 'value',
            },
          },
        },
        'complex_array': [
          {'item': 1},
          {'item': 2},
        ],
      };

      final filter = Filter.fromJson(json);
      final outputJson = filter.toJson();

      // Verify complex nested structures are preserved
      expect(outputJson['sort']['field'], 'loop_count');
      expect(outputJson['sort']['nested']['deeply']['nested'], 'value');
      expect(outputJson['complex_array'], [
        {'item': 1},
        {'item': 2},
      ]);
    });
  });
}
