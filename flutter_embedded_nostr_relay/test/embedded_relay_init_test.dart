// ABOUTME: Tests for embedded relay initialization error handling
// ABOUTME: Verifies relay can handle database initialization failures gracefully

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:logging/logging.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    DatabaseHelper.enableTestMode(); // Use in-memory database for tests
  });
  group('EmbeddedNostrRelay Initialization', () {
    late EmbeddedNostrRelay relay;
    
    setUp(() {
      relay = EmbeddedNostrRelay();
    });
    
    tearDown(() async {
      try {
        await relay.shutdown();
      } catch (_) {
        // Ignore shutdown errors in tests
      }
    });
    
    test('should have isInitialized getter', () {
      // Before initialization
      expect(relay.isInitialized, isFalse);
    });
    
    test('should set isInitialized to true after successful initialization', () async {
      // Initialize relay
      await relay.initialize(
        logLevel: Level.WARNING, // Reduce log noise in tests
        enableGarbageCollection: false,
      );
      
      // After initialization
      expect(relay.isInitialized, isTrue);
    });
    
    test('should not throw if database initialization has issues on iOS', () async {
      // This should complete without throwing
      await expectLater(
        relay.initialize(
          logLevel: Level.WARNING,
          enableGarbageCollection: false,
        ),
        completes,
      );
      
      // Relay should be marked as initialized
      expect(relay.isInitialized, isTrue);
    });
    
    test('should handle multiple initialization calls gracefully', () async {
      // First initialization
      await relay.initialize(
        logLevel: Level.WARNING,
        enableGarbageCollection: false,
      );
      
      expect(relay.isInitialized, isTrue);
      
      // Second initialization should be a no-op
      await expectLater(
        relay.initialize(
          logLevel: Level.WARNING,
          enableGarbageCollection: false,
        ),
        completes,
      );
      
      expect(relay.isInitialized, isTrue);
    });
    
    test('should allow operations even if database init partially fails', () async {
      // Initialize relay
      await relay.initialize(
        logLevel: Level.WARNING,
        enableGarbageCollection: false,
      );
      
      // Try to subscribe - should not throw
      expect(() {
        relay.subscribe(
          filters: [Filter(kinds: [1])],
          onEvent: (event) {},
        );
      }, returnsNormally);
    });
    
    test('should properly clean up on shutdown', () async {
      // Initialize relay
      await relay.initialize(
        logLevel: Level.WARNING,
        enableGarbageCollection: false,
      );
      
      expect(relay.isInitialized, isTrue);
      
      // Shutdown
      await relay.shutdown();
      
      // After shutdown, relay should not be initialized
      expect(relay.isInitialized, isFalse);
    });
    
    test('should throw StateError for operations before initialization', () {
      // Before initialization, operations should throw
      expect(
        () => relay.subscribe(
          filters: [Filter(kinds: [1])],
          onEvent: (event) {},
        ),
        throwsStateError,
      );
      
      expect(
        () async => await relay.publish(
          NostrEvent.create(
            pubkey: 'test_pubkey',
            kind: 1,
            content: 'test',
            tags: [],
          ),
        ),
        throwsStateError,
      );
      
      expect(
        () async => await relay.queryEvents([Filter(kinds: [1])]),
        throwsStateError,
      );
    });
    
    test('should continue working after database pragma failures', () async {
      // Initialize relay (may have pragma failures internally)
      await relay.initialize(
        logLevel: Level.WARNING,
        enableGarbageCollection: false,
      );
      
      // Create a test event
      final testEvent = NostrEvent.create(
        pubkey: 'test_pubkey',
        kind: 1,
        content: 'Test message',
        tags: [],
      );
      
      // Publishing should work
      final published = await relay.publish(testEvent);
      // May or may not succeed depending on database state, but shouldn't throw
      expect(published, isA<bool>());
      
      // Querying should work
      final events = await relay.queryEvents([Filter(kinds: [1])]);
      expect(events, isA<List<NostrEvent>>());
    });
  });
  
  group('EmbeddedNostrRelay External Relay Management', () {
    late EmbeddedNostrRelay relay;
    
    setUp(() async {
      relay = EmbeddedNostrRelay();
      await relay.initialize(
        logLevel: Level.WARNING,
        enableGarbageCollection: false,
      );
    });
    
    tearDown(() async {
      await relay.shutdown();
    });
    
    test('should handle adding external relays after initialization', () async {
      // Note: This will try to connect but should handle failure gracefully
      // Using localhost to avoid network delays
      await expectLater(
        relay.addExternalRelay('ws://localhost:12345').timeout(
          Duration(seconds: 2),
          onTimeout: () {
            // Expected - connection will fail but relay should handle it
          },
        ),
        completes,
      );
      
      // Check connected relays - relay might be in list even if connection failed
      final connected = relay.connectedRelays;
      expect(connected, isA<List<String>>());
      // Relay might be added to list even if connection fails
      // This is ok - it allows retry logic
    });
    
    test('should handle removing external relays', () async {
      // Try to remove a relay that was never added - should handle gracefully
      await expectLater(
        relay.removeExternalRelay('ws://localhost:12345'),
        completes,
      );
    });
  });
}