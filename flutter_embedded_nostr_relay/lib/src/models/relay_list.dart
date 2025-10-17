// ABOUTME: RelayList model representing parsed kind:10002 events from NIP-65
// ABOUTME: Contains user's preferred relays with read/write permissions and access methods

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'relay_metadata.dart';

part 'relay_list.g.dart';

/// Represents a user's relay list as defined in NIP-65.
///
/// This model contains the parsed relay information from a kind:10002 event,
/// including the author's public key, list of relays with their permissions,
/// and when the list was last updated.
///
/// The relay list is used by the outbox model to determine optimal relays
/// for querying and publishing events according to user preferences.
///
/// Example usage:
/// ```dart
/// final relayList = RelayList(
///   authorPubkey: 'user-pubkey',
///   relays: [
///     RelayMetadata(url: 'wss://relay1.com'),
///     RelayMetadata(url: 'wss://read-only.com', read: true, write: false),
///   ],
///   updatedAt: DateTime.now(),
/// );
///
/// // Get relays for reading events about this user
/// final readRelays = relayList.readRelays;
///
/// // Get relays for publishing events from this user  
/// final writeRelays = relayList.writeRelays;
/// ```
@JsonSerializable()
class RelayList extends Equatable {
  /// Public key of the user who owns this relay list.
  final String authorPubkey;
  
  /// List of relays with their associated metadata.
  @JsonKey(
    fromJson: _relaysFromJson,
    toJson: _relaysToJson,
  )
  final List<RelayMetadata> relays;
  
  /// When this relay list was last updated (from the event's created_at).
  @JsonKey(fromJson: _dateTimeFromMilliseconds, toJson: _dateTimeToMilliseconds)
  final DateTime updatedAt;

  const RelayList({
    required this.authorPubkey,
    required this.relays,
    required this.updatedAt,
  });

  /// Create RelayList from JSON representation.
  factory RelayList.fromJson(Map<String, dynamic> json) =>
      _$RelayListFromJson(json);

  /// Convert RelayList to JSON representation.
  Map<String, dynamic> toJson() => _$RelayListToJson(this);

  /// Get all relays that can be used for reading events.
  List<RelayMetadata> get readRelays {
    return relays.where((relay) => relay.read).toList();
  }

  /// Get all relays that can be used for writing/publishing events.
  List<RelayMetadata> get writeRelays {
    return relays.where((relay) => relay.write).toList();
  }

  /// Get relays sorted by priority (highest first, null priorities last).
  List<RelayMetadata> get relaysByPriority {
    final sorted = List<RelayMetadata>.from(relays);
    sorted.sort((a, b) {
      // Put null priorities at the end
      if (a.priority == null && b.priority == null) return 0;
      if (a.priority == null) return 1;
      if (b.priority == null) return -1;
      
      // Sort by priority descending (highest first)
      return b.priority!.compareTo(a.priority!);
    });
    return sorted;
  }

  /// Find a relay by its URL.
  RelayMetadata? findRelayByUrl(String url) {
    try {
      return relays.firstWhere((relay) => relay.url == url);
    } catch (e) {
      return null;
    }
  }

  /// Check if the relay list contains a specific URL.
  bool containsUrl(String url) {
    return relays.any((relay) => relay.url == url);
  }

  /// Check if the relay list is empty.
  bool get isEmpty => relays.isEmpty;

  /// Check if the relay list is not empty.
  bool get isNotEmpty => relays.isNotEmpty;

  /// Create a copy of this relay list with updated fields.
  RelayList copyWith({
    String? authorPubkey,
    List<RelayMetadata>? relays,
    DateTime? updatedAt,
  }) {
    return RelayList(
      authorPubkey: authorPubkey ?? this.authorPubkey,
      relays: relays ?? this.relays,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [authorPubkey, relays, updatedAt];

  @override
  String toString() {
    final pubkeyShort = authorPubkey.length > 8 
        ? authorPubkey.substring(0, 8) 
        : authorPubkey;
    return 'RelayList(author: ${pubkeyShort}..., ${relays.length} relays)';
  }

  // JSON conversion helpers for DateTime
  static DateTime _dateTimeFromMilliseconds(int milliseconds) {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  static int _dateTimeToMilliseconds(DateTime dateTime) {
    return dateTime.millisecondsSinceEpoch;
  }

  // JSON conversion helpers for relays
  static List<RelayMetadata> _relaysFromJson(List<dynamic> json) {
    return json
        .map((e) => RelayMetadata.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static List<Map<String, dynamic>> _relaysToJson(List<RelayMetadata> relays) {
    return relays.map((relay) => relay.toJson()).toList();
  }
}