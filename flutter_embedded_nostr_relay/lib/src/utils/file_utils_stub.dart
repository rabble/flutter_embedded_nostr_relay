// ABOUTME: Stub implementation of file utilities for web
// ABOUTME: Returns default values since file operations don't apply to web

/// Stub implementation for web platform
class FileUtilsImpl {
  static Future<int> getFileSize(String path) async => 0;
  static Future<bool> fileExists(String path) async => false;
}