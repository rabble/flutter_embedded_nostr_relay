// ABOUTME: Service layer for managing Nostr identity and relay interactions
// ABOUTME: Handles key generation, event publishing, and subscriptions

import 'dart:convert';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

class UserProfile {
  final String? name;
  final String? about;
  final String? picture;
  final String? nip05;
  final String? lud16;
  
  UserProfile({
    this.name,
    this.about,
    this.picture,
    this.nip05,
    this.lud16,
  });
  
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (about != null) json['about'] = about;
    if (picture != null) json['picture'] = picture;
    if (nip05 != null) json['nip05'] = nip05;
    if (lud16 != null) json['lud16'] = lud16;
    return json;
  }
}

class NostrIdentity {
  final String publicKey;
  final String privateKey;
  
  NostrIdentity({
    required this.publicKey,
    required this.privateKey,
  });
}

class NostrService {
  final EmbeddedNostrRelay _relay = EmbeddedNostrRelay();
  NostrIdentity? _currentIdentity;
  bool _initialized = false;
  
  NostrIdentity? get currentIdentity => _currentIdentity;
  bool get isInitialized => _initialized;
  
  Future<void> generateNewIdentity() async {
    // Generate new key pair
    final privateKey = NostrCrypto.generatePrivateKey();
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    _currentIdentity = NostrIdentity(
      publicKey: publicKey,
      privateKey: privateKey,
    );
    
    // Initialize relay
    await _relay.initialize();
    
    // Connect to popular public relays
    await _connectToDefaultRelays();
    
    _initialized = true;
  }
  
  Future<void> _connectToDefaultRelays() async {
    final defaultRelays = [
      'wss://relay3.openvine.co',
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.nostr.band',
    ];
    
    for (final relayUrl in defaultRelays) {
      try {
        await _relay.addExternalRelay(relayUrl);
      } catch (e) {
        // Continue with other relays if one fails
        print('Failed to connect to $relayUrl: $e');
      }
    }
  }
  
  Future<void> importIdentity(String privateKey) async {
    // Validate private key format
    if (privateKey.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(privateKey)) {
      throw ArgumentError('Invalid private key format');
    }
    
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    _currentIdentity = NostrIdentity(
      publicKey: publicKey,
      privateKey: privateKey,
    );
    
    // Initialize relay
    await _relay.initialize();
    
    // Connect to popular public relays
    await _connectToDefaultRelays();
    
    _initialized = true;
  }
  
  Future<NostrEvent> publishTextNote(String content) async {
    if (_currentIdentity == null) {
      throw StateError('No identity set');
    }
    
    // Create event
    final event = NostrEvent.create(
      pubkey: _currentIdentity!.publicKey,
      kind: 1, // Text note
      tags: [],
      content: content,
    );
    
    // Sign event
    final signedEvent = event.sign(_currentIdentity!.privateKey);
    
    // Publish to relay
    await _relay.publish(signedEvent);
    
    return signedEvent;
  }
  
  Subscription subscribeToTimeline({
    required Function(NostrEvent) onEvent,
    Function()? onEose,
  }) {
    final filter = Filter(
      kinds: [1], // Text notes
      limit: 100,
    );
    
    print('Subscribing to timeline with filter: kinds=${filter.kinds}, limit=${filter.limit}');
    
    return _relay.subscribe(
      filters: [filter],
      onEvent: (event) {
        print('Received event: ${event.id} - ${event.content.substring(0, event.content.length > 50 ? 50 : event.content.length)}...');
        onEvent(event);
      },
      onEose: () {
        print('EOSE - End of stored events');
        onEose?.call();
      },
    );
  }
  
  Subscription subscribeToAddressableEvents({
    required Function(NostrEvent) onEvent,
    Function()? onEose,
  }) {
    final filter = Filter(
      kinds: [32222], // Addressable video events
      limit: 100,
    );
    
    print('Subscribing to addressable events with filter: kinds=${filter.kinds}, limit=${filter.limit}');
    
    return _relay.subscribe(
      filters: [filter],
      onEvent: (event) {
        print('Received addressable event: ${event.id} - kind: ${event.kind}');
        onEvent(event);
      },
      onEose: () {
        print('EOSE - End of stored addressable events');
        onEose?.call();
      },
    );
  }
  
  Future<NostrEvent> publishAddressableEvent({
    required String dTag,
    required Map<String, dynamic> content,
  }) async {
    if (_currentIdentity == null) {
      throw StateError('No identity set');
    }
    
    // Create addressable event with d-tag
    final event = NostrEvent.create(
      pubkey: _currentIdentity!.publicKey,
      kind: 32222, // Addressable video event
      tags: [
        ['d', dTag], // d-tag makes it addressable
      ],
      content: json.encode(content),
    );
    
    // Sign event
    final signedEvent = event.sign(_currentIdentity!.privateKey);
    
    // Publish to relay
    await _relay.publish(signedEvent);
    
    return signedEvent;
  }
  
  Future<NostrEvent> updateProfile(UserProfile profile) async {
    if (_currentIdentity == null) {
      throw StateError('No identity set');
    }
    
    // Create profile event
    final event = NostrEvent.create(
      pubkey: _currentIdentity!.publicKey,
      kind: 0, // Profile metadata
      tags: [],
      content: json.encode(profile.toJson()),
    );
    
    // Sign event
    final signedEvent = event.sign(_currentIdentity!.privateKey);
    
    // Publish to relay
    await _relay.publish(signedEvent);
    
    return signedEvent;
  }
  
  Future<Map<String, int>> getRelayStats() async {
    final stats = await _relay.getStats();
    stats['connectedRelays'] = _relay.connectedRelays.length;
    return stats;
  }
  
  List<String> get connectedRelays => _relay.connectedRelays;
  
  Future<void> dispose() async {
    await _relay.shutdown();
  }
}