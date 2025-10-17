// ABOUTME: Event insertion rate benchmarks for single and batch operations
// ABOUTME: Tests insertion performance with various event types and batch sizes

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/models/nostr_event.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for single event insertion performance.
/// 
/// Measures the time to insert individual events one by one,
/// including all validation, indexing, and tag processing overhead.
/// This represents the baseline performance for real-time event insertion.
class SingleEventInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  SingleEventInsertionBenchmark(this.config) : super('SingleEventInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate diverse test events
    testEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 6, 7],
      contentSize: 280, // Twitter-like size
    );
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = testEvents[eventIndex % testEvents.length];
    eventIndex++;
    
    // Create unique event to avoid duplicates
    final uniqueEvent = event.copyWith(
      content: '${event.content} #$eventIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
  }
}

/// Benchmark for batch event insertion performance.
/// 
/// Tests bulk insertion performance with various batch sizes,
/// which is critical for sync operations and initial data loading.
class BatchEventInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<List<NostrEvent>> eventBatches;
  int batchIndex = 0;
  final BenchmarkConfig config;

  BatchEventInsertionBenchmark(this.config) : super('BatchEventInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate events for batching
    final allEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [0, 1, 3, 6, 7],
      contentSize: 200,
    );
    
    // Create batches of optimal sizes
    eventBatches = [];
    const batchSizes = [50, 100, 250, 500, 1000];
    
    for (final batchSize in batchSizes) {
      for (int i = 0; i < allEvents.length; i += batchSize) {
        final batch = allEvents.skip(i).take(batchSize).toList();
        if (batch.isNotEmpty) {
          eventBatches.add(batch);
        }
        if (eventBatches.length >= 100) break; // Limit for benchmark
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

/// Benchmark for concurrent event insertion.
/// 
/// Tests insertion performance when multiple operations happen
/// simultaneously, measuring database lock contention and throughput.
class ConcurrentInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  ConcurrentInsertionBenchmark(this.config) : super('ConcurrentInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    testEvents = BenchmarkUtils.generateTestEvents(
      count: config.eventCount,
      kinds: [1, 6, 7],
      contentSize: 150,
    );
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate concurrent insertions by running multiple operations
    final futures = <Future>[];
    
    for (int i = 0; i < 5; i++) { // 5 concurrent operations
      final event = testEvents[(eventIndex + i) % testEvents.length];
      final uniqueEvent = event.copyWith(
        content: '${event.content} #${eventIndex + i}',
      );
      
      futures.add(eventStore.storeEvent(uniqueEvent));
    }
    
    eventIndex += 5;
    
    // Wait for all concurrent operations to complete
    Future.wait(futures);
  }
}

/// Benchmark for large event insertion performance.
/// 
/// Tests insertion performance with events containing large content
/// and many tags, representing complex events like long-form articles.
class LargeEventInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> largeEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  LargeEventInsertionBenchmark(this.config) : super('LargeEventInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate large events with substantial content and many tags
    largeEvents = [];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 1000); i++) {
      // Generate large content (article-sized)
      final contentWords = List.generate(500 + random.nextInt(1500), 
          (j) => 'word$j');
      final content = contentWords.join(' ');
      
      // Generate many tags
      final tags = <List<String>>[];
      
      // Topic tags
      for (int j = 0; j < 5 + random.nextInt(10); j++) {
        tags.add(['t', 'topic$j']);
      }
      
      // Mention tags
      for (int j = 0; j < 3 + random.nextInt(7); j++) {
        tags.add(['p', 'author$j'.padRight(64, '0')]);
      }
      
      // Custom tags
      for (int j = 0; j < random.nextInt(5); j++) {
        tags.add(['custom$j', 'value$j', 'extra$j']);
      }
      
      final event = NostrEvent.create(
        pubkey: 'large_author$i'.padRight(64, '0'),
        kind: 30023, // Long-form content
        tags: tags,
        content: content,
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'large_sig_$i'.padRight(128, '0'),
      );
      
      largeEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = largeEvents[eventIndex % largeEvents.length];
    eventIndex++;
    
    // Create unique event to avoid duplicates
    final uniqueEvent = event.copyWith(
      content: '${event.content} #$eventIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
  }
}

/// Benchmark for replaceable event insertion performance.
/// 
/// Tests the performance of replaceable event logic, including
/// the overhead of finding and marking older events as deleted.
class ReplaceableEventInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> replaceableEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  ReplaceableEventInsertionBenchmark(this.config) : super('ReplaceableEventInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate replaceable events that will trigger replacement logic
    final authors = List.generate(100, (i) => 
        'repl_author$i'.padRight(64, '0'));
    
    replaceableEvents = [];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 5000); i++) {
      final author = authors[i % authors.length];
      final isParameterized = i % 2 == 0;
      
      if (isParameterized) {
        // Parameterized replaceable events (30000-39999)
        final dTag = 'item_${i % 50}'; // Some d-tags repeat for replacement
        
        final event = NostrEvent.create(
          pubkey: author,
          kind: 30000 + (i % 100),
          tags: [['d', dTag], ['title', 'Item $i']],
          content: 'Parameterized replaceable event $i',
          createdAt: DateTime.now().subtract(
            Duration(minutes: random.nextInt(1440))
          ).millisecondsSinceEpoch ~/ 1000,
        ).copyWith(
          sig: 'param_sig_$i'.padRight(128, '0'),
        );
        
        replaceableEvents.add(event);
      } else {
        // Regular replaceable events (10000-19999)
        final event = NostrEvent.create(
          pubkey: author,
          kind: 10000 + (i % 100),
          tags: [['type', 'replaceable']],
          content: 'Regular replaceable event $i',
          createdAt: DateTime.now().subtract(
            Duration(minutes: random.nextInt(1440))
          ).millisecondsSinceEpoch ~/ 1000,
        ).copyWith(
          sig: 'reg_sig_$i'.padRight(128, '0'),
        );
        
        replaceableEvents.add(event);
      }
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

/// Benchmark for mixed event type insertion performance.
/// 
/// Tests insertion performance with a realistic mix of different
/// event kinds, including regular, replaceable, and ephemeral events.
class MixedEventInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> mixedEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  MixedEventInsertionBenchmark(this.config) : super('MixedEventInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate realistic mix of events
    mixedEvents = [];
    final random = Random(42);
    final authors = List.generate(200, (i) => 
        'mixed_author$i'.padRight(64, '0'));
    
    // Event type distribution based on real-world usage
    final eventTypes = [
      {'kind': 1, 'weight': 70},     // Text notes - most common
      {'kind': 6, 'weight': 15},     // Reposts
      {'kind': 7, 'weight': 10},     // Reactions
      {'kind': 0, 'weight': 2},      // Metadata (replaceable)
      {'kind': 3, 'weight': 1},      // Contacts (replaceable)
      {'kind': 10000, 'weight': 1},  // Replaceable
      {'kind': 30023, 'weight': 1},  // Parameterized replaceable
    ];
    
    for (int i = 0; i < min(config.eventCount, 10000); i++) {
      // Select event type based on weights
      final rand = random.nextInt(100);
      int cumulative = 0;
      int selectedKind = 1;
      
      for (final eventType in eventTypes) {
        cumulative += eventType['weight'] as int;
        if (rand < cumulative) {
          selectedKind = eventType['kind'] as int;
          break;
        }
      }
      
      final author = authors[i % authors.length];
      final tags = <List<String>>[];
      String content = 'Mixed event $i of kind $selectedKind';
      
      // Add kind-specific tags and content
      switch (selectedKind) {
        case 1: // Text note
          if (random.nextDouble() < 0.3) {
            tags.add(['t', 'topic${random.nextInt(50)}']);
          }
          if (random.nextDouble() < 0.2) {
            tags.add(['p', authors[random.nextInt(authors.length)]]);
          }
          break;
          
        case 6: // Repost
          tags.add(['e', 'original_event_$i'.padRight(64, '0')]);
          tags.add(['p', authors[random.nextInt(authors.length)]]);
          content = '';
          break;
          
        case 7: // Reaction
          tags.add(['e', 'target_event_$i'.padRight(64, '0')]);
          tags.add(['p', authors[random.nextInt(authors.length)]]);
          content = ['+', '-', '❤️', '🤙', '🔥'][random.nextInt(5)];
          break;
          
        case 0: // Metadata
          content = json.encode({
            'name': 'User $i',
            'about': 'Bio for user $i',
            'picture': 'https://example.com/avatar$i.jpg',
          });
          break;
          
        case 3: // Contacts
          final contacts = authors.take(10 + random.nextInt(40))
              .map((pubkey) => ['p', pubkey]).toList();
          tags.addAll(contacts);
          content = '';
          break;
          
        case 30023: // Long-form content
          tags.add(['d', 'article_${i % 20}']);
          tags.add(['title', 'Article $i']);
          content = 'Long-form content for article $i. ' * 20;
          break;
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: selectedKind,
        tags: tags,
        content: content,
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'mixed_sig_$i'.padRight(128, '0'),
      );
      
      mixedEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = mixedEvents[eventIndex % mixedEvents.length];
    eventIndex++;
    
    // Create unique event to avoid duplicates
    final uniqueEvent = event.copyWith(
      content: '${event.content} #$eventIndex',
    );
    
    eventStore.storeEvent(uniqueEvent);
  }
}

/// Benchmark for high-frequency insertion performance.
/// 
/// Tests insertion performance under high-frequency scenarios,
/// simulating rapid event creation during peak usage periods.
class HighFrequencyInsertionBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> rapidEvents;
  int eventIndex = 0;
  final BenchmarkConfig config;

  HighFrequencyInsertionBenchmark(this.config) : super('HighFrequencyInsertion');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Generate small, simple events for rapid insertion
    rapidEvents = [];
    final authors = List.generate(50, (i) => 
        'rapid_author$i'.padRight(64, '0'));
    
    for (int i = 0; i < min(config.eventCount, 5000); i++) {
      final event = NostrEvent.create(
        pubkey: authors[i % authors.length],
        kind: 1,
        tags: [], // Minimal tags for speed
        content: 'Rapid event $i', // Short content
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'rapid_sig_$i'.padRight(128, '0'),
      );
      
      rapidEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Insert multiple events in rapid succession
    for (int i = 0; i < 10; i++) {
      final event = rapidEvents[(eventIndex + i) % rapidEvents.length];
      final uniqueEvent = event.copyWith(
        content: '${event.content} #${eventIndex + i}',
      );
      
      eventStore.storeEvent(uniqueEvent);
    }
    
    eventIndex += 10;
  }
}