# Flutter Embedded Nostr Relay - Agent System

This directory contains the specialized AI agents designed to build the Flutter Embedded Nostr Relay using agentic programming principles.

## Agent Hierarchy

### Tier 1: Master Coordinator
- **relay-master-coordinator.md** - Orchestrates all development, ensures consistency

### Tier 2: Component Leads
- **protocol-implementation-lead.md** - WebSocket and Nostr protocol expert
- **storage-architecture-lead.md** - SQLite and query optimization specialist
- **networking-lead.md** - External relays and NIP-65 proxy implementation
- **p2p-sync-lead.md** - Negentropy protocol and transport coordination
- **platform-integration-lead.md** - iOS, Android, Web platform differences

### Tier 3: Feature Specialists
- **websocket-server-agent.md** - Local WebSocket server implementation
- **external-relay-client-agent.md** - External relay connections
- **subscription-manager-agent.md** - Subscription and filter management
- **event-validator-agent.md** - Event validation and signature verification
- **negentropy-protocol-agent.md** - Core Negentropy algorithm
- **ble-transport-agent.md** - Bluetooth Low Energy transport
- **wifi-direct-agent.md** - WiFi Direct transport (Android)
- **video-optimization-agent.md** - OpenVine video event optimizations
- **privacy-features-agent.md** - Privacy-preserving relay queries

### Tier 4: Support Agents
- **test-writer-agent.md** - TDD specialist for all components
- **performance-benchmark-agent.md** - Performance testing and optimization
- **security-auditor-agent.md** - Security analysis and validation
- **documentation-agent.md** - API documentation and guides
- **example-app-builder-agent.md** - Example Flutter application

## How to Use These Agents

1. Each agent file contains a complete prompt that defines:
   - The agent's expertise and responsibilities
   - Specific technical knowledge required
   - Constraints from CLAUDE.md and project specs
   - Interfaces with other components
   - Expected deliverables

2. Agents follow these principles:
   - Test-Driven Development (TDD) is mandatory
   - Minimal code changes per task
   - Follow existing code style
   - Never use mocks in tests
   - Document with ABOUTME comments

3. Agent coordination:
   - Start with the Master Coordinator for planning
   - Component Leads design their subsystems
   - Feature Specialists implement specific functionality
   - Support Agents ensure quality throughout

4. Each agent includes:
   - Deep domain knowledge from project documentation
   - Understanding of dependencies and interfaces
   - Platform-specific considerations
   - Performance and security requirements

## Project Guidelines

All agents must follow the guidelines in CLAUDE.md, particularly:
- Address Rabble as "Rabble" 
- Use TodoWrite tool for task tracking
- Implement comprehensive tests (unit, integration, e2e)
- Commit frequently with descriptive messages
- Never throw away old implementations without permission