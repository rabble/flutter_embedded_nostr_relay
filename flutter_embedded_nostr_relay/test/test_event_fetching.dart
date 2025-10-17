// ABOUTME: Test script to verify event fetching from external relays works
// ABOUTME: Tests specific event ID subscription and retrieval through embedded relay

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:logging/logging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Event fetching from external relay', () async {
    // Enable detailed logging
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      print('${record.time}: ${record.level.name}: ${record.message}');
    });

    print('\n=== Testing Event Fetching from External Relay ===\n');
  
  // Initialize embedded relay
  final relay = EmbeddedNostrRelay();
  await relay.initialize(logLevel: Level.ALL);
  print('✅ Embedded relay initialized');
  
  // Add external relay (relay3.openvine.co)
  const externalRelayUrl = 'wss://relay3.openvine.co';
  print('\n📡 Adding external relay: $externalRelayUrl');
  await relay.addExternalRelay(externalRelayUrl);
  
  // Wait a moment for connection to establish
  await Future.delayed(Duration(seconds: 2));
  
  // Test with known event IDs from trending API
  final testEventIds = [
    '017a4d67c42493bafaada95a0408e73fc17395594a7a100392371aa0aaa2eb7e',
    '062997acee619e7b2d94e5ae5bf8b6e63d2e99008a1ebb5fb91aa90e7e5e5778',
  ];
  
  print('\n🔍 Testing subscription with specific event IDs:');
  for (final id in testEventIds) {
    print('  - $id');
  }
  
  // Create filter with specific event IDs
  final filter = Filter(ids: testEventIds);
  
  // Track received events
  final receivedEvents = <NostrEvent>[];
  final completer = Completer<void>();
  bool eoseReceived = false;
  
  // Subscribe to events
  print('\n📨 Creating subscription for specific events...');
  final subscription = relay.subscribe(
    filters: [filter],
    onEvent: (event) {
      print('✅ EVENT RECEIVED: ${event.id}');
      print('   Kind: ${event.kind}');
      print('   Content preview: ${event.content.substring(0, event.content.length.clamp(0, 50))}...');
      receivedEvents.add(event);
    },
    onEose: () {
      print('📭 EOSE received - end of stored events');
      eoseReceived = true;
      // Don't complete immediately on EOSE, wait for external relay events
    },
    onError: (error) {
      print('❌ ERROR: $error');
    },
  );
  
  print('Subscription ID: ${subscription.id}');
  print('\n⏳ Waiting for events from external relay...');
  
  // Wait for up to 10 seconds for events
  Timer(Duration(seconds: 10), () {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  
  // Also listen to the subscription stream
  subscription.eventStream.listen((event) {
    print('🎯 Event from stream: ${event.id}');
  });
  
  await completer.future;
  
  // Results
  print('\n=== RESULTS ===');
  print('EOSE received: $eoseReceived');
  print('Events received: ${receivedEvents.length}');
  
  if (receivedEvents.isEmpty) {
    print('\n❌ NO EVENTS RECEIVED!');
    print('This indicates the embedded relay is not properly forwarding');
    print('REQ messages to external relays or not handling EVENT responses.');
    
    // Check relay status
    print('\n📊 Relay Status:');
    print('Connected external relays: ${relay.connectedRelays}');
    
    final stats = relay.getSubscriptionStats();
    print('Subscription stats: $stats');
  } else {
    print('\n✅ SUCCESS! Received ${receivedEvents.length} events:');
    for (final event in receivedEvents) {
      print('  - Event ${event.id}');
      print('    Kind: ${event.kind}');
      print('    Created: ${DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000)}');
    }
  }
  
  // Test direct query as well
  print('\n🔍 Testing direct query for same event IDs...');
  final queryResult = await relay.queryEvents([filter]);
  print('Direct query returned ${queryResult.length} events');
  
  // Clean up
  await subscription.close();
  await relay.shutdown();
  
    print('\n✅ Test complete\n');
  });
}