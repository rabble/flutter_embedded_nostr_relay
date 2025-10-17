// ABOUTME: Garbage collection impact benchmarks and database maintenance performance
// ABOUTME: Tests GC effects on performance and database cleanup efficiency

import 'dart:async';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/models/nostr_event.dart';
import '../../lib/src/models/filter.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for garbage collection performance impact.
/// 
/// Tests how garbage collection events affect database operation
/// performance by creating memory pressure and measuring timing variations.
class GarbageCollectionPerformanceBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> gcTestEvents;
  final List<List<String>> _memoryPressure = [];
  int operationIndex = 0;
  final BenchmarkConfig config;

  GarbageCollectionPerformanceBenchmark(this.config) : super('GarbageCollectionPerformance');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-populate with baseline data
    gcTestEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 2000),
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    await eventStore.storeEvents(gcTestEvents.take(1000).toList());
  }

  @override
  Future<void> teardown() async {
    _memoryPressure.clear();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Create memory pressure to trigger GC
    if (_memoryPressure.length < 20) {
      final memoryHog = List.generate(1000, (i) => 
          'gc_pressure_string_${operationIndex}_$i');
      _memoryPressure.add(memoryHog);
    }
    
    // Perform database operations while GC may be triggered
    final event = gcTestEvents[operationIndex % gcTestEvents.length];
    final uniqueEvent = event.copyWith(
      content: '${event.content} gc_test#$operationIndex',
    );
    
    // Store event (this may be affected by GC timing)
    eventStore.storeEvent(uniqueEvent);
    
    // Query operation (also affected by GC)
    final results = eventStore.queryEvents([
      Filter(kinds: [1], limit: 100)
    ]);
    
    // Process results while creating more GC pressure
    final processed = <String>[];
    for (final result in results) {
      processed.add('processed_${result.id}');
    }
    
    // Clean up some memory pressure periodically
    if (operationIndex % 25 == 0 && _memoryPressure.isNotEmpty) {
      _memoryPressure.removeAt(0);
    }
    
    // Create more temporary objects
    final temp = List.generate(100, (i) => 'temp_${operationIndex}_$i');
    temp.clear();
    processed.clear();
    results.clear();
    
    operationIndex++;
  }
}

/// Benchmark for garbage collection impact on query performance.
/// 
/// Measures how GC events specifically affect query latency and throughput
/// by running queries during controlled memory pressure scenarios.  
class GarbageCollectionImpactBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<Filter> impactTestFilters;
  final List<Map<String, dynamic>> _garbageObjects = [];
  int queryIndex = 0;
  final BenchmarkConfig config;

  GarbageCollectionImpactBenchmark(this.config) : super('GarbageCollectionImpact');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Create large dataset for GC impact testing
    final testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 20000),
      kinds: [1, 6, 7],
      contentSize: 300,
    );
    
    await eventStore.storeEvents(testEvents);
    
    // Create filters that return different result sizes
    impactTestFilters = [
      Filter(kinds: [1], limit: 50),
      Filter(kinds: [1], limit: 200),
      Filter(kinds: [1], limit: 500),
      Filter(kinds: [1], limit: 1000),
      Filter(kinds: [1, 6, 7], limit: 2000),
    ];
  }

  @override
  Future<void> teardown() async {
    _garbageObjects.clear();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Create garbage objects to trigger GC at various points
    final garbageSize = 500 + queryIndex % 1000;
    final garbage = <String, dynamic>{};
    
    for (int i = 0; i < garbageSize; i++) {
      garbage['key_$i'] = 'garbage_value_${queryIndex}_$i';
    }
    
    _garbageObjects.add(garbage);
    
    // Keep garbage objects around to create memory pressure
    if (_garbageObjects.length > 50) {
      _garbageObjects.removeRange(0, 10);
    }
    
    // Execute query during potential GC
    final filter = impactTestFilters[queryIndex % impactTestFilters.length];
    final results = eventStore.queryEvents([filter]);
    
    // Process results and create more GC pressure
    final processedData = <String, List<String>>{};
    
    for (final event in results) {
      final authorData = processedData[event.pubkey] ?? <String>[];
      authorData.add('${event.content.substring(0, min(20, event.content.length))}_processed');
      processedData[event.pubkey] = authorData;
    }
    
    // Create additional temporary objects during processing
    final tempProcessing = List.generate(200, (i) => 
        'temp_processing_${queryIndex}_$i');
    
    // Simulate complex processing that allocates memory
    final complexData = processedData.entries.map((entry) {
      return {
        'author': entry.key,
        'events': entry.value,
        'metadata': 'processed_at_$queryIndex',
      };
    }).toList();
    
    // Clear temporary data
    tempProcessing.clear();
    complexData.clear();
    processedData.clear();
    results.clear();
    
    queryIndex++;
  }
}

/// Benchmark for database vacuum operation performance.
/// 
/// Tests the performance and impact of database VACUUM operations
/// on a database with fragmentation and deleted events.
class DatabaseVacuumBenchmark extends BenchmarkBase {
  late DatabaseHelper databaseHelper;
  late EventStore eventStore;
  int vacuumIndex = 0;
  final BenchmarkConfig config;

  DatabaseVacuumBenchmark(this.config) : super('DatabaseVacuum');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    databaseHelper = DatabaseHelper.instance;
    eventStore = EventStore();
    
    // Create substantial database content with fragmentation
    final initialEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 10000),
      kinds: [0, 1, 3, 6, 7, 10000, 30000],
      contentSize: 400,
    );
    
    await eventStore.storeEvents(initialEvents);
    
    // Create fragmentation by deleting various events
    final eventIds = initialEvents.take(initialEvents.length ~/ 3)
        .map((e) => e.id).toList();
    await eventStore.deleteEvents(eventIds);
    
    // Add more events to create mixed deleted/active pattern
    final additionalEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 2, 5000),
      kinds: [1, 6, 7],
      contentSize: 250,
    );
    
    await eventStore.storeEvents(additionalEvents);
    
    // Delete some of the additional events to create more fragmentation
    final moreDeleteIds = additionalEvents.take(additionalEvents.length ~/ 4)
        .map((e) => e.id).toList();
    await eventStore.deleteEvents(moreDeleteIds);
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Execute vacuum operation
    databaseHelper.vacuum();
    
    vacuumIndex++;
    
    // Simulate post-vacuum activity to measure impact
    if (vacuumIndex % 5 == 0) {
      // Add some events after vacuum to test performance
      final postVacuumEvents = BenchmarkUtils.generateTestEvents(
        count: 100,
        kinds: [1],
        contentSize: 150,
      );
      
      eventStore.storeEvents(postVacuumEvents);
      
      // Test query performance post-vacuum
      eventStore.queryEvents([Filter(kinds: [1], limit: 200)]);
    }
  }
}

/// Benchmark for database maintenance operations.
/// 
/// Tests various database maintenance operations including
/// statistics updates, index rebuilding, and integrity checks.
class DatabaseMaintenanceBenchmark extends BenchmarkBase {
  late DatabaseHelper databaseHelper;
  late EventStore eventStore;
  int maintenanceIndex = 0;
  final BenchmarkConfig config;

  DatabaseMaintenanceBenchmark(this.config) : super('DatabaseMaintenance');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    databaseHelper = DatabaseHelper.instance;
    eventStore = EventStore();
    
    // Create large dataset for maintenance testing
    final maintenanceEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount, 15000),
      kinds: [0, 1, 3, 6, 7, 10000, 30000],
      contentSize: 350,
    );
    
    await eventStore.storeEvents(maintenanceEvents);
    
    // Create some database activity patterns
    final queryResults = await eventStore.queryEvents([
      Filter(kinds: [1], limit: 2000)
    ]);
    queryResults.clear();
    
    // Create and delete some events to simulate normal operations
    final tempEvents = BenchmarkUtils.generateTestEvents(
      count: 1000,
      kinds: [1, 6, 7],
      contentSize: 200,
    );
    
    await eventStore.storeEvents(tempEvents);
    
    final deleteIds = tempEvents.take(300).map((e) => e.id).toList();
    await eventStore.deleteEvents(deleteIds);
  }

  @override
  Future<void> teardown() async {
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final operationType = maintenanceIndex % 4;
    
    switch (operationType) {
      case 0:
        // Vacuum operation
        databaseHelper.vacuum();
        break;
        
      case 1:
        // Statistics gathering simulation
        _gatherStatistics();
        break;
        
      case 2:
        // Index analysis simulation  
        _analyzeIndexes();
        break;
        
      case 3:
        // Integrity check simulation
        _integrityCheck();
        break;
    }
    
    maintenanceIndex++;
  }

  void _gatherStatistics() {
    // Simulate database statistics gathering
    final stats = databaseHelper.getStats();
    
    // Process statistics
    final eventCount = stats['event_count'] ?? 0;
    final tagCount = stats['tag_count'] ?? 0;
    
    // Simulate statistics processing work
    final processingWork = eventCount + tagCount;
  }

  void _analyzeIndexes() {
    // Simulate index analysis work
    // In a real implementation, this would involve EXPLAIN QUERY PLAN analysis
    
    final queries = [
      'SELECT COUNT(*) FROM events WHERE kind = 1',
      'SELECT COUNT(*) FROM events WHERE pubkey = ?',
      'SELECT COUNT(*) FROM tags WHERE tag_name = "p"',
      'SELECT COUNT(*) FROM events WHERE created_at > ?',
    ];
    
    // Simulate analyzing query plans
    for (final query in queries) {
      final analysisWork = query.length; // Simplified work simulation
    }
  }

  void _integrityCheck() {
    // Simulate database integrity checking
    // This would normally involve foreign key checks, constraint validation, etc.
    
    final checks = [
      'Check event ID consistency',
      'Check tag references',
      'Check deleted event constraints',
      'Check timestamp validity',
    ];
    
    for (final check in checks) {
      final checkWork = check.hashCode; // Simplified work simulation
    }
  }
}

/// Benchmark for memory management during long-running operations.
/// 
/// Tests memory behavior during extended operation periods to detect
/// memory leaks and measure garbage collection frequency.
class LongRunningMemoryBenchmark extends BenchmarkBase {
  late EventStore eventStore;
  late List<NostrEvent> longRunEvents;
  final List<Map<String, dynamic>> _accumulatedData = [];
  int operationCycle = 0;
  final BenchmarkConfig config;

  LongRunningMemoryBenchmark(this.config) : super('LongRunningMemory');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    
    // Pre-populate with baseline data
    longRunEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 5, 5000),
      kinds: [1, 6, 7],
      contentSize: 250,
    );
    
    await eventStore.storeEvents(longRunEvents.take(2000).toList());
  }

  @override
  Future<void> teardown() async {
    _accumulatedData.clear();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    // Simulate long-running operation cycles
    final cycleType = operationCycle % 6;
    
    switch (cycleType) {
      case 0: // Insert operations
        for (int i = 0; i < 10; i++) {
          final event = longRunEvents[(operationCycle + i) % longRunEvents.length];
          final uniqueEvent = event.copyWith(
            content: '${event.content} longrun#${operationCycle}_$i',
          );
          eventStore.storeEvent(uniqueEvent);
        }
        break;
        
      case 1: // Query operations
        final results = eventStore.queryEvents([
          Filter(kinds: [1], limit: 200)
        ]);
        
        // Accumulate some data (potential memory leak simulation)
        final processedResults = results.map((e) => {
          'id': e.id,
          'author': e.pubkey,
          'timestamp': e.createdAt,
          'processed_at': operationCycle,
        }).toList();
        
        _accumulatedData.addAll(processedResults);
        results.clear();
        break;
        
      case 2: // Batch operations
        final batchSize = 25;
        final batch = <NostrEvent>[];
        
        for (int i = 0; i < batchSize; i++) {
          final event = longRunEvents[(operationCycle * batchSize + i) % longRunEvents.length];
          batch.add(event.copyWith(
            content: '${event.content} batch_longrun#${operationCycle}_$i',
          ));
        }
        
        eventStore.storeEvents(batch);
        break;
        
      case 3: // Complex queries
        final complexResults = eventStore.queryEvents([
          Filter(kinds: [1, 6], limit: 500),
          Filter(kinds: [7], limit: 300),
        ]);
        
        // Complex processing
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final event in complexResults) {
          final authorData = grouped[event.pubkey] ?? <Map<String, dynamic>>[];
          authorData.add({
            'event_id': event.id,
            'kind': event.kind,
            'content_length': event.content.length,
            'cycle': operationCycle,
          });
          grouped[event.pubkey] = authorData;
        }
        
        // Store some results (simulating memory accumulation)
        if (grouped.isNotEmpty) {
          _accumulatedData.add({
            'cycle': operationCycle,
            'authors': grouped.keys.length,
            'total_events': complexResults.length,
          });
        }
        
        complexResults.clear();
        break;
        
      case 4: // Memory cleanup cycle
        if (_accumulatedData.length > 1000) {
          _accumulatedData.removeRange(0, 500);
        }
        
        // Force some temporary allocations and cleanup
        final temp = List.generate(1000, (i) => 'cleanup_temp_${operationCycle}_$i');
        temp.clear();
        break;
        
      case 5: // Mixed operations
        // Insert
        final event = longRunEvents[operationCycle % longRunEvents.length];
        eventStore.storeEvent(event.copyWith(
          content: '${event.content} mixed#$operationCycle',
        ));
        
        // Query
        final quickResults = eventStore.queryEvents([
          Filter(kinds: [1], limit: 50)
        ]);
        
        // Process and discard
        final quickProcessed = quickResults.length;
        quickResults.clear();
        
        // Small memory allocation
        final smallTemp = List.generate(100, (i) => 'mixed_$i');
        smallTemp.clear();
        break;
    }
    
    operationCycle++;
    
    // Periodic forced cleanup
    if (operationCycle % 100 == 0) {
      _accumulatedData.clear();
      
      // Create and immediately discard objects to hint at GC
      final gcHint = List.generate(2000, (i) => 'gc_hint_$i');
      gcHint.clear();
    }
  }
}