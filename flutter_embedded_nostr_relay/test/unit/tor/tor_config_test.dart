// ABOUTME: Test suite for Tor configuration model and validation
// ABOUTME: Verifies Tor configuration options and serialization behavior

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/tor/tor_config.dart';

void main() {
  group('TorConfig', () {
    test('should create with default values', () {
      const config = TorConfig();
      
      expect(config.enabled, isFalse);
      expect(config.forceTor, isFalse);
      expect(config.required, isFalse);
      expect(config.torOnlyRelays, isEmpty);
      expect(config.bridges, isEmpty);
      expect(config.timeout, const Duration(minutes: 2));
    });

    test('should create with custom values', () {
      const config = TorConfig(
        enabled: true,
        forceTor: true,
        required: true,
        torOnlyRelays: ['relay1.onion', 'relay2.onion'],
        bridges: ['bridge1', 'bridge2'],
        timeout: Duration(minutes: 5),
      );
      
      expect(config.enabled, isTrue);
      expect(config.forceTor, isTrue);
      expect(config.required, isTrue);
      expect(config.torOnlyRelays, ['relay1.onion', 'relay2.onion']);
      expect(config.bridges, ['bridge1', 'bridge2']);
      expect(config.timeout, const Duration(minutes: 5));
    });

    test('should serialize to JSON', () {
      const config = TorConfig(
        enabled: true,
        forceTor: false,
        torOnlyRelays: ['relay.onion'],
        bridges: ['bridge'],
        timeout: Duration(minutes: 3),
      );
      
      final json = config.toJson();
      
      expect(json['enabled'], isTrue);
      expect(json['forceTor'], isFalse);
      expect(json['required'], isFalse);
      expect(json['torOnlyRelays'], ['relay.onion']);
      expect(json['bridges'], ['bridge']);
      expect(json['timeoutMinutes'], 3);
    });

    test('should deserialize from JSON', () {
      final json = {
        'enabled': true,
        'forceTor': true,
        'required': false,
        'torOnlyRelays': ['relay1.onion', 'relay2.onion'],
        'bridges': ['bridge1'],
        'timeoutMinutes': 5,
      };
      
      final config = TorConfig.fromJson(json);
      
      expect(config.enabled, isTrue);
      expect(config.forceTor, isTrue);
      expect(config.required, isFalse);
      expect(config.torOnlyRelays, ['relay1.onion', 'relay2.onion']);
      expect(config.bridges, ['bridge1']);
      expect(config.timeout, const Duration(minutes: 5));
    });

    test('should support equality comparison', () {
      const config1 = TorConfig(enabled: true, forceTor: false);
      const config2 = TorConfig(enabled: true, forceTor: false);
      const config3 = TorConfig(enabled: false, forceTor: false);
      
      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
    });

    test('should validate onion relay URLs', () {
      expect(TorConfig.isOnionRelay('relay.onion'), isTrue);
      expect(TorConfig.isOnionRelay('wss://relay.onion'), isTrue);
      expect(TorConfig.isOnionRelay('relay.com'), isFalse);
      expect(TorConfig.isOnionRelay('wss://relay.com'), isFalse);
    });

    test('should determine if relay should use Tor', () {
      const config = TorConfig(
        enabled: true,
        forceTor: false,
        torOnlyRelays: ['specific.onion'],
      );
      
      // .onion relays always use Tor
      expect(config.shouldUseTor('relay.onion'), isTrue);
      expect(config.shouldUseTor('wss://relay.onion'), isTrue);
      
      // Specific relays in torOnlyRelays list
      expect(config.shouldUseTor('specific.onion'), isTrue);
      expect(config.shouldUseTor('wss://specific.onion'), isTrue);
      
      // Regular relays don't use Tor by default
      expect(config.shouldUseTor('relay.com'), isFalse);
      
      // Unless forceTor is enabled
      const forceConfig = TorConfig(enabled: true, forceTor: true);
      expect(forceConfig.shouldUseTor('relay.com'), isTrue);
    });

    test('should handle disabled Tor config', () {
      const config = TorConfig(enabled: false);
      
      // Disabled config never uses Tor, even for .onion
      expect(config.shouldUseTor('relay.onion'), isFalse);
      expect(config.shouldUseTor('relay.com'), isFalse);
    });
  });
}