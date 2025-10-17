// ABOUTME: Test helpers and mocks for Riverpod Nostr app
// ABOUTME: Provides test-safe crypto functions and utilities

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';

// Test event creation helper
NostrEvent createTestEvent({
  int kind = 1,
  String content = 'Test content',
  List<List<String>> tags = const [],
  int? createdAt,
  String? privateKey,
}) {
  privateKey ??= NostrCrypto.generatePrivateKey();
  final pubkey = NostrCrypto.getPublicKey(privateKey);
  
  // Create the event with the correct timestamp from the start
  final event = NostrEvent.create(
    pubkey: pubkey,
    kind: kind,
    tags: tags,
    content: content,
    createdAt: createdAt,
  );
  
  // Sign it
  return event.sign(privateKey);
}