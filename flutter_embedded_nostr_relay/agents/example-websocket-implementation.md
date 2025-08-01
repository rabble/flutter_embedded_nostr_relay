# Example: Using Agents to Implement WebSocket Server

This example demonstrates how to use the agent system to implement the local WebSocket server feature.

## Step 1: Planning with Master Coordinator

```
PROMPT TO MASTER COORDINATOR:
"Create a detailed implementation plan for the local WebSocket server that will listen on port 7447. Consider platform differences, message handling, subscription management, and integration with the existing EventStore."

EXPECTED OUTPUT:
- Task breakdown with dependencies
- Integration points with existing code  
- Platform-specific considerations
- Test strategy
- Performance requirements
```

## Step 2: Architecture Design with Protocol Lead

```
PROMPT TO PROTOCOL IMPLEMENTATION LEAD:
"Design the WebSocket server architecture for the embedded relay. Define:
1. Message handler interface
2. Subscription manager integration  
3. Connection lifecycle management
4. Error handling strategy
5. Platform-specific implementations"

EXPECTED OUTPUT:
- Class diagrams
- Interface definitions
- Message flow documentation
- Error handling patterns
```

## Step 3: Implementation with WebSocket Server Agent

```
PROMPT TO WEBSOCKET SERVER AGENT:
"Implement the WebSocket server following TDD:

1. First write failing tests for:
   - Server starts on port 7447
   - Accepts WebSocket connections
   - Handles REQ messages
   - Sends EVENT messages to subscribers
   - Handles client disconnection

2. Then implement the server with:
   - Platform conditional imports
   - Proper error handling
   - Connection management
   - Integration with EventStore

Use the existing project structure:
- lib/src/network/websocket_server.dart (non-web)
- lib/src/network/websocket_server_web.dart (web stub)

Follow CLAUDE.md guidelines, especially ABOUTME comments."

EXPECTED OUTPUT:
- Test file with comprehensive tests
- WebSocket server implementation
- Platform-specific code
- Integration with existing systems
```

## Step 4: Message Handling Implementation

```
PROMPT TO WEBSOCKET SERVER AGENT:
"Implement message handling for the WebSocket server using TDD:

1. Write tests for parsing:
   - REQ messages with filters
   - EVENT messages for publishing  
   - CLOSE messages
   - Invalid message handling

2. Implement handler that:
   - Parses JSON arrays to RelayMessage objects
   - Routes to appropriate handlers
   - Manages subscriptions
   - Sends responses (EVENT, EOSE, OK, NOTICE)

Integrate with existing RelayMessage classes and SubscriptionManager."
```

## Step 5: Testing with Test Writer Agent

```
PROMPT TO TEST WRITER AGENT:
"Create comprehensive integration tests for the WebSocket server:

1. Server lifecycle tests
2. Multiple client connections
3. Subscription management across clients
4. Message broadcast tests
5. Error scenarios
6. Platform-specific tests

Use real WebSocket clients, no mocks. Test with realistic data volumes."
```

## Step 6: Performance Validation

```
PROMPT TO PERFORMANCE BENCHMARK AGENT:
"Benchmark the WebSocket server implementation:

1. Connection handling (target: 1000+ concurrent)
2. Message throughput (target: 10k messages/second)
3. Query response time (target: <10ms)
4. Memory usage with many subscriptions
5. CPU usage under load

Create benchmarks that can be run in CI."
```

## Step 7: Security Audit

```
PROMPT TO SECURITY AUDITOR AGENT:
"Audit the WebSocket server for security issues:

1. Input validation on all messages
2. Resource exhaustion attacks
3. Frame size limits
4. Authentication considerations
5. Cross-origin concerns for web

Document any vulnerabilities and suggest fixes."
```

## Step 8: Documentation

```
PROMPT TO DOCUMENTATION AGENT:
"Document the WebSocket server API:

1. Connection details (ws://localhost:7447)
2. Message format specifications
3. Error responses
4. Example client code
5. Platform differences

Create both API reference and tutorial documentation."
```

## Complete Working Example

Here's how the actual implementation task would look:

```
TO: websocket-server-agent.md

TASK: Implement the core WebSocket server message handling

CONTEXT:
- Existing RelayMessage classes in lib/src/models/relay_message.dart
- EventStore in lib/src/storage/event_store.dart  
- Subscription class in lib/src/models/subscription.dart

REQUIREMENTS:
1. Use TDD - write tests first
2. Handle all Nostr message types
3. Integrate with EventStore for queries
4. Manage subscriptions per connection
5. Send EOSE after historical events
6. Broadcast new events to matching subscriptions

BEGIN IMPLEMENTATION:
```

The agent would then produce:
1. Test file: test/network/websocket_server_test.dart
2. Implementation: lib/src/network/websocket_server.dart
3. Message handler: lib/src/network/message_handler.dart
4. Integration points documented

## Results Verification

After each agent completes their task:

1. Run all tests: `flutter test`
2. Check code coverage: `flutter test --coverage`
3. Run lints: `flutter analyze`
4. Verify integration: Run example app
5. Performance check: Run benchmarks

## Tips for Effective Agent Usage

1. **Be Specific**: Include file paths, class names, method signatures
2. **Provide Context**: Reference existing code and patterns
3. **Set Clear Goals**: Define success criteria and constraints
4. **Iterate**: Use agent feedback to refine implementation
5. **Verify**: Always run tests and benchmarks

This approach ensures high-quality, well-tested implementations that integrate smoothly with the existing codebase.