// ABOUTME: Tests for RelayMetadata model used in NIP-65 relay list management
// ABOUTME: Validates relay URL parsing, read/write permissions, and metadata handling

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_embedded_nostr_relay/src/models/relay_metadata.dart';

void main() {
  group('RelayMetadata', () {
    test('should create metadata with read and write permissions by default', () {
      const url = 'wss://relay.example.com';
      final metadata = RelayMetadata(url: url);
      
      expect(metadata.url, equals(url));
      expect(metadata.read, isTrue);
      expect(metadata.write, isTrue);
      expect(metadata.priority, isNull);
    });
    
    test('should create metadata with specific read/write permissions', () {
      const url = 'wss://read-only.example.com';
      final metadata = RelayMetadata(
        url: url,
        read: true,
        write: false,
      );
      
      expect(metadata.url, equals(url));
      expect(metadata.read, isTrue);
      expect(metadata.write, isFalse);
    });
    
    test('should create metadata with priority', () {
      const url = 'wss://priority.example.com'; 
      const priority = 10;
      final metadata = RelayMetadata(
        url: url,
        priority: priority,
      );
      
      expect(metadata.url, equals(url));
      expect(metadata.priority, equals(priority));
    });
    
    test('should support equality comparison', () {
      const url = 'wss://relay.example.com';
      final metadata1 = RelayMetadata(url: url, read: true, write: false);
      final metadata2 = RelayMetadata(url: url, read: true, write: false);
      final metadata3 = RelayMetadata(url: url, read: false, write: true);
      
      expect(metadata1, equals(metadata2));
      expect(metadata1, isNot(equals(metadata3)));
    });
    
    test('should serialize to and from JSON', () {
      const url = 'wss://relay.example.com';
      const priority = 5;
      final originalMetadata = RelayMetadata(
        url: url,
        read: true,
        write: false,
        priority: priority,
      );
      
      final json = originalMetadata.toJson();
      final deserializedMetadata = RelayMetadata.fromJson(json);
      
      expect(deserializedMetadata, equals(originalMetadata));
      expect(deserializedMetadata.url, equals(url));
      expect(deserializedMetadata.read, isTrue);
      expect(deserializedMetadata.write, isFalse);
      expect(deserializedMetadata.priority, equals(priority));
    });
    
    test('should handle JSON with missing optional fields', () {
      final json = {'url': 'wss://minimal.example.com'};
      final metadata = RelayMetadata.fromJson(json);
      
      expect(metadata.url, equals('wss://minimal.example.com'));
      expect(metadata.read, isTrue);  // default
      expect(metadata.write, isTrue); // default
      expect(metadata.priority, isNull);
    });
    
    test('should validate URL format', () {
      expect(() => RelayMetadata(url: ''), throwsA(isA<ArgumentError>()));
      expect(() => RelayMetadata(url: 'invalid-url'), throwsA(isA<ArgumentError>()));
      expect(() => RelayMetadata(url: 'http://insecure.example.com'), throwsA(isA<ArgumentError>()));
      
      // These should not throw
      expect(() => RelayMetadata(url: 'wss://secure.example.com'), returnsNormally);
      expect(() => RelayMetadata(url: 'ws://localhost:8080'), returnsNormally);
    });
    
    test('should have meaningful toString representation', () {
      final metadata = RelayMetadata(
        url: 'wss://relay.example.com',
        read: true,
        write: false,
        priority: 3,
      );
      
      final toString = metadata.toString();
      expect(toString, contains('wss://relay.example.com'));
      expect(toString, contains('read: true'));
      expect(toString, contains('write: false'));
      expect(toString, contains('priority: 3'));
    });
  });
}