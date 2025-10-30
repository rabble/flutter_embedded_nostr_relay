# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Documentation
- Added comprehensive divine.video/OpenVine integration instructions to README
- Added symlink setup guide for local development with divine.video
- Added architecture notes specific to divine.video integration
- Added common issues and troubleshooting section for divine.video setup
- Split installation instructions into pub.dev and local development options

## [0.1.0] - 2024-08-01

### Added
- Initial release of Flutter Embedded Nostr Relay
- Core Nostr protocol implementation (NIP-01)
- SQLite-based event storage with optimized indexing
- Local WebSocket server on port 7447
- Smart proxy pattern for external relay management
- NIP-65 Outbox Model support
- Negentropy protocol for P2P synchronization
- BLE transport layer with packet fragmentation
- WiFi Direct support for Android
- Video-optimized caching for OpenVine (kind:32222)
- Privacy-preserving external relay queries
- Comprehensive test suite
- Example Flutter application
- Full API documentation
