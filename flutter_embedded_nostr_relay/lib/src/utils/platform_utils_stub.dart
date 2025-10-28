// ABOUTME: Stub implementation of platform utilities for web
// ABOUTME: Returns false for all platform checks since they don't apply to web

/// Stub implementation for web platform
class PlatformUtilsImpl {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => '';
}