// ABOUTME: Tests for the main CLI runner that coordinates all commands and argument parsing
// ABOUTME: Validates command routing, argument parsing, help text, and error handling
import 'package:test/test.dart';
import 'package:args/args.dart';
import '../lib/src/cli_runner.dart';

void main() {
  group('CliRunner', () {
    late CliRunner runner;

    setUp(() {
      runner = CliRunner();
    });

    test('should show help when no arguments provided', () async {
      final result = await runner.run([]);
      expect(result, equals(0)); // Success exit code
    });

    test('should show version with --version flag', () async {
      final result = await runner.run(['--version']);
      expect(result, equals(0));
    });

    test('should route to create command', () async {
      final result = await runner.run(['create', 'test_app', '--template', 'minimal', '--dry-run']);
      expect(result, equals(0));
    });

    test('should route to inspect command', () async {
      final result = await runner.run(['inspect', 'ws://localhost:7447', '--events', '10', '--dry-run']);
      expect(result, equals(0));
    });

    test('should route to validate command', () async {
      final result = await runner.run(['validate', 'event.json', '--dry-run']);
      expect(result, equals(0));
    });

    test('should route to add command', () async {
      final result = await runner.run(['add', 'relay', '--embedded', '--dry-run']);
      expect(result, equals(0));
    });

    test('should handle invalid command', () async {
      final result = await runner.run(['invalid-command']);
      expect(result, equals(1)); // Error exit code
    });

    test('should handle global flags', () async {
      final result = await runner.run(['--verbose', 'create', 'test_app', '--dry-run']);
      expect(result, equals(0));
    });

    test('should show command-specific help', () async {
      final result = await runner.run(['create', '--help']);
      expect(result, equals(0));
    });

    test('should handle argument parsing errors', () async {
      final result = await runner.run(['create']); // Missing required project name
      expect(result, equals(1)); // Error exit code
    });
  });

  group('CommandRegistry', () {
    test('should register all expected commands', () {
      final runner = CliRunner();
      final commands = runner.getAvailableCommands();
      
      expect(commands, contains('create'));
      expect(commands, contains('add'));
      expect(commands, contains('inspect'));
      expect(commands, contains('validate'));
      expect(commands, contains('migrate'));
      expect(commands, contains('test-relay'));
    });

    test('should provide command descriptions', () {
      final runner = CliRunner();
      final descriptions = runner.getCommandDescriptions();
      
      expect(descriptions['create'], isNotEmpty);
      expect(descriptions['inspect'], isNotEmpty);
      expect(descriptions['validate'], isNotEmpty);
    });
  });

  group('ArgumentParser', () {
    test('should parse global arguments', () {
      final parser = ArgParser();
      parser.addFlag('verbose', abbr: 'v', help: 'Verbose output');
      parser.addFlag('version', help: 'Show version');

      final results = parser.parse(['--verbose', '--version']);
      expect(results['verbose'], isTrue);
      expect(results['version'], isTrue);
    });

    test('should parse command-specific arguments', () {
      final parser = ArgParser();
      parser.addCommand('create')
        ..addOption('template', abbr: 't', defaultsTo: 'minimal')
        ..addFlag('force', help: 'Overwrite existing directory');

      final results = parser.parse(['create', '--template', 'social', '--force']);
      expect(results.command!.name, equals('create'));
      expect(results.command!['template'], equals('social'));
      expect(results.command!['force'], isTrue);
    });
  });
}