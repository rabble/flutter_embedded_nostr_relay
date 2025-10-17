// ABOUTME: Nostr event model representing the core data structure for Nostr protocol events
// ABOUTME: Handles JSON serialization/deserialization and provides structured access to event fields
class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      tags: (json['tags'] as List<dynamic>)
          .map((tag) => (tag as List<dynamic>).map((e) => e.toString()).toList())
          .toList(),
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  @override
  String toString() {
    return 'NostrEvent(id: ${id.substring(0, 8)}..., kind: $kind, content: ${content.length > 30 ? content.substring(0, 30) + '...' : content})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NostrEvent && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}