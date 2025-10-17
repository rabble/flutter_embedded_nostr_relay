// ABOUTME: State management for direct messaging functionality
// ABOUTME: Handles encrypted DMs, conversation management, and message subscriptions

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'user_provider.dart';
import 'relay_provider.dart';

class DirectMessage {
  final NostrEvent event;
  final String recipientPubkey;
  final String senderPubkey;
  final String decryptedContent;
  final DateTime timestamp;
  final bool isFromCurrentUser;
  final bool isRead;

  DirectMessage({
    required this.event,
    required this.recipientPubkey,
    required this.senderPubkey,
    required this.decryptedContent,
    required this.timestamp,
    required this.isFromCurrentUser,
    this.isRead = false,
  });

  DirectMessage copyWith({
    bool? isRead,
  }) {
    return DirectMessage(
      event: event,
      recipientPubkey: recipientPubkey,
      senderPubkey: senderPubkey,
      decryptedContent: decryptedContent,
      timestamp: timestamp,
      isFromCurrentUser: isFromCurrentUser,
      isRead: isRead ?? this.isRead,
    );
  }
}

class Conversation {
  final String participantPubkey;
  final UserProfile? participantProfile;
  final List<DirectMessage> messages;
  final DirectMessage? lastMessage;
  final int unreadCount;
  final DateTime lastActivity;

  Conversation({
    required this.participantPubkey,
    this.participantProfile,
    required this.messages,
    this.lastMessage,
    this.unreadCount = 0,
    required this.lastActivity,
  });

  Conversation copyWith({
    UserProfile? participantProfile,
    List<DirectMessage>? messages,
    DirectMessage? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
  }) {
    return Conversation(
      participantPubkey: participantPubkey,
      participantProfile: participantProfile ?? this.participantProfile,
      messages: messages ?? this.messages,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}

class MessagingProvider extends ChangeNotifier {
  static final _logger = Logger('MessagingProvider');
  
  UserProvider? _userProvider;
  RelayProvider? _relayProvider;
  
  // Conversations state
  final Map<String, Conversation> _conversations = {};
  String? _currentConversationPubkey;
  
  // Loading states
  bool _isLoadingConversations = false;
  bool _isLoadingMessages = false;
  bool _isSendingMessage = false;
  
  // Subscriptions
  Subscription? _dmSubscription;
  StreamSubscription<NostrEvent>? _eventStreamSubscription;
  
  // Getters
  List<Conversation> get conversations {
    final convs = _conversations.values.toList();
    convs.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return convs;
  }
  
  Conversation? get currentConversation => 
      _currentConversationPubkey != null 
          ? _conversations[_currentConversationPubkey]
          : null;
  
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingMessages => _isLoadingMessages;
  bool get isSendingMessage => _isSendingMessage;
  
  int get totalUnreadCount => 
      _conversations.values.fold(0, (sum, conv) => sum + conv.unreadCount);

  void setProviders(UserProvider userProvider, RelayProvider relayProvider) {
    _userProvider = userProvider;
    _relayProvider = relayProvider;
    
    if (relayProvider.isInitialized) {
      _startMessageSubscription();
    }
  }

  /// Load all conversations
  Future<void> loadConversations() async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      _logger.warning('User not signed in');
      return;
    }
    
    if (_relayProvider?.relay == null) {
      _logger.warning('Relay not available');
      return;
    }

    _isLoadingConversations = true;
    notifyListeners();

    try {
      final userPubkey = _userProvider!.publicKey!;
      
      // Query DM events where user is sender or recipient
      final filters = [
        // Messages sent by user
        Filter(
          kinds: [4], // Encrypted direct messages
          authors: [userPubkey],
          limit: 500,
        ),
        // Messages sent to user
        Filter(
          kinds: [4],
          pTags: [userPubkey],
          limit: 500,
        ),
      ];

      final dmEvents = await _relayProvider!.relay.queryEvents(filters);
      
      // Process DM events into conversations
      await _processDMEvents(dmEvents);
      
      // Subscribe for real-time updates
      await _startMessageSubscription();
      
    } catch (e) {
      _logger.severe('Failed to load conversations', e);
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  /// Open a conversation with a specific user
  Future<void> openConversation(String pubkey) async {
    _currentConversationPubkey = pubkey;
    
    // Mark messages as read
    final conversation = _conversations[pubkey];
    if (conversation != null && conversation.unreadCount > 0) {
      final updatedMessages = conversation.messages.map((msg) =>
          msg.isFromCurrentUser ? msg : msg.copyWith(isRead: true)).toList();
      
      _conversations[pubkey] = conversation.copyWith(
        messages: updatedMessages,
        unreadCount: 0,
      );
    }
    
    // Load profile if not cached
    if (conversation?.participantProfile == null && _userProvider != null) {
      final profile = await _userProvider!.getProfile(pubkey);
      if (profile != null && _conversations[pubkey] != null) {
        _conversations[pubkey] = _conversations[pubkey]!.copyWith(
          participantProfile: profile,
        );
      }
    }
    
    notifyListeners();
  }

  /// Close current conversation
  void closeConversation() {
    _currentConversationPubkey = null;
    notifyListeners();
  }

  /// Send a direct message
  Future<void> sendMessage({
    required String recipientPubkey,
    required String content,
  }) async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      throw StateError('User not signed in');
    }
    
    if (_relayProvider?.relay == null) {
      throw StateError('Relay not available');
    }

    _isSendingMessage = true;
    notifyListeners();

    try {
      final dmEvent = _userProvider!.createDirectMessage(
        recipientPubkey: recipientPubkey,
        content: content,
      );
      
      final published = await _relayProvider!.relay.publish(dmEvent);
      
      if (published) {
        _logger.info('DM sent: ${dmEvent.id}');
        
        // Add to local conversation immediately
        final message = DirectMessage(
          event: dmEvent,
          recipientPubkey: recipientPubkey,
          senderPubkey: _userProvider!.publicKey!,
          decryptedContent: content, // We know the content since we sent it
          timestamp: DateTime.fromMillisecondsSinceEpoch(dmEvent.createdAt * 1000),
          isFromCurrentUser: true,
          isRead: true,
        );
        
        _addMessageToConversation(message);
      } else {
        throw Exception('Failed to publish message');
      }
    } catch (e) {
      _logger.severe('Failed to send message', e);
      rethrow;
    } finally {
      _isSendingMessage = false;
      notifyListeners();
    }
  }

  /// Load message history for a conversation
  Future<void> loadConversationHistory(String pubkey, {int limit = 50}) async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      return;
    }
    
    if (_relayProvider?.relay == null) {
      return;
    }

    _isLoadingMessages = true;
    notifyListeners();

    try {
      final userPubkey = _userProvider!.publicKey!;
      
      // Get older messages for this conversation
      final conversation = _conversations[pubkey];
      final oldestTimestamp = conversation?.messages.isNotEmpty == true
          ? conversation!.messages.last.timestamp.millisecondsSinceEpoch ~/ 1000
          : DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      final List<Filter> filters = [
        // Messages between user and participant
        Filter(
          kinds: [4],
          authors: [userPubkey],
          pTags: [pubkey],
          until: oldestTimestamp,
          limit: limit,
        ),
        Filter(
          kinds: [4],
          authors: [pubkey],
          pTags: [userPubkey],
          until: oldestTimestamp,
          limit: limit,
        ),
      ];

      final dmEvents = await _relayProvider!.relay.queryEvents(filters);
      
      // Process and add to conversation
      await _processDMEvents(dmEvents);
      
    } catch (e) {
      _logger.severe('Failed to load conversation history', e);
    } finally {
      _isLoadingMessages = false;
      notifyListeners();
    }
  }

  /// Delete a conversation (locally only)
  void deleteConversation(String pubkey) {
    _conversations.remove(pubkey);
    
    if (_currentConversationPubkey == pubkey) {
      _currentConversationPubkey = null;
    }
    
    notifyListeners();
  }

  /// Search conversations by participant name or pubkey
  List<Conversation> searchConversations(String query) {
    if (query.isEmpty) return conversations;
    
    final lowerQuery = query.toLowerCase();
    return conversations.where((conv) {
      final name = conv.participantProfile?.name?.toLowerCase() ?? '';
      final pubkey = conv.participantPubkey.toLowerCase();
      return name.contains(lowerQuery) || pubkey.contains(lowerQuery);
    }).toList();
  }

  // Private methods

  Future<void> _processDMEvents(List<NostrEvent> dmEvents) async {
    if (_userProvider == null) return;
    
    final userPubkey = _userProvider!.publicKey!;
    
    for (final event in dmEvents) {
      try {
        // Determine participants
        final isFromCurrentUser = event.pubkey == userPubkey;
        final otherPubkey = isFromCurrentUser
            ? event.tags.firstWhere(
                (tag) => tag.isNotEmpty && tag[0] == 'p',
                orElse: () => ['', ''],
              )[1]
            : event.pubkey;
        
        if (otherPubkey.isEmpty) continue;
        
        // Decrypt content (placeholder - NIP-04 encryption not implemented)
        final decryptedContent = event.content; // TODO: Implement decryption
        
        final message = DirectMessage(
          event: event,
          recipientPubkey: isFromCurrentUser ? otherPubkey : userPubkey,
          senderPubkey: event.pubkey,
          decryptedContent: decryptedContent,
          timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          isFromCurrentUser: isFromCurrentUser,
          isRead: isFromCurrentUser, // Own messages are always "read"
        );
        
        _addMessageToConversation(message);
        
      } catch (e) {
        _logger.warning('Failed to process DM event ${event.id}', e);
      }
    }
  }

  void _addMessageToConversation(DirectMessage message) {
    final participantPubkey = message.isFromCurrentUser 
        ? message.recipientPubkey 
        : message.senderPubkey;
    
    final existingConversation = _conversations[participantPubkey];
    
    if (existingConversation == null) {
      // Create new conversation
      _conversations[participantPubkey] = Conversation(
        participantPubkey: participantPubkey,
        messages: [message],
        lastMessage: message,
        unreadCount: message.isFromCurrentUser ? 0 : 1,
        lastActivity: message.timestamp,
      );
    } else {
      // Add to existing conversation
      final messages = List<DirectMessage>.from(existingConversation.messages);
      
      // Check if message already exists
      if (!messages.any((m) => m.event.id == message.event.id)) {
        messages.add(message);
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
        final unreadCount = existingConversation.unreadCount + 
            (message.isFromCurrentUser ? 0 : 1);
        
        _conversations[participantPubkey] = existingConversation.copyWith(
          messages: messages,
          lastMessage: message,
          unreadCount: unreadCount,
          lastActivity: message.timestamp,
        );
      }
    }
  }

  Future<void> _startMessageSubscription() async {
    if (_userProvider == null || !_userProvider!.isSignedIn) {
      return;
    }
    
    if (_relayProvider?.relay == null) {
      return;
    }

    // Close existing subscription
    await _dmSubscription?.close();
    
    final userPubkey = _userProvider!.publicKey!;
    
    // Subscribe to new DMs
    _dmSubscription = _relayProvider!.relay.subscribe(
      filters: [
        // Messages sent to user
        Filter(
          kinds: [4],
          pTags: [userPubkey],
          since: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        // Messages sent by user (for multi-device sync)
        Filter(
          kinds: [4],
          authors: [userPubkey],
          since: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      ],
      onEvent: _handleNewDMEvent,
      onError: (error) => _logger.warning('DM subscription error: $error'),
    );
  }

  void _handleNewDMEvent(NostrEvent event) {
    _processDMEvents([event]).then((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _dmSubscription?.close();
    _eventStreamSubscription?.cancel();
    super.dispose();
  }
}