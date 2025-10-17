// ABOUTME: Main executable entry point for the flutter_nostr CLI tool
// ABOUTME: Initializes the CLI runner and handles top-level error catching and exit codes
import 'dart:io';
import '../lib/src/cli_runner.dart';

Future<void> main(List<String> arguments) async {
  final runner = CliRunner();
  
  try {
    final exitCode = await runner.run(arguments);
    exit(exitCode);
  } catch (e) {
    stderr.writeln('Fatal error: $e');
    exit(1);
  }
}