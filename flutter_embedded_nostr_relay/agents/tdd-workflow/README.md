# TDD Workflow Agents

## Overview
This directory contains specialized TDD workflow agents designed to work together as a coordinated system for the Flutter Embedded Nostr Relay project. Each agent has specific expertise while following Rabble's CLAUDE.md guidelines for TDD discipline and testing requirements.

## Agent Hierarchy and Coordination

### **Build & Compilation Layer**
**Primary Goal**: Get the code compiling and building correctly

1. **[build-coordinator.md](./build-coordinator.md)** - Master orchestrator
   - Coordinates all build and compilation activities
   - Tracks current critical issues (Level import, crypto method, RelayMessage constructors)
   - Provides health monitoring and emergency protocols

2. **[compilation-fixer.md](./compilation-fixer.md)** - Error resolution specialist  
   - Fixes specific Dart/Flutter compilation errors using TDD approach
   - Handles import resolution, type errors, method call issues
   - Never batches fixes - one error, one test, one fix cycle

3. **[dependency-resolver.md](./dependency-resolver.md)** - Package management expert
   - Resolves import and dependency issues systematically
   - Manages pubspec.yaml and package version conflicts
   - Ensures all required packages are properly imported

### **Test Management Layer**
**Primary Goal**: Ensure comprehensive test coverage following TDD discipline

4. **[test-coordinator.md](./test-coordinator.md)** - Testing strategy orchestrator
   - Enforces NO EXCEPTIONS POLICY (unit + integration + e2e tests for everything)
   - Coordinates comprehensive testing architecture
   - Ensures pristine test output and real implementations (no mocks in e2e)

5. **[test-fixer.md](./test-fixer.md)** - Test repair specialist
   - Fixes broken tests and maintains test integrity
   - Handles assertion adjustments when implementations change
   - Prevents flaky tests and ensures deterministic behavior

6. **[test-runner.md](./test-runner.md)** - Execution and monitoring expert
   - Executes test suites and interprets results
   - Provides detailed failure analysis and performance metrics
   - Manages test environments and generates reports

7. **[tdd-cycle-manager.md](./tdd-cycle-manager.md)** - Red-Green-Refactor enforcer
   - Strictly enforces TDD discipline: failing test first, minimal fix, then refactor
   - Prevents violations of TDD principles
   - Tracks and manages active TDD cycles

### **Quality Assurance Layer**  
**Primary Goal**: Maintain code quality and prevent regressions

8. **[coverage-analyzer.md](./coverage-analyzer.md)** - Coverage gap identifier
   - Analyzes test coverage and identifies untested code paths
   - Ensures critical components (security, crypto) have 100% coverage
   - Generates detailed coverage reports and improvement strategies

9. **[integration-validator.md](./integration-validator.md)** - Component interaction tester
   - Validates that components work together seamlessly
   - Tests realistic usage patterns and performance characteristics
   - Ensures data flows correctly between system components

10. **[regression-tester.md](./regression-tester.md)** - Change impact guardian
    - Prevents regressions during refactoring and fixes
    - Maintains behavioral consistency across changes
    - Monitors performance and compatibility over time

## Current Critical Issues Being Addressed

### 🔥 Priority 1: Compilation Failures
1. **Level import issue** (`embedded_nostr_relay.dart:46`)
   - **Root Cause**: Missing `import 'package:logging/logging.dart';`
   - **Assigned**: compilation-fixer.md + dependency-resolver.md
   - **TDD Approach**: Write failing test first, add import, verify test passes

2. **Crypto SHA256 method issue** (`crypto.dart:20`)
   - **Root Cause**: `sha256Hash.convert()` should be `sha256.convert()`
   - **Assigned**: compilation-fixer.md
   - **TDD Approach**: Write failing crypto test, fix method call, verify test passes

3. **RelayMessage constructor verification** (`relay_message.dart`)
   - **Status**: Need to verify if actually failing
   - **Assigned**: compilation-fixer.md + test-coordinator.md
   - **TDD Approach**: Write comprehensive constructor tests for all message types

## Agent Communication Flow

### Information Flow:
```
build-coordinator → compilation-fixer → dependency-resolver
        ↓
test-coordinator → test-fixer → test-runner → tdd-cycle-manager
        ↓
coverage-analyzer → integration-validator → regression-tester
        ↓
   Report to Rabble
```

### Emergency Escalation:
```
Any Agent Issue → build-coordinator → Rabble
Critical TDD Violation → tdd-cycle-manager → Rabble  
Regression Detected → regression-tester → Rabble
```

## Collective Responsibilities

### All Agents Must:
- ✅ Address Rabble directly (not "the user")
- ✅ Use TodoWrite tool to track progress
- ✅ Follow strict TDD discipline (Red-Green-Refactor)
- ✅ Ask permission before major changes
- ✅ Report specific file paths and line numbers
- ✅ Push back when something seems wrong

### All Agents Must Never:
- ❌ Skip test-first development
- ❌ Use mocks in end-to-end tests
- ❌ Batch multiple fixes together
- ❌ Ignore test output warnings
- ❌ Remove code comments without proof they're false

## Workflow Example: Fixing Level Import Issue

### Step 1: TDD Cycle Manager - RED Phase
```dart
// test/unit/core/embedded_nostr_relay_test.dart
test('should accept Level.INFO as logLevel parameter', () async {
  final relay = EmbeddedNostrRelay();
  await expectLater(
    relay.initialize(logLevel: Level.INFO),
    completes,
  );
});
// RUN: flutter test → ❌ FAILS (Level type not found)
```

### Step 2: Compilation Fixer - GREEN Phase  
```dart
// lib/src/core/embedded_nostr_relay.dart
import 'package:logging/logging.dart';  // ← Add this line

Future<void> initialize({
  Level logLevel = Level.INFO,  // ← Now compiles
  bool enableGarbageCollection = true,
}) async {
  // ... existing implementation
}
// RUN: flutter test → ✅ PASSES
```

### Step 3: TDD Cycle Manager - REFACTOR Phase
```dart
// Extract logger configuration (optional improvement)
static Logger _createLogger(Level level) {
  Logger.root.level = level;
  return Logger('EmbeddedNostrRelay');
}
// RUN: flutter test → ✅ STILL PASSES
```

### Step 4: Integration Validator
```dart
// test/integration/relay_logging_integration_test.dart
test('relay should log with correct level integration', () async {
  final logMessages = <LogRecord>[];
  Logger.root.onRecord.listen(logMessages.add);
  
  final relay = EmbeddedNostrRelay();
  await relay.initialize(logLevel: Level.INFO);
  
  expect(logMessages.any((log) => 
    log.message.contains('Initializing')), isTrue);
});
```

### Step 5: Coverage Analyzer & Regression Tester
- Verify coverage includes new test scenarios
- Confirm no existing functionality was broken
- Add regression tests for future protection

## Getting Started

### For New Development:
1. **build-coordinator.md** - Check compilation status
2. **test-coordinator.md** - Plan comprehensive testing strategy  
3. **tdd-cycle-manager.md** - Begin Red-Green-Refactor cycle
4. **coverage-analyzer.md** - Verify coverage after implementation

### For Bug Fixes:
1. **regression-tester.md** - Establish baseline behavior
2. **tdd-cycle-manager.md** - Write failing test that reproduces bug
3. **compilation-fixer.md** - Apply minimal fix
4. **integration-validator.md** - Verify fix doesn't break integration

### For Refactoring:
1. **regression-tester.md** - Capture current behavior
2. **tdd-cycle-manager.md** - Ensure all tests pass before refactoring
3. **coverage-analyzer.md** - Maintain coverage during refactoring
4. **integration-validator.md** - Verify integration points remain intact

## Success Metrics

### Build Health:
- ✅ `flutter analyze` returns zero issues
- ✅ `flutter test` runs without compilation errors
- ✅ All imports resolve correctly

### Test Health:
- ✅ Unit tests: 90%+ coverage
- ✅ Integration tests: All component pairs tested
- ✅ E2E tests: All user workflows covered
- ✅ Zero test output warnings

### Quality Health:
- ✅ No regressions in existing functionality  
- ✅ Performance within acceptable thresholds
- ✅ All TDD cycles completed properly

Remember: **We are a coordinated team**. Each agent has specialized expertise, but we all work together toward the common goal of a robust, well-tested Flutter Embedded Nostr Relay!