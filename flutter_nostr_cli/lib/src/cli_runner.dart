// ABOUTME: Main CLI runner that coordinates command parsing, routing, and execution
// ABOUTME: Handles global flags, error handling, and provides the primary entry point for the CLI tool
import 'dart:io' as io;
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'commands/create_command.dart';
import 'commands/add_command.dart';
import 'commands/inspect_command.dart';
import 'commands/validate_command.dart';
import 'commands/migrate_command.dart';
import 'commands/test_relay_command.dart';

class CliRunner extends CommandRunner<int> {
  CliRunner() : super('flutter_nostr', 'CLI tool for Flutter apps with embedded Nostr relay') {
    // Global flags
    argParser.addFlag('verbose', abbr: 'v', help: 'Verbose output');
    argParser.addFlag('version', help: 'Show version information');

    // Register commands
    addCommand(CreateCommand());
    addCommand(AddCommand());
    addCommand(InspectCommand());
    addCommand(ValidateCommand());
    addCommand(MigrateCommand());
    addCommand(TestRelayCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final argResults = parse(args);

      // Handle global flags
      if (argResults['version'] as bool) {
        _showVersion();
        return 0;
      }

      if (argResults.command == null) {
        // Check if any non-flag arguments were provided
        if (argResults.rest.isNotEmpty) {
          io.stderr.writeln('Unknown command: ${argResults.rest.first}');
          printUsage();
          return 1;
        }
        printUsage();
        return 0;
      }

      final result = await runCommand(argResults);
      return result ?? 0;
    } on UsageException catch (e) {
      io.stderr.writeln('Error: ${e.message}');
      io.stderr.writeln();
      io.stderr.writeln(e.usage);
      return 1;
    } catch (e) {
      io.stderr.writeln('Unexpected error: $e');
      return 1;
    }
  }

  void _showVersion() {
    print('flutter_nostr CLI version 0.1.0');
    print('A CLI tool for scaffolding and debugging Flutter apps with embedded Nostr relay');
  }

  List<String> getAvailableCommands() {
    return commands.keys.toList();
  }

  Map<String, String> getCommandDescriptions() {
    return Map.fromEntries(
      commands.entries.map((entry) => MapEntry(entry.key, entry.value.description)),
    );
  }
}