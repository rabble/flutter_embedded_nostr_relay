// ABOUTME: Integration tests for Tor client functionality
// ABOUTME: Tests end-to-end Tor support including configuration and graceful fallback

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_client.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_config.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_support.dart';
import 'package:flutter_embedded_nostr_relay/src/network/relay_client_factory.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_enabled_relay_client.dart';
import 'dart:io';

void main() {
  group('TorIntegration', () {
    late Directory tempDir;
    
    setUpAll(() async {
      // Create temporary directory for Tor state
      tempDir = await Directory.systemTemp.createTemp('tor_test_');
    });
    
    tearDownAll(() async {
      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    
    setUp(() {
      // Reset Tor state for each test
      TorSupport.resetCheck();
    });

    test('should handle Tor unavailable gracefully', () async {
      // In test environment, Tor libraries are not available
      expect(TorSupport.isAvailable, isFalse);
      
      // Attempting to create TorClient should fail gracefully
      final client = TorClient();
      
      expect(() async {
        await client.initialize(
          stateDir: tempDir.path,
          cacheDir: tempDir.path,
        );
      }, throwsException);
    });

    test('should create appropriate client based on availability', () {
      const config = TorConfig(enabled: true);
      
      // Regular relay with Tor enabled but unavailable
      final normalClient = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: config,
      );
      expect(normalClient, isA<ExternalRelayClient>());
      expect(normalClient.runtimeType.toString(), 'ExternalRelayClient');
      
      // .onion relay with Tor enabled but unavailable
      final onionClient = RelayClientFactory.create(
        url: 'wss://relay.onion',
        torConfig: config,
      );
      expect(onionClient, isA<ExternalRelayClient>());
    });

    test('should handle different Tor configurations', () {
      // Test various configurations
      final configs = [
        const TorConfig(enabled: false),
        const TorConfig(enabled: true, forceTor: false),
        const TorConfig(enabled: true, forceTor: true),
        const TorConfig(enabled: true, required: false),
        const TorConfig(enabled: true, torOnlyRelays: ['special.onion']),
      ];
      
      for (final config in configs) {
        expect(() {
          final client = RelayClientFactory.create(
            url: 'wss://test-relay.com',
            torConfig: config,
          );
          expect(client, isA<ExternalRelayClient>());
        }, returnsNormally);
      }
    });

    test('should preserve URLs correctly', () {
      const config = TorConfig(enabled: true);
      final testUrls = [
        'wss://relay.damus.io',
        'wss://relay.onion',
        'ws://localhost:8080',
        'wss://nostr.bitcoiner.social',
      ];
      
      for (final url in testUrls) {
        final client = RelayClientFactory.create(
          url: url,
          torConfig: config,
        );
        expect(client.url, url);
      }
    });

    test('should handle .onion relay detection', () {
      const testCases = [
        ('relay.onion', true),
        ('wss://relay.onion', true),
        ('ws://test.onion/nostr', true),
        ('relay.com', false),
        ('wss://relay.damus.io', false),
        ('ws://localhost:8080', false),
      ];
      
      for (final (url, expected) in testCases) {
        expect(TorConfig.isOnionRelay(url), expected,
            reason: 'URL: $url should ${expected ? '' : 'not '}be detected as .onion');
      }
    });

    test('should follow shouldUseTor logic correctly', () {
      // Test different configurations
      const disabledConfig = TorConfig(enabled: false);
      const basicConfig = TorConfig(enabled: true);
      const forceConfig = TorConfig(enabled: true, forceTor: true);
      const selectiveConfig = TorConfig(
        enabled: true,
        torOnlyRelays: ['special-relay.com'],
      );
      
      // Disabled config never uses Tor
      expect(disabledConfig.shouldUseTor('relay.onion'), isFalse);
      expect(disabledConfig.shouldUseTor('relay.com'), isFalse);
      
      // Basic config uses Tor for .onion only
      expect(basicConfig.shouldUseTor('relay.onion'), isTrue);
      expect(basicConfig.shouldUseTor('relay.com'), isFalse);
      
      // Force config uses Tor for everything
      expect(forceConfig.shouldUseTor('relay.onion'), isTrue);
      expect(forceConfig.shouldUseTor('relay.com'), isTrue);
      
      // Selective config uses Tor for .onion and specified relays
      expect(selectiveConfig.shouldUseTor('relay.onion'), isTrue);
      expect(selectiveConfig.shouldUseTor('special-relay.com'), isTrue);
      expect(selectiveConfig.shouldUseTor('other-relay.com'), isFalse);
    });

    test('should serialize and deserialize TorConfig correctly', () {
      const originalConfig = TorConfig(
        enabled: true,
        forceTor: false,
        required: true,
        torOnlyRelays: ['relay1.onion', 'relay2.com'],
        bridges: ['bridge1', 'bridge2'],
        timeout: Duration(minutes: 5),
      );
      
      // Serialize to JSON
      final json = originalConfig.toJson();
      
      // Deserialize back
      final deserializedConfig = TorConfig.fromJson(json);
      
      // Should be equal
      expect(deserializedConfig, equals(originalConfig));
      expect(deserializedConfig.enabled, isTrue);
      expect(deserializedConfig.forceTor, isFalse);
      expect(deserializedConfig.required, isTrue);
      expect(deserializedConfig.torOnlyRelays, ['relay1.onion', 'relay2.com']);
      expect(deserializedConfig.bridges, ['bridge1', 'bridge2']);
      expect(deserializedConfig.timeout, const Duration(minutes: 5));
    });

    test('should demonstrate complete integration workflow', () async {
      // This test demonstrates how an app would use Tor support
      
      // 1. Check if Tor is available
      final torAvailable = TorSupport.isAvailable;
      expect(torAvailable, isFalse); // In test environment
      
      // 2. Create configuration
      const torConfig = TorConfig(
        enabled: true,
        forceTor: false,
        torOnlyRelays: ['special.onion'],
        timeout: Duration(minutes: 3),
      );
      
      // 3. Create relay clients
      final clients = [
        'wss://relay.damus.io',
        'wss://special.onion',
        'wss://relay.onion',
      ].map((url) => RelayClientFactory.create(
        url: url,
        torConfig: torConfig,
      )).toList();
      
      // 4. All should be ExternalRelayClient due to Tor unavailability
      for (final client in clients) {
        expect(client, isA<ExternalRelayClient>());
      }
      
      // 5. URLs should be preserved
      expect(clients[0].url, 'wss://relay.damus.io');
      expect(clients[1].url, 'wss://special.onion');
      expect(clients[2].url, 'wss://relay.onion');
    });

    test('should handle TorEnabledRelayClient instantiation', () {
      // Direct instantiation should work
      const config = TorConfig(enabled: true);
      
      expect(() {
        final torClient = TorEnabledRelayClient(
          url: 'wss://relay.onion',
          torConfig: config,
        );
        expect(torClient, isA<TorEnabledRelayClient>());
        expect(torClient, isA<ExternalRelayClient>());
        expect(torClient.url, 'wss://relay.onion');
      }, returnsNormally);
    });
  });
}