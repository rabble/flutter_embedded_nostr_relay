// ABOUTME: IO implementation of platform utilities for native platforms
// ABOUTME: Provides actual platform detection using dart:io Platform class

import 'dart:io';

/// IO implementation for native platforms
class PlatformUtilsImpl {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isWindows => Platform.isWindows;
  static bool get isLinux => Platform.isLinux;
  static String get operatingSystem => Platform.operatingSystem;
  static String get operatingSystemVersion => Platform.operatingSystemVersion;
}