// ABOUTME: Performance integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests throughput, latency, memory usage, and performance under various load conditions

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/core/embedded_nostr_relay.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PerformanceMetrics {
  final DateTime startTime;
  final DateTime endTime;
  final int operationCount;
  final int bytesProcessed;
  final Map<String, dynamic> additionalMetrics;

  PerformanceMetrics({
    required this.startTime,
    required this.endTime,
    required this.operationCount,
    this.bytesProcessed = 0,
    this.additionalMetrics = const {},
  });

  Duration get duration => endTime.difference(startTime);
  double get operationsPerSecond => operationCount / duration.inMilliseconds * 1000;
  double get megabytesPerSecond => bytesProcessed / duration.inMilliseconds * 1000 / (1024 * 1024);

  @override
  String toString() {
    return 'PerformanceMetrics(\n'
        '  duration: ${duration.inMilliseconds}ms\n'
        '  operations: $operationCount\n'
        '  ops/sec: ${operationsPerSecond.toStringAsFixed(2)}\n'
        '  MB/sec: ${megabytesPerSecond.toStringAsFixed(2)}\n'
        '  additional: $additionalMetrics\n'
        ')';
  }
}

class LoadTestClient {
  final WebSocketChannel channel;
  final String id;
  final List<String> responses = [];
  final Completer<void> _readyCompleter = Completer<void>();
  bool _isReady = false;
  int _expectedMessages = 0;
  final Completer<void> _allMessagesReceived = Completer<void>();

  LoadTestClient(this.channel, this.id) {
    channel.stream.listen(
      (message) {
        responses.add(message);
        if (responses.length >= _expectedMessages && !_allMessagesReceived.isCompleted) {
          _allMessagesReceived.complete();
        }
      },
      onDone: () {
        if (!_allMessagesReceived.isCompleted) {
          _allMessagesReceived.complete();
        }
      },
    );
  }

  void send(dynamic message) {
    channel.sink.add(json.encode(message));
  }

  void markReady() {
    _isReady = true;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  void expectMessages(int count) {
    _expectedMessages = count;
    if (responses.length >= count && !_allMessagesReceived.isCompleted) {
      _allMessagesReceived.complete();
    }
  }

  Future<void> waitForReady() => _readyCompleter.future;
  Future<void> waitForAllMessages() => _allMessagesReceived.future;

  Future<void> close() async {
    await channel.sink.close();
  }

  int get messageCount => responses.length;
  
  List<Map<String, dynamic>> getEventMessages() {
    return responses
        .where((response) {
          final parsed = json.decode(response) as List;
          return parsed[0] == 'EVENT';
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return parsed[2] as Map<String, dynamic>;
        })
        .toList();
  }
}

void main() {
  group('Performance Integration Tests', () {
    late WebSocketServer server;
    late SubscriptionManager subscriptionManager;
    late EventStore eventStore;
    late DatabaseHelper databaseHelper;
    
    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    
    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      databaseHelper = DatabaseHelper.instance;
      eventStore = EventStore(databaseHelper: databaseHelper);
      subscriptionManager = SubscriptionManager();
      
      server = WebSocketServer(
        subscriptionManager: subscriptionManager,
        eventStore: eventStore,
      );
      
      await server.start(port: 0);
    });
    
    tearDown(() async {
      await server.stop();
      await subscriptionManager.close();
      await DatabaseHelper.reset();
    });

    Future<LoadTestClient> createLoadTestClient(String id) async {
      final channel = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );
      return LoadTestClient(channel, id);
    }

    NostrEvent createTestEvent({
      required String pubkey,
      required int index,
      int kind = 1,
      List<List<String>>? tags,
      String? content,
    }) {
      return NostrEvent.create(
        pubkey: pubkey,
        kind: kind,
        tags: tags ?? [['t', 'performance'], ['index', index.toString()]],
        content: content ?? 'Performance test event $index',
      ).copyWith(
        sig: 'perf_sig_$index' + '1' * (120 - 'perf_sig_$index'.length),
      );
    }

    group('Throughput Tests', () {
      test('should handle high-volume event publishing', () async {
        const int eventCount = 1000;
        const int batchSize = 100;
        
        final client = await createLoadTestClient('throughput-publisher');
        final monitor = await createLoadTestClient('throughput-monitor');
        
        try {
          // Monitor subscribes to all events
          monitor.send(['REQ', 'monitor', {'kinds': [1], 'limit': eventCount + 100}]);
          await Future.delayed(Duration(milliseconds: 50));
          monitor.expectMessages(eventCount + 1); // events + EOSE
          
          final startTime = DateTime.now();
          int totalBytes = 0;
          
          // Publish events in batches
          for (int batch = 0; batch < eventCount ~/ batchSize; batch++) {
            final batchEvents = <NostrEvent>[];
            
            for (int i = 0; i < batchSize; i++) {
              final eventIndex = batch * batchSize + i;
              final event = createTestEvent(
                pubkey: 'throughput_author' + '0' * (64 - 'throughput_author'.length),
                index: eventIndex,
                content: 'High volume event $eventIndex with some additional content to test throughput',
              );
              batchEvents.add(event);
            }
            
            // Send batch
            for (final event in batchEvents) {
              final eventMessage = json.encode(['EVENT', event.toJson()]);
              totalBytes += eventMessage.length;
              client.send(['EVENT', event.toJson()]);
            }
            
            // Small delay between batches to avoid overwhelming
            await Future.delayed(Duration(milliseconds: 10));
          }
          
          // Wait for all messages to be processed
          await monitor.waitForAllMessages().timeout(Duration(seconds: 30));
          
          final endTime = DateTime.now();
          
          final metrics = PerformanceMetrics(
            startTime: startTime,
            endTime: endTime,
            operationCount: eventCount,
            bytesProcessed: totalBytes,
            additionalMetrics: {
              'eventsReceived': monitor.getEventMessages().length,
              'serverStats': server.getStatistics(),
            },
          );
          
          print('Throughput Test Results: $metrics');
          
          // Performance assertions
          expect(metrics.operationsPerSecond, greaterThan(100), 
                 reason: 'Should handle at least 100 events per second');
          expect(monitor.getEventMessages().length, equals(eventCount),
                 reason: 'All events should be received by monitor');
          
        } finally {
          await client.close();
          await monitor.close();
        }
      });

      test('should handle concurrent publishing from multiple clients', () async {
        const int clientCount = 10;
        const int eventsPerClient = 100;
        const int totalEvents = clientCount * eventsPerClient;
        
        final publishers = <LoadTestClient>[];
        final monitor = await createLoadTestClient('concurrent-monitor');
        
        try {
          // Create publisher clients
          for (int i = 0; i < clientCount; i++) {
            publishers.add(await createLoadTestClient('publisher-$i'));
          }
          
          // Monitor subscribes to all events
          monitor.send(['REQ', 'concurrent-monitor', {'kinds': [1], 'limit': totalEvents + 100}]);
          await Future.delayed(Duration(milliseconds: 100));
          monitor.expectMessages(totalEvents + 1); // events + EOSE
          
          final startTime = DateTime.now();
          
          // All clients publish concurrently
          final publishFutures = <Future>[];
          
          for (int clientIndex = 0; clientIndex < clientCount; clientIndex++) {
            publishFutures.add(() async {
              final client = publishers[clientIndex];
              final pubkey = 'concurrent_$clientIndex' + '0' * (64 - 'concurrent_$clientIndex'.length);
              
              for (int eventIndex = 0; eventIndex < eventsPerClient; eventIndex++) {
                final event = createTestEvent(
                  pubkey: pubkey,
                  index: eventIndex,
                  content: 'Concurrent event from client $clientIndex, event $eventIndex',
                );
                
                client.send(['EVENT', event.toJson()]);
                
                // Random small delay to simulate real-world timing
                if (eventIndex % 10 == 0) {
                  await Future.delayed(Duration(milliseconds: Random().nextInt(5)));
                }
              }
            }());
          }
          
          await Future.wait(publishFutures);
          
          // Wait for all events to be processed
          await monitor.waitForAllMessages().timeout(Duration(seconds: 45));
          
          final endTime = DateTime.now();
          
          final metrics = PerformanceMetrics(
            startTime: startTime,
            endTime: endTime,
            operationCount: totalEvents,
            additionalMetrics: {
              'clientCount': clientCount,
              'eventsPerClient': eventsPerClient,
              'eventsReceived': monitor.getEventMessages().length,
              'activeConnections': server.activeConnections,
            },
          );
          
          print('Concurrent Publishing Test Results: $metrics');
          
          // Performance assertions
          expect(metrics.operationsPerSecond, greaterThan(50),
                 reason: 'Should handle at least 50 concurrent ops per second');
          expect(monitor.getEventMessages().length, equals(totalEvents),
                 reason: 'All events should be received');
          
        } finally {
          for (final publisher in publishers) {
            await publisher.close();
          }
          await monitor.close();
        }
      });
    });

    group('Query Performance Tests', () {
      test('should handle large dataset queries efficiently', () async {
        const int datasetSize = 5000;
        const int batchSize = 500;
        
        final setupClient = await createLoadTestClient('setup-client');
        
        try {
          // Populate large dataset
          print('Setting up dataset of $datasetSize events...');
          
          final authors = <String>[];
          for (int i = 0; i < 20; i++) {
            authors.add('author$i' + '0' * (64 - 'author$i'.length));
          }
          
          for (int batch = 0; batch < datasetSize ~/ batchSize; batch++) {
            for (int i = 0; i < batchSize; i++) {
              final eventIndex = batch * batchSize + i;
              final event = createTestEvent(
                pubkey: authors[eventIndex % authors.length],
                index: eventIndex,
                kind: (eventIndex % 5) + 1, // Kinds 1-5
                tags: [
                  ['t', 'dataset'],
                  ['category', (eventIndex % 10).toString()],
                  ['batch', batch.toString()],
                ],
                content: 'Dataset event $eventIndex with searchable content for testing query performance',
              );
              
              setupClient.send(['EVENT', event.toJson()]);
            }
            
            if (batch % 5 == 0) {
              await Future.delayed(Duration(milliseconds: 50));
            }
          }
          
          // Wait for all events to be stored
          await Future.delayed(Duration(seconds: 5));
          
          print('Dataset setup complete. Starting query performance tests...');
          
          // Test various query patterns
          final queryClient = await createLoadTestClient('query-client');
          
          final queryTests = [
            {
              'name': 'Query by kind',
              'filter': {'kinds': [1], 'limit': 1000},
              'expectedMin': 800,
            },
            {
              'name': 'Query by author',
              'filter': {'authors': [authors[0]], 'limit': 500},
              'expectedMin': 200,
            },
            {
              'name': 'Query by tag',
              'filter': {'#t': ['dataset'], 'limit': 2000},
              'expectedMin': 1500,
            },
            {
              'name': 'Complex query',
              'filter': {
                'kinds': [1, 2, 3],
                '#category': ['1', '2', '3'],
                'limit': 500
              },
              'expectedMin': 100,
            },
            {
              'name': 'Time-range query',
              'filter': {
                'kinds': [1],
                'since': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
                'limit': 1000
              },
              'expectedMin': 800,
            },
          ];
          
          for (final queryTest in queryTests) {
            queryClient.responses.clear();
            
            final startTime = DateTime.now();
            
            queryClient.send(['REQ', 'perf-query', queryTest['filter']]);
            
            // Wait for EOSE
            while (!queryClient.responses.any((r) => json.decode(r)[0] == 'EOSE')) {
              await Future.delayed(Duration(milliseconds: 10));
              
              // Timeout after 5 seconds
              if (DateTime.now().difference(startTime).inSeconds > 5) {
                fail('Query timeout: ${queryTest['name']}');
              }
            }
            
            final endTime = DateTime.now();
            final duration = endTime.difference(startTime);
            
            final eventCount = queryClient.responses
                .where((r) => json.decode(r)[0] == 'EVENT')
                .length;
            
            print('${queryTest['name']}: ${duration.inMilliseconds}ms, $eventCount events');
            
            // Performance assertions
            expect(duration.inMilliseconds, lessThan(2000),
                   reason: '${queryTest['name']} should complete within 2 seconds');
            expect(eventCount, greaterThanOrEqualTo(queryTest['expectedMin']),
                   reason: '${queryTest['name']} should return expected minimum results');
          }
          
          await queryClient.close();
          
        } finally {
          await setupClient.close();
        }
      });

      test('should handle subscription with large result sets efficiently', () async {
        const int eventCount = 2000;
        
        // Pre-populate events
        final setupClient = await createLoadTestClient('large-setup');
        
        try {
          for (int i = 0; i < eventCount; i++) {
            final event = createTestEvent(
              pubkey: 'large_dataset_author' + '0' * (64 - 'large_dataset_author'.length),
              index: i,
              content: 'Large dataset event $i for subscription performance testing',
            );
            
            setupClient.send(['EVENT', event.toJson()]);
            
            if (i % 200 == 0) {
              await Future.delayed(Duration(milliseconds: 50));
            }
          }
          
          await Future.delayed(Duration(seconds: 3));
          
          // Test subscription to large result set
          final subscriberClient = await createLoadTestClient('large-subscriber');
          
          final startTime = DateTime.now();
          
          subscriberClient.send(['REQ', 'large-sub', {
            'kinds': [1],
            '#t': ['performance'],
            'limit': eventCount + 100
          }]);
          
          // Wait for all events and EOSE
          while (true) {
            final hasEose = subscriberClient.responses.any((r) => json.decode(r)[0] == 'EOSE');
            if (hasEose) break;
            
            await Future.delayed(Duration(milliseconds: 50));
            
            // Timeout after 10 seconds
            if (DateTime.now().difference(startTime).inSeconds > 10) {
              fail('Large subscription timeout');
            }
          }
          
          final endTime = DateTime.now();
          final duration = endTime.difference(startTime);
          
          final receivedEvents = subscriberClient.getEventMessages();
          
          final metrics = PerformanceMetrics(
            startTime: startTime,
            endTime: endTime,
            operationCount: receivedEvents.length,
            additionalMetrics: {
              'expectedEvents': eventCount,
              'receivedEvents': receivedEvents.length,
              'memoryUsage': await databaseHelper.getStats(),
            },
          );
          
          print('Large Subscription Test Results: $metrics');
          
          // Performance assertions
          expect(duration.inSeconds, lessThan(8),
                 reason: 'Large subscription should complete within 8 seconds');
          expect(receivedEvents.length, greaterThanOrEqualTo(eventCount * 0.95),
                 reason: 'Should receive at least 95% of events');
          
          await subscriberClient.close();
          
        } finally {
          await setupClient.close();
        }
      });
    });

    group('Memory and Resource Tests', () {
      test('should handle memory efficiently with many concurrent subscriptions', () async {
        const int subscriptionCount = 100;
        const int eventsToPublish = 500;
        
        final subscribers = <LoadTestClient>[];
        final publisher = await createLoadTestClient('memory-publisher');
        
        try {
          // Create many subscribers with different filters
          for (int i = 0; i < subscriptionCount; i++) {
            final subscriber = await createLoadTestClient('subscriber-$i');
            subscribers.add(subscriber);
            
            // Different subscription patterns to stress filter matching
            final filters = [
              {'kinds': [1], 'limit': 100},
              {'kinds': [1, 7], 'limit': 50},
              {'#t': ['memory-test'], 'limit': 75},
              {'authors': ['memory_author' + '0' * (64 - 'memory_author'.length)], 'limit': 60},
            ];
            
            subscriber.send(['REQ', 'memory-sub-$i', filters[i % filters.length]]);
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          final initialStats = await databaseHelper.getStats();
          final initialServerStats = server.getStatistics();
          
          // Publish events that will match various subscriptions
          final startTime = DateTime.now();
          
          for (int i = 0; i < eventsToPublish; i++) {
            final event = createTestEvent(
              pubkey: 'memory_author' + '0' * (64 - 'memory_author'.length),
              index: i,
              tags: [['t', 'memory-test'], ['index', i.toString()]],
              content: 'Memory test event $i with content that tests memory usage patterns',
            );
            
            publisher.send(['EVENT', event.toJson()]);
            
            if (i % 50 == 0) {
              await Future.delayed(Duration(milliseconds: 20));
            }
          }
          
          // Wait for processing
          await Future.delayed(Duration(seconds: 3));
          
          final endTime = DateTime.now();
          final finalStats = await databaseHelper.getStats();
          final finalServerStats = server.getStatistics();
          
          final metrics = PerformanceMetrics(
            startTime: startTime,
            endTime: endTime,
            operationCount: eventsToPublish,
            additionalMetrics: {
              'subscriptionCount': subscriptionCount,
              'initialDbStats': initialStats,
              'finalDbStats': finalStats,
              'initialServerStats': initialServerStats,
              'finalServerStats': finalServerStats,
              'activeConnections': server.activeConnections,
            },
          );
          
          print('Memory Efficiency Test Results: $metrics');
          
          // Performance assertions
          expect(server.activeConnections, equals(subscriptionCount + 1),
                 reason: 'All connections should remain active');
          expect(finalServerStats['totalMessagesReceived'], 
                 greaterThan(initialServerStats['totalMessagesReceived']),
                 reason: 'Server should have processed messages');
          
          // Verify subscribers received events
          int totalEventsReceived = 0;
          for (final subscriber in subscribers) {
            totalEventsReceived += subscriber.getEventMessages().length;
          }
          
          expect(totalEventsReceived, greaterThan(eventsToPublish),
                 reason: 'Total events received should exceed published (due to overlapping subscriptions)');
          
        } finally {
          await publisher.close();
          for (final subscriber in subscribers) {
            await subscriber.close();
          }
        }
      });

      test('should handle database growth and cleanup efficiently', () async {
        const int eventCount = 1000;
        const int batchSize = 100;
        
        final client = await createLoadTestClient('cleanup-client');
        
        try {
          final initialStats = await databaseHelper.getStats();
          
          // Generate events over time
          for (int batch = 0; batch < eventCount ~/ batchSize; batch++) {
            final batchStartTime = DateTime.now();
            
            for (int i = 0; i < batchSize; i++) {
              final eventIndex = batch * batchSize + i;
              
              // Mix of regular and replaceable events
              final isReplaceable = eventIndex % 10 == 0;
              final kind = isReplaceable ? 10000 : 1;
              
              final event = createTestEvent(
                pubkey: 'cleanup_author' + '0' * (64 - 'cleanup_author'.length),
                index: eventIndex,
                kind: kind,
                content: 'Cleanup test event $eventIndex with timestamp ${DateTime.now().millisecondsSinceEpoch}',
              );
              
              client.send(['EVENT', event.toJson()]);
            }
            
            await Future.delayed(Duration(milliseconds: 100));
            
            // Periodically check database growth
            if (batch % 5 == 0) {
              final currentStats = await databaseHelper.getStats();
              print('Batch $batch completed, DB stats: $currentStats');
              
              // Verify reasonable growth
              expect(currentStats['event_count'], greaterThan(initialStats['event_count']));
            }
          }
          
          final finalStats = await databaseHelper.getStats();
          
          print('Database Growth Test - Initial: $initialStats, Final: $finalStats');
          
          // Verify database handled growth efficiently
          expect(finalStats['event_count'], greaterThan(eventCount * 0.9),
                 reason: 'Should store most events (accounting for replaceable events)');
          
          // Test query performance on grown database
          client.responses.clear();
          
          final queryStartTime = DateTime.now();
          client.send(['REQ', 'cleanup-query', {'kinds': [1], 'limit': 500}]);
          
          while (!client.responses.any((r) => json.decode(r)[0] == 'EOSE')) {
            await Future.delayed(Duration(milliseconds: 10));
            
            if (DateTime.now().difference(queryStartTime).inSeconds > 5) {
              fail('Query performance degraded after database growth');
            }
          }
          
          final queryDuration = DateTime.now().difference(queryStartTime);
          print('Query after growth: ${queryDuration.inMilliseconds}ms');
          
          expect(queryDuration.inMilliseconds, lessThan(2000),
                 reason: 'Queries should remain fast after database growth');
          
        } finally {
          await client.close();
        }
      });
    });

    group('Latency Tests', () {
      test('should maintain low latency for real-time event routing', () async {
        const int testIterations = 100;
        
        final publisher = await createLoadTestClient('latency-publisher');
        final subscriber = await createLoadTestClient('latency-subscriber');
        
        try {
          // Subscriber listens for real-time events
          subscriber.send(['REQ', 'latency-sub', {'kinds': [1], 'limit': testIterations + 10}]);
          await Future.delayed(Duration(milliseconds: 100));
          subscriber.responses.clear(); // Clear EOSE
          
          final latencies = <Duration>[];
          
          for (int i = 0; i < testIterations; i++) {
            final sendTime = DateTime.now();
            
            final event = createTestEvent(
              pubkey: 'latency_author' + '0' * (64 - 'latency_author'.length),
              index: i,
              content: 'Latency test event $i sent at ${sendTime.millisecondsSinceEpoch}',
            );
            
            publisher.send(['EVENT', event.toJson()]);
            
            // Wait for subscriber to receive the event
            int initialCount = subscriber.getEventMessages().length;
            while (subscriber.getEventMessages().length <= initialCount) {
              await Future.delayed(Duration(microseconds: 500));
              
              // Timeout after 1 second
              if (DateTime.now().difference(sendTime).inMilliseconds > 1000) {
                fail('Event routing timeout for iteration $i');
              }
            }
            
            final receiveTime = DateTime.now();
            final latency = receiveTime.difference(sendTime);
            latencies.add(latency);
            
            // Small delay between iterations
            await Future.delayed(Duration(milliseconds: 10));
          }
          
          // Calculate latency statistics
          latencies.sort();
          final averageLatency = latencies.map((l) => l.inMicroseconds).reduce((a, b) => a + b) / latencies.length;
          final medianLatency = latencies[latencies.length ~/ 2];
          final p95Latency = latencies[(latencies.length * 0.95).floor()];
          final maxLatency = latencies.last;
          
          print('Latency Test Results:');
          print('  Average: ${(averageLatency / 1000).toStringAsFixed(2)}ms');
          print('  Median: ${medianLatency.inMilliseconds}ms');
          print('  95th percentile: ${p95Latency.inMilliseconds}ms');
          print('  Maximum: ${maxLatency.inMilliseconds}ms');
          
          // Performance assertions
          expect(averageLatency / 1000, lessThan(50),
                 reason: 'Average latency should be under 50ms');
          expect(p95Latency.inMilliseconds, lessThan(100),
                 reason: '95th percentile latency should be under 100ms');
          expect(maxLatency.inMilliseconds, lessThan(500),
                 reason: 'Maximum latency should be under 500ms');
          
        } finally {
          await publisher.close();
          await subscriber.close();
        }
      });
    });

    group('Stress Tests', () {
      test('should remain stable under sustained load', () async {
        const int durationMinutes = 1; // Reduced for testing
        const int publishRatePerSecond = 20;
        const int subscriberCount = 10;
        
        final publisher = await createLoadTestClient('stress-publisher');
        final subscribers = <LoadTestClient>[];
        
        try {
          // Create subscribers
          for (int i = 0; i < subscriberCount; i++) {
            final subscriber = await createLoadTestClient('stress-subscriber-$i');
            subscribers.add(subscriber);
            subscriber.send(['REQ', 'stress-sub-$i', {'kinds': [1], 'limit': 10000}]);
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          final startTime = DateTime.now();
          final endTime = startTime.add(Duration(minutes: durationMinutes));
          
          int eventsSent = 0;
          int errorsEncountered = 0;
          
          while (DateTime.now().isBefore(endTime)) {
            final batchStartTime = DateTime.now();
            
            // Send events at target rate
            for (int i = 0; i < publishRatePerSecond; i++) {
              try {
                final event = createTestEvent(
                  pubkey: 'stress_author' + '0' * (64 - 'stress_author'.length),
                  index: eventsSent,
                  content: 'Stress test event $eventsSent at ${DateTime.now().millisecondsSinceEpoch}',
                );
                
                publisher.send(['EVENT', event.toJson()]);
                eventsSent++;
              } catch (e) {
                errorsEncountered++;
                print('Error sending event $eventsSent: $e');
              }
            }
            
            // Maintain rate by waiting for remainder of second
            final batchDuration = DateTime.now().difference(batchStartTime);
            final remainingTime = Duration(seconds: 1) - batchDuration;
            if (remainingTime.inMilliseconds > 0) {
              await Future.delayed(remainingTime);
            }
          }
          
          final actualDuration = DateTime.now().difference(startTime);
          
          // Wait for final processing
          await Future.delayed(Duration(seconds: 2));
          
          final finalStats = server.getStatistics();
          
          print('Stress Test Results:');
          print('  Duration: ${actualDuration.inSeconds}s');
          print('  Events sent: $eventsSent');
          print('  Errors: $errorsEncountered');
          print('  Average rate: ${eventsSent / actualDuration.inSeconds} events/sec');
          print('  Server stats: $finalStats');
          
          // Stability assertions
          expect(errorsEncountered, lessThan(eventsSent * 0.01),
                 reason: 'Error rate should be less than 1%');
          expect(server.activeConnections, equals(subscriberCount + 1),
                 reason: 'All connections should remain active');
          expect(finalStats['totalMessagesReceived'], greaterThan(eventsSent),
                 reason: 'Server should have processed all sent messages');
          
          // Verify subscribers are still receiving events
          int totalEventsReceived = 0;
          for (final subscriber in subscribers) {
            totalEventsReceived += subscriber.getEventMessages().length;
          }
          
          expect(totalEventsReceived, greaterThan(eventsSent * subscriberCount * 0.8),
                 reason: 'Subscribers should receive most broadcasted events');
          
        } finally {
          await publisher.close();
          for (final subscriber in subscribers) {
            await subscriber.close();
          }
        }
      });
    });
  });
}