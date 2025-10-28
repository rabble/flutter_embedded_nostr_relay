// ABOUTME: Web stub for path_provider functionality
// ABOUTME: Returns null directory since Web doesn't have file system access

/// Stub class for Directory on Web
class Directory {
  final String path;
  Directory(this.path);

  /// Stub method - always returns false on Web
  bool existsSync() => false;

  /// Stub method - does nothing on Web
  void createSync({bool recursive = false}) {
    // No-op on Web
  }
}

/// Get application documents directory (stub for Web)
Future<Directory> getApplicationDocumentsDirectory() async {
  throw UnsupportedError('getApplicationDocumentsDirectory is not supported on Web');
}

/// Get application support directory (stub for Web)
Future<Directory> getApplicationSupportDirectory() async {
  throw UnsupportedError('getApplicationSupportDirectory is not supported on Web');
}