// ABOUTME: Comprehensive integration test runner for the Flutter Embedded Nostr Relay
// ABOUTME: Coordinates execution of all integration test suites with reporting and cleanup

import 'dart:io';
import 'dart:convert';

/// Integration test runner that executes all test suites and provides comprehensive reporting
void main(List<String> args) async {
  print('🚀 Flutter Embedded Nostr Relay - Integration Test Suite');
  print('═' * 60);
  
  final testRunner = IntegrationTestRunner();
  await testRunner.runAllTests(args);
}

class IntegrationTestRunner {
  final List<TestSuite> testSuites = [
    TestSuite(
      name: 'NIP Compliance',
      file: 'nip_compliance_integration_test.dart',
      description: 'Tests protocol compliance for NIP-01, NIP-09, NIP-11, NIP-65',
      estimatedDuration: Duration(minutes: 3),
      priority: TestPriority.critical,
    ),
    TestSuite(
      name: 'Multi-Client Interactions',
      file: 'multi_client_interaction_test.dart',
      description: 'Tests concurrent operations and event routing across multiple clients',
      estimatedDuration: Duration(minutes: 4),
      priority: TestPriority.high,
    ),
    TestSuite(
      name: 'Persistence & Recovery',
      file: 'persistence_recovery_integration_test.dart',
      description: 'Tests database persistence, crash recovery, and data consistency',
      estimatedDuration: Duration(minutes: 5),
      priority: TestPriority.high,
    ),
    TestSuite(
      name: 'Performance',
      file: 'performance_integration_test.dart',
      description: 'Tests throughput, latency, memory usage, and performance limits',
      estimatedDuration: Duration(minutes: 6),
      priority: TestPriority.medium,
    ),
    TestSuite(
      name: 'Error Handling',
      file: 'error_handling_integration_test.dart',
      description: 'Tests malformed messages, edge cases, and error recovery',
      estimatedDuration: Duration(minutes: 3),
      priority: TestPriority.medium,
    ),
    TestSuite(
      name: 'Real-World Usage',
      file: 'real_world_usage_integration_test.dart',
      description: 'Tests common Nostr workflows and practical usage scenarios',
      estimatedDuration: Duration(minutes: 4),
      priority: TestPriority.low,
    ),
  ];

  Future<void> runAllTests(List<String> args) async {
    final config = TestConfig.fromArgs(args);
    final results = <TestResult>[];
    
    print('Configuration:');
    print('  Filter: ${config.filter ?? 'all'}');
    print('  Priority: ${config.minPriority.name}');
    print('  Parallel: ${config.parallel}');
    print('  Verbose: ${config.verbose}');
    print('');
    
    final filteredSuites = _filterTestSuites(config);
    
    if (filteredSuites.isEmpty) {
      print('❌ No test suites match the specified criteria');
      exit(1);
    }
    
    print('Test Suites to Execute:');
    for (final suite in filteredSuites) {
      print('  ✓ ${suite.name} (${suite.priority.name})');
    }
    print('');
    
    final totalEstimatedTime = filteredSuites.fold<Duration>(
      Duration.zero,
      (total, suite) => total + suite.estimatedDuration,
    );
    
    print('Estimated total time: ${_formatDuration(totalEstimatedTime)}');
    print('═' * 60);
    print('');
    
    final overallStartTime = DateTime.now();
    
    if (config.parallel && filteredSuites.length > 1) {
      results.addAll(await _runTestsInParallel(filteredSuites, config));
    } else {
      results.addAll(await _runTestsSequentially(filteredSuites, config));
    }
    
    final overallEndTime = DateTime.now();
    final totalDuration = overallEndTime.difference(overallStartTime);
    
    await _generateReport(results, totalDuration, config);
    
    final hasFailures = results.any((r) => !r.passed);
    exit(hasFailures ? 1 : 0);
  }
  
  List<TestSuite> _filterTestSuites(TestConfig config) {
    return testSuites.where((suite) {
      // Filter by priority
      if (suite.priority.index < config.minPriority.index) {
        return false;
      }
      
      // Filter by name pattern
      if (config.filter != null) {
        final pattern = RegExp(config.filter!, caseSensitive: false);
        return pattern.hasMatch(suite.name) || pattern.hasMatch(suite.file);
      }
      
      return true;
    }).toList();
  }
  
  Future<List<TestResult>> _runTestsSequentially(
    List<TestSuite> suites,
    TestConfig config,
  ) async {
    final results = <TestResult>[];
    
    for (int i = 0; i < suites.length; i++) {
      final suite = suites[i];
      print('📋 Running ${suite.name} (${i + 1}/${suites.length})');
      print('   ${suite.description}');
      
      final result = await _runSingleTest(suite, config);
      results.add(result);
      
      print('   ${result.passed ? '✅' : '❌'} ${result.passed ? 'PASSED' : 'FAILED'} '
            'in ${_formatDuration(result.duration)}');
      
      if (!result.passed && config.verbose) {
        print('   Error Output:');
        print('   ${result.output.split('\n').map((line) => '     $line').join('\n')}');
      }
      
      print('');
    }
    
    return results;
  }
  
  Future<List<TestResult>> _runTestsInParallel(
    List<TestSuite> suites,
    TestConfig config,
  ) async {
    print('🔄 Running ${suites.length} test suites in parallel...');
    print('');
    
    final futures = suites.map((suite) => _runSingleTest(suite, config)).toList();
    final results = await Future.wait(futures);
    
    // Print results as they complete
    for (int i = 0; i < results.length; i++) {
      final suite = suites[i];
      final result = results[i];
      
      print('${result.passed ? '✅' : '❌'} ${suite.name}: '
            '${result.passed ? 'PASSED' : 'FAILED'} '
            'in ${_formatDuration(result.duration)}');
    }
    
    print('');
    return results;
  }
  
  Future<TestResult> _runSingleTest(TestSuite suite, TestConfig config) async {
    final startTime = DateTime.now();
    
    try {
      final process = await Process.start(
        'flutter',
        [
          'test',
          'test/integration/${suite.file}',
          if (config.verbose) '--verbose',
        ],
        workingDirectory: Directory.current.path,
      );
      
      final outputBuffer = StringBuffer();
      process.stdout.transform(utf8.decoder).listen((data) {
        outputBuffer.write(data);
        if (config.verbose) {
          stdout.write(data);
        }
      });
      
      process.stderr.transform(utf8.decoder).listen((data) {
        outputBuffer.write(data);
        if (config.verbose) {
          stderr.write(data);
        }
      });
      
      final exitCode = await process.exitCode;
      final endTime = DateTime.now();
      
      return TestResult(
        suite: suite,
        passed: exitCode == 0,
        duration: endTime.difference(startTime),
        output: outputBuffer.toString(),
        exitCode: exitCode,
      );
      
    } catch (e) {
      final endTime = DateTime.now();
      
      return TestResult(
        suite: suite,
        passed: false,
        duration: endTime.difference(startTime),
        output: 'Failed to run test: $e',
        exitCode: -1,
      );
    }
  }
  
  Future<void> _generateReport(
    List<TestResult> results,
    Duration totalDuration,
    TestConfig config,
  ) async {
    print('═' * 60);
    print('📊 Integration Test Results Summary');
    print('═' * 60);
    
    final passed = results.where((r) => r.passed).length;
    final failed = results.length - passed;
    
    print('Overall: ${passed}/${results.length} test suites passed');
    print('Duration: ${_formatDuration(totalDuration)}');
    print('');
    
    if (failed > 0) {
      print('❌ Failed Test Suites:');
      for (final result in results.where((r) => !r.passed)) {
        print('  • ${result.suite.name}');
        print('    Duration: ${_formatDuration(result.duration)}');
        print('    Exit Code: ${result.exitCode}');
      }
      print('');
    }
    
    print('✅ Passed Test Suites:');
    for (final result in results.where((r) => r.passed)) {
      print('  • ${result.suite.name} (${_formatDuration(result.duration)})');
    }
    print('');
    
    // Generate detailed report file
    await _writeDetailedReport(results, totalDuration, config);
    
    if (failed == 0) {
      print('🎉 All integration tests passed!');
      print('   The Flutter Embedded Nostr Relay is ready for production use.');
    } else {
      print('⚠️  Some integration tests failed.');
      print('   Please review the failed tests before proceeding.');
    }
  }
  
  Future<void> _writeDetailedReport(
    List<TestResult> results,
    Duration totalDuration,
    TestConfig config,
  ) async {
    final reportFile = File('integration_test_report.json');
    
    final report = {
      'timestamp': DateTime.now().toIso8601String(),
      'totalDuration': totalDuration.inMilliseconds,
      'configuration': {
        'filter': config.filter,
        'minPriority': config.minPriority.name,
        'parallel': config.parallel,
        'verbose': config.verbose,
      },
      'summary': {
        'total': results.length,
        'passed': results.where((r) => r.passed).length,
        'failed': results.where((r) => !r.passed).length,
      },
      'results': results.map((result) => {
        'suite': result.suite.name,
        'file': result.suite.file,
        'description': result.suite.description,
        'priority': result.suite.priority.name,
        'passed': result.passed,
        'duration': result.duration.inMilliseconds,
        'exitCode': result.exitCode,
        'hasOutput': result.output.isNotEmpty,
      }).toList(),
    };
    
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report)
    );
    
    print('📄 Detailed report written to: ${reportFile.path}');
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

class TestSuite {
  final String name;
  final String file;
  final String description;
  final Duration estimatedDuration;
  final TestPriority priority;
  
  TestSuite({
    required this.name,
    required this.file,
    required this.description,
    required this.estimatedDuration,
    required this.priority,
  });
}

class TestResult {
  final TestSuite suite;
  final bool passed;
  final Duration duration;
  final String output;
  final int exitCode;
  
  TestResult({
    required this.suite,
    required this.passed,
    required this.duration,
    required this.output,
    required this.exitCode,
  });
}

enum TestPriority {
  critical,
  high,
  medium,
  low,
}

class TestConfig {
  final String? filter;
  final TestPriority minPriority;
  final bool parallel;
  final bool verbose;
  
  TestConfig({
    this.filter,
    this.minPriority = TestPriority.low,
    this.parallel = false,
    this.verbose = false,
  });
  
  factory TestConfig.fromArgs(List<String> args) {
    String? filter;
    TestPriority minPriority = TestPriority.low;
    bool parallel = false;
    bool verbose = false;
    
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      
      switch (arg) {
        case '--filter':
        case '-f':
          if (i + 1 < args.length) {
            filter = args[i + 1];
            i++;
          }
          break;
          
        case '--priority':
        case '-p':
          if (i + 1 < args.length) {
            final priorityStr = args[i + 1].toLowerCase();
            switch (priorityStr) {
              case 'critical':
                minPriority = TestPriority.critical;
                break;
              case 'high':
                minPriority = TestPriority.high;
                break;
              case 'medium':
                minPriority = TestPriority.medium;
                break;
              case 'low':
                minPriority = TestPriority.low;
                break;
            }
            i++;
          }
          break;
          
        case '--parallel':
          parallel = true;
          break;
          
        case '--verbose':
        case '-v':
          verbose = true;
          break;
          
        case '--help':
        case '-h':
          _printUsage();
          exit(0);
      }
    }
    
    return TestConfig(
      filter: filter,
      minPriority: minPriority,
      parallel: parallel,
      verbose: verbose,
    );
  }
  
  static void _printUsage() {
    print('Integration Test Runner Usage:');
    print('');
    print('dart test/integration/run_integration_tests.dart [options]');
    print('');
    print('Options:');
    print('  --filter, -f <pattern>    Filter test suites by name pattern');
    print('  --priority, -p <level>    Minimum priority level (critical|high|medium|low)');
    print('  --parallel                Run test suites in parallel');
    print('  --verbose, -v             Enable verbose output');
    print('  --help, -h                Show this help message');
    print('');
    print('Examples:');
    print('  dart test/integration/run_integration_tests.dart');
    print('  dart test/integration/run_integration_tests.dart --filter nip');
    print('  dart test/integration/run_integration_tests.dart --priority high --parallel');
    print('  dart test/integration/run_integration_tests.dart --verbose');
  }
}