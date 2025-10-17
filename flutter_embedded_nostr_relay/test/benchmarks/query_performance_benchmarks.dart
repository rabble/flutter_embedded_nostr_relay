// ABOUTME: Query performance benchmarks for complex filter combinations
// ABOUTME: Tests query optimization and index effectiveness with large datasets

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/models/nostr_event.dart';
import '../../lib/src/models/filter.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for simple kind-based queries.
/// 
/// Tests the most common query pattern in Nostr - filtering events by kind.
/// This benchmark represents the baseline query performance that most
/// applications depend on.
class SimpleKindQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> kindFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  SimpleKindQueryBenchmark(this.config) : super('SimpleKindQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create large dataset with realistic kind distribution
    final testEvents = <NostrEvent>[];
    final random = Random(42);
    
    // Kind distribution based on real-world usage
    final kindDistribution = {
      1: 0.70,    // Text notes - most common
      6: 0.15,    // Reposts
      7: 0.10,    // Reactions
      0: 0.02,    // Metadata
      3: 0.02,    // Contacts
      4: 0.01,    // DMs
    };
    
    for (int i = 0; i < min(config.eventCount, 50000); i++) {
      final rand = random.nextDouble();
      int kind = 1;
      double cumulative = 0.0;
      
      for (final entry in kindDistribution.entries) {
        cumulative += entry.value;
        if (rand <= cumulative) {
          kind = entry.key;
          break;
        }
      }
      
      final event = NostrEvent.create(
        pubkey: 'author${i % 1000}'.padRight(64, '0'),
        kind: kind,
        tags: kind == 1 ? [['t', 'topic${i % 50}']] : [],
        content: 'Event $i content for kind $kind benchmarking',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200)) // Up to 30 days
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'sig_$i'.padRight(128, '0'),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create filters for different kinds with various limits
    kindFilters = [
      Filter(kinds: [1], limit: 50),
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [1], limit: 500),
      Filter(kinds: [1], limit: 1000),
      Filter(kinds: [6], limit: 100),
      Filter(kinds: [7], limit: 200),
      Filter(kinds: [0], limit: 10),
      Filter(kinds: [1, 6], limit: 300),
      Filter(kinds: [1, 6, 7], limit: 500),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = kindFilters[filterIndex % kindFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for author-based queries.
/// 
/// Tests query performance when filtering by author pubkey,
/// which is critical for profile views and author timelines.
class AuthorQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> authorFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  AuthorQueryBenchmark(this.config) : super('AuthorQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create authors with realistic activity patterns
    final authors = List.generate(1000, (i) => 
        'author${i.toString().padLeft(4, '0')}' + '0' * (64 - 10));
    
    final testEvents = <NostrEvent>[];
    final random = Random(42);
    
    // Some authors are more active than others (power law distribution)
    for (int i = 0; i < min(config.eventCount, 50000); i++) {
      // Power law: some authors post much more than others
      final authorIndex = (pow(random.nextDouble(), 2) * authors.length).floor();
      final author = authors[authorIndex];
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: [1, 6, 7][random.nextInt(3)],
        tags: [['t', 'topic${random.nextInt(100)}']],
        content: 'Event $i from author $authorIndex',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'sig_$i'.padRight(128, '0'),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create filters for different author query patterns
    authorFilters = [
      // Single author queries
      Filter(authors: [authors[0]], limit: 100),
      Filter(authors: [authors[1]], limit: 50),
      Filter(authors: [authors[2]], limit: 200),
      
      // Multiple author queries (following lists)
      Filter(authors: authors.take(10).toList(), limit: 500),
      Filter(authors: authors.skip(10).take(20).toList(), limit: 300),
      Filter(authors: authors.skip(30).take(50).toList(), limit: 1000),
      
      // Author + kind combinations
      Filter(authors: [authors[0]], kinds: [1], limit: 100),
      Filter(authors: authors.take(5).toList(), kinds: [1, 6], limit: 200),
      
      // Large following list simulation
      Filter(authors: authors.take(100).toList(), limit: 1000),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = authorFilters[filterIndex % authorFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for tag-based queries.
/// 
/// Tests performance of tag queries including hashtags (#t),
/// mentions (#p), and event references (#e).
class TagQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> tagFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  TagQueryBenchmark(this.config) : super('TagQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    final authors = List.generate(500, (i) => 
        'author$i'.padRight(64, '0'));
    final hashtags = List.generate(200, (i) => 'topic$i');
    
    final testEvents = <NostrEvent>[];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 40000); i++) {
      final author = authors[i % authors.length];
      final tags = <List<String>>[];
      
      // Add hashtags (some events have multiple)
      final numHashtags = random.nextInt(4); // 0-3 hashtags
      for (int j = 0; j < numHashtags; j++) {
        tags.add(['t', hashtags[random.nextInt(hashtags.length)]]);
      }
      
      // Add mentions (some events mention users)
      if (random.nextDouble() < 0.3) { // 30% of events have mentions
        final numMentions = 1 + random.nextInt(3); // 1-3 mentions
        for (int j = 0; j < numMentions; j++) {
          tags.add(['p', authors[random.nextInt(authors.length)]]);
        }
      }
      
      // Add event references for some events
      if (random.nextDouble() < 0.2) { // 20% reference other events
        tags.add(['e', 'event_id_${random.nextInt(1000)}'.padRight(64, '0')]);
      }
      
      // Add some custom tags
      if (random.nextDouble() < 0.1) {
        tags.add(['custom', 'value${random.nextInt(100)}']);
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: 1,
        tags: tags,
        content: 'Event $i with tags: ${tags.map((t) => t.join(':')).join(', ')}',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'sig_$i'.padRight(128, '0'),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create various tag-based filters
    tagFilters = [
      // Single hashtag queries
      Filter(kinds: [1], limit: 100), // Using generic tags field
      
      // Multiple hashtag queries
      Filter(kinds: [1], eTags: ['event_id_1'.padRight(64, '0')], limit: 50),
      
      // Mention queries
      Filter(pTags: [authors[0]], limit: 100),
      Filter(pTags: authors.take(5).toList(), limit: 200),
      Filter(pTags: authors.take(20).toList(), limit: 500),
      
      // Event reference queries
      Filter(eTags: ['event_id_1'.padRight(64, '0')], limit: 50),
      
      // Combined tag + kind queries
      Filter(kinds: [1], pTags: [authors[0]], limit: 100),
      Filter(kinds: [1], pTags: authors.take(10).toList(), limit: 300),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = tagFilters[filterIndex % tagFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for complex multi-condition queries.
/// 
/// Tests performance of queries with multiple filter conditions,
/// representing real-world application query patterns.
class ComplexFilterQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> complexFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  ComplexFilterQueryBenchmark(this.config) : super('ComplexFilterQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    final authors = List.generate(200, (i) => 
        'author$i'.padRight(64, '0'));
    
    final testEvents = <NostrEvent>[];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 30000); i++) {
      final author = authors[i % authors.length];
      final kind = [1, 6, 7][random.nextInt(3)];
      
      final tags = <List<String>>[];
      tags.add(['t', 'topic${random.nextInt(50)}']);
      
      if (random.nextDouble() < 0.4) {
        tags.add(['p', authors[random.nextInt(authors.length)]]);
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: 'Complex filter test event $i',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'sig_$i'.padRight(128, '0'),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create complex filter combinations
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    complexFilters = [
      // Multi-kind + multi-author + time range
      Filter(
        kinds: [1, 6],
        authors: authors.take(10).toList(),
        since: now - 86400, // Last 24 hours
        limit: 200,
      ),
      
      // Kind + mentions + time range
      Filter(
        kinds: [1],
        pTags: authors.take(5).toList(),
        since: now - 604800, // Last week
        until: now - 86400,  // But not today
        limit: 100,
      ),
      
      // Complex tag combinations
      Filter(
        kinds: [1, 6, 7],
        authors: authors.skip(20).take(30).toList(),
        pTags: authors.take(10).toList(),
        limit: 300,
      ),
      
      // Large result set with multiple conditions
      Filter(
        kinds: [1],
        authors: authors.take(50).toList(),
        since: now - 2592000, // Last month
        limit: 1000,
      ),
      
      // Specific time window with multiple kinds
      Filter(
        kinds: [1, 6, 7],
        since: now - 172800, // Last 48 hours
        until: now - 43200,  // 12 hours ago
        limit: 500,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = complexFilters[filterIndex % complexFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for time range queries.
/// 
/// Tests performance of queries with since/until parameters,
/// which are critical for pagination and timeline views.
class TimeRangeQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> timeFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  TimeRangeQueryBenchmark(this.config) : super('TimeRangeQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    final testEvents = <NostrEvent>[];
    final random = Random(42);
    final baseTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // Create events spread over 90 days with realistic distribution
    for (int i = 0; i < min(config.eventCount, 40000); i++) {
      // More recent events are more common (exponential decay)
      final dayOffset = (pow(random.nextDouble(), 0.5) * 90).floor();
      final timestamp = baseTime - (dayOffset * 86400);
      
      final event = NostrEvent.create(
        pubkey: 'author${i % 500}'.padRight(64, '0'),
        kind: 1,
        tags: [['t', 'topic${i % 100}']],
        content: 'Time range test event $i',
        createdAt: timestamp,
      ).copyWith(
        sig: 'sig_$i'.padRight(128, '0'),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create time range filters
    timeFilters = [
      // Recent time ranges
      Filter(
        kinds: [1],
        since: baseTime - 3600, // Last hour
        limit: 100,
      ),
      Filter(
        kinds: [1],
        since: baseTime - 86400, // Last day
        limit: 500,
      ),
      Filter(
        kinds: [1],
        since: baseTime - 604800, // Last week
        limit: 1000,
      ),
      
      // Specific time windows
      Filter(
        kinds: [1],
        since: baseTime - 172800, // 48 hours ago
        until: baseTime - 86400,  // 24 hours ago
        limit: 200,
      ),
      Filter(
        kinds: [1],
        since: baseTime - 604800, // Week ago
        until: baseTime - 259200, // 3 days ago
        limit: 300,
      ),
      
      // Older time ranges
      Filter(
        kinds: [1],
        since: baseTime - 2592000, // Month ago
        until: baseTime - 604800,  // Week ago
        limit: 500,
      ),
      
      // Very specific time windows
      Filter(
        kinds: [1],
        since: baseTime - 7200,  // 2 hours ago
        until: baseTime - 3600,  // 1 hour ago
        limit: 50,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = timeFilters[filterIndex % timeFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for queries with different limit values.
/// 
/// Tests how query performance scales with result set size,
/// measuring the impact of limit values on query execution time.
class LimitedQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> limitFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  LimitedQueryBenchmark(this.config) : super('LimitedQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create a large dataset
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 50000),
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create filters with different limit values
    limitFilters = [
      Filter(kinds: [1], limit: 1),
      Filter(kinds: [1], limit: 10),
      Filter(kinds: [1], limit: 50),
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [1], limit: 200),
      Filter(kinds: [1], limit: 500),
      Filter(kinds: [1], limit: 1000),
      Filter(kinds: [1], limit: 2000),
      Filter(kinds: [1], limit: 5000),
      Filter(kinds: [1]), // No limit
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = limitFilters[filterIndex % limitFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for multi-filter queries.
/// 
/// Tests performance when multiple filters are provided in a single
/// query, representing complex search scenarios.
class MultiFilterQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<List<Filter>> multiFilters;
  int filterSetIndex = 0;
  final BenchmarkConfig config;

  MultiFilterQueryBenchmark(this.config) : super('MultiFilterQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    final authors = List.generate(100, (i) => 
        'author$i'.padRight(64, '0'));
    
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 30000),
      kinds: [0, 1, 3, 6, 7],
      contentSize: 150,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create multi-filter combinations
    multiFilters = [
      // Two simple filters
      [
        Filter(kinds: [1], limit: 100),
        Filter(kinds: [6], limit: 50),
      ],
      
      // Different authors
      [
        Filter(authors: [authors[0]], limit: 50),
        Filter(authors: [authors[1]], limit: 50),
        Filter(authors: [authors[2]], limit: 50),
      ],
      
      // Different kinds + authors
      [
        Filter(kinds: [1], authors: authors.take(10).toList(), limit: 100),
        Filter(kinds: [6], authors: authors.skip(10).take(10).toList(), limit: 100),
      ],
      
      // Complex multi-filter
      [
        Filter(kinds: [1], limit: 200),
        Filter(kinds: [6, 7], authors: authors.take(20).toList(), limit: 100),
        Filter(authors: authors.skip(50).take(5).toList(), limit: 50),
      ],
      
      // Many small filters
      List.generate(10, (i) => Filter(
        authors: [authors[i]],
        kinds: [1],
        limit: 20,
      )),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filters = multiFilters[filterSetIndex % multiFilters.length];
    filterSetIndex++;
    
    eventStore.queryEvents(filters);
  }
}