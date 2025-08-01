# Agent Usage Guide for Flutter Embedded Nostr Relay

## Overview

This guide explains how to use the specialized AI agents to build the Flutter Embedded Nostr Relay using agentic programming principles.

## Quick Start

### 1. Project Planning Phase

Start with the Master Coordinator:
```
Use agent: relay-master-coordinator.md
Task: Create a development plan for implementing the WebSocket server component
```

The Master Coordinator will:
- Analyze dependencies
- Create a task breakdown
- Assign work to appropriate agents
- Define integration points

### 2. Component Design Phase

Use Component Lead agents for architecture:
```
Use agent: protocol-implementation-lead.md
Task: Design the WebSocket message handling architecture with proper separation of concerns
```

### 3. Implementation Phase

Use Feature Specialist agents for coding:
```
Use agent: websocket-server-agent.md
Task: Implement the WebSocket server that listens on port 7447 with TDD
```

### 4. Quality Assurance Phase

Use Support agents throughout:
```
Use agent: test-writer-agent.md
Task: Write comprehensive tests for WebSocket message parsing
```

## Example Workflow: Implementing Negentropy Sync

### Step 1: Planning
```
Agent: relay-master-coordinator.md
Input: Plan the implementation of Negentropy P2P synchronization feature
Output: 
- Task breakdown
- Agent assignments
- Integration requirements
- Timeline
```

### Step 2: Protocol Design
```
Agent: p2p-sync-lead.md
Input: Design the Negentropy protocol implementation architecture
Output:
- Protocol flow diagrams
- Interface definitions
- Transport abstraction layer
- Performance considerations
```

### Step 3: Core Algorithm
```
Agent: negentropy-protocol-agent.md
Input: Implement the Negentropy XOR-based fingerprinting algorithm with TDD
Output:
- Core algorithm implementation
- Unit tests
- Performance benchmarks
- Integration interfaces
```

### Step 4: Transport Implementation
```
Agent: ble-transport-agent.md
Input: Implement BLE transport with packet fragmentation for 512-byte MTU
Output:
- BLE service implementation
- Packet fragmentation logic
- Reconnection handling
- Platform-specific code
```

### Step 5: Integration Testing
```
Agent: test-writer-agent.md
Input: Create integration tests for Negentropy sync over BLE
Output:
- Integration test suite
- Mock peer implementation
- Performance tests
- Edge case coverage
```

## Agent Coordination Patterns

### Sequential Development
1. Master Coordinator → Component Lead → Feature Specialist → Test Writer
2. Each agent completes their task before the next begins
3. Best for: dependent features, complex integrations

### Parallel Development
1. Master Coordinator assigns multiple independent tasks
2. Multiple Feature Specialists work simultaneously
3. Component Lead coordinates integration
4. Best for: independent features, rapid development

### Iterative Refinement
1. Feature Specialist implements initial version
2. Performance Agent benchmarks
3. Security Agent audits
4. Feature Specialist refines based on feedback
5. Best for: optimization, security-critical features

## Best Practices

### 1. Always Start with Planning
- Use Master Coordinator for any feature over 100 lines
- Get component architecture from Component Leads
- Define clear interfaces before implementation

### 2. Maintain Context
- Pass relevant documentation to agents
- Include previous agent outputs when continuing work
- Reference specific files and line numbers

### 3. Follow TDD Strictly
```
Example prompt:
"Using TDD, implement the event validation logic. First write failing tests for:
1. Valid event signature verification
2. Invalid event rejection
3. Replaceable event handling
Then implement the minimal code to pass each test."
```

### 4. Integrate Continuously
- After each feature, run integration tests
- Use Master Coordinator to verify compatibility
- Update documentation immediately

### 5. Platform-Specific Code
```
Example for platform agent:
"Implement WebSocket server for non-web platforms. Use conditional imports:
- websocket_server.dart for mobile/desktop
- websocket_server_web.dart for web (stub only)
Ensure clean separation and no runtime errors."
```

## Common Tasks and Agent Assignments

| Task | Primary Agent | Supporting Agents |
|------|--------------|-------------------|
| Add new message type | protocol-implementation-lead.md | test-writer-agent.md |
| Optimize query performance | storage-architecture-lead.md | performance-benchmark-agent.md |
| Implement new NIP | protocol-implementation-lead.md | documentation-agent.md |
| Add platform feature | platform-integration-lead.md | test-writer-agent.md |
| Security hardening | security-auditor-agent.md | All feature agents |
| Create example | example-app-builder-agent.md | documentation-agent.md |

## Troubleshooting

### Agent Produces Incorrect Output
1. Verify agent has access to latest code
2. Include specific constraints in prompt
3. Reference CLAUDE.md guidelines
4. Provide concrete examples

### Integration Conflicts
1. Use Master Coordinator to resolve
2. Clearly define interfaces
3. Run integration tests frequently
4. Maintain consistent API design

### Performance Issues
1. Use Performance Benchmark Agent first
2. Profile with real data (100k events)
3. Focus on query optimization
4. Consider platform limitations

## Advanced Patterns

### Cross-Component Features
For features spanning multiple components:
1. Master Coordinator creates integration plan
2. Each Component Lead designs their part
3. Feature Specialists implement in parallel
4. Integration testing brings together

### Breaking Changes
When API changes are needed:
1. Master Coordinator assesses impact
2. Documentation Agent updates specs
3. All affected agents are notified
4. Coordinated implementation begins

### Performance-Critical Paths
For <10ms response requirements:
1. Performance Agent creates benchmarks
2. Feature Agent implements with profiling
3. Storage Agent optimizes queries
4. Platform Agent handles specific optimizations

## Measuring Success

Each agent's output should be measured against:
1. **Correctness**: All tests pass
2. **Performance**: Meets specified targets
3. **Security**: Passes security audit
4. **Maintainability**: Clear, documented code
5. **Compatibility**: Works on all platforms

Use the Master Coordinator to verify all criteria are met before considering a feature complete.