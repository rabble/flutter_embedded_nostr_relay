// ABOUTME: Performance report generation tools for benchmark results
// ABOUTME: Creates detailed HTML, JSON, and markdown reports with analysis and visualizations

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'benchmark_utils.dart';

/// Generates comprehensive performance reports from benchmark results.
/// 
/// Creates multiple report formats including detailed HTML reports,
/// machine-readable JSON data, and summary markdown files.
class ReportGenerator {
  static const String _reportsDir = 'test/benchmarks/reports';
  
  /// Generate performance reports in multiple formats.
  /// 
  /// Creates comprehensive reports based on the specified detail level:
  /// - 'summary': Basic performance metrics and pass/fail status
  /// - 'detailed': Full metrics with charts and analysis
  /// - 'full': Complete data dump with raw results
  Future<void> generateReport(
    BenchmarkSuiteResult results, 
    String reportLevel
  ) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    
    // Ensure reports directory exists
    await Directory(_reportsDir).create(recursive: true);
    
    // Generate JSON report (always created for data preservation)
    await _generateJsonReport(results, timestamp);
    
    // Generate reports based on level
    switch (reportLevel) {
      case 'summary':
        await _generateSummaryReport(results, timestamp);
        break;
      case 'detailed':
        await _generateDetailedReport(results, timestamp);
        await _generateSummaryReport(results, timestamp);
        break;
      case 'full':
        await _generateDetailedReport(results, timestamp);
        await _generateSummaryReport(results, timestamp);
        await _generateFullDataDump(results, timestamp);
        break;
    }
    
    // Generate latest symlinks/copies for easy access
    await _updateLatestReports(timestamp);
  }

  /// Generate machine-readable JSON report.
  Future<void> _generateJsonReport(BenchmarkSuiteResult results, String timestamp) async {
    final jsonData = results.toJson();
    
    final file = File('$_reportsDir/benchmark_results_$timestamp.json');
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(jsonData));
  }

  /// Generate summary markdown report.
  Future<void> _generateSummaryReport(BenchmarkSuiteResult results, String timestamp) async {
    final buffer = StringBuffer();
    
    buffer.writeln('# Flutter Embedded Nostr Relay Performance Summary');
    buffer.writeln();
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Event Count: ${results.config.eventCount}');
    buffer.writeln('Total Duration: ${results.totalDuration?.inSeconds ?? 0}s');
    buffer.writeln();
    
    // Overall status
    buffer.writeln('## Overall Results');
    buffer.writeln();
    buffer.writeln('- **Status**: ${results.success ? "✅ PASSED" : "❌ FAILED"}');
    buffer.writeln('- **Total Benchmarks**: ${results.results.length}');
    buffer.writeln('- **Successful**: ${results.successfulBenchmarks}');
    buffer.writeln('- **Failed**: ${results.failedBenchmarks}');
    buffer.writeln();
    
    if (results.successfulBenchmarks > 0) {
      // Performance summary
      buffer.writeln('## Performance Summary');
      buffer.writeln();
      
      final successfulResults = results.results.where((r) => r.success).toList();
      
      // Group by category
      final categories = <String, List<BenchmarkResult>>{};
      for (final result in successfulResults) {
        final category = _extractCategory(result.name);
        categories[category] = (categories[category] ?? [])..add(result);
      }
      
      for (final category in categories.keys) {
        buffer.writeln('### ${_formatCategoryName(category)}');
        buffer.writeln();
        
        final categoryResults = categories[category]!;
        final avgOps = categoryResults.map((r) => r.operationsPerSecond)
            .reduce((a, b) => a + b) / categoryResults.length;
        
        buffer.writeln('- **Average Performance**: ${avgOps.toStringAsFixed(0)} ops/sec');
        buffer.writeln('- **Benchmarks**: ${categoryResults.length}');
        
        // Check targets
        final targetMet = _checkCategoryTargets(category, categoryResults);
        buffer.writeln('- **Target Status**: ${targetMet ? "✅ MET" : "⚠️ BELOW TARGET"}');
        buffer.writeln();
        
        // Top performers in category
        final sortedResults = categoryResults.toList()
          ..sort((a, b) => b.operationsPerSecond.compareTo(a.operationsPerSecond));
        
        buffer.writeln('**Top Performers:**');
        for (int i = 0; i < min(3, sortedResults.length); i++) {
          final result = sortedResults[i];
          buffer.writeln('${i + 1}. ${result.name}: ${result.operationsPerSecond.toStringAsFixed(0)} ops/sec');
        }
        buffer.writeln();
      }
      
      // 100k+ Event Performance Assessment
      buffer.writeln('## 100k+ Event Performance Assessment');
      buffer.writeln();
      
      final assessments = _assess100kPerformance(results);
      for (final assessment in assessments.entries) {
        final status = assessment.value['status'] as bool;
        final value = assessment.value['value'];
        final target = assessment.value['target'];
        
        buffer.writeln('- **${assessment.key}**: ${status ? "✅" : "⚠️"} $value (target: $target)');
      }
      buffer.writeln();
    }
    
    if (results.failedBenchmarks > 0) {
      buffer.writeln('## Failed Benchmarks');
      buffer.writeln();
      
      final failedResults = results.results.where((r) => !r.success).toList();
      for (final result in failedResults) {
        buffer.writeln('- **${result.name}**: ${result.error ?? "Unknown error"}');
      }
      buffer.writeln();
    }
    
    // Memory usage summary
    buffer.writeln('## Memory Usage Summary');
    buffer.writeln();
    
    if (results.successfulBenchmarks > 0) {
      final memoryResults = results.results.where((r) => r.success).toList();
      final avgMemoryDelta = memoryResults
          .map((r) => r.memoryDelta)
          .reduce((a, b) => a + b) / memoryResults.length;
      
      buffer.writeln('- **Average Memory Delta**: ${avgMemoryDelta.toStringAsFixed(0)} KB');
      buffer.writeln('- **Total Memory Delta**: ${results.totalMemoryDelta} KB');
      
      final efficiency = _assessMemoryEfficiency(avgMemoryDelta);
      buffer.writeln('- **Memory Efficiency**: $efficiency');
    } else {
      buffer.writeln('- No successful benchmarks for memory analysis');
    }
    buffer.writeln();
    
    // Recommendations
    buffer.writeln('## Recommendations');
    buffer.writeln();
    
    final recommendations = _generateRecommendations(results);
    for (final recommendation in recommendations) {
      buffer.writeln('- $recommendation');
    }
    
    final file = File('$_reportsDir/performance_summary_$timestamp.md');
    await file.writeAsString(buffer.toString());
  }

  /// Generate detailed HTML report with charts and analysis.
  Future<void> _generateDetailedReport(BenchmarkSuiteResult results, String timestamp) async {
    final buffer = StringBuffer();
    
    // HTML header
    buffer.writeln('''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flutter Embedded Nostr Relay Performance Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 15px; }
        h3 { color: #7f8c8d; }
        .status-success { color: #27ae60; font-weight: bold; }
        .status-failure { color: #e74c3c; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .metric-card { background: #ecf0f1; padding: 15px; margin: 10px 0; border-radius: 5px; display: inline-block; min-width: 200px; margin-right: 15px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #2c3e50; }
        .metric-label { color: #7f8c8d; font-size: 14px; }
        .chart-container { width: 100%; height: 400px; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .performance-good { background-color: #d5f4e6; }
        .performance-warning { background-color: #ffeaa7; }
        .performance-poor { background-color: #fab1a0; }
        .code { background: #2c3e50; color: #ecf0f1; padding: 10px; border-radius: 5px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Flutter Embedded Nostr Relay Performance Report</h1>
        <p><strong>Generated:</strong> ${DateTime.now().toIso8601String()}</p>
        <p><strong>Configuration:</strong> ${results.config.eventCount} events, ${results.config.maxConcurrency} max concurrency</p>
        <p><strong>Duration:</strong> ${results.totalDuration?.inSeconds ?? 0} seconds</p>
''');

    // Overall status section
    buffer.writeln('<h2>📊 Overall Results</h2>');
    buffer.writeln('<div class="metric-card">');
    buffer.writeln('<div class="metric-value ${results.success ? 'status-success' : 'status-failure'}">${results.success ? 'PASSED' : 'FAILED'}</div>');
    buffer.writeln('<div class="metric-label">Overall Status</div>');
    buffer.writeln('</div>');
    
    buffer.writeln('<div class="metric-card">');
    buffer.writeln('<div class="metric-value">${results.results.length}</div>');
    buffer.writeln('<div class="metric-label">Total Benchmarks</div>');
    buffer.writeln('</div>');
    
    buffer.writeln('<div class="metric-card">');
    buffer.writeln('<div class="metric-value status-success">${results.successfulBenchmarks}</div>');
    buffer.writeln('<div class="metric-label">Successful</div>');
    buffer.writeln('</div>');
    
    if (results.failedBenchmarks > 0) {
      buffer.writeln('<div class="metric-card">');
      buffer.writeln('<div class="metric-value status-failure">${results.failedBenchmarks}</div>');
      buffer.writeln('<div class="metric-label">Failed</div>');
      buffer.writeln('</div>');
    }
    
    // Performance charts
    if (results.successfulBenchmarks > 0) {
      buffer.writeln('<h2>📈 Performance Charts</h2>');
      
      // Operations per second chart
      buffer.writeln('<h3>Operations Per Second by Benchmark</h3>');
      buffer.writeln('<div class="chart-container">');
      buffer.writeln('<canvas id="opsChart"></canvas>');
      buffer.writeln('</div>');
      
      // Memory usage chart
      buffer.writeln('<h3>Memory Usage by Benchmark</h3>');
      buffer.writeln('<div class="chart-container">');
      buffer.writeln('<canvas id="memoryChart"></canvas>');
      buffer.writeln('</div>');
      
      // Category performance chart
      buffer.writeln('<h3>Average Performance by Category</h3>');
      buffer.writeln('<div class="chart-container">');
      buffer.writeln('<canvas id="categoryChart"></canvas>');
      buffer.writeln('</div>');
    }
    
    // Detailed results table
    buffer.writeln('<h2>📋 Detailed Results</h2>');
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln('<tr><th>Benchmark</th><th>Status</th><th>Ops/Sec</th><th>Score (μs)</th><th>Memory Δ (KB)</th><th>Duration (ms)</th></tr>');
    buffer.writeln('</thead>');
    buffer.writeln('<tbody>');
    
    for (final result in results.results) {
      final rowClass = result.success 
          ? (result.operationsPerSecond > 1000 ? 'performance-good' 
             : result.operationsPerSecond > 100 ? 'performance-warning' 
             : 'performance-poor')
          : 'performance-poor';
      
      buffer.writeln('<tr class="$rowClass">');
      buffer.writeln('<td>${result.name}</td>');
      buffer.writeln('<td class="${result.success ? 'status-success' : 'status-failure'}">${result.success ? '✅ PASS' : '❌ FAIL'}</td>');
      buffer.writeln('<td>${result.success ? result.operationsPerSecond.toStringAsFixed(0) : 'N/A'}</td>');
      buffer.writeln('<td>${result.success ? result.score.toStringAsFixed(2) : 'N/A'}</td>');
      buffer.writeln('<td>${result.memoryDelta}</td>');
      buffer.writeln('<td>${result.duration.inMilliseconds}</td>');
      buffer.writeln('</tr>');
    }
    
    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    
    // 100k Performance Assessment
    buffer.writeln('<h2>🎯 100k+ Event Performance Assessment</h2>');
    final assessments = _assess100kPerformance(results);
    
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln('<tr><th>Metric</th><th>Current</th><th>Target</th><th>Status</th></tr>');
    buffer.writeln('</thead>');
    buffer.writeln('<tbody>');
    
    for (final assessment in assessments.entries) {
      final status = assessment.value['status'] as bool;
      final value = assessment.value['value'];
      final target = assessment.value['target'];
      final statusClass = status ? 'status-success' : 'status-warning';
      
      buffer.writeln('<tr>');
      buffer.writeln('<td>${assessment.key}</td>');
      buffer.writeln('<td>$value</td>');
      buffer.writeln('<td>$target</td>');
      buffer.writeln('<td class="$statusClass">${status ? '✅ MET' : '⚠️ BELOW'}</td>');
      buffer.writeln('</tr>');
    }
    
    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    
    // JavaScript for charts
    buffer.writeln('<script>');
    _generateChartScript(buffer, results);
    buffer.writeln('</script>');
    
    buffer.writeln('</div></body></html>');
    
    final file = File('$_reportsDir/performance_report_$timestamp.html');
    await file.writeAsString(buffer.toString());
  }

  /// Generate full data dump for analysis.
  Future<void> _generateFullDataDump(BenchmarkSuiteResult results, String timestamp) async {
    final fullData = {
      'metadata': {
        'generated_at': DateTime.now().toIso8601String(),
        'generator_version': '1.0.0',
        'benchmark_suite_version': '1.0.0',
      },
      'configuration': results.config.toJson(),
      'results': results.toJson(),
      'analysis': {
        'performance_targets': BenchmarkUtils.performanceTargets,
        'category_analysis': _analyzeCategoryPerformance(results),
        'memory_analysis': _analyzeMemoryUsage(results),
        'recommendations': _generateRecommendations(results),
      },
    };
    
    final file = File('$_reportsDir/full_data_dump_$timestamp.json');
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(fullData));
  }

  /// Update latest report links for easy access.
  Future<void> _updateLatestReports(String timestamp) async {
    final updates = [
      ['benchmark_results_$timestamp.json', 'latest_results.json'],
      ['performance_summary_$timestamp.md', 'latest_summary.md'],
      ['performance_report_$timestamp.html', 'latest_report.html'],
    ];
    
    for (final update in updates) {
      final source = File('$_reportsDir/${update[0]}');
      final target = File('$_reportsDir/${update[1]}');
      
      if (await source.exists()) {
        try {
          if (await target.exists()) {
            await target.delete();
          }
          await source.copy(target.path);
        } catch (e) {
          // Ignore copy errors - not critical
        }
      }
    }
  }

  String _extractCategory(String benchmarkName) {
    final name = benchmarkName.toLowerCase();
    if (name.contains('database')) return 'database';
    if (name.contains('insertion') || name.contains('insert')) return 'insertion';
    if (name.contains('query')) return 'query';
    if (name.contains('memory')) return 'memory';
    if (name.contains('concurrent')) return 'concurrent';
    if (name.contains('subscription')) return 'subscription';
    if (name.contains('gc') || name.contains('garbage')) return 'gc';
    return 'other';
  }

  String _formatCategoryName(String category) {
    switch (category) {
      case 'database': return 'Database Operations';
      case 'insertion': return 'Event Insertion';
      case 'query': return 'Query Performance';
      case 'memory': return 'Memory Management';
      case 'concurrent': return 'Concurrent Operations';
      case 'subscription': return 'Subscription Routing';
      case 'gc': return 'Garbage Collection';
      default: return 'Other';
    }
  }

  bool _checkCategoryTargets(String category, List<BenchmarkResult> results) {
    final targets = BenchmarkUtils.performanceTargets[category];
    if (targets == null) return true;
    
    final avgOps = results.map((r) => r.operationsPerSecond)
        .reduce((a, b) => a + b) / results.length;
    
    // Simplified target checking - in reality would be more sophisticated
    switch (category) {
      case 'insertion':
        return avgOps >= (targets['single_ops_per_second'] ?? 1000);
      case 'query':
        return avgOps >= 20; // 50ms = ~20 ops/sec
      case 'concurrent':
        return avgOps >= (targets['multi_client_ops_per_second'] ?? 100);
      default:
        return avgOps >= 100; // Generic target
    }
  }

  Map<String, Map<String, dynamic>> _assess100kPerformance(BenchmarkSuiteResult results) {
    final assessment = <String, Map<String, dynamic>>{};
    
    // Event Insertion Rate
    final insertionResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('insertion'))
        .toList();
    
    if (insertionResults.isNotEmpty) {
      final avgInsertionRate = insertionResults
          .map((r) => r.operationsPerSecond)
          .reduce((a, b) => a + b) / insertionResults.length;
      
      assessment['Event Insertion Rate'] = {
        'value': '${avgInsertionRate.toStringAsFixed(0)} ops/sec',
        'target': '1000+ ops/sec',
        'status': avgInsertionRate >= 1000,
      };
    }
    
    // Query Latency
    final queryResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('query'))
        .toList();
    
    if (queryResults.isNotEmpty) {
      final avgQueryLatency = queryResults
          .map((r) => r.score / 1000) // Convert μs to ms
          .reduce((a, b) => a + b) / queryResults.length;
      
      assessment['Query Latency'] = {
        'value': '${avgQueryLatency.toStringAsFixed(1)}ms',
        'target': '<50ms',
        'status': avgQueryLatency < 50,
      };
    }
    
    // Memory Efficiency
    final memoryResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('memory'))
        .toList();
    
    if (memoryResults.isNotEmpty) {
      final avgMemoryDelta = memoryResults
          .map((r) => r.memoryDelta)
          .reduce((a, b) => a + b) / memoryResults.length;
      
      assessment['Memory Efficiency'] = {
        'value': _assessMemoryEfficiency(avgMemoryDelta),
        'target': 'Good',
        'status': avgMemoryDelta < 5000, // Less than 5MB growth is good
      };
    }
    
    // Concurrent Performance
    final concurrentResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('concurrent'))
        .toList();
    
    if (concurrentResults.isNotEmpty) {
      final avgConcurrentRate = concurrentResults
          .map((r) => r.operationsPerSecond)
          .reduce((a, b) => a + b) / concurrentResults.length;
      
      assessment['Concurrent Performance'] = {
        'value': '${avgConcurrentRate.toStringAsFixed(0)} ops/sec',
        'target': '100+ ops/sec',
        'status': avgConcurrentRate >= 100,
      };
    }
    
    return assessment;
  }

  String _assessMemoryEfficiency(double avgMemoryDelta) {
    if (avgMemoryDelta < 1000) return 'Excellent';
    if (avgMemoryDelta < 5000) return 'Good';
    if (avgMemoryDelta < 10000) return 'Fair';
    return 'Poor';
  }

  List<String> _generateRecommendations(BenchmarkSuiteResult results) {
    final recommendations = <String>[];
    
    // Check for failed benchmarks
    if (results.failedBenchmarks > 0) {
      recommendations.add('Address ${results.failedBenchmarks} failed benchmark(s) before production deployment');
    }
    
    // Check insertion performance
    final insertionResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('insertion'))
        .toList();
    
    if (insertionResults.isNotEmpty) {
      final avgRate = insertionResults
          .map((r) => r.operationsPerSecond)
          .reduce((a, b) => a + b) / insertionResults.length;
      
      if (avgRate < 500) {
        recommendations.add('Insertion performance is below optimal - consider batch insertion optimization');
      }
    }
    
    // Check memory usage
    if (results.totalMemoryDelta > 50000) { // 50MB+
      recommendations.add('High memory usage detected - review memory management and consider garbage collection tuning');
    }
    
    // Check query performance
    final queryResults = results.results
        .where((r) => r.success && r.name.toLowerCase().contains('query'))
        .toList();
    
    if (queryResults.isNotEmpty) {
      final avgLatency = queryResults
          .map((r) => r.score / 1000)
          .reduce((a, b) => a + b) / queryResults.length;
      
      if (avgLatency > 100) { // 100ms+
        recommendations.add('Query latency is high - consider database indexing optimization');
      }
    }
    
    // General recommendations
    if (results.successfulBenchmarks > 0) {
      recommendations.add('Monitor performance in production environment with real-world data patterns');
      recommendations.add('Consider running benchmarks periodically to detect performance regressions');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Performance looks good! Continue monitoring in production.');
    }
    
    return recommendations;
  }

  Map<String, dynamic> _analyzeCategoryPerformance(BenchmarkSuiteResult results) {
    final analysis = <String, dynamic>{};
    
    final categories = <String, List<BenchmarkResult>>{};
    for (final result in results.results.where((r) => r.success)) {
      final category = _extractCategory(result.name);
      categories[category] = (categories[category] ?? [])..add(result);
    }
    
    for (final category in categories.keys) {
      final categoryResults = categories[category]!;
      
      analysis[category] = {
        'count': categoryResults.length,
        'avg_ops_per_second': categoryResults
            .map((r) => r.operationsPerSecond)
            .reduce((a, b) => a + b) / categoryResults.length,
        'avg_memory_delta': categoryResults
            .map((r) => r.memoryDelta)
            .reduce((a, b) => a + b) / categoryResults.length,
        'best_performer': categoryResults
            .reduce((a, b) => a.operationsPerSecond > b.operationsPerSecond ? a : b)
            .name,
      };
    }
    
    return analysis;
  }

  Map<String, dynamic> _analyzeMemoryUsage(BenchmarkSuiteResult results) {
    final successfulResults = results.results.where((r) => r.success).toList();
    
    if (successfulResults.isEmpty) {
      return {'status': 'no_data'};
    }
    
    final memoryDeltas = successfulResults.map((r) => r.memoryDelta).toList()
      ..sort();
    
    return {
      'total_delta': results.totalMemoryDelta,
      'average_delta': results.totalMemoryDelta / successfulResults.length,
      'median_delta': memoryDeltas[memoryDeltas.length ~/ 2],
      'max_delta': memoryDeltas.last,
      'min_delta': memoryDeltas.first,
      'high_memory_benchmarks': successfulResults
          .where((r) => r.memoryDelta > 5000)
          .map((r) => r.name)
          .toList(),
    };
  }

  void _generateChartScript(StringBuffer buffer, BenchmarkSuiteResult results) {
    final successfulResults = results.results.where((r) => r.success).toList();
    
    // Operations per second chart
    buffer.writeln('''
const opsCtx = document.getElementById('opsChart').getContext('2d');
new Chart(opsCtx, {
    type: 'bar',
    data: {
        labels: ${jsonEncode(successfulResults.map((r) => r.name).toList())},
        datasets: [{
            label: 'Operations per Second',
            data: ${jsonEncode(successfulResults.map((r) => r.operationsPerSecond).toList())},
            backgroundColor: 'rgba(52, 152, 219, 0.8)',
            borderColor: 'rgba(52, 152, 219, 1)',
            borderWidth: 1
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
            y: {
                beginAtZero: true,
                title: {
                    display: true,
                    text: 'Operations per Second'
                }
            }
        }
    }
});
''');

    // Memory usage chart
    buffer.writeln('''
const memoryCtx = document.getElementById('memoryChart').getContext('2d');
new Chart(memoryCtx, {
    type: 'bar',
    data: {
        labels: ${jsonEncode(successfulResults.map((r) => r.name).toList())},
        datasets: [{
            label: 'Memory Delta (KB)',
            data: ${jsonEncode(successfulResults.map((r) => r.memoryDelta).toList())},
            backgroundColor: 'rgba(231, 76, 60, 0.8)',
            borderColor: 'rgba(231, 76, 60, 1)',
            borderWidth: 1
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
            y: {
                title: {
                    display: true,
                    text: 'Memory Delta (KB)'
                }
            }
        }
    }
});
''');

    // Category performance chart
    final categories = <String, List<BenchmarkResult>>{};
    for (final result in successfulResults) {
      final category = _extractCategory(result.name);
      categories[category] = (categories[category] ?? [])..add(result);
    }
    
    final categoryLabels = categories.keys.map(_formatCategoryName).toList();
    final categoryAvgs = categories.values.map((results) => 
        results.map((r) => r.operationsPerSecond).reduce((a, b) => a + b) / results.length
    ).toList();
    
    buffer.writeln('''
const categoryCtx = document.getElementById('categoryChart').getContext('2d');
new Chart(categoryCtx, {
    type: 'doughnut',
    data: {
        labels: ${jsonEncode(categoryLabels)},
        datasets: [{
            data: ${jsonEncode(categoryAvgs)},
            backgroundColor: [
                'rgba(52, 152, 219, 0.8)',
                'rgba(46, 204, 113, 0.8)',
                'rgba(155, 89, 182, 0.8)',
                'rgba(241, 196, 15, 0.8)',
                'rgba(230, 126, 34, 0.8)',
                'rgba(231, 76, 60, 0.8)',
                'rgba(149, 165, 166, 0.8)'
            ]
        }]
    },
    options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                position: 'bottom'
            }
        }
    }
});
''');
  }
}