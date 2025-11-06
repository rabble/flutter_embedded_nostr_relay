// ABOUTME: IO implementation for path_provider functionality
// ABOUTME: Provides actual file system access on mobile and desktop platforms

export 'dart:io' show Directory;

// Re-export the path_provider functions for non-Web platforms
export 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory, getApplicationSupportDirectory;