// ABOUTME: File utilities that work across all platforms including web
// ABOUTME: Provides safe file operations using conditional compilation

import 'file_utils_stub.dart'
  if (dart.library.io) 'file_utils_io.dart';

/// File utilities that work on all platforms
class FileUtils {
  /// Get file size in bytes, returns 0 on web
  static Future<int> getFileSize(String path) => FileUtilsImpl.getFileSize(path);
  
  /// Check if file exists, returns false on web
  static Future<bool> fileExists(String path) => FileUtilsImpl.fileExists(path);
}