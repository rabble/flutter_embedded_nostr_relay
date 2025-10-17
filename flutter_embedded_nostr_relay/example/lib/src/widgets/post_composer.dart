// ABOUTME: Widget for composing and publishing new posts to Nostr
// ABOUTME: Supports text content, media attachments, and reply functionality

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/timeline_provider.dart';
import '../providers/user_provider.dart';

class PostComposer extends StatefulWidget {
  final ScrollController? scrollController;
  final VoidCallback? onPostPublished;
  final String? replyToEventId;
  final String? replyToAuthor;

  const PostComposer({
    super.key,
    this.scrollController,
    this.onPostPublished,
    this.replyToEventId,
    this.replyToAuthor,
  });

  @override
  State<PostComposer> createState() => _PostComposerState();
}

class _PostComposerState extends State<PostComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isPublishing = false;
  
  // Character limits
  static const int _maxCharacters = 2000;
  static const int _warningThreshold = 1800;

  @override
  void initState() {
    super.initState();
    // Auto-focus the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canPublish {
    final text = _textController.text.trim();
    return text.isNotEmpty && 
           text.length <= _maxCharacters && 
           !_isPublishing;
  }

  int get _remainingCharacters => _maxCharacters - _textController.text.length;

  Color _getCharacterCountColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = _remainingCharacters;
    
    if (remaining < 0) {
      return colorScheme.error;
    } else if (remaining < (_maxCharacters - _warningThreshold)) {
      return colorScheme.primary;
    } else {
      return colorScheme.onSurfaceVariant;
    }
  }

  Future<void> _publishPost() async {
    if (!_canPublish) return;

    setState(() {
      _isPublishing = true;
    });

    try {
      final timelineProvider = context.read<TimelineProvider>();
      final content = _textController.text.trim();
      
      List<String>? replyTo;
      List<String>? mentionPubkeys;
      
      if (widget.replyToEventId != null) {
        replyTo = [widget.replyToEventId!];
      }
      
      if (widget.replyToAuthor != null) {
        mentionPubkeys = [widget.replyToAuthor!];
      }
      
      await timelineProvider.publishPost(
        content: content,
        replyTo: replyTo,
        mentionPubkeys: mentionPubkeys,
      );

      // Clear the text field
      _textController.clear();
      
      // Call the callback
      widget.onPostPublished?.call();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post published successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish post: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        final profile = userProvider.profile;
        
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    // Cancel button
                    TextButton(
                      onPressed: _isPublishing ? null : () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    
                    const Spacer(),
                    
                    // Title
                    Text(
                      widget.replyToEventId != null ? 'Reply' : 'New Post',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Publish button
                    FilledButton(
                      onPressed: _canPublish ? _publishPost : null,
                      child: _isPublishing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Post'),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Reply context (if replying)
                if (widget.replyToEventId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Replying to @${widget.replyToAuthor?.substring(0, 8) ?? 'unknown'}...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Composer content
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile picture
                      CircleAvatar(
                        radius: 20,
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
                      
                      const SizedBox(width: 12),
                      
                      // Text input
                      Expanded(
                        child: Column(
                          children: [
                            // Text field
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText: widget.replyToEventId != null
                                      ? 'What\'s your reply?'
                                      : 'What\'s happening?',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                                style: theme.textTheme.bodyLarge,
                                textInputAction: TextInputAction.newline,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            
                            // Character counter and actions
                            Row(
                              children: [
                                // TODO: Add media attachment button
                                IconButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Media attachments coming soon'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.image_outlined),
                                ),
                                
                                // TODO: Add emoji picker button
                                IconButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Emoji picker coming soon'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.emoji_emotions_outlined),
                                ),
                                
                                const Spacer(),
                                
                                // Character counter
                                Text(
                                  _remainingCharacters.toString(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _getCharacterCountColor(context),
                                    fontWeight: _remainingCharacters < 100
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom padding for keyboard
                SizedBox(
                  height: MediaQuery.of(context).viewInsets.bottom,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}