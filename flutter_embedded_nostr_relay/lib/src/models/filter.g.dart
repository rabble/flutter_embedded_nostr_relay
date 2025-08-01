// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'filter.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Filter _$FilterFromJson(Map<String, dynamic> json) => Filter(
  ids: (json['ids'] as List<dynamic>?)?.map((e) => e as String).toList(),
  authors: (json['authors'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  kinds: (json['kinds'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  tags: (json['tags'] as Map<String, dynamic>?)?.map(
    (k, e) =>
        MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
  ),
  since: (json['since'] as num?)?.toInt(),
  until: (json['until'] as num?)?.toInt(),
  limit: (json['limit'] as num?)?.toInt(),
  eTags: (json['#e'] as List<dynamic>?)?.map((e) => e as String).toList(),
  pTags: (json['#p'] as List<dynamic>?)?.map((e) => e as String).toList(),
  aTags: (json['#a'] as List<dynamic>?)?.map((e) => e as String).toList(),
  dTags: (json['#d'] as List<dynamic>?)?.map((e) => e as String).toList(),
);

Map<String, dynamic> _$FilterToJson(Filter instance) => <String, dynamic>{
  'ids': ?instance.ids,
  'authors': ?instance.authors,
  'kinds': ?instance.kinds,
  'tags': ?instance.tags,
  'since': ?instance.since,
  'until': ?instance.until,
  'limit': ?instance.limit,
  '#e': ?instance.eTags,
  '#p': ?instance.pTags,
  '#a': ?instance.aTags,
  '#d': ?instance.dTags,
};
