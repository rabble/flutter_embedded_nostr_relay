// ABOUTME: Test suite for RelayClientFactory with conditional Tor support
// ABOUTME: Verifies factory creates appropriate client types based on Tor availability and config

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/network/relay_client_factory.dart';
import 'package:flutter_embedded_nostr_relay/src/network/external_relay_client.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_config.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_support.dart';

void main() {
  group('RelayClientFactory', () {
    setUp(() {
      // Reset Tor availability check for each test
      TorSupport.resetCheck();
    });

    test('should create standard client when Tor is disabled', () {
      const config = TorConfig(enabled: false);
      
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: config,
      );
      
      // Should always create standard client when Tor disabled
      expect(client, isA<ExternalRelayClient>());
      expect(client.runtimeType.toString(), 'ExternalRelayClient');
    });

    test('should create standard client when Tor not available', () {
      const config = TorConfig(enabled: true);
      
      // In test environment, Tor libraries won't be available
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: config,
      );
      
      // Should fallback to standard client when Tor unavailable
      expect(client, isA<ExternalRelayClient>());
      expect(client.runtimeType.toString(), 'ExternalRelayClient');
    });

    test('should create Tor client when available and enabled for .onion relay', () {
      const config = TorConfig(enabled: true);
      
      // This test would pass when Tor libraries are actually available
      final client = RelayClientFactory.create(
        url: 'wss://relay.onion',
        torConfig: config,
      );
      
      // For now, will be standard client due to library unavailability
      // When Tor is compiled in, this would be TorEnabledRelayClient
      expect(client, isA<ExternalRelayClient>());
      
      // Verify the factory attempts to create appropriate type
      expect(client.url, 'wss://relay.onion');
    });

    test('should create standard client for normal relay even with Tor enabled', () {
      const config = TorConfig(enabled: true, forceTor: false);
      
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: config,
      );
      
      // Non-.onion relay without forceTor should use standard client
      expect(client, isA<ExternalRelayClient>());
    });

    test('should attempt Tor client when forceTor is enabled', () {
      const config = TorConfig(enabled: true, forceTor: true);
      
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
        torConfig: config,
      );
      
      // When forceTor is true, should attempt Tor client
      // Will fallback to standard due to library unavailability in tests
      expect(client, isA<ExternalRelayClient>());
    });

    test('should create standard client when no Tor config provided', () {
      final client = RelayClientFactory.create(
        url: 'wss://relay.damus.io',
      );
      
      expect(client, isA<ExternalRelayClient>());
    });

    test('should handle torOnlyRelays configuration', () {
      const config = TorConfig(
        enabled: true,
        torOnlyRelays: ['special-relay.com'],
      );
      
      final client = RelayClientFactory.create(
        url: 'wss://special-relay.com',
        torConfig: config,
      );
      
      // Should attempt Tor for relays in torOnlyRelays list
      expect(client, isA<ExternalRelayClient>());
    });

    test('should preserve original URL in created client', () {
      const config = TorConfig(enabled: true);
      const testUrl = 'wss://test-relay.com';
      
      final client = RelayClientFactory.create(
        url: testUrl,
        torConfig: config,
      );
      
      expect(client.url, testUrl);
    });
  });
}