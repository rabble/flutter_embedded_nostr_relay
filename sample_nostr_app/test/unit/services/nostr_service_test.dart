// ABOUTME: Unit tests for NostrService that manages relay and identity
// ABOUTME: Tests service initialization, event publishing, and subscriptions

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_nostr_app/services/nostr_service.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Enable test mode for database
  setUpAll(() {
    DatabaseHelper.enableTestMode();
  });
  
  group('NostrService', () {
    late NostrService service;
    
    setUp(() {
      service = NostrService();
    });
    
    tearDown(() async {
      await service.dispose();
    });
    
    test('initializes with null identity', () {
      expect(service.currentIdentity, isNull);
      expect(service.isInitialized, isFalse);
    });
    
    test('generates new identity with valid keys', () async {
      await service.generateNewIdentity();
      
      expect(service.currentIdentity, isNotNull);
      expect(service.currentIdentity!.publicKey.length, 64);
      expect(service.currentIdentity!.privateKey.length, 64);
      expect(service.isInitialized, isTrue);
    });
    
    test('imports existing identity from private key', () async {
      // Use a test private key (all zeros for testing)
      final testPrivateKey = '0' * 64;
      
      await service.importIdentity(testPrivateKey);
      
      expect(service.currentIdentity, isNotNull);
      expect(service.currentIdentity!.privateKey, testPrivateKey);
      expect(service.isInitialized, isTrue);
    });
    
    test('publishes text note event', () async {
      await service.generateNewIdentity();
      
      final content = 'Hello Nostr!';
      final event = await service.publishTextNote(content);
      
      expect(event, isNotNull);
      expect(event.kind, 1);
      expect(event.content, content);
      expect(event.pubkey, service.currentIdentity!.publicKey);
      expect(event.sig.isNotEmpty, isTrue);
    });
    
    test('subscribes to timeline events', () async {
      await service.generateNewIdentity();
      
      final events = <NostrEvent>[];
      final subscription = service.subscribeToTimeline(
        onEvent: (event) => events.add(event),
      );
      
      expect(subscription, isNotNull);
      expect(subscription.filters.first.kinds, contains(1));
      
      // Publish an event
      await service.publishTextNote('Test event');
      
      // Wait for event propagation
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(events.isNotEmpty, isTrue);
      expect(events.first.content, 'Test event');
    });
    
    test('updates user profile', () async {
      await service.generateNewIdentity();
      
      final profile = UserProfile(
        name: 'Test User',
        about: 'Test bio',
        picture: 'https://example.com/pic.jpg',
      );
      
      final event = await service.updateProfile(profile);
      
      expect(event, isNotNull);
      expect(event.kind, 0);
      
      final content = json.decode(event.content);
      expect(content['name'], 'Test User');
      expect(content['about'], 'Test bio');
      expect(content['picture'], 'https://example.com/pic.jpg');
    });
    
    test('retrieves relay statistics', () async {
      await service.generateNewIdentity();
      
      final stats = await service.getRelayStats();
      
      expect(stats, isNotNull);
      expect(stats['eventCount'], anyOf(isA<int>(), isNull));
      expect(stats['connectionCount'], anyOf(isA<int>(), isNull));
    });
  });
}