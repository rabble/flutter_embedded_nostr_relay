# Contributing to Flutter Embedded Nostr Relay

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## We Develop with Github
We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

## We Use [Github Flow](https://guides.github.com/introduction/flow/index.html), So All Code Changes Happen Through Pull Requests
Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests:

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Issue that pull request!

## Any contributions you make will be under the MIT Software License
In short, when you submit code changes, your submissions are understood to be under the same [MIT License](LICENSE) that covers the project. Feel free to contact the maintainers if that's a concern.

## Report bugs using Github's [issues](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues)
We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/OpenVine/flutter_embedded_nostr_relay/issues/new); it's that easy!

## Write bug reports with detail, background, and sample code

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

## Development Process

1. **Set up your development environment**
   ```bash
   git clone https://github.com/OpenVine/flutter_embedded_nostr_relay.git
   cd flutter_embedded_nostr_relay
   flutter pub get
   ```

2. **Run tests**
   ```bash
   flutter test
   ```

3. **Run the example app**
   ```bash
   cd example
   flutter run
   ```

### Building with Tor Support

If you're contributing to Tor-related features:

1. **Install Rust** (required for building Arti)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Build with Tor libraries**
   ```bash
   ./scripts/build_with_tor.sh
   ```

3. **Test with Tor enabled**
   ```bash
   flutter test --dart-define=TOR_ENABLED=true
   ```

## Code Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `flutter format` to format your code
- Run `flutter analyze` to catch any issues

## Testing

- Write tests for all new functionality
- Ensure all tests pass before submitting PR
- Aim for high code coverage
- Include unit tests, integration tests, and e2e tests where appropriate

### Test-Driven Development (TDD)

We follow TDD practices, especially for new features:

1. **Write failing tests first**
2. **Implement minimum code to pass**
3. **Refactor while keeping tests green**

Example:
```dart
// 1. Write failing test
test('should enable Tor for relay connections', () async {
  final relay = MockEmbeddedNostrRelay();
  final provider = RelayProvider(relay);
  
  await provider.setTorForRelays(true);
  
  expect(provider.torForRelays, isTrue);
  verify(relay.setTorForRelays(true)).called(1);
});

// 2. Implement feature
// 3. Refactor
```

### Tor-Specific Testing

When testing Tor features:
- Use conditional imports to separate Tor/non-Tor code paths
- Mock Tor library availability in tests
- Test graceful degradation when Tor is unavailable

## License
By contributing, you agree that your contributions will be licensed under its MIT License.