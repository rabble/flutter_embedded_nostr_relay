// ABOUTME: Nostr event model implementing NIP-01 event structure
// ABOUTME: Handles event creation, validation, serialization and signature verification

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import '../utils/crypto.dart';

part 'nostr_event.g.dart';

@JsonSerializable()
class NostrEvent extends Equatable {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
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

  /// Create a new unsigned event
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

  /// Sign this event with the given private key
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

  /// Verify the signature of this event
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
    return (kind >= 10000 && kind < 20000) || 
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

  @override
  List<Object?> get props => [id, pubkey, createdAt, kind, tags, content, sig];

  @override
  String toString() {
    return 'NostrEvent(id: $id, kind: $kind, pubkey: ${pubkey.substring(0, 8)}...)';
  }
}