// ABOUTME: Relay information model according to NIP-11
// ABOUTME: Contains relay metadata, supported NIPs, limitations, and contact info

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'relay_info.g.dart';

@JsonSerializable()
class RelayInfo extends Equatable {
  final String? name;
  final String? description;
  final String? pubkey;
  final String? contact;
  final List<int>? supportedNips;
  final String? software;
  final String? version;
  final RelayLimitation? limitation;
  final Map<String, dynamic>? retentionPolicy;
  final List<List<String>>? relayCountries;
  final Map<String, dynamic>? paymentsUrl;
  final Map<String, dynamic>? fees;
  final String? icon;

  const RelayInfo({
    this.name,
    this.description,
    this.pubkey,
    this.contact,
    this.supportedNips,
    this.software,
    this.version,
    this.limitation,
    this.retentionPolicy,
    this.relayCountries,
    this.paymentsUrl,
    this.fees,
    this.icon,
  });

  factory RelayInfo.fromJson(Map<String, dynamic> json) =>
      _$RelayInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RelayInfoToJson(this);

  /// Default relay info for the embedded relay
  factory RelayInfo.embedded() {
    return RelayInfo(
      name: 'Flutter Embedded Nostr Relay',
      description: 'A self-contained Nostr relay running inside your Flutter app',
      software: 'flutter_embedded_nostr_relay',
      version: '0.1.0',
      supportedNips: [
        1,   // Basic protocol
        2,   // Contact list and petnames
        9,   // Event deletion
        11,  // Relay information document
        12,  // Generic tag queries
        15,  // End of stored events notice
        16,  // Event treatment
        20,  // Command results
        22,  // Event created_at limits
        26,  // Delegated event signing
        28,  // Public chat
        33,  // Parameterized replaceable events
        40,  // Expiration timestamp
        42,  // Authentication of clients to relays
        50,  // Search capability
        65,  // Relay list metadata
      ],
      limitation: RelayLimitation(
        maxMessageLength: 65536,
        maxSubscriptions: 100,
        maxFilters: 10,
        maxLimit: 5000,
        maxSubidLength: 256,
        maxEventTags: 2000,
        maxContentLength: 65536,
        minPowDifficulty: 0,
        authRequired: false,
        paymentRequired: false,
        restrictedWrites: false,
        createdAtLowerLimit: null,
        createdAtUpperLimit: null,
      ),
    );
  }

  /// Check if a specific NIP is supported
  bool supportsNip(int nip) {
    return supportedNips?.contains(nip) ?? false;
  }

  @override
  List<Object?> get props => [
        name,
        description,
        pubkey,
        contact,
        supportedNips,
        software,
        version,
        limitation,
        retentionPolicy,
        relayCountries,
        paymentsUrl,
        fees,
        icon,
      ];
}

@JsonSerializable()
class RelayLimitation extends Equatable {
  @JsonKey(name: 'max_message_length')
  final int? maxMessageLength;
  
  @JsonKey(name: 'max_subscriptions')
  final int? maxSubscriptions;
  
  @JsonKey(name: 'max_filters')
  final int? maxFilters;
  
  @JsonKey(name: 'max_limit')
  final int? maxLimit;
  
  @JsonKey(name: 'max_subid_length')
  final int? maxSubidLength;
  
  @JsonKey(name: 'max_event_tags')
  final int? maxEventTags;
  
  @JsonKey(name: 'max_content_length')
  final int? maxContentLength;
  
  @JsonKey(name: 'min_pow_difficulty')
  final int? minPowDifficulty;
  
  @JsonKey(name: 'auth_required')
  final bool? authRequired;
  
  @JsonKey(name: 'payment_required')
  final bool? paymentRequired;
  
  @JsonKey(name: 'restricted_writes')
  final bool? restrictedWrites;
  
  @JsonKey(name: 'created_at_lower_limit')
  final int? createdAtLowerLimit;
  
  @JsonKey(name: 'created_at_upper_limit')
  final int? createdAtUpperLimit;

  const RelayLimitation({
    this.maxMessageLength,
    this.maxSubscriptions,
    this.maxFilters,
    this.maxLimit,
    this.maxSubidLength,
    this.maxEventTags,
    this.maxContentLength,
    this.minPowDifficulty,
    this.authRequired,
    this.paymentRequired,
    this.restrictedWrites,
    this.createdAtLowerLimit,
    this.createdAtUpperLimit,
  });

  factory RelayLimitation.fromJson(Map<String, dynamic> json) =>
      _$RelayLimitationFromJson(json);

  Map<String, dynamic> toJson() => _$RelayLimitationToJson(this);

  @override
  List<Object?> get props => [
        maxMessageLength,
        maxSubscriptions,
        maxFilters,
        maxLimit,
        maxSubidLength,
        maxEventTags,
        maxContentLength,
        minPowDifficulty,
        authRequired,
        paymentRequired,
        restrictedWrites,
        createdAtLowerLimit,
        createdAtUpperLimit,
      ];
}