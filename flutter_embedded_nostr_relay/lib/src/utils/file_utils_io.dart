// ABOUTME: IO implementation of file utilities for native platforms
// ABOUTME: Provides actual file operations using dart:io File class

import 'dart:io';

/// IO implementation for native platforms
class FileUtilsImpl {
  static Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }
  
  static Future<bool> fileExists(String path) async {
    final file = File(path);
    return await file.exists();
  }
}