// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RelayMetadata _$RelayMetadataFromJson(Map<String, dynamic> json) =>
    RelayMetadata(
      url: json['url'] as String,
      read: json['read'] as bool? ?? true,
      write: json['write'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt(),
    );

Map<String, dynamic> _$RelayMetadataToJson(RelayMetadata instance) =>
    <String, dynamic>{
      'url': instance.url,
      'read': instance.read,
      'write': instance.write,
      'priority': instance.priority,
    };
