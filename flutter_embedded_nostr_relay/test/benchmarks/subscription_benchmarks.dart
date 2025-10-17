// ABOUTME: Subscription routing performance benchmarks for real-time event distribution
// ABOUTME: Tests filter matching, routing efficiency, and subscription management scalability

import 'dart:async';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../lib/src/storage/database_helper.dart';
import '../../lib/src/storage/event_store.dart';
import '../../lib/src/core/subscription_manager.dart';
import '../../lib/src/models/nostr_event.dart';
import '../../lib/src/models/filter.dart';
import '../../lib/src/models/subscription.dart';
import '../utils/benchmark_utils.dart';

/// Benchmark for basic subscription routing performance.
/// 
/// Tests the time required to route events to matching subscriptions,
/// measuring the core filter matching and event distribution logic.
class SubscriptionRoutingBenchmark extends BenchmarkBase {
  late SubscriptionManager subscriptionManager;
  late EventStore eventStore;
  late List<NostrEvent> routingEvents;
  late List<Subscription> testSubscriptions;
  int eventIndex = 0;
  final BenchmarkConfig config;

  SubscriptionRoutingBenchmark(this.config) : super('SubscriptionRouting');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    subscriptionManager = SubscriptionManager();
    
    // Create diverse subscriptions for routing tests
    testSubscriptions = [];
    final authors = List.generate(100, (i) => 
        'routing_author$i'.padRight(64, '0'));
    
    // Create 50 different subscriptions with various filters
    for (int i = 0; i < 50; i++) {
      final subscriptionId = 'routing_sub_$i';
      final filter = _createVariedFilter(i, authors);
      
      final subscription = Subscription(
        id: subscriptionId,
        filters: [filter],
        clientId: 'routing_client_${i % 10}', // 10 clients with multiple subs each
      );
      
      testSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Create events that will match various subscriptions
    routingEvents = [];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount, 5000); i++) {
      final author = authors[i % authors.length];
      final kind = [1, 6, 7][random.nextInt(3)];
      
      final tags = <List<String>>[];
      if (random.nextDouble() < 0.3) {
        tags.add(['t', 'topic${random.nextInt(20)}']);
      }
      if (random.nextDouble() < 0.2) {
        tags.add(['p', authors[random.nextInt(authors.length)]]);
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: 'Routing test event $i',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'routing_sig_$i'.padRight(128, '0'),
      );
      
      routingEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await subscriptionManager.close();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = routingEvents[eventIndex % routingEvents.length];
    eventIndex++;
    
    // Test routing performance by finding matching subscriptions
    final matchingSubscriptions = subscriptionManager.findMatchingSubscriptions(event);
    
    // Simulate routing work
    for (final subscription in matchingSubscriptions) {
      // Simulate sending event to client
      final clientId = subscription.clientId;
      final eventData = event.toJson();
      
      // Basic processing simulation
      final messageSize = eventData.toString().length;
    }
  }

  Filter _createVariedFilter(int index, List<String> authors) {
    final filterType = index % 8;
    
    switch (filterType) {
      case 0:
        return Filter(kinds: [1], limit: 100);
      case 1:
        return Filter(kinds: [6], limit: 50);
      case 2:
        return Filter(kinds: [7], limit: 200);
      case 3:
        return Filter(authors: [authors[index % authors.length]], limit: 100);
      case 4:
        return Filter(authors: authors.skip(index).take(5).toList(), limit: 200);
      case 5:
        return Filter(kinds: [1, 6], limit: 150);
      case 6:
        return Filter(
          kinds: [1],
          since: DateTime.now().subtract(Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
          limit: 300,
        );
      case 7:
        return Filter(
          kinds: [1, 6, 7],
          authors: authors.skip(index * 2).take(10).toList(),
          limit: 250,
        );
      default:
        return Filter(kinds: [1], limit: 100);
    }
  }
}

/// Benchmark for handling many concurrent subscriptions.
/// 
/// Tests subscription management performance as the number of
/// active subscriptions grows, measuring memory usage and routing efficiency.
class ManySubscriptionsBenchmark extends BenchmarkBase {
  late SubscriptionManager subscriptionManager;
  late EventStore eventStore;
  late List<NostrEvent> testEvents;
  final List<Subscription> activeSubscriptions = [];
  int operationIndex = 0;
  final BenchmarkConfig config;

  ManySubscriptionsBenchmark(this.config) : super('ManySubscriptions');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    subscriptionManager = SubscriptionManager();
    
    // Create many subscriptions (up to 1000)
    final authors = List.generate(200, (i) => 
        'many_author$i'.padRight(64, '0'));
    
    for (int i = 0; i < min(1000, config.eventCount ~/ 100); i++) {
      final subscriptionId = 'many_sub_$i';
      final clientId = 'many_client_${i % 50}'; // 50 clients with multiple subs
      
      // Create varied filters to stress different matching paths
      Filter filter;
      final filterType = i % 10;
      
      switch (filterType) {
        case 0:
          filter = Filter(kinds: [1], limit: 50 + (i % 100));
          break;
        case 1:
          filter = Filter(kinds: [6, 7], limit: 25 + (i % 50));
          break;
        case 2:
          filter = Filter(authors: [authors[i % authors.length]], limit: 100);
          break;
        case 3:
          filter = Filter(authors: authors.skip(i % 50).take(5).toList(), limit: 200);
          break;
        case 4:
          filter = Filter(kinds: [1, 6], limit: 150);
          break;
        case 5:
          filter = Filter(
            kinds: [1],
            since: DateTime.now().subtract(Duration(hours: i % 168)).millisecondsSinceEpoch ~/ 1000,
            limit: 100 + (i % 200),
          );
          break;
        case 6:
          filter = Filter(kinds: [1, 6, 7], limit: 300);
          break;
        case 7:
          filter = Filter(
            authors: authors.skip(i % 100).take(10).toList(),
            kinds: [1],
            limit: 150,
          );
          break;
        case 8:
          filter = Filter(
            kinds: [1, 6],
            since: DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
            until: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            limit: 500,
          );
          break;
        case 9:
          filter = Filter(
            kinds: [1],
            authors: authors.take(20).toList(),
            limit: 400,
          );
          break;
        default:
          filter = Filter(kinds: [1], limit: 100);
      }
      
      final subscription = Subscription(
        id: subscriptionId,
        filters: [filter],
        clientId: clientId,
      );
      
      activeSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Create events that will match various subscription patterns
    testEvents = BenchmarkUtils.generateTestEvents(
      count: min(config.eventCount ~/ 10, 2000),
      kinds: [1, 6, 7],
      contentSize: 180,
    );
  }

  @override
  Future<void> teardown() async {
    activeSubscriptions.clear();
    await subscriptionManager.close();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = testEvents[operationIndex % testEvents.length];
    operationIndex++;
    
    // Test routing with many subscriptions
    final matchingSubscriptions = subscriptionManager.findMatchingSubscriptions(event);
    
    // Simulate routing overhead with many matches
    int routingWork = 0;
    for (final subscription in matchingSubscriptions) {
      routingWork += subscription.filters.length;
      
      // Simulate per-client routing work
      final eventJson = event.toJson();
      routingWork += eventJson.toString().length;
    }
    
    // Periodically add/remove subscriptions to test dynamic behavior
    if (operationIndex % 100 == 0) {
      // Remove some old subscriptions
      if (activeSubscriptions.length > 500) {
        final toRemove = activeSubscriptions.take(10).toList();
        for (final sub in toRemove) {
          subscriptionManager.removeSubscription(sub.id);
          activeSubscriptions.remove(sub);
        }
      }
      
      // Add some new subscriptions
      for (int i = 0; i < 5; i++) {
        final newSubId = 'dynamic_sub_${operationIndex}_$i';
        final newFilter = Filter(kinds: [1], limit: 100);
        final newSub = Subscription(
          id: newSubId,
          filters: [newFilter],
          clientId: 'dynamic_client_$i',
        );
        
        activeSubscriptions.add(newSub);
        subscriptionManager.addSubscription(newSub);
      }
    }
  }
}

/// Benchmark for filter matching efficiency.
/// 
/// Tests the performance of the filter matching algorithm with
/// various filter complexity levels and event characteristics.
class FilterMatchingBenchmark extends BenchmarkBase {
  late SubscriptionManager subscriptionManager;
  late List<NostrEvent> complexEvents;
  late List<Subscription> complexSubscriptions;
  int eventIndex = 0;
  final BenchmarkConfig config;

  FilterMatchingBenchmark(this.config) : super('FilterMatching');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    subscriptionManager = SubscriptionManager();
    
    final authors = List.generate(300, (i) => 
        'filter_author$i'.padRight(64, '0'));
    
    // Create subscriptions with increasingly complex filters
    complexSubscriptions = [];
    
    for (int i = 0; i < 200; i++) {
      final subscriptionId = 'complex_sub_$i';
      final complexity = i % 5;
      final filter = _createComplexFilter(complexity, i, authors);
      
      final subscription = Subscription(
        id: subscriptionId,
        filters: [filter],
        clientId: 'complex_client_${i % 20}',
      );
      
      complexSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Create events with complex tag structures for testing
    complexEvents = [];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount ~/ 5, 3000); i++) {
      final author = authors[i % authors.length];
      final kind = [1, 6, 7][random.nextInt(3)];
      
      final tags = <List<String>>[];
      
      // Add many different types of tags
      final numTopics = random.nextInt(8);
      for (int j = 0; j < numTopics; j++) {
        tags.add(['t', 'topic${random.nextInt(100)}']);
      }
      
      final numMentions = random.nextInt(5);
      for (int j = 0; j < numMentions; j++) {
        tags.add(['p', authors[random.nextInt(authors.length)]]);
      }
      
      final numEventRefs = random.nextInt(3);
      for (int j = 0; j < numEventRefs; j++) {
        tags.add(['e', 'event_${random.nextInt(1000)}'.padRight(64, '0')]);
      }
      
      // Add custom tags
      final numCustom = random.nextInt(4);
      for (int j = 0; j < numCustom; j++) {
        tags.add(['custom$j', 'value${random.nextInt(50)}', 'extra$j']);
      }
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: 'Complex filter test event $i with many tags',
        createdAt: DateTime.now().subtract(
          Duration(minutes: random.nextInt(43200))
        ).millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'complex_sig_$i'.padRight(128, '0'),
      );
      
      complexEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await subscriptionManager.close();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = complexEvents[eventIndex % complexEvents.length];
    eventIndex++;
    
    // Test complex filter matching
    final matchingSubscriptions = subscriptionManager.findMatchingSubscriptions(event);
    
    // Simulate the overhead of complex matching
    int matchingWork = 0;
    for (final subscription in matchingSubscriptions) {
      for (final filter in subscription.filters) {
        // Simulate filter evaluation work
        matchingWork += filter.kinds?.length ?? 0;
        matchingWork += filter.authors?.length ?? 0;
        matchingWork += filter.pTags?.length ?? 0;
        matchingWork += filter.eTags?.length ?? 0;
        matchingWork += event.tags.length;
      }
    }
  }

  Filter _createComplexFilter(int complexity, int index, List<String> authors) {
    switch (complexity) {
      case 0: // Simple filter
        return Filter(kinds: [1], limit: 100);
        
      case 1: // Kind + author filter
        return Filter(
          kinds: [1, 6],
          authors: [authors[index % authors.length]],
          limit: 150,
        );
        
      case 2: // Multi-author filter
        return Filter(
          kinds: [1],
          authors: authors.skip(index % 100).take(10).toList(),
          limit: 200,
        );
        
      case 3: // Tag-based filter
        return Filter(
          kinds: [1, 6, 7],
          pTags: authors.skip(index % 50).take(5).toList(),
          limit: 250,
        );
        
      case 4: // Complex multi-condition filter
        return Filter(
          kinds: [1, 6],
          authors: authors.skip(index % 100).take(20).toList(),
          pTags: authors.skip((index * 2) % 100).take(10).toList(),
          since: DateTime.now().subtract(
            Duration(hours: 24 + (index % 168))
          ).millisecondsSinceEpoch ~/ 1000,
          until: DateTime.now().subtract(
            Duration(hours: index % 24)
          ).millisecondsSinceEpoch ~/ 1000,
          limit: 500,
        );
        
      default:
        return Filter(kinds: [1], limit: 100);
    }
  }
}

/// Benchmark for real-time event routing performance.
/// 
/// Tests the end-to-end performance of routing events to subscriptions
/// in real-time scenarios, including WebSocket message preparation.
class RealTimeRoutingBenchmark extends BenchmarkBase {
  late SubscriptionManager subscriptionManager;
  late EventStore eventStore;
  late List<NostrEvent> realTimeEvents;
  late List<Subscription> realTimeSubscriptions;
  int operationIndex = 0;
  final BenchmarkConfig config;

  RealTimeRoutingBenchmark(this.config) : super('RealTimeRouting');

  @override
  Future<void> setup() async {
    DatabaseHelper.enableTestMode();
    eventStore = EventStore();
    subscriptionManager = SubscriptionManager();
    
    // Create realistic real-time subscriptions
    realTimeSubscriptions = [];
    final authors = List.generate(100, (i) => 
        'realtime_author$i'.padRight(64, '0'));
    
    // Timeline subscriptions (most common)
    for (int i = 0; i < 30; i++) {
      final subscription = Subscription(
        id: 'timeline_$i',
        filters: [Filter(kinds: [1, 6], limit: 100)],
        clientId: 'realtime_client_$i',
      );
      realTimeSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Following subscriptions
    for (int i = 0; i < 20; i++) {
      final followingList = authors.skip(i * 5).take(10).toList();
      final subscription = Subscription(
        id: 'following_$i',
        filters: [Filter(authors: followingList, kinds: [1], limit: 200)],
        clientId: 'realtime_client_$i',
      );
      realTimeSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Notification subscriptions
    for (int i = 0; i < 15; i++) {
      final userPubkey = authors[i];
      final subscription = Subscription(
        id: 'notifications_$i',
        filters: [
          Filter(pTags: [userPubkey], kinds: [1, 6, 7], limit: 100),
        ],
        clientId: 'realtime_client_$i',
      );
      realTimeSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Hashtag subscriptions
    for (int i = 0; i < 10; i++) {
      final subscription = Subscription(
        id: 'hashtag_$i',
        filters: [Filter(kinds: [1], limit: 150)], // Using generic filter for hashtags
        clientId: 'realtime_client_$i',
      );
      realTimeSubscriptions.add(subscription);
      subscriptionManager.addSubscription(subscription);
    }
    
    // Create realistic real-time events
    realTimeEvents = [];
    final random = Random(42);
    
    for (int i = 0; i < min(config.eventCount ~/ 5, 2000); i++) {
      final author = authors[i % authors.length];
      final kind = _selectRealisticKind(random);
      
      final tags = <List<String>>[];
      final content = _generateRealisticContent(i, kind, random, tags, authors);
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ).copyWith(
        sig: 'realtime_sig_$i'.padRight(128, '0'),
      );
      
      realTimeEvents.add(event);
    }
  }

  @override
  Future<void> teardown() async {
    await subscriptionManager.close();
    await DatabaseHelper.reset();
  }

  @override
  void run() {
    final event = realTimeEvents[operationIndex % realTimeEvents.length];
    operationIndex++;
    
    // Simulate complete real-time routing process
    
    // 1. Find matching subscriptions
    final matchingSubscriptions = subscriptionManager.findMatchingSubscriptions(event);
    
    // 2. Prepare event messages for each matching subscription
    final routingResults = <String, String>{};
    
    for (final subscription in matchingSubscriptions) {
      // Simulate WebSocket message preparation
      final eventMessage = ['EVENT', subscription.id, event.toJson()];
      final serializedMessage = eventMessage.toString(); // Simplified JSON encoding
      
      routingResults[subscription.clientId] = serializedMessage;
    }
    
    // 3. Simulate message queueing/delivery overhead
    int deliveryWork = 0;
    for (final entry in routingResults.entries) {
      deliveryWork += entry.value.length;
    }
    
    // 4. Update subscription statistics
    for (final subscription in matchingSubscriptions) {
      // Simulate subscription activity tracking
      final activity = subscription.id.hashCode;
    }
  }

  int _selectRealisticKind(Random random) {
    final kindProbability = random.nextDouble();
    
    if (kindProbability < 0.70) return 1;      // Text notes - 70%
    if (kindProbability < 0.85) return 6;      // Reposts - 15%
    if (kindProbability < 0.95) return 7;      // Reactions - 10%
    if (kindProbability < 0.98) return 0;      // Metadata - 3%
    return 3;                                   // Contacts - 2%
  }

  String _generateRealisticContent(
    int index, 
    int kind, 
    Random random, 
    List<List<String>> tags,
    List<String> authors,
  ) {
    switch (kind) {
      case 0: // Metadata
        return '{"name":"User $index","about":"Real-time test user"}';
        
      case 1: // Text note
        // Add realistic tags
        if (random.nextDouble() < 0.3) {
          tags.add(['t', 'realtime']);
        }
        if (random.nextDouble() < 0.2) {
          tags.add(['p', authors[random.nextInt(authors.length)]]);
        }
        return 'Real-time text note $index #realtime';
        
      case 3: // Contacts
        final contactCount = 10 + random.nextInt(50);
        for (int i = 0; i < contactCount; i++) {
          tags.add(['p', authors[i % authors.length]]);
        }
        return '';
        
      case 6: // Repost
        tags.add(['e', 'original_event_$index'.padRight(64, '0')]);
        tags.add(['p', authors[random.nextInt(authors.length)]]);
        return '';
        
      case 7: // Reaction
        tags.add(['e', 'target_event_$index'.padRight(64, '0')]);
        tags.add(['p', authors[random.nextInt(authors.length)]]);
        return ['+', '❤️', '🤙', '🔥'][random.nextInt(4)];
        
      default:
        return 'Real-time event $index';
    }
  }
}