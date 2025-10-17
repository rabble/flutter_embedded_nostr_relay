// ABOUTME: State management for user identity and key management
// ABOUTME: Handles key generation, import, profile management, and authentication

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

class UserProfile {
  final String pubkey;
  final String? name;
  final String? about;
  final String? picture;
  final String? nip05;
  final String? banner;
  final String? website;
  final List<String> relays;
  final DateTime? lastUpdated;

  const UserProfile({
    required this.pubkey,
    this.name,
    this.about,
    this.picture,
    this.nip05,
    this.banner,
    this.website,
    this.relays = const [],
    this.lastUpdated,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      pubkey: json['pubkey'],
      name: json['name'],
      about: json['about'],
      picture: json['picture'],
      nip05: json['nip05'],
      banner: json['banner'],
      website: json['website'],
      relays: List<String>.from(json['relays'] ?? []),
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pubkey': pubkey,
      'name': name,
      'about': about,
      'picture': picture,
      'nip05': nip05,
      'banner': banner,
      'website': website,
      'relays': relays,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
    };
  }

  UserProfile copyWith({
    String? name,
    String? about,
    String? picture,
    String? nip05,
    String? banner,
    String? website,
    List<String>? relays,
  }) {
    return UserProfile(
      pubkey: pubkey,
      name: name ?? this.name,
      about: about ?? this.about,
      picture: picture ?? this.picture,
      nip05: nip05 ?? this.nip05,
      banner: banner ?? this.banner,
      website: website ?? this.website,
      relays: relays ?? this.relays,
      lastUpdated: DateTime.now(),
    );
  }
}

class UserProvider extends ChangeNotifier {
  static final _logger = Logger('UserProvider');
  
  String? _privateKey;
  String? _publicKey;
  UserProfile? _profile;
  bool _isSignedIn = false;
  
  // Profile cache for other users
  final Map<String, UserProfile> _profileCache = {};
  
  // Getters
  bool get isSignedIn => _isSignedIn;
  String? get privateKey => _privateKey;
  String? get publicKey => _publicKey;
  UserProfile? get profile => _profile;
  Map<String, UserProfile> get profileCache => _profileCache;

  UserProvider() {
    _loadUserFromStorage();
  }

  /// Generate a new key pair
  Future<Map<String, String>> generateKeyPair() async {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (i) => random.nextInt(256));
    final privateKey = HEX.encode(bytes);
    
    // Generate public key from private key using NostrCrypto
    final publicKey = NostrCrypto.getPublicKey(privateKey);
    
    return {
      'privateKey': privateKey,
      'publicKey': publicKey,
    };
  }

  /// Sign in with a private key
  Future<void> signInWithPrivateKey(String privateKey) async {
    try {
      // Validate private key format
      if (privateKey.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(privateKey)) {
        throw ArgumentError('Invalid private key format');
      }
      
      final publicKey = NostrCrypto.getPublicKey(privateKey);
      
      _privateKey = privateKey.toLowerCase();
      _publicKey = publicKey;
      _isSignedIn = true;
      
      // Try to load existing profile
      await _loadProfile();
      
      // Save to storage
      await _saveUserToStorage();
      
      _logger.info('User signed in with pubkey: $publicKey');
      notifyListeners();
      
    } catch (e) {
      _logger.severe('Failed to sign in with private key', e);
      rethrow;
    }
  }

  /// Sign in with a new generated key pair
  Future<void> signInWithNewKey() async {
    final keyPair = await generateKeyPair();
    await signInWithPrivateKey(keyPair['privateKey']!);
  }

  /// Sign out
  Future<void> signOut() async {
    _privateKey = null;
    _publicKey = null;
    _profile = null;
    _isSignedIn = false;
    _profileCache.clear();
    
    // Clear from storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_private_key');
    await prefs.remove('user_profile');
    
    _logger.info('User signed out');
    notifyListeners();
  }

  /// Update user profile
  Future<void> updateProfile({
    String? name,
    String? about,
    String? picture,
    String? nip05,
    String? banner,
    String? website,
    List<String>? relays,
  }) async {
    if (!_isSignedIn || _publicKey == null || _privateKey == null) {
      throw StateError('User not signed in');
    }

    // Create or update profile
    _profile = (_profile ?? UserProfile(pubkey: _publicKey!)).copyWith(
      name: name,
      about: about,
      picture: picture,
      nip05: nip05,
      banner: banner,
      website: website,
      relays: relays,
    );

    // Create metadata event (kind 0)
    final metadata = {
      if (_profile!.name != null) 'name': _profile!.name,
      if (_profile!.about != null) 'about': _profile!.about,
      if (_profile!.picture != null) 'picture': _profile!.picture,
      if (_profile!.nip05 != null) 'nip05': _profile!.nip05,
      if (_profile!.banner != null) 'banner': _profile!.banner,
      if (_profile!.website != null) 'website': _profile!.website,
    };

    final event = NostrEvent.create(
      pubkey: _publicKey!,
      kind: 0, // Metadata
      tags: [],
      content: jsonEncode(metadata),
    ).sign(_privateKey!);

    // TODO: Publish to relay when publish method is available
    // await relayProvider.relay.publish(event);

    await _saveUserToStorage();
    
    _logger.info('Profile updated for pubkey: $_publicKey');
    notifyListeners();
  }

  /// Get profile for a specific pubkey
  Future<UserProfile?> getProfile(String pubkey) async {
    // Check cache first
    if (_profileCache.containsKey(pubkey)) {
      return _profileCache[pubkey];
    }

    // TODO: Query from relay when query method is available
    // For now, return null - this would be implemented with:
    // final events = await relay.queryEvents([
    //   Filter(kinds: [0], authors: [pubkey], limit: 1)
    // ]);
    
    return null;
  }

  /// Cache a profile
  void cacheProfile(UserProfile profile) {
    _profileCache[profile.pubkey] = profile;
    notifyListeners();
  }

  /// Sign an event
  NostrEvent signEvent(NostrEvent event) {
    if (!_isSignedIn || _privateKey == null) {
      throw StateError('User not signed in');
    }
    return event.sign(_privateKey!);
  }

  /// Create and sign a text note event
  NostrEvent createTextNote({
    required String content,
    List<List<String>>? tags,
    List<String>? replyTo,
    List<String>? mentionPubkeys,
  }) {
    if (!_isSignedIn || _publicKey == null || _privateKey == null) {
      throw StateError('User not signed in');
    }

    final eventTags = <List<String>>[];
    
    // Add reply tags
    if (replyTo != null) {
      for (final eventId in replyTo) {
        eventTags.add(['e', eventId, '', 'reply']);
      }
    }
    
    // Add mention tags
    if (mentionPubkeys != null) {
      for (final pubkey in mentionPubkeys) {
        eventTags.add(['p', pubkey]);
      }
    }
    
    // Add custom tags
    if (tags != null) {
      eventTags.addAll(tags);
    }

    return NostrEvent.create(
      pubkey: _publicKey!,
      kind: 1, // Text note
      tags: eventTags,
      content: content,
    ).sign(_privateKey!);
  }

  /// Create and sign a reaction event
  NostrEvent createReaction({
    required String eventId,
    required String eventAuthor,
    required String reaction,
  }) {
    if (!_isSignedIn || _publicKey == null || _privateKey == null) {
      throw StateError('User not signed in');
    }

    return NostrEvent.create(
      pubkey: _publicKey!,
      kind: 7, // Reaction
      tags: [
        ['e', eventId],
        ['p', eventAuthor],
      ],
      content: reaction,
    ).sign(_privateKey!);
  }

  /// Create and sign a direct message event
  NostrEvent createDirectMessage({
    required String recipientPubkey,
    required String content,
  }) {
    if (!_isSignedIn || _publicKey == null || _privateKey == null) {
      throw StateError('User not signed in');
    }

    // TODO: Implement NIP-04 encryption
    final encryptedContent = content; // Placeholder

    return NostrEvent.create(
      pubkey: _publicKey!,
      kind: 4, // Encrypted direct message
      tags: [
        ['p', recipientPubkey],
      ],
      content: encryptedContent,
    ).sign(_privateKey!);
  }

  // Private methods

  Future<void> _loadUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final privateKey = prefs.getString('user_private_key');
      
      if (privateKey != null) {
        await signInWithPrivateKey(privateKey);
      }
    } catch (e) {
      _logger.warning('Failed to load user from storage', e);
    }
  }

  Future<void> _saveUserToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_privateKey != null) {
        await prefs.setString('user_private_key', _privateKey!);
      }
      
      if (_profile != null) {
        await prefs.setString('user_profile', jsonEncode(_profile!.toJson()));
      }
    } catch (e) {
      _logger.warning('Failed to save user to storage', e);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString('user_profile');
      
      if (profileJson != null) {
        final profileData = jsonDecode(profileJson);
        _profile = UserProfile.fromJson(profileData);
      }
    } catch (e) {
      _logger.warning('Failed to load profile from storage', e);
    }
  }
}