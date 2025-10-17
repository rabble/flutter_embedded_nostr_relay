// ABOUTME: Database operation benchmarks for event storage and retrieval
// ABOUTME: Tests SQLite performance with large datasets and complex queries

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

/// Benchmark for single event database insertion performance.
/// 
/// Measures the time to insert individual events into the database,
/// including all indexing and tag processing overhead. This benchmark
/// represents the baseline performance for event storage operations.
class DatabaseInsertBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  DatabaseInsertBenchmark(this.config) : super('DatabaseInsert');

  @override
  Future<void> setup() async {
    // Enable test mode for in-memory database
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-generate test events
    testEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 6, 7],
      contentSize: 280,
    );
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Use events in round-robin fashion to avoid running out
    final event = testEvents[eventIndex % testEvents.length];
    eventIndex++;
    
    // Create a unique copy to avoid duplicate ID issues
    final uniqueEvent = event.copyWith(
      content: '${event.content} #$eventIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
  }
}

/// Benchmark for batch event insertion performance.
/// 
/// Measures the performance of bulk event insertion operations,
/// which are critical for sync scenarios and data import operations.
/// Tests various batch sizes to find optimal performance characteristics.
class DatabaseBatchInsertBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<List<NostrEvent>> eventBatches;
  int batchIndex = 0;
  final BenchmarkConfig config;

  DatabaseBatchInsertBenchmark(this.config) : super('DatabaseBatchInsert');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create batches of different sizes for testing
    final allEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 3, 6, 7],
      contentSize: 200,
    );
    
    eventBatches = [];
    const batchSizes = [10, 50, 100, 500, 1000];
    
    for (final batchSize in batchSizes) {
      for (int i = 0; i < allEvents.length; i += batchSize) {
        final batch = allEvents.skip(i).take(batchSize).toList();
        if (batch.isNotEmpty) {
          eventBatches.add(batch);
        }
      }
    }
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final batch = eventBatches[batchIndex % eventBatches.length];
    batchIndex++;
    
    eventStore.storeEvents(batch);
  }
}

/// Benchmark for basic database query performance.
/// 
/// Tests fundamental query operations against a populated database,
/// measuring the performance of various filter combinations and
/// result set sizes.
class DatabaseQueryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> testFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  DatabaseQueryBenchmark(this.config) : super('DatabaseQuery');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Populate database with test data
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 10000), // Limit for setup speed
      kinds: [0, 1, 3, 6, 7],
      contentSize: 150,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create diverse filter combinations
    testFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [1, 6], limit: 200),
      Filter(authors: testEvents.take(10).map((e) => e.pubkey).toList(), limit: 50),
      Filter(kinds: [1], limit: 500),
      Filter(
        since: DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
        kinds: [1],
        limit: 300,
      ),
      Filter(kinds: [1, 3, 6, 7], limit: 1000),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = testFilters[filterIndex % testFilters.length];
    filterIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for database index performance with large datasets.
/// 
/// Tests query performance as the database grows, measuring the
/// effectiveness of indexing strategies for various query patterns.
class DatabaseIndexPerformanceBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> complexFilters;
  int queryIndex = 0;
  final BenchmarkConfig config;

  DatabaseIndexPerformanceBenchmark(this.config) : super('DatabaseIndexPerformance');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create a large dataset to test index performance
    final authors = List.generate(100, (i) => 
        'author${i.toString().padLeft(3, '0')}' + '0' * (64 - 9));
    
    final testEvents = <NostrEvent>[];
    final random = Random(42); // Seed for reproducible results
    
    for (int i = 0; i < min(config.eventCount, 50000); i++) {
      final author = authors[i % authors.length];
      final kind = [0, 1, 3, 6, 7][random.nextInt(5)];
      final tags = <List<String>>[];
      
      // Add various tags for testing tag queries
      if (kind == 1) {
        tags.addAll([
          ['t', 'topic${random.nextInt(20)}'],
          ['p', authors[random.nextInt(authors.length)]],
        ]);
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: 'Test event $i with content for benchmarking',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(10080)) // Up to 1 week ago
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'benchmark_sig_$i' + '0' * (128 - 'benchmark_sig_$i'.length),
      );
      
      testEvents.add(event);
    }
    
    await eventStore.storeEvents(testEvents);
    
    // Create complex filters that stress different indexes
    complexFilters = [
      // Kind + author combination (common pattern)
      Filter(
        kinds: [1],
        authors: authors.take(5).toList(),
        limit: 100,
      ),
      // Tag-based queries
      Filter(
        pTags: authors.take(10).toList(),
        kinds: [1],
        limit: 200,
      ),
      // Time range + kind queries
      Filter(
        kinds: [1, 6],
        since: DateTime.now().subtract(Duration(days: 3)).millisecondsSinceEpoch ~/ 1000,
        until: DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
        limit: 500,
      ),
      // Complex multi-condition queries
      Filter(
        kinds: [1],
        authors: authors.skip(10).take(20).toList(),
        since: DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
        limit: 300,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = complexFilters[queryIndex % complexFilters.length];
    queryIndex++;
    
    eventStore.queryEvents([filter]);
  }
}

/// Benchmark for replaceable event handling performance.
/// 
/// Tests the performance of replaceable event logic, including
/// the deletion of older events and proper handling of parameterized
/// replaceable events with d-tags.
class DatabaseReplaceableEventBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> replaceableEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  DatabaseReplaceableEventBenchmark(this.config) : super('DatabaseReplaceableEvent');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate replaceable events (kind 10000-19999 and 30000-39999)
    final authors = List.generate(50, (i) => 
        'repl_author$i' + '0' * (64 - 'repl_author$i'.length));
    
    replaceableEvents = [];
    
    // Regular replaceable events (10000-19999)
    for (int i = 0; i < config.eventCount ~/ 4; i++) {
      final author = authors[i % authors.length];
      final kind = 10000 + (i % 100); // Various replaceable kinds
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: [],
        content: 'Replaceable event $i content',
        createdAt: DateTime.now().subtract(
          Duration(minutes: Random().nextInt(1440))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'repl_sig_$i' + '0' * (128 - 'repl_sig_$i'.length),
      );
      
      replaceableEvents.add(event);
    }
    
    // Parameterized replaceable events (30000-39999)
    for (int i = 0; i < config.eventCount ~/ 4; i++) {
      final author = authors[i % authors.length];
      final kind = 30000 + (i % 100);
      final dTag = 'article_${i % 20}'; // Some d-tags repeat for replacement testing
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: [['d', dTag]],
        content: 'Parameterized replaceable event $i',
        createdAt: DateTime.now().subtract(
          Duration(minutes: Random().nextInt(1440))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'param_repl_sig_$i' + '0' * (128 - 'param_repl_sig_$i'.length),
      );
      
      replaceableEvents.add(event);
    }
    
    // Shuffle to create realistic replacement patterns
    replaceableEvents.shuffle(Random(42));
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = replaceableEvents[eventIndex % replaceableEvents.length];
    eventIndex++;
    
    eventStore.storeEvent(event);
  }
}

/// Benchmark for database concurrent access performance.
/// 
/// Tests database performance under concurrent read/write scenarios,
/// measuring lock contention and transaction throughput.
class DatabaseConcurrentAccessBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  late List<Filter> testFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  DatabaseConcurrentAccessBenchmark(this.config) : super('DatabaseConcurrentAccess');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-populate with some data
    final initialEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 5000),
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    await eventStore.storeEvents(initialEvents);
    
    // Prepare events for concurrent insertion
    testEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 3, 6, 7],
      contentSize: 150,
    );
    
    // Prepare filters for concurrent querying
    testFilters = [
      Filter(kinds: [1], limit: 50),
      Filter(kinds: [1, 6], limit: 100),
      Filter(kinds: [1], limit: 200),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate concurrent read/write operations
    final isWrite = operationIndex % 3 == 0; // 1/3 writes, 2/3 reads
    
    if (isWrite) {
      final event = testEvents[operationIndex % testEvents.length];
      eventStore.storeEvent(event.copyWith(
        content: '${event.content} #$operationIndex',
      ));
    } else {
      final filter = testFilters[operationIndex % testFilters.length];
      eventStore.queryEvents([filter]);
    }
    
    operationIndex++;
  }
}

/// Benchmark for database vacuum and maintenance operations.
/// 
/// Tests the performance impact of database maintenance operations
/// like VACUUM, ANALYZE, and REINDEX on a large database.
class DatabaseMaintenanceBenchmark extends BenchmarkBase {
  late DatabaseHelper dbHelper;
  final BenchmarkConfig config;

  DatabaseMaintenanceBenchmark(this.config) : super('DatabaseMaintenance');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    dbHelper = DatabaseHelper.instance;
    
    // Create a large database with some fragmentation
    final eventStore = EventStore();
    
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 20000),
      kinds: [0, 1, 3, 6, 7, 10000, 30000],
      contentSize: 300,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create some fragmentation by deleting events
    final eventIds = testEvents.take(testEvents.length ~/ 4)
        .map((e) => e.id).toList();
    await eventStore.deleteEvents(eventIds);
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Test vacuum operation performance
    dbHelper.vacuum();
  }
}