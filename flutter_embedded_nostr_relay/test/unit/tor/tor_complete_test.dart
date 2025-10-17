// ABOUTME: Complete test suite for all Tor functionality without Flutter dependencies
// ABOUTME: Tests the complete Tor integration including factory, config, and support

import 'package:test/test.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_config.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_support.dart';
import 'package:flutter_embedded_nostr_relay/src/network/relay_client_factory.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_enabled_relay_client.dart';

void main() {
  group('TorCompleteIntegration', () {
    setUp(() {
      TorSupport.resetCheck();
    });

    test('should handle complete Tor workflow', () {
      // 1. Feature detection
      expect(TorSupport.isAvailable, isFalse); // In test environment
      expect(TorSupport.libraryPath, isNotEmpty);
      
      // 2. Configuration
      const config = TorConfig(
        enabled: true,
        forceTor: false,
        torOnlyRelays: ['special.onion'],
        bridges: ['bridge1', 'bridge2'],
        timeout: Duration(minutes: 3),
      );
      
      // 3. Serialization/deserialization
      final json = config.toJson();
      final roundTrip = TorConfig.fromJson(json);
      expect(roundTrip, equals(config));
      
      // 4. Relay detection logic
      expect(config.shouldUseTor('relay.onion'), isTrue);
      expect(config.shouldUseTor('special.onion'), isTrue);
      expect(config.shouldUseTor('other.com'), isFalse);
      
      // 5. Client factory
      final clients = [
        'wss://relay.damus.io',
        'wss://special.onion',
        'wss://relay.onion',
      ].map((url) => RelayClientFactory.create(
        url: url,
        torConfig: config,
      )).toList();
      
      // All should be ExternalRelayClient due to Tor unavailability
      for (final client in clients) {
        expect(client, isA<ExternalRelayClient>());
      }
    });

    test('should demonstrate graceful degradation', () {
      // When Tor is not available, everything should still work
      expect(TorSupport.isAvailable, isFalse);
      
      // Force Tor configuration
      const forceConfig = TorConfig(enabled: true, forceTor: true);
      
      // Even with forceTor, should fallback gracefully
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: forceConfig,
      );
      
      expect(client, isA<ExternalRelayClient>());
      expect(client.url, 'wss://relay.damus.io');
    });

    test('should handle all configuration options', () {
      final configs = [
        const TorConfig(), // Default
        const TorConfig(enabled: false),
        const TorConfig(enabled: true),
        const TorConfig(enabled: true, forceTor: true),
        const TorConfig(enabled: true, required: true),
        const TorConfig(
          enabled: true,
          forceTor: false,
          required: false,
          torOnlyRelays: ['relay1.onion', 'relay2.com'],
          bridges: ['bridge1', 'bridge2'],
          timeout: Duration(minutes: 5),
        ),
      ];
      
      for (final config in configs) {
        expect(() {
          final client = RelayClientFactory.create(
            url: 'wss://test.com',
            torConfig: config,
          );
          expect(client, isA<ExternalRelayClient>());
        }, returnsNormally);
      }
    });

    test('should validate onion detection correctly', () {
      final testCases = [
        ('relay.onion', true),
        ('wss://relay.onion', true),
        ('ws://test.onion/path', true),
        ('relay.com', false),
        ('relay.onion.com', false), // Not actually .onion
        ('fake-onion.com', false),
        ('wss://normal-relay.io', false),
      ];
      
      for (final (url, shouldBeOnion) in testCases) {
        expect(TorConfig.isOnionRelay(url), shouldBeOnion,
            reason: 'URL $url detection failed');
      }
    });

    test('should handle TorEnabledRelayClient creation', () {
      const config = TorConfig(enabled: true);
      
      // Direct creation should work
      final torClient = TorEnabledRelayClient(
        url: 'wss://relay.onion',
        torConfig: config,
      );
      
      expect(torClient, isA<TorEnabledRelayClient>());
      expect(torClient, isA<ExternalRelayClient>());
      expect(torClient.url, 'wss://relay.onion');
    });

    test('should demonstrate conditional compilation pattern', () {
      // This shows how the conditional import system works
      const config = TorConfig(enabled: true);
      
      // Factory uses conditional imports
      final standardClient = RelayClientFactory.create(
        url: 'wss://relay.com',
        torConfig: config,
      );
      
      final onionClient = RelayClientFactory.create(
        url: 'wss://relay.onion',
        torConfig: config,
      );
      
      // In test environment without Tor libraries, both are standard clients
      expect(standardClient, isA<ExternalRelayClient>());
      expect(onionClient, isA<ExternalRelayClient>());
      
      // But URLs are preserved
      expect(standardClient.url, 'wss://relay.com');
      expect(onionClient.url, 'wss://relay.onion');
    });

    test('should handle complex configuration scenarios', () {
      // Scenario 1: Privacy-conscious user
      const privacyConfig = TorConfig(
        enabled: true,
        forceTor: true,
        torOnlyRelays: [],
        bridges: ['obfs4 192.168.1.1:443'],
        timeout: Duration(minutes: 5),
      );
      
      // All relays should use Tor when forceTor is true
      expect(privacyConfig.shouldUseTor('wss://relay.damus.io'), isTrue);
      expect(privacyConfig.shouldUseTor('wss://relay.onion'), isTrue);
      
      // Scenario 2: Selective Tor usage
      const selectiveConfig = TorConfig(
        enabled: true,
        forceTor: false,
        torOnlyRelays: ['censored-relay.com', 'private.io'],
      );
      
      expect(selectiveConfig.shouldUseTor('wss://relay.onion'), isTrue);
      expect(selectiveConfig.shouldUseTor('wss://censored-relay.com'), isTrue);
      expect(selectiveConfig.shouldUseTor('wss://public-relay.io'), isFalse);
      
      // Scenario 3: Tor disabled
      const disabledConfig = TorConfig(enabled: false);
      
      expect(disabledConfig.shouldUseTor('wss://relay.onion'), isFalse);
      expect(disabledConfig.shouldUseTor('wss://any-relay.com'), isFalse);
    });

    test('should maintain consistency across reloads', () {
      // Feature detection should be consistent
      final firstCheck = TorSupport.isAvailable;
      final secondCheck = TorSupport.isAvailable;
      expect(firstCheck, equals(secondCheck));
      
      // Platform library paths should be consistent
      final firstPath = TorSupport.libraryPath;
      final secondPath = TorSupport.libraryPath;
      expect(firstPath, equals(secondPath));
    });
  });
}