# Integration Tests for Flutter Embedded Nostr Relay

This directory contains comprehensive integration tests that verify the Flutter Embedded Nostr Relay's functionality across various real-world scenarios, protocol compliance, performance characteristics, and error handling capabilities.

## Test Suite Overview

### 🔒 NIP Compliance Tests (`nip_compliance_integration_test.dart`)
**Priority: Critical** | **Duration: ~3 minutes**

Validates strict compliance with Nostr Improvement Proposals (NIPs):
- **NIP-01**: Basic protocol flow, message formats, event structure
- **NIP-09**: Event deletion functionality and validation  
- **NIP-11**: Relay information document (HTTP endpoint)
- **NIP-65**: Relay list metadata and replaceable events
- **Protocol Limits**: Message size, subscription counts, filter validation
- **Event Types**: Regular, replaceable, parameterized replaceable, ephemeral

### 🔄 Multi-Client Interaction Tests (`multi_client_interaction_test.dart`)  
**Priority: High** | **Duration: ~4 minutes**

Tests complex scenarios with multiple concurrent WebSocket clients:
- **Concurrent Subscriptions**: Overlapping filters and subscription management
- **Event Broadcasting**: Real-time routing to all matching subscriptions
- **Connection Management**: Graceful handling of client disconnections
- **Resource Management**: Performance under many concurrent connections
- **Event Ordering**: Consistency across multiple clients

### 💾 Persistence & Recovery Tests (`persistence_recovery_integration_test.dart`)
**Priority: High** | **Duration: ~5 minutes**

Validates data durability and system recovery:
- **Database Persistence**: Event storage across database sessions
- **Server Restart Recovery**: State restoration after shutdown
- **Data Consistency**: Referential integrity and transaction safety
- **Crash Recovery**: Handling unexpected shutdowns
- **Migration Scenarios**: Schema changes and upgrades

### ⚡ Performance Tests (`performance_integration_test.dart`)
**Priority: Medium** | **Duration: ~6 minutes**

Measures performance characteristics under various loads:
- **Throughput**: High-volume event publishing (1000+ events)
- **Concurrent Publishing**: Multiple clients publishing simultaneously  
- **Query Performance**: Large dataset queries and complex filters
- **Memory Efficiency**: Resource usage with many subscriptions
- **Latency**: Real-time event routing response times
- **Stress Testing**: Sustained load over time

### 🛡️ Error Handling Tests (`error_handling_integration_test.dart`)
**Priority: Medium** | **Duration: ~3 minutes**

Validates robustness against various error conditions:
- **Malformed Messages**: Invalid JSON, binary data, oversized messages
- **Invalid Events**: Missing fields, wrong types, invalid signatures
- **Subscription Errors**: Invalid filters, excessive subscriptions
- **Connection Errors**: Abrupt disconnections, network issues
- **Database Errors**: Constraint violations, storage failures
- **Resource Exhaustion**: Memory pressure, connection limits

### 🌍 Real-World Usage Tests (`real_world_usage_integration_test.dart`)
**Priority: Low** | **Duration: ~4 minutes**

Simulates practical Nostr application scenarios:
- **Social Media Workflows**: Posting, reactions, mentions, timelines
- **Content Discovery**: Hashtag-based and author-based discovery
- **Mobile App Patterns**: Backgrounding, syncing, push notifications
- **Community Events**: Event coordination and discussions
- **Content Moderation**: User-initiated filtering
- **Cross-Platform Sync**: Multi-device usage patterns

## Running the Tests

### Quick Start

Run all integration tests:
```bash
dart test/integration/run_integration_tests.dart
```

### Filtering Tests

Run only critical and high priority tests:
```bash  
dart test/integration/run_integration_tests.dart --priority high
```

Run tests matching a pattern:
```bash
dart test/integration/run_integration_tests.dart --filter nip
dart test/integration/run_integration_tests.dart --filter performance
```

### Parallel Execution

Run tests in parallel for faster execution:
```bash
dart test/integration/run_integration_tests.dart --parallel
```

### Verbose Output

Enable detailed output for debugging:
```bash
dart test/integration/run_integration_tests.dart --verbose
```

### Individual Test Suites

Run a specific test suite directly:
```bash
flutter test test/integration/nip_compliance_integration_test.dart
flutter test test/integration/performance_integration_test.dart
```

## Test Configuration

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--filter, -f` | Filter tests by name pattern | `--filter nip` |
| `--priority, -p` | Minimum priority level | `--priority high` |
| `--parallel` | Run tests in parallel | `--parallel` |
| `--verbose, -v` | Enable verbose output | `--verbose` |
| `--help, -h` | Show help message | `--help` |

### Priority Levels

- **Critical**: Core protocol compliance (must pass)
- **High**: Essential functionality (should pass)  
- **Medium**: Performance and error handling (nice to pass)
- **Low**: Real-world scenarios (good to pass)

## Test Reports

The test runner generates detailed reports:

### Console Output
- Real-time progress and results
- Summary statistics  
- Failed test details
- Performance metrics

### JSON Report (`integration_test_report.json`)
- Structured test results
- Execution metrics
- Configuration details
- Failure analysis data

## Test Architecture

### Test Client Classes

**`TestClient`** (Multi-Client Tests)
- WebSocket connection management
- Message sending/receiving
- Response filtering and analysis

**`ErrorTestClient`** (Error Handling Tests)  
- Enhanced error detection
- Binary/malformed message support
- Connection state monitoring

**`LoadTestClient`** (Performance Tests)
- Performance metric collection
- Concurrent operation support
- Message counting and timing

**`NostrUser`** (Real-World Tests)
- High-level Nostr operations
- Social media workflow simulation
- Realistic interaction patterns

### Helper Utilities

**`PerformanceMetrics`**
- Throughput calculation
- Latency measurement  
- Resource usage tracking

**Event Generators**
- Realistic content creation
- Valid/invalid event construction
- Load testing data generation

## Requirements

### Dependencies
- Flutter SDK
- `web_socket_channel` package
- `sqflite_common_ffi` for database testing

### Test Environment
- Desktop platform (Windows, macOS, Linux)
- SQLite FFI support
- Available ports for WebSocket servers

### Resource Requirements
- **Memory**: ~512MB for full test suite
- **CPU**: Multi-core recommended for parallel execution
- **Storage**: ~100MB for temporary databases
- **Network**: Localhost connectivity

## Development Guidelines

### Adding New Tests

1. **Choose appropriate test suite** based on functionality
2. **Follow existing patterns** for client management and assertions
3. **Clean up resources** in `tearDown()` methods
4. **Use descriptive test names** and documentation
5. **Include performance expectations** where relevant

### Test Structure

```dart
group('Feature Category', () {
  test('should handle specific scenario', () async {
    // Setup
    final client = await createTestClient('test-id');
    
    try {
      // Test logic
      // ...
      
      // Assertions
      expect(result, expectedValue);
      
    } finally {
      // Cleanup
      await client.close();
    }
  });
});
```

### Best Practices

- **Isolated Tests**: Each test should be independent
- **Resource Cleanup**: Always close connections and reset databases
- **Realistic Data**: Use valid Nostr event structures
- **Error Handling**: Test both success and failure scenarios
- **Documentation**: Clear descriptions of test purpose and expectations

## Troubleshooting

### Common Issues

**Database Lock Errors**
- Ensure proper cleanup in `tearDown()`
- Check for unclosed connections
- Use `DatabaseHelper.reset()` between tests

**Port Conflicts**  
- Use `port: 0` for random port assignment
- Ensure servers are stopped in `tearDown()`
- Check for lingering processes

**Memory Issues**
- Limit concurrent connections in tests
- Clear response buffers regularly
- Monitor resource usage during development

**Flaky Tests**
- Add appropriate delays for async operations
- Use deterministic data where possible
- Implement proper synchronization

### Debug Mode

Enable verbose logging:
```bash
dart test/integration/run_integration_tests.dart --verbose
```

Run single test with full output:
```bash
flutter test test/integration/nip_compliance_integration_test.dart --verbose
```

## Contributing

When contributing new integration tests:

1. **Follow the established patterns** in existing test files
2. **Document test purpose** clearly in comments
3. **Add to test runner** configuration if creating new suite
4. **Test locally** before submitting
5. **Update this README** with new test descriptions

## Performance Benchmarks

Expected performance baselines:

| Metric | Minimum | Target | Notes |
|--------|---------|--------|-------|
| Event Publishing | 100 events/sec | 500 events/sec | Single client |
| Concurrent Clients | 20 clients | 100 clients | With subscriptions |
| Query Response | <2s | <500ms | 5000 event dataset |
| Memory Usage | <512MB | <256MB | Full test suite |
| Event Latency | <100ms | <50ms | Real-time routing |

These benchmarks help ensure the relay maintains acceptable performance for production use.