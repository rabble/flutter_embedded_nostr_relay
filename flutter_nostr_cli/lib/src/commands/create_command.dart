// ABOUTME: Create command for scaffolding new Flutter applications with embedded Nostr relay
// ABOUTME: Supports multiple templates (social, chat, minimal) and handles project generation with dependencies
import 'dart:io' as io;
import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import '../generators/project_generator.dart';
import '../templates/template_manager.dart';

class CreateCommand extends Command<int> {
  final FileSystem _fileSystem;
  final String _workingDirectory;

  CreateCommand({FileSystem? fileSystem, String? workingDirectory})
      : _fileSystem = fileSystem ?? const LocalFileSystem(),
        _workingDirectory = workingDirectory ?? io.Directory.current.path {
    argParser.addOption(
      'template',
      abbr: 't',
      defaultsTo: 'minimal',
      allowed: ['minimal', 'social', 'chat'],
      help: 'The template to use for the new project',
    );
    argParser.addFlag(
      'force',
      help: 'Overwrite existing files and directories',
      defaultsTo: false,
    );
    argParser.addFlag(
      'dry-run',
      help: 'Show what would be created without actually creating files',
      defaultsTo: false,
    );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Flutter app with embedded Nostr relay';

  @override
  String get invocation => 'flutter_nostr create <project-name> [options]';

  @override
  Future<int> run() async {
    final args = argResults!;
    
    if (args.rest.isEmpty) {
      usageException('Project name is required');
    }

    final projectName = args.rest.first;
    final template = args['template'] as String;
    final force = args['force'] as bool;
    final dryRun = args['dry-run'] as bool;

    if (dryRun) {
      print('Would create project "$projectName" with template "$template"');
      return 0;
    }

    await create(projectName, template: template, force: force);
    return 0;
  }

  Future<void> create(String projectName, {String template = 'minimal', bool force = false}) async {
    // Validate project name
    if (!_isValidProjectName(projectName)) {
      throw ArgumentError('Invalid project name: $projectName. Must be a valid Dart package name.');
    }

    // Validate template
    if (!['minimal', 'social', 'chat'].contains(template)) {
      throw ArgumentError('Invalid template: $template. Must be one of: minimal, social, chat');
    }

    final projectPath = path.join(_workingDirectory, projectName);
    final projectDir = _fileSystem.directory(projectPath);

    // Check if directory exists
    if (projectDir.existsSync() && !force) {
      throw FileSystemException('Directory already exists: $projectPath. Use --force to overwrite.');
    }

    // Create the project
    final generator = ProjectGenerator(_fileSystem);
    final templateManager = TemplateManager();

    print('Creating Flutter project with Nostr relay...');
    print('Project: $projectName');
    print('Template: $template');
    print('Location: $projectPath');

    // Generate the project structure
    await generator.generateProject(
      projectPath: projectPath,
      projectName: projectName,
      template: template,
      templateManager: templateManager,
    );

    print('✅ Project created successfully!');
    print('');
    print('Next steps:');
    print('  cd $projectName');
    print('  flutter pub get');
    print('  flutter run');
  }

  bool _isValidProjectName(String name) {
    // Basic validation for Dart package names
    final validPattern = RegExp(r'^[a-z][a-z0-9_]*$');
    return validPattern.hasMatch(name) && !name.startsWith('_');
  }
}