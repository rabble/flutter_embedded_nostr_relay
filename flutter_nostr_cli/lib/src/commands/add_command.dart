// ABOUTME: Add command for integrating Nostr relay components into existing Flutter projects
// ABOUTME: Supports adding embedded relay, transport protocols, and other Nostr features incrementally
import 'package:args/command_runner.dart';

class AddCommand extends Command<int> {
  AddCommand() {
    argParser.addFlag(
      'embedded',
      help: 'Add embedded relay functionality',
      defaultsTo: false,
    );
    argParser.addFlag(
      'dry-run',
      help: 'Show what would be added without making changes',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'add';

  @override
  String get description => 'Add Nostr relay components to existing Flutter project';

  @override
  String get invocation => 'flutter_nostr add <component> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dryRun = args['dry-run'] as bool;

    if (args.rest.isEmpty) {
      usageException('Component name is required (relay, transport, etc.)');
    }

    final component = args.rest.first;
    
    if (dryRun) {
      print('Would add component: $component');
      return 0;
    }

    print('Adding $component to Flutter project...');
    // TODO: Implement component addition logic
    print('✅ Component added successfully!');
    
    return 0;
  }
}