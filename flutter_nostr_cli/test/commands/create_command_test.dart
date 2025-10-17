// ABOUTME: Tests for the create command that scaffolds new Flutter apps with embedded Nostr relay
// ABOUTME: Validates project generation, template selection, and dependency setup
import 'dart:io';
import 'package:test/test.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import '../../lib/src/commands/create_command.dart';

void main() {
  group('CreateCommand', () {
    late MemoryFileSystem fs;
    late CreateCommand command;
    late Directory tempDir;

    setUp(() {
      fs = MemoryFileSystem();
      tempDir = fs.systemTempDirectory.createTempSync('flutter_nostr_test');
      command = CreateCommand(fileSystem: fs, workingDirectory: tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create minimal project with default template', () async {
      final projectName = 'test_app';
      final projectPath = path.join(tempDir.path, projectName);

      await command.create(projectName, template: 'minimal');

      // Verify project structure
      expect(fs.directory(projectPath).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'pubspec.yaml')).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'lib', 'main.dart')).existsSync(), isTrue);
      
      // Verify dependency inclusion
      final pubspec = fs.file(path.join(projectPath, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('flutter_embedded_nostr_relay'));
      expect(pubspec, contains('name: $projectName'));
    });

    test('should create social app template', () async {
      final projectName = 'social_app';
      final projectPath = path.join(tempDir.path, projectName);

      await command.create(projectName, template: 'social');

      // Verify social-specific files
      expect(fs.file(path.join(projectPath, 'lib', 'screens', 'feed_screen.dart')).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'lib', 'models', 'profile.dart')).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'lib', 'services', 'follow_service.dart')).existsSync(), isTrue);
    });

    test('should create chat app template', () async {
      final projectName = 'chat_app';
      final projectPath = path.join(tempDir.path, projectName);

      await command.create(projectName, template: 'chat');

      // Verify chat-specific files
      expect(fs.file(path.join(projectPath, 'lib', 'screens', 'chat_list_screen.dart')).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'lib', 'screens', 'chat_screen.dart')).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'lib', 'models', 'message.dart')).existsSync(), isTrue);
    });

    test('should throw error for invalid template', () async {
      expect(
        () => command.create('test_app', template: 'invalid'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw error for invalid project name', () async {
      expect(
        () => command.create('123invalid-name', template: 'minimal'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should not overwrite existing directory without force flag', () async {
      final projectName = 'existing_app';
      final projectPath = path.join(tempDir.path, projectName);
      
      // Create existing directory
      fs.directory(projectPath).createSync();
      fs.file(path.join(projectPath, 'existing.txt')).writeAsStringSync('content');

      expect(
        () => command.create(projectName, template: 'minimal'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('should overwrite existing directory with force flag', () async {
      final projectName = 'existing_app';
      final projectPath = path.join(tempDir.path, projectName);
      
      // Create existing directory
      fs.directory(projectPath).createSync();
      fs.file(path.join(projectPath, 'existing.txt')).writeAsStringSync('content');

      await command.create(projectName, template: 'minimal', force: true);

      expect(fs.directory(projectPath).existsSync(), isTrue);
      expect(fs.file(path.join(projectPath, 'existing.txt')).existsSync(), isFalse);
      expect(fs.file(path.join(projectPath, 'pubspec.yaml')).existsSync(), isTrue);
    });
  });
}