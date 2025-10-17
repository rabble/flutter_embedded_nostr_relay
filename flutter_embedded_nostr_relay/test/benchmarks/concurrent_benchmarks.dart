// ABOUTME: Concurrent operation benchmarks for multi-client scenarios
// ABOUTME: Tests performance under concurrent load and resource contention

import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/models/nostr_event.dart';
import '../../lib/src/models/filter.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for concurrent read/write operations.
/// 
/// Tests database performance when multiple clients perform
/// simultaneous read and write operations, measuring lock
/// contention and throughput degradation.
class ConcurrentReadWriteBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  late List<Filter> testFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  ConcurrentReadWriteBenchmark(this.config) : super('ConcurrentReadWrite');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-populate with base dataset
    testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 5000),
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    await eventStore.storeEvents(testEvents.take(2000).toList());
    
    // Prepare additional events for concurrent insertion
    testEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 6, 7],
      contentSize: 150,
    );
    
    testFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [1, 6], limit: 200),
      Filter(kinds: [7], limit: 50),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate concurrent operations with mixed read/write workload
    final futures = <Future>[];
    
    // 60% reads, 40% writes - typical workload
    for (int i = 0; i < 5; i++) {
      if (i < 3) {
        // Read operations
        final filter = testFilters[i % testFilters.length];
        futures.add(eventStore.queryEvents([filter]).then((results) {
          // Simulate processing
          for (final event in results) {
            final _ = event.content.length;
          }
          results.clear();
        }));
      } else {
        // Write operations
        final event = testEvents[operationIndex % testEvents.length];
        final uniqueEvent = event.copyWith(
          content: '${event.content} concurrent#$operationIndex',
        );
        futures.add(eventStore.storeEvent(uniqueEvent));
      }
    }
    
    operationIndex++;
    
    // Wait for all concurrent operations
    Future.wait(futures);
  }
}

/// Benchmark for multi-client simulation.
/// 
/// Simulates multiple clients performing operations simultaneously,
/// testing scalability and resource sharing efficiency.
class MultiClientBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<List<NostrEvent>> clientEvents;
  late List<List<Filter>> clientFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  MultiClientBenchmark(this.config) : super('MultiClient');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    const clientCount = 10;
    clientEvents = [];
    clientFilters = [];
    
    // Create unique event sets for each simulated client
    for (int clientId = 0; clientId < clientCount; clientId++) {
      final events = BenchmarkUtils.generateTestEvents(
        count: config.eventCount ~/ clientCount,
        kinds: [1, 6, 7],
        contentSize: 180,
      ).map((event) => event.copyWith(
        pubkey: 'client_${clientId}_author'.padRight(64, '0'),
        content: 'Client $clientId: ${event.content}',
      )).toList();
      
      clientEvents.add(events);
      
      // Each client has different query patterns
      final filters = [
        Filter(kinds: [1], limit: 50 + clientId * 10),
        Filter(authors: ['client_${clientId}_author'.padRight(64, '0')], limit: 100),
        Filter(kinds: [1, 6], limit: 150),
      ];
      
      clientFilters.add(filters);
    }
    
    // Pre-populate with some data from each client
    for (int i = 0; i < clientCount; i++) {
      await eventStore.storeEvents(clientEvents[i].take(100).toList());
    }
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate operations from multiple clients concurrently
    final futures = <Future>[];
    const clientCount = 10;
    
    for (int clientId = 0; clientId < clientCount; clientId++) {
      final isWrite = (operationIndex + clientId) % 3 == 0;
      
      if (isWrite) {
        // Client performs write operation
        final events = clientEvents[clientId];
        final event = events[operationIndex % events.length];
        final uniqueEvent = event.copyWith(
          content: '${event.content} op#$operationIndex',
        );
        
        futures.add(eventStore.storeEvent(uniqueEvent));
      } else {
        // Client performs read operation
        final filters = clientFilters[clientId];
        final filter = filters[operationIndex % filters.length];
        
        futures.add(eventStore.queryEvents([filter]).then((results) {
          // Simulate client processing
          int processingWork = 0;
          for (final event in results) {
            processingWork += event.content.length;
          }
          results.clear();
        }));
      }
    }
    
    operationIndex++;
    
    // Wait for all client operations
    Future.wait(futures);
  }
}

/// Benchmark for resource contention scenarios.
/// 
/// Tests performance when multiple operations compete for
/// the same resources, measuring contention impact.
class ContentionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> hotspotEvents;
  int operationIndex = 0;
  final BenchmarkConfig config;

  ContentionBenchmark(this.config) : super('Contention');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create events that will cause contention (same author, replaceable events)
    const hotAuthor = 'contention_hotspot_author' + '0' * (64 - 25);
    
    hotspotEvents = [];
    
    // Regular events from hot author
    for (int i = 0; i < min(config.eventCount ~/ 4, 1000); i++) {
      final event = NostrEvent.create(
        pubkey: hotAuthor,
        kind: 1,
        tags: [['t', 'hotspot']],
        content: 'Contention test event $i',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - i,
      ).copyWith(
        sig: 'contention_sig_$i'.padRight(128, '0'),
      );
      
      hotspotEvents.add(event);
    }
    
    // Replaceable events that will cause contention during replacement
    for (int i = 0; i < min(config.eventCount ~/ 8, 500); i++) {
      final event = NostrEvent.create(
        pubkey: hotAuthor,
        kind: 10000, // Replaceable kind
        tags: [['type', 'replaceable']],
        content: 'Replaceable contention event $i',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - i,
      ).copyWith(
        sig: 'repl_contention_sig_$i'.padRight(128, '0'),
      );
      
      hotspotEvents.add(event);
    }
    
    // Parameterized replaceable events with same d-tags
    for (int i = 0; i < min(config.eventCount ~/ 8, 500); i++) {
      final dTag = 'hot_item_${i % 10}'; // Only 10 different d-tags
      
      final event = NostrEvent.create(
        pubkey: hotAuthor,
        kind: 30000,
        tags: [['d', dTag]],
        content: 'Parameterized replaceable $i',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - i,
      ).copyWith(
        sig: 'param_contention_sig_$i'.padRight(128, '0'),
      );
      
      hotspotEvents.add(event);
    }
    
    // Pre-populate to create existing data for contention
    await eventStore.storeEvents(hotspotEvents.take(500).toList());
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Create high contention by having multiple operations target the same resources
    final futures = <Future>[];
    
    // Multiple concurrent operations on the same hot author
    for (int i = 0; i < 8; i++) {
      final event = hotspotEvents[operationIndex % hotspotEvents.length];
      
      // Create variations to avoid exact duplicates
      final uniqueEvent = event.copyWith(
        content: '${event.content} contention#${operationIndex}_$i',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      
      futures.add(eventStore.storeEvent(uniqueEvent));
    }
    
    // Concurrent queries for the same hot author
    const hotAuthor = 'contention_hotspot_author' + '0' * (64 - 25);
    for (int i = 0; i < 3; i++) {
      futures.add(eventStore.queryEvents([
        Filter(authors: [hotAuthor], limit: 100)
      ]).then((results) {
        // Simulate processing contention
        for (final event in results) {
          final _ = event.id.hashCode;
        }
        results.clear();
      }));
    }
    
    operationIndex++;
    
    // Wait for all contending operations
    Future.wait(futures);
  }
}

/// Benchmark for scalability testing.
/// 
/// Tests how performance scales with increasing numbers of
/// concurrent operations and clients.
class ScalabilityBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> scalabilityEvents;
  late List<Filter> scalabilityFilters;
  int operationIndex = 0;
  final BenchmarkConfig config;

  ScalabilityBenchmark(this.config) : super('Scalability');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create a large, diverse dataset
    scalabilityEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 20000),
      kinds: [0, 1, 3, 6, 7, 10000, 30000],
      contentSize: 200,
    );
    
    // Pre-populate with substantial data
    await eventStore.storeEvents(scalabilityEvents.take(10000).toList());
    
    // Create filters that stress different aspects
    final authors = scalabilityEvents.take(100).map((e) => e.pubkey).toList();
    
    scalabilityFilters = [
      Filter(kinds: [1], limit: 50),
      Filter(kinds: [1], limit: 200),
      Filter(kinds: [1], limit: 1000),
      Filter(authors: authors.take(10).toList(), limit: 500),
      Filter(authors: authors.take(50).toList(), limit: 1000),
      Filter(
        kinds: [1, 6, 7],
        since: DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
        limit: 2000,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Scale concurrent operations based on current iteration
    final concurrencyLevel = min(2 + (operationIndex ~/ 10), config.maxConcurrency);
    final futures = <Future>[];
    
    // Mix of operations with increasing concurrency
    for (int i = 0; i < concurrencyLevel; i++) {
      final operationType = i % 4;
      
      switch (operationType) {
        case 0: // Single insert
          final event = scalabilityEvents[operationIndex % scalabilityEvents.length];
          final uniqueEvent = event.copyWith(
            content: '${event.content} scale#${operationIndex}_$i',
          );
          futures.add(eventStore.storeEvent(uniqueEvent));
          break;
          
        case 1: // Batch insert
          final batchSize = 5 + (operationIndex % 20);
          final batch = <NostrEvent>[];
          
          for (int j = 0; j < batchSize; j++) {
            final event = scalabilityEvents[(operationIndex + j) % scalabilityEvents.length];
            batch.add(event.copyWith(
              content: '${event.content} batch_scale#${operationIndex}_${i}_$j',
            ));
          }
          
          futures.add(eventStore.storeEvents(batch));
          break;
          
        case 2: // Simple query
          final filter = scalabilityFilters[i % scalabilityFilters.length];
          futures.add(eventStore.queryEvents([filter]).then((results) {
            // Simulate varying processing loads
            final processingIntensity = 1 + (operationIndex % 10);
            for (int p = 0; p < processingIntensity; p++) {
              for (final event in results) {
                final _ = event.content.hashCode;
              }
            }
            results.clear();
          }));
          break;
          
        case 3: // Complex query
          final complexFilters = [
            Filter(kinds: [1], limit: 100 + (i * 50)),
            Filter(kinds: [6, 7], limit: 50 + (i * 25)),
          ];
          
          futures.add(eventStore.queryEvents(complexFilters).then((results) {
            // Complex processing simulation
            final groupedByAuthor = <String, int>{};
            for (final event in results) {
              groupedByAuthor[event.pubkey] = 
                  (groupedByAuthor[event.pubkey] ?? 0) + 1;
            }
            groupedByAuthor.clear();
            results.clear();
          }));
          break;
      }
    }
    
    operationIndex++;
    
    // Wait for all scalability operations
    Future.wait(futures);
  }
}

/// Benchmark for concurrent subscription management.
/// 
/// Tests concurrent subscription operations including subscription
/// creation, modification, and cleanup under load.  
class ConcurrentSubscriptionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> subscriptionFilters;
  final Map<String, List<Filter>> activeSubscriptions = {};
  int operationIndex = 0;
  final BenchmarkConfig config;

  ConcurrentSubscriptionBenchmark(this.config) : super('ConcurrentSubscription');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();  
    eventStore = EventStore();
    
    // Pre-populate with data for subscriptions
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 5, 10000),
      kinds: [1, 6, 7],
      contentSize: 150,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create diverse subscription filters
    final authors = testEvents.take(50).map((e) => e.pubkey).toList();
    
    subscriptionFilters = [
      Filter(kinds: [1], limit: 100),
      Filter(kinds: [6], limit: 50),
      Filter(kinds: [7], limit: 200),
      Filter(authors: authors.take(5).toList(), limit: 100),
      Filter(authors: authors.skip(5).take(10).toList(), limit: 200),
      Filter(kinds: [1, 6], limit: 300),
      Filter(
        kinds: [1],
        since: DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
        limit: 500,
      ),
    ];
  }

  @override
  Future<void> teardown() async {
    activeSubscriptions.clear();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate concurrent subscription operations
    final futures = <Future>[];
    
    // Create/modify subscriptions concurrently
    for (int i = 0; i < 5; i++) {
      final subscriptionId = 'concurrent_sub_${operationIndex}_$i';
      final filter = subscriptionFilters[i % subscriptionFilters.length];
      
      // Simulate subscription query
      futures.add(eventStore.queryEvents([filter]).then((results) {
        // Store subscription state
        activeSubscriptions[subscriptionId] = [filter];
        
        // Simulate subscription processing
        for (final event in results) {
          final _ = event.kind;
        }
        
        results.clear();
        return subscriptionId;
      }));
    }
    
    // Simulate subscription cleanup for older subscriptions
    if (activeSubscriptions.length > 20) {
      final oldSubscriptions = activeSubscriptions.keys.take(5).toList();
      for (final subId in oldSubscriptions) {
        activeSubscriptions.remove(subId);
      }
    }
    
    operationIndex++;
    
    // Wait for all subscription operations
    Future.wait(futures);
  }
}