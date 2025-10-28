// ABOUTME: Nostr event model implementing NIP-01 event structure
// ABOUTME: Handles event creation, validation, serialization and signature verification

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import '../utils/crypto.dart';

part 'nostr_event.g.dart';

/// Represents a Nostr event according to NIP-01.
/// 
/// A NostrEvent is the fundamental data structure in the Nostr protocol.
/// Every event contains an ID, public key of the author, timestamp, kind,
/// tags, content, and cryptographic signature.
/// 
/// ## Event Types
/// 
/// Events are categorized by their `kind` field:
/// - `0`: Metadata (user profiles)
/// - `1`: Text notes (tweets/posts)
/// - `2`: Recommend relay
/// - `3`: Contacts (following list)
/// - `4`: Encrypted direct messages
/// - `5`: Event deletion
/// - `6`: Reposts
/// - `7`: Reactions
/// - `10000-19999`: Replaceable events
/// - `20000-29999`: Ephemeral events (not stored)
/// - `30000-39999`: Parameterized replaceable events
/// 
/// ## Creating Events
/// 
/// ```dart
/// // Create an unsigned event
/// final event = NostrEvent.create(
///   pubkey: userPublicKey,
///   kind: 1,
///   content: 'Hello, Nostr!',
///   tags: [
///     ['t', 'hello'],        // Topic tag
///     ['p', friendPubkey],   // Mention a user
///   ],
/// );
/// 
/// // Sign the event
/// final signedEvent = event.sign(userPrivateKey);
/// 
/// // Verify the event
/// print(signedEvent.isValid); // true
/// ```
/// 
/// ## Event Validation
/// 
/// Events are automatically validated when created and can be verified:
/// - ID must match SHA256 hash of serialized event data
/// - Signature must be valid for the event ID and public key
/// - All required fields must be present
/// 
/// ## Replaceable Events
/// 
/// Some event kinds are replaceable, meaning newer events from the same
/// author replace older ones:
/// 
/// ```dart
/// if (event.isReplaceable) {
///   print('This event can be replaced by newer versions');
/// }
/// 
/// if (event.isParameterizedReplaceable) {
///   print('D-tag: ${event.dTagValue}');
/// }
/// ```
/// 
/// ## Tags and References
/// 
/// Events can reference other events and users through tags:
/// 
/// ```dart
/// // Get all mentioned users
/// final mentionedUsers = event.mentionedPubkeys;
/// 
/// // Get all referenced events
/// final referencedEvents = event.referencedEventIds;
/// 
/// // Check if event mentions a specific user
/// if (event.mentions(userPubkey)) {
///   print('This event mentions you!');
/// }
/// ```
@JsonSerializable()
class NostrEvent extends Equatable {
  /// Unique identifier for this event (32-byte lowercase hex).
  /// 
  /// The ID is calculated as the SHA256 hash of the serialized event data
  /// according to NIP-01. This ensures events cannot be tampered with
  /// without invalidating the ID.
  final String id;
  
  /// Public key of the event author (32-byte lowercase hex).
  /// 
  /// This identifies who created and signed the event. The corresponding
  /// private key must be used to generate a valid signature.
  final String pubkey;
  
  /// Unix timestamp when the event was created (seconds since epoch).
  /// 
  /// This should represent when the event was actually created by the author,
  /// not when it was received by the relay.
  @JsonKey(name: 'created_at')
  final int createdAt;
  
  /// Event kind determining the event type and how it should be interpreted.
  /// 
  /// Common kinds:
  /// - 0: Metadata/profile
  /// - 1: Text note
  /// - 3: Contact list
  /// - 4: Encrypted DM
  /// - 5: Deletion request
  /// - 6: Repost
  /// - 7: Reaction
  final int kind;
  
  /// Array of tags providing additional event metadata.
  /// 
  /// Each tag is an array of strings where the first element is the tag name:
  /// - ['e', eventId]: References another event
  /// - ['p', pubkey]: References/mentions a user
  /// - ['t', topic]: Topic/hashtag
  /// - ['d', identifier]: Identifier for parameterized replaceable events
  final List<List<String>> tags;
  
  /// The main content of the event.
  /// 
  /// For text notes this is the message text. For other event types this
  /// might be JSON data or empty. The interpretation depends on the event kind.
  final String content;
  
  /// Schnorr signature of the event ID (64-byte lowercase hex).
  /// 
  /// This proves the event was created by the holder of the private key
  /// corresponding to the public key. The signature covers the event ID.
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) =>
      _$NostrEventFromJson(json);

  Map<String, dynamic> toJson() => _$NostrEventToJson(this);

  /// Create a new unsigned event.
  /// 
  /// This factory constructor creates an event with a calculated ID but no
  /// signature. The event must be signed with [sign] before it can be published.
  /// 
  /// The event ID is calculated according to NIP-01 by hashing the serialized
  /// event data: `[0, pubkey, created_at, kind, tags, content]`.
  /// 
  /// Parameters:
  /// - [pubkey]: Author's public key (32-byte hex string)
  /// - [kind]: Event type (see class documentation for common kinds)
  /// - [tags]: Array of tag arrays for metadata
  /// - [content]: Main event content
  /// - [createdAt]: Unix timestamp (defaults to current time)
  /// 
  /// Example:
  /// ```dart
  /// final event = NostrEvent.create(
  ///   pubkey: '1234567890abcdef...',
  ///   kind: 1,
  ///   content: 'Hello, world!',
  ///   tags: [['t', 'greeting']],
  /// );
  /// 
  /// final signedEvent = event.sign(privateKey);
  /// ```
  factory NostrEvent.create({
    required String pubkey,
    required int kind,
    required List<List<String>> tags,
    required String content,
    int? createdAt,
  }) {
    final timestamp = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Calculate event ID according to NIP-01
    final eventData = [
      0, // version
      pubkey,
      timestamp,
      kind,
      tags,
      content,
    ];
    
    final serialized = json.encode(eventData);
    final id = NostrCrypto.sha256(serialized);
    
    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: timestamp,
      kind: kind,
      tags: tags,
      content: content,
      sig: '', // Will be signed later
    );
  }

  /// Sign this event with the given private key.
  /// 
  /// Creates a new [NostrEvent] instance with a valid signature. The signature
  /// is generated using the Schnorr signature algorithm over the event ID.
  /// 
  /// Parameters:
  /// - [privateKey]: The private key corresponding to the event's pubkey (32-byte hex)
  /// 
  /// Returns a new [NostrEvent] with the same data but with a valid signature.
  /// 
  /// Example:
  /// ```dart
  /// final unsignedEvent = NostrEvent.create(
  ///   pubkey: myPubkey,
  ///   kind: 1,
  ///   content: 'Hello!',
  ///   tags: [],
  /// );
  /// 
  /// final signedEvent = unsignedEvent.sign(myPrivateKey);
  /// print(signedEvent.isValid); // true
  /// ```
  NostrEvent sign(String privateKey) {
    final signature = NostrCrypto.signEvent(this, privateKey);
    return NostrEvent(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: signature,
    );
  }

  /// Verify that this event has a valid ID and signature.
  /// 
  /// Performs two checks:
  /// 1. Verifies that the event ID matches the hash of the event data
  /// 2. Verifies that the signature is valid for the event ID and public key
  /// 
  /// Returns `true` if both checks pass, `false` otherwise.
  /// 
  /// This should be called before storing or relaying events to ensure
  /// they haven't been tampered with.
  /// 
  /// Example:
  /// ```dart
  /// if (event.isValid) {
  ///   await relay.publish(event);
  /// } else {
  ///   print('Invalid event - rejecting');
  /// }
  /// ```
  bool get isValid {
    // Verify ID matches content
    final eventData = [
      0,
      pubkey,
      createdAt,
      kind,
      tags,
      content,
    ];

    final serialized = json.encode(eventData);
    final calculatedId = NostrCrypto.sha256(serialized);

    if (calculatedId != id) {
      return false;
    }

    // Verify signature
    return NostrCrypto.verifySignature(id, pubkey, sig);
  }

  /// Check if this is a replaceable event
  bool get isReplaceable {
    // Kind 0 (metadata), 3 (contact list) are replaceable
    // Also kinds 10000-19999 and 30000-39999
    return kind == 0 || kind == 3 ||
           (kind >= 10000 && kind < 20000) ||
           (kind >= 30000 && kind < 40000);
  }

  /// Check if this is an ephemeral event
  bool get isEphemeral {
    return kind >= 20000 && kind < 30000;
  }

  /// Check if this is a parameterized replaceable event
  bool get isParameterizedReplaceable {
    return kind >= 30000 && kind < 40000;
  }

  /// Get the 'd' tag value for parameterized replaceable events
  String? get dTagValue {
    if (!isParameterizedReplaceable) return null;
    
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == 'd') {
        return tag.length > 1 ? tag[1] : '';
      }
    }
    return '';
  }

  /// Get all 'p' tags (mentioned pubkeys)
  List<String> get mentionedPubkeys {
    return tags
        .where((tag) => tag.isNotEmpty && tag[0] == 'p')
        .map((tag) => tag.length > 1 ? tag[1] : '')
        .where((pubkey) => pubkey.isNotEmpty)
        .toList();
  }

  /// Get all 'e' tags (referenced events)
  List<String> get referencedEventIds {
    return tags
        .where((tag) => tag.isNotEmpty && tag[0] == 'e')
        .map((tag) => tag.length > 1 ? tag[1] : '')
        .where((eventId) => eventId.isNotEmpty)
        .toList();
  }

  /// Check if this event references another event
  bool references(String eventId) {
    return referencedEventIds.contains(eventId);
  }

  /// Check if this event mentions a pubkey
  bool mentions(String pubkey) {
    return mentionedPubkeys.contains(pubkey);
  }

  /// Create a copy of this event with updated fields
  NostrEvent copyWith({
    String? id,
    String? pubkey,
    int? createdAt,
    int? kind,
    List<List<String>>? tags,
    String? content,
    String? sig,
  }) {
    return NostrEvent(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      tags: tags ?? this.tags,
      content: content ?? this.content,
      sig: sig ?? this.sig,
    );
  }

  @override
  List<Object?> get props => [id, pubkey, createdAt, kind, tags, content, sig];

  @override
  String toString() {
    return 'NostrEvent(id: $id, kind: $kind, pubkey: ${pubkey.substring(0, 8)}...)';
  }
}