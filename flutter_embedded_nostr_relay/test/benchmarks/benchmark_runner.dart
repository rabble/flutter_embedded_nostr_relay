// ABOUTME: Main benchmark runner that executes all performance benchmarks
// ABOUTME: Provides comprehensive performance testing for 100k+ event scenarios

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_benchmarks.dart';
import 'event_insertion_benchmarks.dart';
import 'query_performance_benchmarks.dart';
import 'memory_benchmarks.dart';
import 'concurrent_benchmarks.dart';
import 'subscription_benchmarks.dart';
import 'gc_benchmarks.dart';
import '../utils/benchmark_utils.dart';
import '../utils/report_generator.dart';

/// Comprehensive benchmark suite for Flutter Embedded Nostr Relay.
/// 
/// This runner executes all performance benchmarks targeting 100k+ event scenarios
/// and generates detailed performance reports. The benchmarks cover all critical
/// performance aspects including database operations, memory usage, concurrency,
/// and platform-specific optimizations.
/// 
/// ## Benchmark Categories
/// 
/// - **Database Benchmarks**: Event storage, query performance, indexing
/// - **Event Insertion**: Single and batch insertion rates
/// - **Query Performance**: Complex filter performance with large datasets
/// - **Memory Benchmarks**: Memory usage patterns and garbage collection
/// - **Concurrent Operations**: Multi-client performance and resource contention
/// - **Subscription Routing**: Real-time event routing performance
/// - **Platform Optimizations**: Platform-specific performance characteristics
/// 
/// ## Usage
/// 
/// ```bash
/// # Run all benchmarks
/// dart test/benchmarks/benchmark_runner.dart
/// 
/// # Run specific benchmark category
/// dart test/benchmarks/benchmark_runner.dart --category=database
/// 
/// # Run with custom dataset size
/// dart test/benchmarks/benchmark_runner.dart --events=50000
/// 
/// # Generate detailed report
/// dart test/benchmarks/benchmark_runner.dart --report=detailed
/// ```
/// 
/// ## Environment Setup
/// 
/// The runner automatically configures the test environment:
/// - Sets up SQLite FFI for desktop testing
/// - Initializes in-memory database for consistent results
/// - Configures optimal database settings for performance
/// - Manages memory usage tracking
/// 
/// ## Report Generation
/// 
/// Results are automatically saved to:
/// - `test/benchmarks/reports/benchmark_results.json` - Raw data
/// - `test/benchmarks/reports/performance_report.html` - Formatted report
/// - `test/benchmarks/reports/performance_summary.md` - Summary markdown
class BenchmarkRunner {
  static const Map<String, String> _benchmarkCategories = {
    'database': 'Database Operations',
    'insertion': 'Event Insertion',
    'query': 'Query Performance', 
    'memory': 'Memory Usage',
    'concurrent': 'Concurrent Operations',
    'subscription': 'Subscription Routing',
    'gc': 'Garbage Collection',
    'all': 'All Benchmarks',
  };

  final int eventCount;
  final String category;
  final String reportLevel;
  final bool verbose;
  final BenchmarkConfig config;
  final ReportGenerator reportGenerator;

  BenchmarkRunner({
    this.eventCount = 100000,
    this.category = 'all',
    this.reportLevel = 'summary',
    this.verbose = false,
  }) : config = BenchmarkConfig(eventCount: eventCount),
       reportGenerator = ReportGenerator();

  /// Run the complete benchmark suite.
  /// 
  /// Executes benchmarks based on the configured category and generates
  /// performance reports. The benchmarks are run in order of dependency
  /// with proper cleanup between runs.
  /// 
  /// Returns a [BenchmarkSuiteResult] containing all performance metrics
  /// and timing data for analysis and reporting.
  Future<BenchmarkSuiteResult> run() async {
    print('🚀 Flutter Embedded Nostr Relay Performance Benchmarks');
    print('═' * 60);
    print('Event Count: ${config.eventCount.toString().padLeft(10)}');
    print('Category:    ${_benchmarkCategories[category] ?? category}');
    print('Report:      ${reportLevel}');
    print('═' * 60);
    print();

    await _setupEnvironment();
    
    final suiteStartTime = DateTime.now();
    final results = BenchmarkSuiteResult(
      startTime: suiteStartTime,
      config: config,
    );

    try {
      if (category == 'all' || category == 'database') {
        await _runDatabaseBenchmarks(results);
      }
      
      if (category == 'all' || category == 'insertion') {
        await _runInsertionBenchmarks(results);
      }
      
      if (category == 'all' || category == 'query') {
        await _runQueryBenchmarks(results);
      }
      
      if (category == 'all' || category == 'memory') {
        await _runMemoryBenchmarks(results);
      }
      
      if (category == 'all' || category == 'concurrent') {
        await _runConcurrentBenchmarks(results);
      }
      
      if (category == 'all' || category == 'subscription') {
        await _runSubscriptionBenchmarks(results);
      }
      
      if (category == 'all' || category == 'gc') {
        await _runGarbageCollectionBenchmarks(results);
      }

      results.endTime = DateTime.now();
      results.success = true;

      await _generateReports(results);
      _printSummary(results);

    } catch (error, stackTrace) {
      results.endTime = DateTime.now();
      results.success = false;
      results.error = error.toString();
      
      print('❌ Benchmark suite failed: $error');
      if (verbose) {
        print('Stack trace: $stackTrace');
      }
    }

    return results;
  }

  Future<void> _setupEnvironment() async {
    print('⚙️  Setting up benchmark environment...');
    
    // Initialize SQLite FFI for desktop testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Ensure reports directory exists
    final reportsDir = Directory('test/benchmarks/reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    
    print('✅ Environment ready');
    print();
  }

  Future<void> _runDatabaseBenchmarks(BenchmarkSuiteResult results) async {
    print('📊 Running Database Benchmarks...');
    
    final benchmarks = [
      DatabaseInsertBenchmark(config),
      DatabaseBatchInsertBenchmark(config),
      DatabaseQueryBenchmark(config),
      DatabaseIndexPerformanceBenchmark(config),
      DatabaseReplaceableEventBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runInsertionBenchmarks(BenchmarkSuiteResult results) async {
    print('⚡ Running Event Insertion Benchmarks...');
    
    final benchmarks = [
      SingleEventInsertionBenchmark(config),
      BatchEventInsertionBenchmark(config),
      ConcurrentInsertionBenchmark(config),
      LargeEventInsertionBenchmark(config),
      ReplaceableEventInsertionBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runQueryBenchmarks(BenchmarkSuiteResult results) async {
    print('🔍 Running Query Performance Benchmarks...');
    
    final benchmarks = [
      SimpleKindQueryBenchmark(config),
      AuthorQueryBenchmark(config),
      TagQueryBenchmark(config),
      ComplexFilterQueryBenchmark(config),
      TimeRangeQueryBenchmark(config),
      LimitedQueryBenchmark(config),
      MultiFilterQueryBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runMemoryBenchmarks(BenchmarkSuiteResult results) async {
    print('🧠 Running Memory Usage Benchmarks...');
    
    final benchmarks = [
      MemoryGrowthBenchmark(config),
      MemoryEfficiencyBenchmark(config),
      LargeDatasetMemoryBenchmark(config),
      MemoryLeakDetectionBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runConcurrentBenchmarks(BenchmarkSuiteResult results) async {
    print('🔄 Running Concurrent Operation Benchmarks...');
    
    final benchmarks = [
      ConcurrentReadWriteBenchmark(config),
      MultiClientBenchmark(config),
      ContentionBenchmark(config),
      ScalabilityBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runSubscriptionBenchmarks(BenchmarkSuiteResult results) async {
    print('📡 Running Subscription Routing Benchmarks...');
    
    final benchmarks = [
      SubscriptionRoutingBenchmark(config),
      ManySubscriptionsBenchmark(config),
      FilterMatchingBenchmark(config),
      RealTimeRoutingBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runGarbageCollectionBenchmarks(BenchmarkSuiteResult results) async {
    print('🗑️  Running Garbage Collection Benchmarks...');
    
    final benchmarks = [
      GarbageCollectionPerformanceBenchmark(config),
      GarbageCollectionImpactBenchmark(config),
      DatabaseVacuumBenchmark(config),
    ];

    for (final benchmark in benchmarks) {
      await _runSingleBenchmark(benchmark, results);
    }
  }

  Future<void> _runSingleBenchmark(
    BenchmarkBase benchmark, 
    BenchmarkSuiteResult results
  ) async {
    final benchmarkName = benchmark.name;
    print('  Running $benchmarkName...');
    
    try {
      final startTime = DateTime.now();
      final beforeMemory = _getMemoryUsage();
      
      final score = benchmark.measure();
      
      final endTime = DateTime.now();
      final afterMemory = _getMemoryUsage();
      
      final result = BenchmarkResult(
        name: benchmarkName,
        score: score,
        startTime: startTime,
        endTime: endTime,
        memoryBefore: beforeMemory,
        memoryAfter: afterMemory,
        success: true,
      );
      
      results.addResult(result);
      
      final duration = endTime.difference(startTime);
      final opsPerSecond = (1000000 / score).round(); // score is in microseconds
      
      print('    ✅ Score: ${score.toStringAsFixed(2)}μs/op '
            '(${opsPerSecond} ops/sec) '
            'Duration: ${duration.inMilliseconds}ms');
      
      if (verbose) {
        print('    Memory: ${beforeMemory}KB → ${afterMemory}KB '
              '(Δ${afterMemory - beforeMemory}KB)');
      }
      
    } catch (error) {
      final result = BenchmarkResult(
        name: benchmarkName,
        score: -1,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        memoryBefore: 0,
        memoryAfter: 0,
        success: false,
        error: error.toString(),
      );
      
      results.addResult(result);
      print('    ❌ Failed: $error');
    }
  }

  int _getMemoryUsage() {
    // This is a simplified memory usage estimation
    // In a real implementation, you might use platform-specific APIs
    // or vm_service for more accurate memory tracking
    final info = ProcessInfo.currentRss;
    return info ~/ 1024; // Convert to KB
  }

  Future<void> _generateReports(BenchmarkSuiteResult results) async {
    print();
    print('📝 Generating reports...');
    
    await reportGenerator.generateReport(results, reportLevel);
    
    print('  ✅ Reports saved to test/benchmarks/reports/');
  }

  void _printSummary(BenchmarkSuiteResult results) async {
    print();
    print('📈 Benchmark Summary');
    print('═' * 40);
    
    final duration = results.endTime!.difference(results.startTime);
    print('Total Duration: ${duration.inSeconds}s');
    print('Benchmarks Run: ${results.results.length}');
    
    final successful = results.results.where((r) => r.success).length;
    final failed = results.results.length - successful;
    
    print('Successful:     $successful');
    if (failed > 0) {
      print('Failed:         $failed');
    }
    
    if (successful > 0) {
      print();
      print('Top Performers:');
      final sortedResults = results.results
          .where((r) => r.success)
          .toList()
        ..sort((a, b) => a.score.compareTo(b.score));
      
      for (int i = 0; i < min(5, sortedResults.length); i++) {
        final result = sortedResults[i];
        final opsPerSecond = (1000000 / result.score).round();
        print('  ${i + 1}. ${result.name}: ${opsPerSecond} ops/sec');
      }
    }
    
    print();
    print('🎯 100k+ Event Performance Targets:');
    print('  Event Insertion: ${_checkTarget(results, 'insertion', 1000)} ops/sec (target: 1000+)');
    print('  Query Latency:   ${_checkTarget(results, 'query', 50, true)}ms (target: <50ms)');
    print('  Memory Usage:    ${_getMemoryEfficiency(results)} (target: efficient)');
    print('  Concurrency:     ${_checkTarget(results, 'concurrent', 100)} ops/sec (target: 100+)');
    
    print();
    print(results.success ? '✅ All benchmarks completed successfully!' 
                          : '❌ Some benchmarks failed - check logs for details');
  }

  String _checkTarget(BenchmarkSuiteResult results, String category, double target, [bool lowerIsBetter = false]) {
    final categoryResults = results.results
        .where((r) => r.name.toLowerCase().contains(category) && r.success)
        .toList();
    
    if (categoryResults.isEmpty) return 'N/A';
    
    final avgScore = categoryResults
        .map((r) => lowerIsBetter ? r.score / 1000 : 1000000 / r.score)
        .reduce((a, b) => a + b) / categoryResults.length;
    
    final targetMet = lowerIsBetter ? avgScore < target : avgScore > target;
    final indicator = targetMet ? '✅' : '⚠️';
    
    return '$indicator ${avgScore.toStringAsFixed(0)}';
  }

  String _getMemoryEfficiency(BenchmarkSuiteResult results) {
    final memoryResults = results.results
        .where((r) => r.name.toLowerCase().contains('memory') && r.success)
        .toList();
    
    if (memoryResults.isEmpty) return 'N/A';
    
    final avgGrowth = memoryResults
        .map((r) => r.memoryAfter - r.memoryBefore)
        .reduce((a, b) => a + b) / memoryResults.length;
    
    if (avgGrowth < 1000) return '✅ Excellent';
    if (avgGrowth < 5000) return '✅ Good';
    if (avgGrowth < 10000) return '⚠️ Moderate';
    return '❌ High';
  }
}

/// Entry point for benchmark execution
Future<void> main(List<String> args) async {
  // Parse command line arguments
  int eventCount = 100000;
  String category = 'all';
  String reportLevel = 'summary';
  bool verbose = false;

  for (final arg in args) {
    if (arg.startsWith('--events=')) {
      eventCount = int.parse(arg.split('=')[1]);
    } else if (arg.startsWith('--category=')) {
      category = arg.split('=')[1];
    } else if (arg.startsWith('--report=')) {
      reportLevel = arg.split('=')[1];
    } else if (arg == '--verbose' || arg == '-v') {
      verbose = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsage();
      return;
    }
  }

  final runner = BenchmarkRunner(
    eventCount: eventCount,
    category: category,
    reportLevel: reportLevel,
    verbose: verbose,
  );

  final results = await runner.run();
  
  exit(results.success ? 0 : 1);
}

void _printUsage() {
  print('Flutter Embedded Nostr Relay Benchmark Runner');
  print();
  print('Usage: dart test/benchmarks/benchmark_runner.dart [options]');
  print();
  print('Options:');
  print('  --events=N       Number of events for testing (default: 100000)');
  print('  --category=CAT   Benchmark category to run (default: all)');
  print('                   Options: database, insertion, query, memory,');
  print('                           concurrent, subscription, gc, all');
  print('  --report=LEVEL   Report detail level (default: summary)');
  print('                   Options: summary, detailed, full');
  print('  --verbose, -v    Enable verbose output');
  print('  --help, -h       Show this help message');
  print();
  print('Examples:');
  print('  dart test/benchmarks/benchmark_runner.dart');
  print('  dart test/benchmarks/benchmark_runner.dart --events=50000 --category=database');
  print('  dart test/benchmarks/benchmark_runner.dart --report=detailed --verbose');
}