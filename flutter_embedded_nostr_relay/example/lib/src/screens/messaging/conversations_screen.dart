// ABOUTME: Screen displaying list of direct message conversations
// ABOUTME: Shows conversation previews with unread counts and last messages

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../providers/messaging_provider.dart';
import '../../providers/user_provider.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search conversations...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        
        // Conversations list
        Expanded(
          child: Consumer<MessagingProvider>(
            builder: (context, messagingProvider, child) {
              if (messagingProvider.isLoadingConversations) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading conversations...'),
                    ],
                  ),
                );
              }

              final allConversations = messagingProvider.conversations;
              final conversations = _searchQuery.isEmpty
                  ? allConversations
                  : messagingProvider.searchConversations(_searchQuery);

              if (conversations.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return _ConversationTile(
                    conversation: conversation,
                    onTap: () => _openConversation(conversation.participantPubkey),
                    onDelete: () => _deleteConversation(conversation.participantPubkey),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.message_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No conversations yet' : 'No matching conversations',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Start a conversation by messaging someone!'
                  : 'Try a different search term',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _showNewConversationDialog,
                icon: const Icon(Icons.add),
                label: const Text('New Message'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openConversation(String pubkey) {
    final messagingProvider = context.read<MessagingProvider>();
    messagingProvider.openConversation(pubkey);
    
    // TODO: Navigate to conversation screen
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening conversation with ${pubkey.substring(0, 8)}...'),
      ),
    );
  }

  void _deleteConversation(String pubkey) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: const Text('Are you sure you want to delete this conversation? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.read<MessagingProvider>().deleteConversation(pubkey);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showNewConversationDialog() {
    final TextEditingController pubkeyController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pubkeyController,
              decoration: const InputDecoration(
                labelText: 'Recipient Public Key',
                hintText: 'Enter the public key of the person you want to message',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final pubkey = pubkeyController.text.trim();
              if (pubkey.isNotEmpty) {
                Navigator.of(context).pop();
                _openConversation(pubkey);
              }
            },
            child: const Text('Start Chat'),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profile = conversation.participantProfile;
    final lastMessage = conversation.lastMessage;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.surfaceContainerHighest,
        backgroundImage: profile?.picture != null
            ? NetworkImage(profile!.picture!)
            : null,
        child: profile?.picture == null
            ? Icon(
                Icons.person,
                color: colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      
      title: Row(
        children: [
          Expanded(
            child: Text(
              profile?.name ?? 'Anonymous',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: conversation.unreadCount > 0 
                    ? FontWeight.bold 
                    : FontWeight.normal,
              ),
            ),
          ),
          
          if (conversation.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '@${conversation.participantPubkey.substring(0, 16)}...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          
          if (lastMessage != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (lastMessage.isFromCurrentUser) ...[
                  Icon(
                    Icons.send,
                    size: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                ],
                
                Expanded(
                  child: Text(
                    lastMessage.decryptedContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: conversation.unreadCount > 0 
                          ? FontWeight.w500 
                          : FontWeight.normal,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                Text(
                  timeago.format(lastMessage.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      
      onTap: onTap,
      
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete),
              title: Text('Delete'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}