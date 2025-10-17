# Flutter Nostr CLI

A command-line tool for scaffolding and debugging Flutter applications with embedded Nostr relay functionality.

## Installation

```bash
dart pub global activate flutter_nostr_cli
```

## Commands

### Create
Create a new Flutter app with embedded Nostr relay:

```bash
flutter_nostr create my_app --template social
flutter_nostr create chat_app --template chat
flutter_nostr create minimal_app --template minimal
```

### Add
Add Nostr components to existing Flutter project:

```bash
flutter_nostr add relay --embedded
flutter_nostr add transport --ble
```

### Inspect
Debug and monitor Nostr relay connections:

```bash
flutter_nostr inspect ws://localhost:7447
flutter_nostr inspect wss://relay.example.com --kind 1 --events 50
```

### Validate
Validate Nostr event format and signatures:

```bash
flutter_nostr validate event.json
flutter_nostr validate events.json --signature
```

### Test Relay
Test relay connectivity:

```bash
flutter_nostr test-relay ws://localhost:7447
```

### Migrate
Migrate existing projects:

```bash
flutter_nostr migrate --from traditional-relay
flutter_nostr analyze --relay-usage
```

## Templates

- **minimal**: Basic Flutter app with embedded Nostr relay
- **social**: Social media app template with feed and profiles  
- **chat**: Chat application with direct messaging

## Development

Run tests:
```bash
dart test
```

Build:
```bash
dart compile exe bin/flutter_nostr_cli.dart -o flutter_nostr
```