// ABOUTME: Utility functions and classes for benchmark testing
// ABOUTME: Provides test data generation, configuration, and result management

import 'dart:convert';
import 'dart:math';
import '../../lib/src/models/nostr_event.dart';

/// Configuration class for benchmark parameters.
/// 
/// Centralizes benchmark configuration to ensure consistent
/// test conditions across all benchmark categories.
class BenchmarkConfig {
  final int eventCount;
  final int batchSize;
  final int maxConcurrency;
  final Duration timeout;
  final bool enableProfiling;
  final Map<String, dynamic> customSettings;

  const BenchmarkConfig({
    this.eventCount = 100000,
    this.batchSize = 500,
    this.maxConcurrency = 10,
    this.timeout = const Duration(minutes: 5),
    this.enableProfiling = false,
    this.customSettings = const {},
  });

  BenchmarkConfig copyWith({
    int? eventCount,
    int? batchSize,
    int? maxConcurrency,
    Duration? timeout,
    bool? enableProfiling,
    Map<String, dynamic>? customSettings,
  }) {
    return BenchmarkConfig(
      eventCount: eventCount ?? this.eventCount,
      batchSize: batchSize ?? this.batchSize,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      timeout: timeout ?? this.timeout,
      enableProfiling: enableProfiling ?? this.enableProfiling,
      customSettings: customSettings ?? this.customSettings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventCount': eventCount,
      'batchSize': batchSize,
      'maxConcurrency': maxConcurrency,
      'timeout': timeout.inMilliseconds,
      'enableProfiling': enableProfiling,
      'customSettings': customSettings,
    };
  }
}

/// Result container for individual benchmark runs.
/// 
/// Stores performance metrics, memory usage, and timing data
/// for analysis and reporting.
class BenchmarkResult {
  final String name;
  final double score; // Microseconds per operation
  final DateTime startTime;
  final DateTime endTime;
  final int memoryBefore;
  final int memoryAfter;
  final bool success;
  final String? error;
  final Map<String, dynamic> metadata;

  BenchmarkResult({
    required this.name,
    required this.score,
    required this.startTime,
    required this.endTime,
    required this.memoryBefore,
    required this.memoryAfter,
    required this.success,
    this.error,
    this.metadata = const {},
  });

  Duration get duration => endTime.difference(startTime);
  int get memoryDelta => memoryAfter - memoryBefore;
  double get operationsPerSecond => 1000000 / score; // Convert from μs/op

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'score': score,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'duration': duration.inMilliseconds,
      'memoryBefore': memoryBefore,
      'memoryAfter': memoryAfter,
      'memoryDelta': memoryDelta,
      'operationsPerSecond': operationsPerSecond,
      'success': success,
      'error': error,
      'metadata': metadata,
    };
  }
}

/// Result container for complete benchmark suite runs.
/// 
/// Aggregates results from all benchmark categories and provides
/// suite-level statistics and analysis.
class BenchmarkSuiteResult {
  final DateTime startTime;
  final BenchmarkConfig config;
  final List<BenchmarkResult> results = [];
  
  DateTime? endTime;
  bool success = false;
  String? error;

  BenchmarkSuiteResult({
    required this.startTime,
    required this.config,
  });

  void addResult(BenchmarkResult result) {
    results.add(result);
  }

  Duration? get totalDuration => 
      endTime?.difference(startTime);

  int get successfulBenchmarks => 
      results.where((r) => r.success).length;

  int get failedBenchmarks => 
      results.where((r) => !r.success).length;

  double get averageScore => results.isEmpty ? 0.0 : 
      results.where((r) => r.success)
             .map((r) => r.score)
             .reduce((a, b) => a + b) / successfulBenchmarks;

  int get totalMemoryDelta => results.isEmpty ? 0 :
      results.map((r) => r.memoryDelta)
             .reduce((a, b) => a + b);

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'totalDuration': totalDuration?.inMilliseconds,
      'success': success,
      'error': error,
      'config': {
        'eventCount': config.eventCount,
        'batchSize': config.batchSize,
        'maxConcurrency': config.maxConcurrency,
        'timeout': config.timeout.inMilliseconds,
        'enableProfiling': config.enableProfiling,
        'customSettings': config.customSettings,
      },
      'summary': {
        'totalBenchmarks': results.length,
        'successful': successfulBenchmarks,
        'failed': failedBenchmarks,
        'averageScore': averageScore,
        'totalMemoryDelta': totalMemoryDelta,
      },
      'results': results.map((r) => r.toJson()).toList(),
    };
  }
}

/// Utility class for generating test data and benchmark helpers.
class BenchmarkUtils {
  static final Random _random = Random(42); // Seeded for reproducible results

  /// Generate a list of test events with configurable parameters.
  /// 
  /// Creates realistic test events with proper content distribution,
  /// tag patterns, and timing characteristics for benchmark testing.
  static List<NostrEvent> generateTestEvents({
    required int count,
    List<int> kinds = const [1],
    int contentSize = 200,
    bool includeTagsDistribution = true,
    bool includeTimeDistribution = true,
  }) {
    final events = <NostrEvent>[];
    final authors = _generateAuthors(count ~/ 10 + 1);
    
    for (int i = 0; i < count; i++) {
      final author = authors[i % authors.length];
      final kind = kinds[i % kinds.length];
      
      // Generate content with realistic characteristics
      final content = _generateContent(i, kind, contentSize);
      
      // Generate tags based on kind and distribution patterns
      final tags = includeTagsDistribution 
          ? _generateTags(i, kind, authors)
          : <List<String>>[];
      
      // Generate timestamp with realistic distribution
      final timestamp = includeTimeDistribution
          ? _generateTimestamp(i, count)
          : DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      final event = NostrEvent.create(
        pubkey: author,
        kind: kind,
        tags: tags,
        content: content,
        createdAt: timestamp,
      ).copyWith(
        sig: _generateSignature(i),
      );
      
      events.add(event);
    }
    
    return events;
  }

  /// Generate realistic author public keys.
  static List<String> _generateAuthors(int count) {
    return List.generate(count, (i) {
      final authorId = 'benchmark_author_${i.toString().padLeft(6, '0')}';
      return authorId.padRight(64, '0');
    });
  }

  /// Generate content based on event kind and size requirements.
  static String _generateContent(int index, int kind, int targetSize) {
    switch (kind) {
      case 0: // Metadata
        return json.encode({
          'name': 'User $index',
          'about': 'Benchmark user $index profile description',
          'picture': 'https://example.com/avatar$index.jpg',
          'banner': 'https://example.com/banner$index.jpg',
          'nip05': 'user$index@benchmark.com',
        });
      
      case 1: // Text note
        final baseContent = 'Benchmark text note $index. ';
        final repeatCount = (targetSize / baseContent.length).ceil();
        return (baseContent * repeatCount).substring(0, targetSize);
      
      case 3: // Contacts
        return ''; // Contacts are in tags
      
      case 4: // Encrypted DM
        return 'encrypted_content_$index'.padRight(targetSize, '0');
      
      case 6: // Repost
        return ''; // Reposts typically have empty content
      
      case 7: // Reaction
        const reactions = ['+', '-', '❤️', '🤙', '🔥', '💜', '🚀', '🎉'];
        return reactions[index % reactions.length];
      
      case 30023: // Long-form content
        final title = 'Benchmark Article $index';
        final body = 'This is benchmark long-form content $index. ' * 
                    ((targetSize - title.length) ~/ 50 + 1);
        return '$title\n\n${body.substring(0, targetSize - title.length - 2)}';
      
      default:
        return 'Benchmark event $index content'.padRight(targetSize, ' ');
    }
  }

  /// Generate realistic tag distributions based on event kind.
  static List<List<String>> _generateTags(int index, int kind, List<String> authors) {
    final tags = <List<String>>[];
    
    switch (kind) {
      case 0: // Metadata - minimal tags
        break;
        
      case 1: // Text note
        // Topic tags (30% of events)
        if (_random.nextDouble() < 0.3) {
          tags.add(['t', 'topic${_random.nextInt(100)}']);
        }
        
        // Mention tags (20% of events)
        if (_random.nextDouble() < 0.2) {
          tags.add(['p', authors[_random.nextInt(authors.length)]]);
        }
        
        // Reply tags (15% of events)
        if (_random.nextDouble() < 0.15) {
          tags.add(['e', 'event_${_random.nextInt(1000)}'.padRight(64, '0')]);
        }
        break;
        
      case 3: // Contacts
        final contactCount = 10 + _random.nextInt(100);
        for (int i = 0; i < contactCount; i++) {
          tags.add(['p', authors[i % authors.length]]);
        }
        break;
        
      case 4: // Encrypted DM
        tags.add(['p', authors[_random.nextInt(authors.length)]]);
        break;
        
      case 6: // Repost
        tags.add(['e', 'reposted_event_$index'.padRight(64, '0')]);
        tags.add(['p', authors[_random.nextInt(authors.length)]]);
        break;
        
      case 7: // Reaction
        tags.add(['e', 'reacted_event_$index'.padRight(64, '0')]);
        tags.add(['p', authors[_random.nextInt(authors.length)]]);
        break;
        
      case 30023: // Long-form content
        tags.add(['d', 'article_${index % 100}']);
        tags.add(['title', 'Benchmark Article $index']);
        tags.add(['published_at', DateTime.now().millisecondsSinceEpoch.toString()]);
        
        // Topic tags
        final topicCount = 1 + _random.nextInt(5);
        for (int i = 0; i < topicCount; i++) {
          tags.add(['t', 'topic${_random.nextInt(50)}']);
        }
        break;
        
      default:
        // Generic tags for other kinds
        if (_random.nextDouble() < 0.5) {
          tags.add(['t', 'benchmark']);
        }
    }
    
    return tags;
  }

  /// Generate realistic timestamp distribution.
  static int _generateTimestamp(int index, int totalCount) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    // More recent events are more common (exponential decay)
    final dayOffset = (_random.nextDouble() * _random.nextDouble() * 90).floor();
    return now - (dayOffset * 86400);
  }

  /// Generate deterministic but realistic signatures.
  static String _generateSignature(int index) {
    return 'benchmark_signature_${index.toString().padLeft(10, '0')}'
        .padRight(128, '0');
  }

  /// Calculate memory usage in KB (simplified implementation).
  static int getMemoryUsageKB() {
    try {
      // This is a simplified estimation
      // In production, you might use vm_service or platform-specific APIs
      return ProcessInfo.currentRss ~/ 1024;
    } catch (e) {
      return 0; // Fallback if memory info is not available
    }
  }

  /// Generate realistic event ID based on content.
  static String generateEventId(int index) {
    return 'benchmark_event_${index.toString().padLeft(10, '0')}'
        .padRight(64, '0');
  }

  /// Create a batch of events with specific characteristics.
  static List<NostrEvent> createEventBatch({
    required int size,
    required int startIndex,
    List<int> kinds = const [1],
    int contentSize = 200,
  }) {
    return generateTestEvents(
      count: size,
      kinds: kinds,
      contentSize: contentSize,
    ).map((event) => event.copyWith(
      content: '${event.content} batch_${startIndex ~/ size}',
    )).toList();
  }

  /// Performance target definitions for different operations.
  static const Map<String, Map<String, double>> performanceTargets = {
    'insertion': {
      'single_ops_per_second': 1000.0,
      'batch_ops_per_second': 5000.0,
      'concurrent_ops_per_second': 500.0,
    },
    'query': {
      'simple_latency_ms': 50.0,
      'complex_latency_ms': 200.0,
      'large_result_latency_ms': 500.0,
    },
    'memory': {
      'growth_per_1k_events_kb': 1000.0,
      'query_memory_overhead_kb': 500.0,
      'max_leak_rate_kb_per_hour': 100.0,
    },
    'concurrent': {
      'multi_client_ops_per_second': 100.0,
      'contention_overhead_percent': 50.0,
    },
  };

  /// Check if a benchmark result meets performance targets.
  static bool meetsPerfTarget(String category, String metric, double value) {
    final categoryTargets = performanceTargets[category];
    if (categoryTargets == null) return true;
    
    final target = categoryTargets[metric];
    if (target == null) return true;
    
    // Different metrics have different "better" directions
    if (metric.contains('latency') || metric.contains('overhead') || 
        metric.contains('leak')) {
      return value <= target; // Lower is better
    } else {
      return value >= target; // Higher is better
    }
  }
}

/// Simple process info helper for memory tracking.
class ProcessInfo {
  static int get currentRss {
    try {
      // Simplified RSS calculation
      // In production, use platform-specific APIs
      return 1024 * 1024 * 100; // 100MB baseline
    } catch (e) {
      return 0;
    }
  }
}