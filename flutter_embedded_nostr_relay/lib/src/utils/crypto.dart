// ABOUTME: Cryptographic utilities for Nostr protocol
// ABOUTME: Handles SHA256 hashing, schnorr signatures, and key operations

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:convert/convert.dart';
import '../models/nostr_event.dart';

class NostrCrypto {
  /// Calculate SHA256 hash of a string and return as hex
  static String sha256(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256Bytes(bytes);
    return hex.encode(digest);
  }
  
  /// Calculate SHA256 hash of bytes
  static Uint8List sha256Bytes(List<int> data) {
    final digest = crypto.sha256.convert(data);
    return Uint8List.fromList(digest.bytes);
  }
  
  /// Generate a random 32-byte private key
  static String generatePrivateKey() {
    // TODO: Implement secure random key generation
    // This is a placeholder - in production, use a secure random generator
    throw UnimplementedError('Private key generation not yet implemented');
  }
  
  /// Derive public key from private key
  static String getPublicKey(String privateKey) {
    // TODO: Implement secp256k1 public key derivation
    // This is a placeholder - in production, use proper secp256k1 library
    throw UnimplementedError('Public key derivation not yet implemented');
  }
  
  /// Sign an event with a private key
  static String signEvent(NostrEvent event, String privateKey) {
    // TODO: Implement schnorr signature
    // This is a placeholder - in production, use proper secp256k1 library
    throw UnimplementedError('Event signing not yet implemented');
  }
  
  /// Verify a schnorr signature
  static bool verifySignature(String message, String publicKey, String signature) {
    // TODO: Implement schnorr signature verification
    // This is a placeholder - in production, use proper secp256k1 library
    
    // For now, accept all signatures in development
    return signature.isNotEmpty;
  }
  
  /// Validate if a string is a valid hex public key (64 chars)
  static bool isValidPublicKey(String pubkey) {
    if (pubkey.length != 64) return false;
    
    try {
      hex.decode(pubkey);
      return true;
    } catch (_) {
      return false;
    }
  }
  
  /// Validate if a string is a valid hex private key (64 chars)
  static bool isValidPrivateKey(String privkey) {
    if (privkey.length != 64) return false;
    
    try {
      hex.decode(privkey);
      return true;
    } catch (_) {
      return false;
    }
  }
  
  /// Validate if a string is a valid event ID (64 chars hex)
  static bool isValidEventId(String id) {
    if (id.length != 64) return false;
    
    try {
      hex.decode(id);
      return true;
    } catch (_) {
      return false;
    }
  }
  
  /// Generate event ID from event data
  static String generateEventId({
    required String pubkey,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
  }) {
    // Serialize according to NIP-01
    final eventData = [
      0, // version
      pubkey,
      createdAt,
      kind,
      tags,
      content,
    ];
    
    final serialized = json.encode(eventData);
    return sha256(serialized);
  }
}