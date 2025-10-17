// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RelayList _$RelayListFromJson(Map<String, dynamic> json) => RelayList(
  authorPubkey: json['authorPubkey'] as String,
  relays: RelayList._relaysFromJson(json['relays'] as List),
  updatedAt: RelayList._dateTimeFromMilliseconds(
    (json['updatedAt'] as num).toInt(),
  ),
);

Map<String, dynamic> _$RelayListToJson(RelayList instance) => <String, dynamic>{
  'authorPubkey': instance.authorPubkey,
  'relays': RelayList._relaysToJson(instance.relays),
  'updatedAt': RelayList._dateTimeToMilliseconds(instance.updatedAt),
};
