// ABOUTME: Tests for the validate command that verifies Nostr event format and signatures
// ABOUTME: Validates event structure, signature verification, and content validation
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import '../../lib/src/commands/validate_command.dart';
import '../../lib/src/models/nostr_event.dart';

void main() {
  group('ValidateCommand', () {
    late ValidateCommand command;
    late MemoryFileSystem fs;
    late Directory tempDir;

    setUp(() {
      command = ValidateCommand();
      fs = MemoryFileSystem();
      tempDir = fs.systemTempDirectory.createTempSync('validate_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should validate correct event structure', () {
      final validEvent = {
        'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Hello, Nostr!',
        'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      };

      final result = command.validateEventStructure(validEvent);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('should reject event with missing required fields', () {
      final invalidEvent = {
        'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        // missing created_at
        'kind': 1,
        'tags': [],
        'content': 'Hello, Nostr!',
        'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      };

      final result = command.validateEventStructure(invalidEvent);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Missing required field: created_at'));
    });

    test('should reject event with invalid pubkey format', () {
      final invalidEvent = {
        'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'pubkey': 'invalid_pubkey', // Too short
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Hello, Nostr!',
        'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      };

      final result = command.validateEventStructure(invalidEvent);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid pubkey format'));
    });

    test('should reject event with invalid signature format', () {
      final invalidEvent = {
        'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Hello, Nostr!',
        'sig': 'invalid_sig' // Too short
      };

      final result = command.validateEventStructure(invalidEvent);
      expect(result.isValid, isFalse);
      expect(result.errors, contains('Invalid signature format'));
    });

    test('should validate event from JSON file', () async {
      final validEvent = {
        'id': 'a1b2c3d4e5f6',
        'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'created_at': 1234567890,
        'kind': 1,
        'tags': [],
        'content': 'Hello from file!',
        'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      };

      final eventFile = fs.file(path.join(tempDir.path, 'event.json'));
      eventFile.writeAsStringSync(jsonEncode(validEvent));

      final result = await command.validateFromFile(eventFile.path, fs);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('should handle invalid JSON file', () async {
      final eventFile = fs.file(path.join(tempDir.path, 'invalid.json'));
      eventFile.writeAsStringSync('invalid json');

      final result = await command.validateFromFile(eventFile.path, fs);
      expect(result.isValid, isFalse);
      expect(result.errors.first, startsWith('Invalid JSON format'));
    });

    test('should validate array of events', () async {
      final events = [
        {
          'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'created_at': 1234567890,
          'kind': 1,
          'tags': [],
          'content': 'Event 1',
          'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
        },
        {
          'id': '5678567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'created_at': 1234567891,
          'kind': 1,
          'tags': [],
          'content': 'Event 2',
          'sig': 'invalid_sig' // This one is invalid
        }
      ];

      final eventFile = fs.file(path.join(tempDir.path, 'events.json'));
      eventFile.writeAsStringSync(jsonEncode(events));

      final results = await command.validateArrayFromFile(eventFile.path, fs);
      expect(results.length, equals(2));
      expect(results[0].isValid, isTrue);
      expect(results[1].isValid, isFalse);
    });

    test('should validate kind-specific content', () {
      // Test metadata event (kind 0)
      final metadataEvent = {
        'id': 'meta123',
        'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'created_at': 1234567890,
        'kind': 0,
        'tags': [],
        'content': '{"name": "Alice", "about": "Nostr user"}',
        'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      };

      final result = command.validateKindSpecific(metadataEvent);
      expect(result.isValid, isTrue);

      // Test with invalid JSON in metadata
      metadataEvent['content'] = 'invalid json';
      final invalidResult = command.validateKindSpecific(metadataEvent);
      expect(invalidResult.isValid, isFalse);
      expect(invalidResult.errors, contains('Kind 0 content must be valid JSON'));
    });

    test('should generate validation report', () {
      final events = [
        {
          'id': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'pubkey': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          'created_at': 1234567890,
          'kind': 1,
          'tags': [],
          'content': 'Valid event',
          'sig': '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
        },
        {
          'id': 'invalid1',
          'pubkey': 'invalid',
          'created_at': 1234567890,
          'kind': 1,
          'tags': [],
          'content': 'Invalid event',
          'sig': 'invalid'
        }
      ];

      final report = command.generateReport(events);
      expect(report, contains('Validation Report'));
      expect(report, contains('Total Events: 2'));
      expect(report, contains('Valid Events: 1'));
      expect(report, contains('Invalid Events: 1'));
      expect(report, contains('Success Rate: 50.0%'));
    });
  });
}