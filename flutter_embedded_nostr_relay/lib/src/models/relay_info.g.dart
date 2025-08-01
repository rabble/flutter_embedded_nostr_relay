// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RelayInfo _$RelayInfoFromJson(Map<String, dynamic> json) => RelayInfo(
  name: json['name'] as String?,
  description: json['description'] as String?,
  pubkey: json['pubkey'] as String?,
  contact: json['contact'] as String?,
  supportedNips: (json['supportedNips'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  software: json['software'] as String?,
  version: json['version'] as String?,
  limitation: json['limitation'] == null
      ? null
      : RelayLimitation.fromJson(json['limitation'] as Map<String, dynamic>),
  retentionPolicy: json['retentionPolicy'] as Map<String, dynamic>?,
  relayCountries: (json['relayCountries'] as List<dynamic>?)
      ?.map((e) => (e as List<dynamic>).map((e) => e as String).toList())
      .toList(),
  paymentsUrl: json['paymentsUrl'] as Map<String, dynamic>?,
  fees: json['fees'] as Map<String, dynamic>?,
  icon: json['icon'] as String?,
);

Map<String, dynamic> _$RelayInfoToJson(RelayInfo instance) => <String, dynamic>{
  'name': instance.name,
  'description': instance.description,
  'pubkey': instance.pubkey,
  'contact': instance.contact,
  'supportedNips': instance.supportedNips,
  'software': instance.software,
  'version': instance.version,
  'limitation': instance.limitation,
  'retentionPolicy': instance.retentionPolicy,
  'relayCountries': instance.relayCountries,
  'paymentsUrl': instance.paymentsUrl,
  'fees': instance.fees,
  'icon': instance.icon,
};

RelayLimitation _$RelayLimitationFromJson(Map<String, dynamic> json) =>
    RelayLimitation(
      maxMessageLength: (json['max_message_length'] as num?)?.toInt(),
      maxSubscriptions: (json['max_subscriptions'] as num?)?.toInt(),
      maxFilters: (json['max_filters'] as num?)?.toInt(),
      maxLimit: (json['max_limit'] as num?)?.toInt(),
      maxSubidLength: (json['max_subid_length'] as num?)?.toInt(),
      maxEventTags: (json['max_event_tags'] as num?)?.toInt(),
      maxContentLength: (json['max_content_length'] as num?)?.toInt(),
      minPowDifficulty: (json['min_pow_difficulty'] as num?)?.toInt(),
      authRequired: json['auth_required'] as bool?,
      paymentRequired: json['payment_required'] as bool?,
      restrictedWrites: json['restricted_writes'] as bool?,
      createdAtLowerLimit: (json['created_at_lower_limit'] as num?)?.toInt(),
      createdAtUpperLimit: (json['created_at_upper_limit'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RelayLimitationToJson(RelayLimitation instance) =>
    <String, dynamic>{
      'max_message_length': instance.maxMessageLength,
      'max_subscriptions': instance.maxSubscriptions,
      'max_filters': instance.maxFilters,
      'max_limit': instance.maxLimit,
      'max_subid_length': instance.maxSubidLength,
      'max_event_tags': instance.maxEventTags,
      'max_content_length': instance.maxContentLength,
      'min_pow_difficulty': instance.minPowDifficulty,
      'auth_required': instance.authRequired,
      'payment_required': instance.paymentRequired,
      'restricted_writes': instance.restrictedWrites,
      'created_at_lower_limit': instance.createdAtLowerLimit,
      'created_at_upper_limit': instance.createdAtUpperLimit,
    };
