// ABOUTME: Memory usage pattern benchmarks for large dataset scenarios
// ABOUTME: Tests memory efficiency, growth patterns, and garbage collection impact

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/models/nostr_event.dart';
import '../../lib/src/models/filter.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for memory growth patterns during event storage.
/// 
/// Measures how memory usage grows as the database size increases,
/// helping identify memory leaks and inefficient memory usage patterns.
class MemoryGrowthBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  MemoryGrowthBenchmark(this.config) : super('MemoryGrowth');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate events for memory growth testing
    testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 10000),
      kinds: [1, 6, 7],
      contentSize: 500, // Larger content to stress memory
    );
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Store events in batches and measure memory growth
    const batchSize = 100;
    final startIndex = eventIndex;
    
    for (int i = 0; i < batchSize && eventIndex < testEvents.length; i++) {
      final event = testEvents[eventIndex];
      final uniqueEvent = event.copyWith(
        content: '${event.content} #$eventIndex',
      );
      
      eventStore.storeEvent(uniqueEvent);
      eventIndex++;
    }
    
    // Force garbage collection attempt
    if (eventIndex % 1000 == 0) {
      // Trigger garbage collection hints
      List.generate(1000, (i) => []).clear();
    }
  }
}

/// Benchmark for memory efficiency during query operations.
/// 
/// Tests memory usage patterns during large query operations,
/// measuring memory allocation and deallocation efficiency.
class MemoryEfficiencyBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> queryFilters;
  int filterIndex = 0;
  final BenchmarkConfig config;

  MemoryEfficiencyBenchmark(this.config) : super('MemoryEfficiency');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-populate database with large dataset
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 20000),
      kinds: [1, 6, 7],
      contentSize: 300,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create filters that return different result set sizes
    queryFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [1], limit: 500),
      Filter(kinds: [1], limit: 1000),
      Filter(kinds: [1], limit: 2000),
      Filter(kinds: [1, 6, 7], limit: 5000),
      Filter(kinds: [1]), // No limit - potentially large result set
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = queryFilters[filterIndex % queryFilters.length];
    filterIndex++;
    
    // Execute query and immediately release results
    final results = eventStore.queryEvents([filter]);
    
    // Process results to simulate real usage
    int totalContentLength = 0;
    for (final event in results) {
      totalContentLength += event.content.length;
    }
    
    // Clear results reference to help garbage collection
    results.clear();
  }
}

/// Benchmark for memory usage with large datasets.
/// 
/// Tests memory behavior when working with very large datasets,
/// focusing on query performance and memory pressure scenarios.
class LargeDatasetMemoryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> largeQueryFilters;
  int queryIndex = 0;
  final BenchmarkConfig config;

  LargeDatasetMemoryBenchmark(this.config) : super('LargeDatasetMemory');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create very large dataset
    final authors = List.generate(500, (i) => 
        'memory_author$i'.padRight(64, '0'));
    
    final largeEvents = <NostrEvent>[];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 50000); i++) {
      final author = authors[i % authors.length];
      
      // Create events with substantial content and tags
      final tags = <List<String>>[];
      for (int j = 0; j < 3 + random.nextInt(7); j++) {
        tags.add(['t', 'topic${random.nextInt(200)}']);
      }
      for (int j = 0; j < random.nextInt(3); j++) {
        tags.add(['p', authors[random.nextInt(authors.length)]]);
      }
      
      final content = 'Large memory test event $i. ' * (5 + random.nextInt(20));
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: 1,
        tags: tags,
        content: content,
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'mem_sig_$i'.padRight(128, '0'),
      );
      
      largeEvents.add(event);
    }
    
    await eventStore.storeEvents(largeEvents);
    
    // Create queries that stress memory with large result sets
    largeQueryFilters = [
      Filter(kinds: [1], limit: 5000),
      Filter(kinds: [1], limit: 10000),
      Filter(authors: authors.take(100).toList(), limit: 3000),
      Filter(authors: authors.take(50).toList(), kinds: [1]),
      Filter(
        since: DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
        kinds: [1],
        limit: 8000,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final filter = largeQueryFilters[queryIndex % largeQueryFilters.length];
    queryIndex++;
    
    final results = eventStore.queryEvents([filter]);
    
    // Simulate processing large result set
    int processingCounter = 0;
    for (final event in results) {
      // Simulate string operations that might allocate memory
      final processedContent = event.content.toUpperCase();
      final tagString = event.tags.map((t) => t.join(':')).join(',');
      processingCounter += processedContent.length + tagString.length;
    }
    
    // Clear references
    results.clear();
  }
}

/// Benchmark for memory leak detection.
/// 
/// Performs repetitive operations to detect potential memory leaks
/// in the event storage and query systems.
class MemoryLeakDetectionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> leakTestEvents;
  late List<Filter> leakTestFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  MemoryLeakDetectionBenchmark(this.config) : super('MemoryLeakDetection');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create moderate dataset for leak testing
    leakTestEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 1000),
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    // Pre-populate with some data
    await eventStore.storeEvents(leakTestEvents.take(500).toList());
    
    leakTestFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [6], limit: 50),
      Filter(kinds: [7], limit: 200),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Perform mixed operations repeatedly to detect leaks
    final operation = operationIndex % 4;
    
    switch (operation) {
      case 0: // Insert operation
        final event = leakTestEvents[operationIndex % leakTestEvents.length];
        final uniqueEvent = event.copyWith(
          content: '${event.content} #$operationIndex',
        );
        eventStore.storeEvent(uniqueEvent);
        break;
        
      case 1: // Query operation
        final filter = leakTestFilters[operationIndex % leakTestFilters.length];
        final results = eventStore.queryEvents([filter]);
        
        // Process and release results
        for (final event in results) {
          final _ = event.content.length; // Simple processing
        }
        results.clear();
        break;
        
      case 2: // Batch insert operation
        final batchSize = 10;
        final batch = <NostrEvent>[];
        
        for (int i = 0; i < batchSize; i++) {
          final event = leakTestEvents[(operationIndex + i) % leakTestEvents.length];
          batch.add(event.copyWith(
            content: '${event.content} batch#${operationIndex + i}',
          ));
        }
        
        eventStore.storeEvents(batch);
        break;
        
      case 3: // Complex query operation
        final complexFilter = Filter(
          kinds: [1, 6],
          since: DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
          limit: 500,
        );
        
        final results = eventStore.queryEvents([complexFilter]);
        
        // Simulate complex processing
        final processedData = <String, int>{};
        for (final event in results) {
          processedData[event.pubkey] = (processedData[event.pubkey] ?? 0) + 1;
        }
        
        processedData.clear();
        results.clear();
        break;
    }
    
    operationIndex++;
    
    // Periodically suggest garbage collection
    if (operationIndex % 100 == 0) {
      // Create and discard temporary objects to stress GC
      final temp = List.generate(100, (i) => 'temp_$i');
      temp.clear();
    }
  }
}

/// Benchmark for memory pressure scenarios.
/// 
/// Tests system behavior under memory pressure conditions,
/// simulating low-memory environments and stress conditions.
class MemoryPressureBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> pressureTestEvents;
  final List<List<NostrEvent>> _memoryHogs = [];
  int operationIndex = 0;
  final BenchmarkConfig config;

  MemoryPressureBenchmark(this.config) : super('MemoryPressure');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create events with large content to create memory pressure
    pressureTestEvents = [];
    
    for (int i = 0; i < min(config.eventCount ~/ 20, 500); i++) {
      // Create events with substantial content
      final largeContent = 'Memory pressure test content $i. ' * 100;
      
      final event = NostrEvent.create(
        pubkey: 'pressure_author$i'.padRight(64, '0'),
        kind: 1,
        tags: List.generate(20, (j) => ['tag$j', 'value$j']),
        content: largeContent,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'pressure_sig_$i'.padRight(128, '0'),
      );
      
      pressureTestEvents.add(event);
    }
    
    // Pre-populate database
    await eventStore.storeEvents(pressureTestEvents.take(200).toList());
  }

  @override
  Future<void> teardown() async {
    // Clear memory hogs
    _memoryHogs.clear();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Create memory pressure by holding references to large objects
    if (_memoryHogs.length < 10) {
      final memoryHog = List.generate(1000, (i) => 
          pressureTestEvents[i % pressureTestEvents.length]);
      _memoryHogs.add(memoryHog);
    }
    
    // Perform operations under memory pressure
    final event = pressureTestEvents[operationIndex % pressureTestEvents.length];
    final uniqueEvent = event.copyWith(
      content: '${event.content} pressure#$operationIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
    
    // Query under pressure
    final results = eventStore.queryEvents([
      Filter(kinds: [1], limit: 200)
    ]);
    
    // Process results while under memory pressure
    final processed = results.map((e) => e.content.toUpperCase()).toList();
    processed.clear();
    results.clear();
    
    operationIndex++;
    
    // Occasionally release some memory pressure
    if (operationIndex % 50 == 0 && _memoryHogs.isNotEmpty) {
      _memoryHogs.removeAt(0);
    }
  }
}

/// Benchmark for garbage collection impact on performance.
/// 
/// Measures how garbage collection events impact operation performance
/// by creating and discarding large numbers of objects.
class GarbageCollectionImpactBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> gcTestEvents;
  int operationIndex = 0;
  final BenchmarkConfig config;

  GarbageCollectionImpactBenchmark(this.config) : super('GarbageCollectionImpact');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    gcTestEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 5, 2000),
      kinds: [1, 6, 7],
      contentSize: 300,
    );
    
    // Pre-populate database
    await eventStore.storeEvents(gcTestEvents.take(1000).toList());
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Create many temporary objects to trigger garbage collection
    final garbageObjects = <String>[];
    for (int i = 0; i < 1000; i++) {
      garbageObjects.add('garbage_object_${operationIndex}_$i');
    }
    
    // Perform database operation while garbage collection may be occurring
    final event = gcTestEvents[operationIndex % gcTestEvents.length];
    final uniqueEvent = event.copyWith(
      content: '${event.content} gc#$operationIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
    
    // Query operation
    final results = eventStore.queryEvents([
      Filter(kinds: [1], limit: 100)
    ]);
    
    // Create more garbage during processing
    final moreGarbage = results.map((e) => 
        'processed_${e.id}_$operationIndex').toList();
    
    // Clear all temporary objects
    garbageObjects.clear();
    moreGarbage.clear();
    results.clear();
    
    operationIndex++;
  }
}

/// Benchmark for memory usage during concurrent operations.
/// 
/// Tests memory behavior when multiple operations run concurrently,
/// measuring memory allocation patterns under concurrent load.
class ConcurrentMemoryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> concurrentTestEvents;
  late List<Filter> concurrentFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  ConcurrentMemoryBenchmark(this.config) : super('ConcurrentMemory');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    concurrentTestEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 1000),
      kinds: [1, 6, 7],
      contentSize: 250,
    );
    
    // Pre-populate
    await eventStore.storeEvents(concurrentTestEvents.take(500).toList());
    
    concurrentFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [6], limit: 50),
      Filter(kinds: [1, 6, 7], limit: 200),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Run multiple operations concurrently to stress memory allocation
    final futures = <Future>[];
    
    // Concurrent insertions
    for (int i = 0; i < 3; i++) {
      final event = concurrentTestEvents[(operationIndex + i) % concurrentTestEvents.length];
      final uniqueEvent = event.copyWith(
        content: '${event.content} concurrent#${operationIndex + i}',
      );
      
      futures.add(eventStore.storeEvent(uniqueEvent));
    }
    
    // Concurrent queries
    for (int i = 0; i < 2; i++) {
      final filter = concurrentFilters[i % concurrentFilters.length];
      final future = eventStore.queryEvents([filter]).then((results) {
        // Process results in memory
        final processed = results.map((e) => e.content.length).toList();
        processed.clear();
        results.clear();
      });
      futures.add(future);
    }
    
    // Wait for all concurrent operations
    Future.wait(futures);
    
    operationIndex += 5;
  }
}