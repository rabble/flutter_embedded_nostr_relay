// ABOUTME: Project generator for creating Flutter applications with embedded Nostr relay
// ABOUTME: Coordinates template rendering, file creation, and dependency setup for new projects
import 'dart:io';
import 'package:file/file.dart';
import 'package:path/path.dart' as path;
import '../templates/template_manager.dart';

class ProjectGenerator {
  final FileSystem _fileSystem;

  ProjectGenerator(this._fileSystem);

  Future<void> generateProject({
    required String projectPath,
    required String projectName,
    required String template,
    required TemplateManager templateManager,
  }) async {
    // Create project directory
    final projectDir = _fileSystem.directory(projectPath);
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
    projectDir.createSync(recursive: true);

    // Generate basic Flutter project structure
    await _createBasicStructure(projectPath, projectName);
    
    // Apply template-specific files
    await _applyTemplate(projectPath, projectName, template, templateManager);
    
    // Add Nostr relay dependencies
    await _addNostrDependencies(projectPath, projectName);
  }

  Future<void> _createBasicStructure(String projectPath, String projectName) async {
    // Create basic Flutter directories
    final directories = [
      'lib',
      'lib/screens',
      'lib/models', 
      'lib/services',
      'lib/widgets',
      'test',
      'android',
      'ios',
      'web',
    ];

    for (final dir in directories) {
      _fileSystem.directory(path.join(projectPath, dir)).createSync(recursive: true);
    }

    // Create basic pubspec.yaml
    final pubspec = _generatePubspec(projectName);
    _fileSystem.file(path.join(projectPath, 'pubspec.yaml')).writeAsStringSync(pubspec);

    // Create basic main.dart
    final mainDart = _generateMainDart(projectName);
    _fileSystem.file(path.join(projectPath, 'lib', 'main.dart')).writeAsStringSync(mainDart);
  }

  Future<void> _applyTemplate(String projectPath, String projectName, String template, TemplateManager templateManager) async {
    switch (template) {
      case 'social':
        await _createSocialFiles(projectPath, projectName);
        break;
      case 'chat':
        await _createChatFiles(projectPath, projectName);
        break;
      case 'minimal':
      default:
        // Minimal template is just the basic structure
        break;
    }
  }

  Future<void> _createSocialFiles(String projectPath, String projectName) async {
    // Create feed screen
    final feedScreen = '''
import 'package:flutter/material.dart';

class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Feed')),
      body: Center(child: Text('Social Feed Coming Soon')),
    );
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'screens', 'feed_screen.dart')).writeAsStringSync(feedScreen);

    // Create profile model
    final profileModel = '''
class Profile {
  final String pubkey;
  final String name;
  final String about;
  final String picture;

  Profile({
    required this.pubkey,
    required this.name,
    required this.about,
    required this.picture,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      pubkey: json['pubkey'] ?? '',
      name: json['name'] ?? '',
      about: json['about'] ?? '',
      picture: json['picture'] ?? '',
    );
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'models', 'profile.dart')).writeAsStringSync(profileModel);

    // Create follow service
    final followService = '''
class FollowService {
  final List<String> _following = [];

  List<String> get following => _following;

  void follow(String pubkey) {
    if (!_following.contains(pubkey)) {
      _following.add(pubkey);
    }
  }

  void unfollow(String pubkey) {
    _following.remove(pubkey);
  }

  bool isFollowing(String pubkey) {
    return _following.contains(pubkey);
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'services', 'follow_service.dart')).writeAsStringSync(followService);
  }

  Future<void> _createChatFiles(String projectPath, String projectName) async {
    // Create chat list screen
    final chatListScreen = '''
import 'package:flutter/material.dart';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chats')),
      body: Center(child: Text('Chat List Coming Soon')),
    );
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'screens', 'chat_list_screen.dart')).writeAsStringSync(chatListScreen);

    // Create chat screen
    final chatScreen = '''
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  
  ChatScreen({required this.chatId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Center(child: Text('Chat Interface Coming Soon')),
    );
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'screens', 'chat_screen.dart')).writeAsStringSync(chatScreen);

    // Create message model
    final messageModel = '''
class Message {
  final String id;
  final String content;
  final String sender;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.content,
    required this.sender,
    required this.timestamp,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      content: json['content'],
      sender: json['sender'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] * 1000),
    );
  }
}
''';
    _fileSystem.file(path.join(projectPath, 'lib', 'models', 'message.dart')).writeAsStringSync(messageModel);
  }

  Future<void> _addNostrDependencies(String projectPath, String projectName) async {
    // This would add the embedded relay dependency to pubspec.yaml
    // For now, it's handled in the basic pubspec generation
  }

  String _generatePubspec(String projectName) {
    return '''
name: $projectName
description: A Flutter app with embedded Nostr relay.
version: 1.0.0+1

environment:
  sdk: ^3.8.1
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  
  # Nostr relay functionality
  flutter_embedded_nostr_relay:
    path: ../flutter_embedded_nostr_relay
  
  # UI dependencies
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
''';
  }

  String _generateMainDart(String projectName) {
    return '''
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${projectName.replaceAll('_', ' ').toUpperCase()}',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: '${projectName.replaceAll('_', ' ').toUpperCase()}'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Welcome to your Nostr-powered Flutter app!',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            Text(
              'Your embedded Nostr relay is ready to use.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
''';
  }
}