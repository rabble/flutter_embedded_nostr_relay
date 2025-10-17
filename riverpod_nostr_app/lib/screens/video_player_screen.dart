// ABOUTME: Video player screen for playing vine videos with controls and looping
// ABOUTME: Uses Chewie wrapper around video_player for enhanced video playback

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_embedded_nostr_relay/flutter_embedded_nostr_relay.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerScreen extends StatefulWidget {
  final NostrEvent vineEvent;
  
  const VideoPlayerScreen({super.key, required this.vineEvent});
  
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _videoUrl;
  String? _title;
  String? _description;
  final List<String> _hashtags = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _extractVideoData();
    _initializeVideo();
  }
  
  void _extractVideoData() {
    _title = 'Vine Video';
    _description = widget.vineEvent.content.isNotEmpty ? widget.vineEvent.content : null;
    
    // Extract data from tags
    for (final tag in widget.vineEvent.tags) {
      if (tag.isEmpty) continue;
      
      switch (tag[0]) {
        case 'title':
          if (tag.length > 1) _title = tag[1];
          break;
        case 'imeta':
          // Parse imeta tags which contain url, image, blurhash, etc.
          for (int i = 1; i < tag.length - 1; i += 2) {
            final key = tag[i];
            final value = tag[i + 1];
            if (key == 'url') {
              _videoUrl = value;
            }
          }
          break;
        case 't':
          if (tag.length > 1) _hashtags.add(tag[1]);
          break;
      }
    }
  }
  
  Future<void> _initializeVideo() async {
    if (_videoUrl == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No video URL found in event';
      });
      return;
    }
    
    // On web, video_player has issues with many video formats
    // Let's skip video initialization on web for now and show a fallback
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Web video player not yet supported. Click "Open Video" to view in a new tab.';
      });
      return;
    }
    
    try {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(_videoUrl!));
      await _videoController!.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: true,
        showControlsOnInitialize: false,
        aspectRatio: _videoController!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.purple,
          handleColor: Colors.purple,
          backgroundColor: Colors.grey.shade300,
          bufferedColor: Colors.purple.shade200,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error playing video',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load video: $e';
      });
    }
  }
  
  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _title ?? 'Vine Video',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_videoUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final uri = Uri.parse(_videoUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  if (mounted) {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(content: Text('Could not open video URL')),
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Implement sharing
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sharing not implemented yet')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Video player
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error,
                                color: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!kIsWeb) ...[
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          _isLoading = true;
                                          _errorMessage = null;
                                        });
                                        _initializeVideo();
                                      },
                                      child: const Text('Retry'),
                                    ),
                                    const SizedBox(width: 16),
                                  ],
                                  if (_videoUrl != null)
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final uri = Uri.parse(_videoUrl!);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        } else {
                                          if (mounted) {
                                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                                            scaffoldMessenger.showSnackBar(
                                              const SnackBar(content: Text('Could not open video URL')),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text('Open Video'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : _chewieController != null
                        ? Chewie(controller: _chewieController!)
                        : const Center(
                            child: Text(
                              'No video available',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
          ),
          
          // Video info panel
          Container(
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  _title ?? 'Vine Video',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                // Description
                if (_description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _description!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
                
                // Hashtags
                if (_hashtags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _hashtags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade600,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '#$tag',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
                
                // Author info
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.purple.shade600,
                      child: const Icon(Icons.person, size: 16, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${widget.vineEvent.pubkey.substring(0, 8)}...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTimestamp(widget.vineEvent.createdAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 30) {
      return '${diff.inDays}d ago';
    } else {
      return '${(diff.inDays / 30).round()}mo ago';
    }
  }
}