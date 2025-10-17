# Flutter Embedded Nostr Relay Performance Benchmarks

A comprehensive performance benchmark suite targeting 100k+ event scenarios for the Flutter Embedded Nostr Relay.

## Overview

This benchmark suite provides thorough performance testing covering all critical aspects of the Nostr relay implementation:

- **Database Operations**: Event storage, retrieval, and indexing performance
- **Event Insertion**: Single and batch insertion rates with various event types
- **Query Performance**: Complex filter performance with large datasets
- **Memory Usage**: Memory efficiency and garbage collection impact
- **Concurrent Operations**: Multi-client performance and resource contention
- **Subscription Routing**: Real-time event routing and filter matching
- **Platform Optimizations**: Performance characteristics across different platforms

## Quick Start

### Run All Benchmarks (Default)
```bash
./test/benchmarks/run_benchmarks.sh
```

### Run Specific Categories
```bash
# Database benchmarks only
./test/benchmarks/run_benchmarks.sh --category database

# Query performance with detailed report  
./test/benchmarks/run_benchmarks.sh --category query --report detailed

# Memory benchmarks with custom event count
./test/benchmarks/run_benchmarks.sh --category memory --events 50000
```

### Generate Detailed Reports
```bash
# Detailed HTML report with charts
./test/benchmarks/run_benchmarks.sh --report detailed

# Full data dump for analysis
./test/benchmarks/run_benchmarks.sh --report full --verbose
```

## Benchmark Categories

### Database Operations
- **DatabaseInsert**: Single event insertion performance
- **DatabaseBatchInsert**: Bulk insertion with various batch sizes
- **DatabaseQuery**: Basic query performance with different filters
- **DatabaseIndexPerformance**: Query performance with large datasets
- **DatabaseReplaceableEvent**: Replaceable event handling efficiency
- **DatabaseConcurrentAccess**: Concurrent read/write performance
- **DatabaseMaintenance**: VACUUM and maintenance operation impact

### Event Insertion
- **SingleEventInsertion**: Individual event insertion rates
- **BatchEventInsertion**: Batch insertion optimization
- **ConcurrentInsertion**: Concurrent insertion performance
- **LargeEventInsertion**: Performance with large content and many tags
- **ReplaceableEventInsertion**: Replaceable event processing overhead
- **MixedEventInsertion**: Realistic mix of event types
- **HighFrequencyInsertion**: Peak usage simulation

### Query Performance
- **SimpleKindQuery**: Basic kind-based filtering (most common pattern)
- **AuthorQuery**: Author-based queries and following lists
- **TagQuery**: Hashtag, mention, and reference queries
- **ComplexFilterQuery**: Multi-condition filter combinations
- **TimeRangeQuery**: Timeline and pagination queries
- **LimitedQuery**: Performance scaling with result set size
- **MultiFilterQuery**: Multiple filters in single query

### Memory Management
- **MemoryGrowth**: Memory usage patterns during database growth
- **MemoryEfficiency**: Memory allocation during query operations
- **LargeDatasetMemory**: Memory behavior with very large datasets
- **MemoryLeakDetection**: Long-running operation leak detection
- **MemoryPressure**: Performance under memory constraints
- **GarbageCollectionImpact**: GC timing impact on operations
- **ConcurrentMemory**: Memory usage during concurrent operations

### Concurrent Operations
- **ConcurrentReadWrite**: Mixed read/write workload performance
- **MultiClient**: Multiple client simulation
- **Contention**: Resource contention and hotspot performance
- **Scalability**: Performance scaling with concurrent load
- **ConcurrentSubscription**: Concurrent subscription management

### Subscription Routing
- **SubscriptionRouting**: Basic event routing performance
- **ManySubscriptions**: Performance with large numbers of subscriptions
- **FilterMatching**: Complex filter matching efficiency
- **RealTimeRouting**: End-to-end real-time event distribution

### Garbage Collection
- **GarbageCollectionPerformance**: GC impact on database operations
- **GarbageCollectionImpact**: GC effects on query performance
- **DatabaseVacuum**: Database maintenance operation performance
- **DatabaseMaintenance**: Various maintenance operations
- **LongRunningMemory**: Extended operation memory behavior

## Configuration Options

### Command Line Arguments

```bash
./test/benchmarks/run_benchmarks.sh [options]

Options:
  -e, --events N       Number of events for testing (default: 100000)
  -c, --category CAT   Benchmark category to run (default: all)
  -r, --report LEVEL   Report detail level (default: summary)  
  -v, --verbose        Enable verbose output
  -h, --help           Show help message

Categories:
  database, insertion, query, memory, concurrent, subscription, gc, all

Report Levels:
  summary   - Basic metrics and pass/fail status
  detailed  - Full metrics with HTML charts
  full      - Complete data dump with analysis
```

### Direct Dart Execution

```bash
# Run with custom configuration
dart test/benchmarks/benchmark_runner.dart --events=50000 --category=database --report=detailed

# Verbose output
dart test/benchmarks/benchmark_runner.dart --verbose

# Help
dart test/benchmarks/benchmark_runner.dart --help
```

## Performance Targets

The benchmark suite includes performance targets for 100k+ event scenarios:

### Event Insertion
- **Single Insertion**: 1,000+ operations/second
- **Batch Insertion**: 5,000+ operations/second  
- **Concurrent Insertion**: 500+ operations/second

### Query Performance
- **Simple Queries**: <50ms latency
- **Complex Queries**: <200ms latency
- **Large Result Sets**: <500ms latency

### Memory Usage
- **Growth Rate**: <1MB per 1k events
- **Query Overhead**: <500KB per query
- **Leak Rate**: <100KB/hour

### Concurrent Operations
- **Multi-Client**: 100+ operations/second
- **Contention Overhead**: <50% performance impact

## Report Output

### File Locations
- `test/benchmarks/reports/latest_results.json` - Raw benchmark data
- `test/benchmarks/reports/latest_summary.md` - Performance summary
- `test/benchmarks/reports/latest_report.html` - Detailed HTML report

### Report Contents

#### Summary Report (Markdown)
- Overall pass/fail status
- Performance summary by category
- 100k+ event performance assessment
- Memory usage analysis
- Recommendations for optimization

#### Detailed Report (HTML)
- Interactive performance charts
- Detailed results table with color coding
- Category-wise performance analysis
- Memory usage visualization
- Target vs. actual performance comparison

#### Full Data Dump (JSON)
- Complete benchmark results
- Configuration details
- Performance analysis data
- Raw metrics for external analysis

## Interpreting Results

### Performance Indicators
- **✅ Green**: Performance targets met
- **⚠️ Yellow**: Below target but acceptable
- **❌ Red**: Performance issues require attention

### Key Metrics
- **Operations/Second**: Higher is better for throughput
- **Latency (μs/ms)**: Lower is better for response time
- **Memory Delta**: Lower is better for efficiency
- **Success Rate**: Should be 100% for production readiness

### Common Issues
1. **High Memory Usage**: May indicate memory leaks or inefficient operations
2. **Poor Query Performance**: Often solved with better indexing
3. **Low Insertion Rates**: May benefit from batch optimization
4. **Concurrent Contention**: Indicates need for better resource management

## Customization

### Adding Custom Benchmarks

1. Create new benchmark class extending `BenchmarkBase`
2. Implement required methods: `setup()`, `teardown()`, `run()`
3. Add to appropriate benchmark file or create new category
4. Update `benchmark_runner.dart` to include new benchmark

### Custom Performance Targets

Edit `BenchmarkUtils.performanceTargets` in `test/utils/benchmark_utils.dart`:

```dart
static const Map<String, Map<String, double>> performanceTargets = {
  'custom_category': {
    'target_metric': 1000.0,
    'latency_target': 50.0,
  },
};
```

### Custom Report Generation

Extend `ReportGenerator` in `test/utils/report_generator.dart` to add custom report formats or analysis.

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Performance Benchmarks

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  benchmarks:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: dart-lang/setup-dart@v1
    
    - name: Install dependencies
      run: dart pub get
      
    - name: Run performance benchmarks
      run: ./test/benchmarks/run_benchmarks.sh --events=25000 --report=detailed
      
    - name: Upload benchmark results
      uses: actions/upload-artifact@v3
      with:
        name: benchmark-reports
        path: test/benchmarks/reports/
```

### Performance Regression Detection

Set up automated alerts for performance regressions:

```bash
# Example script to check for regressions
./test/benchmarks/run_benchmarks.sh --report=full
python scripts/check_performance_regression.py test/benchmarks/reports/latest_results.json
```

## Dependencies

- `benchmark_harness: ^2.3.0` - Core benchmarking framework
- `sqflite_common_ffi: ^2.3.3` - Database testing support
- Dart SDK 3.8.1+
- Flutter 3.0.0+

## Troubleshooting

### Common Issues

1. **"Dart SDK not found"**
   - Install Dart SDK: https://dart.dev/get-dart

2. **"Must be run from root directory"**
   - Ensure you're in `flutter_embedded_nostr_relay/` directory

3. **Out of memory errors**
   - Reduce event count: `--events=10000`
   - Run specific categories instead of all

4. **Slow benchmark execution**
   - Use smaller event counts for development
   - Run specific categories during development
   - Full runs for CI/production validation

### Performance Tips

1. **Development**: Use `--events=10000` for faster iteration
2. **CI/CD**: Use `--events=50000` for reasonable CI times  
3. **Release**: Use `--events=100000+` for full validation
4. **Memory constrained**: Use `--category` to run specific tests

## Contributing

When adding new benchmarks:

1. Follow existing naming conventions
2. Include comprehensive documentation
3. Add appropriate performance targets
4. Update this README with new benchmark descriptions
5. Test with various event counts and configurations

## License

This benchmark suite is part of the Flutter Embedded Nostr Relay project and follows the same license terms.