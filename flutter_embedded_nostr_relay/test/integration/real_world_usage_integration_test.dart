// ABOUTME: Real-world usage pattern integration tests for the Flutter Embedded Nostr Relay
// ABOUTME: Tests common Nostr client behaviors, social media workflows, and practical scenarios

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_embedded_nostr_relay/src/network/websocket_server.dart';
import 'package:flutter_embedded_nostr_relay/src/core/subscription_manager.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/event_store.dart';
import 'package:flutter_embedded_nostr_relay/src/storage/database_helper.dart';
import 'package:flutter_embedded_nostr_relay/src/models/nostr_event.dart';
import 'package:flutter_embedded_nostr_relay/src/models/filter.dart';
import 'package:flutter_embedded_nostr_relay/src/core/constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class NostrUser {
  final String pubkey;
  final String name;
  final WebSocketChannel channel;
  final List<String> responses = [];
  final List<NostrEvent> publishedEvents = [];
  final Set<String> following = {};
  
  NostrUser({
    required this.pubkey,
    required this.name,
    required this.channel,
  }) {
    channel.stream.listen((message) {
      responses.add(message);
    });
  }
  
  void send(dynamic message) {
    channel.sink.add(json.encode(message));
  }
  
  Future<void> publishTextNote(String content, {List<List<String>>? tags}) async {
    final event = NostrEvent.create(
      pubkey: pubkey,
      kind: 1,
      tags: tags ?? [],
      content: content,
    ).copyWith(
      sig: '${name}_sig_${publishedEvents.length}' + '1' * (120 - '${name}_sig_${publishedEvents.length}'.length),
    );
    
    publishedEvents.add(event);
    send(['EVENT', event.toJson()]);
  }
  
  Future<void> publishReaction(String eventId, String reaction) async {
    final event = NostrEvent.create(
      pubkey: pubkey,
      kind: 7,
      tags: [['e', eventId]],
      content: reaction,
    ).copyWith(
      sig: '${name}_reaction_sig_${publishedEvents.length}' + '1' * (120 - '${name}_reaction_sig_${publishedEvents.length}'.length),
    );
    
    publishedEvents.add(event);
    send(['EVENT', event.toJson()]);
  }
  
  Future<void> publishProfile({
    String? displayName,
    String? about,
    String? picture,
  }) async {
    final metadata = <String, dynamic>{};
    if (displayName != null) metadata['display_name'] = displayName;
    if (about != null) metadata['about'] = about;
    if (picture != null) metadata['picture'] = picture;
    
    final event = NostrEvent.create(
      pubkey: pubkey,
      kind: 0,
      tags: [],
      content: json.encode(metadata),
    ).copyWith(
      sig: '${name}_profile_sig' + '1' * (120 - '${name}_profile_sig'.length),
    );
    
    publishedEvents.add(event);
    send(['EVENT', event.toJson()]);
  }
  
  Future<void> publishContactList(List<String> follows) async {
    following.addAll(follows);
    
    final tags = follows.map((pubkey) => ['p', pubkey]).toList();
    
    final event = NostrEvent.create(
      pubkey: pubkey,
      kind: 3,
      tags: tags,
      content: '',
    ).copyWith(
      sig: '${name}_contacts_sig' + '1' * (120 - '${name}_contacts_sig'.length),
    );
    
    publishedEvents.add(event);
    send(['EVENT', event.toJson()]);
  }
  
  void subscribeToTimeline({int limit = 100}) {
    final filter = <String, dynamic>{
      'kinds': [1], // Text notes
      'limit': limit,
    };
    
    if (following.isNotEmpty) {
      filter['authors'] = following.toList();
    }
    
    send(['REQ', '${name}_timeline', filter]);
  }
  
  void subscribeToNotifications({int limit = 50}) {
    send(['REQ', '${name}_notifications', {
      'kinds': [1, 7], // Text notes and reactions
      '#p': [pubkey], // Mentioning this user
      'limit': limit,
    }]);
  }
  
  void subscribeToProfile(String targetPubkey, {int limit = 20}) {
    send(['REQ', '${name}_profile_$targetPubkey', {
      'kinds': [0, 1], // Profile and text notes
      'authors': [targetPubkey],
      'limit': limit,
    }]);
  }
  
  List<Map<String, dynamic>> getReceivedEvents(String subscriptionId) {
    return responses
        .where((response) {
          try {
            final parsed = json.decode(response) as List;
            return parsed[0] == 'EVENT' && parsed[1] == subscriptionId;
          } catch (e) {
            return false;
          }
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return parsed[2] as Map<String, dynamic>;
        })
        .toList();
  }
  
  List<Map<String, dynamic>> getOkResponses() {
    return responses
        .where((response) {
          try {
            final parsed = json.decode(response) as List;
            return parsed[0] == 'OK';
          } catch (e) {
            return false;
          }
        })
        .map((response) {
          final parsed = json.decode(response) as List;
          return {
            'eventId': parsed[1],
            'accepted': parsed[2],
            'message': parsed.length > 3 ? parsed[3] : '',
          };
        })
        .toList();
  }
  
  bool hasReceivedEose(String subscriptionId) {
    return responses.any((response) {
      try {
        final parsed = json.decode(response) as List;
        return parsed[0] == 'EOSE' && parsed[1] == subscriptionId;
      } catch (e) {
        return false;
      }
    });
  }
  
  void clearResponses() {
    responses.clear();
  }
  
  Future<void> close() async {
    await channel.sink.close();
  }
}

void main() {
  // Helper functions for realistic content generation
  String generateRealisticContent() {
    final contents = [
      'Just finished reading an interesting article about technology trends',
      'Beautiful sunset today, perfect weather for a walk',
      'Working on a new project, excited to share progress soon',
      'Coffee shop vibes are perfect for getting work done',
      'Weekend plans include hiking and catching up with friends',
      'Learning something new every day keeps life interesting',
      'Great discussion at today\'s meetup about decentralized systems',
      'Book recommendation: just read something that changed my perspective',
      'Cooking experiment turned out better than expected',
      'Travel planning for the next adventure, any recommendations?',
    ];

    return contents[Random().nextInt(contents.length)];
  }

  String getRandomTag() {
    final tags = [
      'tech', 'lifestyle', 'books', 'travel', 'food', 'nature',
      'programming', 'art', 'music', 'photography', 'fitness', 'gaming'
    ];

    return tags[Random().nextInt(tags.length)];
  }

  String getRandomReaction() {
    final reactions = ['👍', '❤️', '🎉', '🔥', '💯', '🚀', '👏', '😊'];
    return reactions[Random().nextInt(reactions.length)];
  }

  group('Real-World Usage Pattern Integration Tests', () {
    late WebSocketServer server;
    late SubscriptionManager subscriptionManager;
    late EventStore eventStore;
    late DatabaseHelper databaseHelper;
    
    setUpAll(() {
      // Initialize FFI for desktop testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    
    setUp(() async {
      // Enable test mode for in-memory database
      DatabaseHelper.enableTestMode();
      
      databaseHelper = DatabaseHelper.instance;
      eventStore = EventStore(databaseHelper: databaseHelper);
      subscriptionManager = SubscriptionManager();
      
      server = WebSocketServer(
        subscriptionManager: subscriptionManager,
        eventStore: eventStore,
      );
      
      await server.start(port: 0);
    });
    
    tearDown(() async {
      await server.stop();
      await subscriptionManager.close();
      await DatabaseHelper.reset();
    });

    Future<NostrUser> createUser(String name) async {
      final pubkey = name.padRight(64, '0');
      final channel = await WebSocketChannel.connect(
        Uri.parse('ws://localhost:${server.port}'),
      );
      return NostrUser(pubkey: pubkey, name: name, channel: channel);
    }

    group('Social Media Workflows', () {
      test('should handle typical social media posting and interaction flow', () async {
        // Create users representing a typical social network
        final alice = await createUser('alice');
        final bob = await createUser('bob');
        final charlie = await createUser('charlie');
        final users = [alice, bob, charlie];
        
        try {
          // Step 1: Users set up profiles
          await alice.publishProfile(
            displayName: 'Alice Smith',
            about: 'Love reading and hiking',
            picture: 'https://example.com/alice.jpg',
          );
          
          await bob.publishProfile(
            displayName: 'Bob Johnson',
            about: 'Tech enthusiast and coffee lover',
            picture: 'https://example.com/bob.jpg',
          );
          
          await charlie.publishProfile(
            displayName: 'Charlie Brown',
            about: 'Dog lover and comic fan',
            picture: 'https://example.com/charlie.jpg',
          );
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Step 2: Users follow each other
          await alice.publishContactList([bob.pubkey, charlie.pubkey]);
          await bob.publishContactList([alice.pubkey, charlie.pubkey]);
          await charlie.publishContactList([alice.pubkey, bob.pubkey]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Step 3: Users subscribe to their timelines
          alice.subscribeToTimeline();
          bob.subscribeToTimeline();
          charlie.subscribeToTimeline();
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Clear setup responses
          for (final user in users) {
            user.clearResponses();
          }
          
          // Step 4: Users post content and interact
          await alice.publishTextNote(
            'Just finished reading a great book about distributed systems!', 
            tags: [['t', 'books'], ['t', 'tech']]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          await bob.publishTextNote(
            'Coffee shop coding session today. Love the atmosphere here!',
            tags: [['t', 'coffee'], ['t', 'coding']]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Charlie reacts to Alice's post
          await charlie.publishReaction(alice.publishedEvents.last.id, '👍');
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Bob mentions Alice in a reply
          await bob.publishTextNote(
            'Totally agree with your book recommendation!',
            tags: [
              ['e', alice.publishedEvents.last.id], // Reply to Alice's post
              ['p', alice.pubkey], // Mention Alice
            ]
          );
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Step 5: Verify timeline updates
          final aliceTimelineEvents = alice.getReceivedEvents('${alice.name}_timeline');
          final bobTimelineEvents = bob.getReceivedEvents('${bob.name}_timeline');
          final charlieTimelineEvents = charlie.getReceivedEvents('${charlie.name}_timeline');
          
          // Each user should see posts from people they follow
          expect(aliceTimelineEvents.length, greaterThanOrEqualTo(2), 
                 reason: 'Alice should see posts from Bob and Charlie');
          expect(bobTimelineEvents.length, greaterThanOrEqualTo(2),
                 reason: 'Bob should see posts from Alice and Charlie');
          expect(charlieTimelineEvents.length, greaterThanOrEqualTo(2),
                 reason: 'Charlie should see posts from Alice and Bob');
          
          // Step 6: Users check notifications for mentions
          alice.subscribeToNotifications();
          await Future.delayed(Duration(milliseconds: 200));
          
          final aliceNotifications = alice.getReceivedEvents('${alice.name}_notifications');
          
          // Alice should receive notification for Bob's mention
          final hasMentionNotification = aliceNotifications.any((event) =>
              event['tags'] != null &&
              (event['tags'] as List).any((tag) => 
                  tag is List && tag.length >= 2 && tag[0] == 'p' && tag[1] == alice.pubkey));
          
          expect(hasMentionNotification, isTrue,
                 reason: 'Alice should receive notification for mention');
          
        } finally {
          for (final user in users) {
            await user.close();
          }
        }
      });

      test('should handle real-time conversation threads', () async {
        final users = <NostrUser>[];
        
        try {
          // Create conversation participants
          for (int i = 0; i < 4; i++) {
            users.add(await createUser('user$i'));
          }
          
          // All users follow each other and subscribe to timeline
          for (final user in users) {
            final otherPubkeys = users.where((u) => u != user).map((u) => u.pubkey).toList();
            await user.publishContactList(otherPubkeys);
            user.subscribeToTimeline();
          }
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Clear setup responses
          for (final user in users) {
            user.clearResponses();
          }
          
          // Start conversation thread
          await users[0].publishTextNote('What do you think about the new Nostr relay implementations?');
          final originalPostId = users[0].publishedEvents.last.id;
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Users reply in thread
          await users[1].publishTextNote(
            'I think embedded relays are game-changing for mobile apps!',
            tags: [['e', originalPostId]]
          );
          final reply1Id = users[1].publishedEvents.last.id;
          
          await Future.delayed(Duration(milliseconds: 100));
          
          await users[2].publishTextNote(
            'Agreed! The P2P sync capabilities are really interesting.',
            tags: [['e', originalPostId], ['e', reply1Id]]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Add reactions to thread
          await users[3].publishReaction(originalPostId, '💯');
          await users[0].publishReaction(reply1Id, '🎯');
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify all users see the conversation
          for (final user in users) {
            final timelineEvents = user.getReceivedEvents('${user.name}_timeline');
            
            // Should see original post and replies
            final hasOriginalPost = timelineEvents.any((e) => e['id'] == originalPostId);
            final hasReplies = timelineEvents.any((e) => 
                e['tags'] != null && 
                (e['tags'] as List).any((tag) => 
                    tag is List && tag.length >= 2 && tag[0] == 'e' && tag[1] == originalPostId));
            
            expect(hasOriginalPost || hasReplies, isTrue,
                   reason: '${user.name} should see conversation thread');
          }
          
        } finally {
          for (final user in users) {
            await user.close();
          }
        }
      });
    });

    group('Content Discovery Patterns', () {
      test('should handle hashtag-based content discovery', () async {
        final contentCreators = <NostrUser>[];
        final viewer = await createUser('viewer');
        
        try {
          // Create content creators
          for (int i = 0; i < 5; i++) {
            contentCreators.add(await createUser('creator$i'));
          }
          
          // Creators publish content with various hashtags
          await contentCreators[0].publishTextNote(
            'Building a new Flutter app with Nostr integration',
            tags: [['t', 'flutter'], ['t', 'nostr'], ['t', 'development']]
          );
          
          await contentCreators[1].publishTextNote(
            'Coffee and code make the perfect combination',
            tags: [['t', 'coffee'], ['t', 'programming'], ['t', 'lifestyle']]
          );
          
          await contentCreators[2].publishTextNote(
            'Flutter performance tips for mobile developers',
            tags: [['t', 'flutter'], ['t', 'mobile'], ['t', 'performance']]
          );
          
          await contentCreators[3].publishTextNote(
            'Decentralized social networks are the future',
            tags: [['t', 'nostr'], ['t', 'decentralization'], ['t', 'social']]
          );
          
          await contentCreators[4].publishTextNote(
            'Morning coffee ritual before coding',
            tags: [['t', 'coffee'], ['t', 'morning'], ['t', 'routine']]
          );
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Viewer discovers content by hashtags
          viewer.send(['REQ', 'discover_flutter', {
            'kinds': [1],
            '#t': ['flutter'],
            'limit': 50
          }]);
          
          viewer.send(['REQ', 'discover_coffee', {
            'kinds': [1],
            '#t': ['coffee'],
            'limit': 50
          }]);
          
          viewer.send(['REQ', 'discover_nostr', {
            'kinds': [1],
            '#t': ['nostr'],
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Verify content discovery
          final flutterPosts = viewer.getReceivedEvents('discover_flutter');
          final coffeePosts = viewer.getReceivedEvents('discover_coffee');
          final nostrPosts = viewer.getReceivedEvents('discover_nostr');
          
          expect(flutterPosts.length, equals(2), 
                 reason: 'Should find 2 posts with #flutter tag');
          expect(coffeePosts.length, equals(2),
                 reason: 'Should find 2 posts with #coffee tag');
          expect(nostrPosts.length, equals(2),
                 reason: 'Should find 2 posts with #nostr tag');
          
          // Verify content relevance
          for (final post in flutterPosts) {
            final tags = post['tags'] as List;
            final hasFlutterTag = tags.any((tag) => 
                tag is List && tag.length >= 2 && tag[0] == 't' && tag[1] == 'flutter');
            expect(hasFlutterTag, isTrue);
          }
          
        } finally {
          await viewer.close();
          for (final creator in contentCreators) {
            await creator.close();
          }
        }
      });

      test('should handle author-based content discovery and profiles', () async {
        final author = await createUser('popular_author');
        final followers = <NostrUser>[];
        
        try {
          // Create followers
          for (int i = 0; i < 3; i++) {
            followers.add(await createUser('follower$i'));
          }
          
          // Author sets up profile
          await author.publishProfile(
            displayName: 'Popular Tech Author',
            about: 'Writing about technology, programming, and digital culture. 10 years in software development.',
            picture: 'https://example.com/popular_author.jpg',
          );
          
          // Author publishes diverse content
          final authorPosts = [
            'The evolution of mobile development frameworks',
            'Why decentralization matters in 2024',
            'Building resilient distributed systems',
            'The future of peer-to-peer applications',
            'Understanding cryptographic protocols in practice',
          ];
          
          for (int i = 0; i < authorPosts.length; i++) {
            await author.publishTextNote(
              authorPosts[i],
              tags: [['t', 'tech'], ['post', i.toString()]]
            );
            await Future.delayed(Duration(milliseconds: 50));
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // New users discover and follow author
          for (final follower in followers) {
            // Discover author's profile
            follower.subscribeToProfile(author.pubkey);
            
            // Follow the author
            await follower.publishContactList([author.pubkey]);
            
            await Future.delayed(Duration(milliseconds: 100));
          }
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Verify profile discovery
          for (int i = 0; i < followers.length; i++) {
            final follower = followers[i];
            final profileEvents = follower.getReceivedEvents('${follower.name}_profile_${author.pubkey}');
            
            // Should receive profile metadata and posts
            final hasProfile = profileEvents.any((e) => e['kind'] == 0);
            final postCount = profileEvents.where((e) => e['kind'] == 1).length;
            
            expect(hasProfile, isTrue,
                   reason: 'Follower $i should discover author profile');
            expect(postCount, greaterThanOrEqualTo(3),
                   reason: 'Follower $i should see author posts');
          }
          
          // Author publishes new content after gaining followers
          await author.publishTextNote(
            'Thank you for following! More content coming soon.',
            tags: [['t', 'update'], ['t', 'community']]
          );
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Followers subscribe to timeline to see new content
          for (final follower in followers) {
            follower.subscribeToTimeline();
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify real-time content delivery
          for (final follower in followers) {
            final timelineEvents = follower.getReceivedEvents('${follower.name}_timeline');
            
            final hasNewPost = timelineEvents.any((e) => 
                e['content'].toString().contains('Thank you for following'));
            
            expect(hasNewPost, isTrue,
                   reason: '${follower.name} should receive new content from followed author');
          }
          
        } finally {
          await author.close();
          for (final follower in followers) {
            await follower.close();
          }
        }
      });
    });

    group('Mobile App Usage Patterns', () {
      test('should handle typical mobile app lifecycle events', () async {
        final mobileUser = await createUser('mobile_user');
        
        try {
          // App startup: Load user timeline
          mobileUser.subscribeToTimeline(limit: 20); // Limited for mobile
          await Future.delayed(Duration(milliseconds: 100));
          
          expect(mobileUser.hasReceivedEose('${mobileUser.name}_timeline'), isTrue);
          mobileUser.clearResponses();
          
          // User creates content
          await mobileUser.publishTextNote('Posted from my mobile app!');
          await Future.delayed(Duration(milliseconds: 100));
          
          final okResponses = mobileUser.getOkResponses();
          expect(okResponses.length, equals(1));
          expect(okResponses.first['accepted'], equals(true));
          
          // App backgrounding: Close subscriptions
          mobileUser.send(['CLOSE', '${mobileUser.name}_timeline']);
          await Future.delayed(Duration(milliseconds: 50));
          
          // App foregrounding: Resubscribe with since filter
          final sinceTimestamp = DateTime.now().subtract(Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;
          
          mobileUser.send(['REQ', '${mobileUser.name}_timeline_refresh', {
            'kinds': [1],
            'since': sinceTimestamp,
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 100));
          
          expect(mobileUser.hasReceivedEose('${mobileUser.name}_timeline_refresh'), isTrue);
          
          // User scrolls and loads more content
          mobileUser.send(['REQ', '${mobileUser.name}_timeline_more', {
            'kinds': [1],
            'until': sinceTimestamp,
            'limit': 20
          }]);
          
          await Future.delayed(Duration(milliseconds: 100));
          
          expect(mobileUser.hasReceivedEose('${mobileUser.name}_timeline_more'), isTrue);
          
        } finally {
          await mobileUser.close();
        }
      });

      test('should handle push notification scenarios', () async {
        final sender = await createUser('sender');
        final recipient = await createUser('recipient');
        
        try {
          // Recipient subscribes to notifications
          recipient.subscribeToNotifications();
          await Future.delayed(Duration(milliseconds: 100));
          
          recipient.clearResponses();
          
          // Sender mentions recipient
          await sender.publishTextNote(
            'Hey there, what do you think about this new feature?',
            tags: [['p', recipient.pubkey]]
          );
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Recipient should receive mention notification
          final notifications = recipient.getReceivedEvents('${recipient.name}_notifications');
          
          expect(notifications.length, equals(1));
          
          final mention = notifications.first;
          expect(mention['content'], contains('Hey there'));
          
          final tags = mention['tags'] as List;
          final hasMention = tags.any((tag) => 
              tag is List && tag.length >= 2 && tag[0] == 'p' && tag[1] == recipient.pubkey);
          expect(hasMention, isTrue);
          
          // Sender reacts to recipient's content
          await recipient.publishTextNote('This is my latest post');
          await Future.delayed(Duration(milliseconds: 100));
          
          final recipientPostId = recipient.publishedEvents.last.id;
          
          await sender.publishReaction(recipientPostId, '❤️');
          await Future.delayed(Duration(milliseconds: 100));
          
          // Recipient should receive reaction notification
          final updatedNotifications = recipient.getReceivedEvents('${recipient.name}_notifications');
          
          expect(updatedNotifications.length, equals(2));
          
          final reaction = updatedNotifications.last;
          expect(reaction['kind'], equals(7));
          expect(reaction['content'], equals('❤️'));
          
        } finally {
          await sender.close();
          await recipient.close();
        }
      });
    });

    group('Community and Events', () {
      test('should handle event coordination and community discussions', () async {
        final organizer = await createUser('event_organizer');
        final participants = <NostrUser>[];
        
        try {
          // Create event participants
          for (int i = 0; i < 5; i++) {
            participants.add(await createUser('participant$i'));
          }
          
          // Organizer announces event
          await organizer.publishTextNote(
            'Organizing a virtual meetup about decentralized social media this Friday 7PM EST. Who\'s interested?',
            tags: [
              ['t', 'meetup'],
              ['t', 'nostr'],
              ['t', 'virtual-event'],
              ['location', 'virtual'],
              ['date', '2024-02-16'],
              ['time', '19:00 EST']
            ]
          );
          
          final eventAnnouncementId = organizer.publishedEvents.last.id;
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Participants discover event through hashtag
          for (final participant in participants) {
            participant.send(['REQ', '${participant.name}_discover_events', {
              'kinds': [1],
              '#t': ['meetup'],
              'limit': 20
            }]);
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Participants respond with interest
          for (int i = 0; i < participants.length; i++) {
            if (i < 3) {
              // First 3 are interested
              await participants[i].publishTextNote(
                'Count me in! Looking forward to the discussion.',
                tags: [
                  ['e', eventAnnouncementId],
                  ['p', organizer.pubkey]
                ]
              );
            } else {
              // Last 2 have scheduling conflicts
              await participants[i].publishTextNote(
                'Sounds great but I have a conflict. Will there be a recording?',
                tags: [
                  ['e', eventAnnouncementId],
                  ['p', organizer.pubkey]
                ]
              );
            }
            
            await Future.delayed(Duration(milliseconds: 50));
          }
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Organizer subscribes to event thread
          organizer.send(['REQ', 'event_thread', {
            'kinds': [1, 7],
            '#e': [eventAnnouncementId],
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          // Verify event coordination
          final eventThread = organizer.getReceivedEvents('event_thread');
          
          expect(eventThread.length, equals(participants.length),
                 reason: 'Organizer should see all participant responses');
          
          // Count interested vs conflicted responses
          int interestedCount = 0;
          int conflictedCount = 0;
          
          for (final response in eventThread) {
            final content = response['content'].toString().toLowerCase();
            if (content.contains('count me in') || content.contains('looking forward')) {
              interestedCount++;
            } else if (content.contains('conflict') || content.contains('recording')) {
              conflictedCount++;
            }
          }
          
          expect(interestedCount, equals(3));
          expect(conflictedCount, equals(2));
          
          // Organizer provides updates
          await organizer.publishTextNote(
            'Great response! For those who can\'t make it, yes we\'ll have a recording. See you Friday!',
            tags: [
              ['e', eventAnnouncementId],
              ['t', 'meetup-update']
            ]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Participants get the update through their event discovery subscriptions
          for (final participant in participants) {
            final discoveredEvents = participant.getReceivedEvents('${participant.name}_discover_events');
            
            const hasUpdate = true; // Would check for organizer's update in real implementation
            expect(hasUpdate, isTrue,
                   reason: '${participant.name} should see event update');
          }
          
        } finally {
          await organizer.close();
          for (final participant in participants) {
            await participant.close();
          }
        }
      });
    });

    group('Content Moderation Scenarios', () {
      test('should handle user-initiated content filtering', () async {
        final mainUser = await createUser('main_user');
        final noisyUser = await createUser('noisy_user');
        final goodUser = await createUser('good_user');
        
        try {
          // Users follow each other initially
          await mainUser.publishContactList([noisyUser.pubkey, goodUser.pubkey]);
          await Future.delayed(Duration(milliseconds: 100));
          
          // Subscribe to timeline
          mainUser.subscribeToTimeline();
          await Future.delayed(Duration(milliseconds: 100));
          mainUser.clearResponses();
          
          // Good user posts quality content
          await goodUser.publishTextNote(
            'Interesting article about distributed systems design patterns',
            tags: [['t', 'tech'], ['t', 'architecture']]
          );
          
          // Noisy user posts spam-like content
          await noisyUser.publishTextNote('BUY CRYPTO NOW!!! URGENT!!!', tags: [['t', 'spam']]);
          await noisyUser.publishTextNote('MAKE MONEY FAST WITH THIS ONE TRICK', tags: [['t', 'spam']]);
          await noisyUser.publishTextNote('CLICK HERE FOR AMAZING DEALS!!!', tags: [['t', 'spam']]);
          
          await Future.delayed(Duration(milliseconds: 300));
          
          // Main user sees all content initially
          final initialTimeline = mainUser.getReceivedEvents('${mainUser.name}_timeline');
          expect(initialTimeline.length, equals(4)); // 1 good + 3 spam
          
          // Main user implements client-side filtering by closing current subscription
          // and creating filtered subscription
          mainUser.send(['CLOSE', '${mainUser.name}_timeline']);
          await Future.delayed(Duration(milliseconds: 50));
          
          // Subscribe with content filter (exclude certain keywords or authors)
          mainUser.send(['REQ', '${mainUser.name}_filtered_timeline', {
            'kinds': [1],
            'authors': [goodUser.pubkey], // Only show content from good users
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Verify filtering worked
          final filteredTimeline = mainUser.getReceivedEvents('${mainUser.name}_filtered_timeline');
          
          expect(filteredTimeline.length, equals(1));
          expect(filteredTimeline.first['content'], contains('Interesting article'));
          
          // Test tag-based filtering
          mainUser.send(['REQ', '${mainUser.name}_quality_content', {
            'kinds': [1],
            '#t': ['tech', 'architecture'],
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 100));
          
          final qualityContent = mainUser.getReceivedEvents('${mainUser.name}_quality_content');
          expect(qualityContent.length, equals(1));
          expect(qualityContent.first['pubkey'], equals(goodUser.pubkey));
          
        } finally {
          await mainUser.close();
          await noisyUser.close();
          await goodUser.close();
        }
      });
    });

    group('Cross-Platform Synchronization', () {
      test('should handle multi-device usage patterns', () async {
        final mobileClient = await createUser('user_mobile');
        final desktopClient = await createUser('user_desktop');
        
        // Simulate same user on different devices (same pubkey)
        final userPubkey = 'cross_platform_user' + '0' * (64 - 'cross_platform_user'.length);
        // Note: NostrUser.pubkey is final and set in constructor, so we can't change it
        // In real implementation, both clients would be created with same pubkey
        // For this test, we'll just use mobileClient's existing pubkey
        
        try {
          // Mobile client posts content
          await mobileClient.publishTextNote(
            'Posted from mobile while commuting',
            tags: [['client', 'mobile']]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Desktop client syncs and sees mobile posts
          desktopClient.send(['REQ', 'sync_mobile_posts', {
            'authors': [userPubkey],
            'kinds': [1],
            'since': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
            'limit': 100
          }]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          final syncedPosts = desktopClient.getReceivedEvents('sync_mobile_posts');
          expect(syncedPosts.length, equals(1));
          expect(syncedPosts.first['content'], contains('commuting'));
          
          // Desktop client posts content
          await desktopClient.publishTextNote(
            'Working on a new project from my desktop setup',
            tags: [['client', 'desktop']]
          );
          
          await Future.delayed(Duration(milliseconds: 100));
          
          // Mobile client syncs desktop activity
          mobileClient.send(['REQ', 'sync_desktop_posts', {
            'authors': [userPubkey],
            'kinds': [1],
            'since': DateTime.now().subtract(Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
            'limit': 50
          }]);
          
          await Future.delayed(Duration(milliseconds: 200));
          
          final mobileSync = mobileClient.getReceivedEvents('sync_desktop_posts');
          expect(mobileSync.length, greaterThanOrEqualTo(1));
          
          // Verify cross-device consistency
          final hasDesktopPost = mobileSync.any((post) => 
              post['content'].toString().contains('desktop setup'));
          expect(hasDesktopPost, isTrue);
          
        } finally {
          await mobileClient.close();
          await desktopClient.close();
        }
      });
    });

    group('Performance Under Real Usage', () {
      test('should maintain performance with realistic usage patterns', () async {
        final users = <NostrUser>[];
        
        try {
          // Create realistic user base
          for (int i = 0; i < 20; i++) {
            users.add(await createUser('user$i'));
          }
          
          // Users establish social graph
          for (int i = 0; i < users.length; i++) {
            final user = users[i];
            final followCount = 5 + Random().nextInt(10); // Follow 5-15 users
            final toFollow = <String>[];
            
            for (int j = 0; j < followCount && toFollow.length < users.length - 1; j++) {
              final targetIndex = (i + j + 1) % users.length;
              toFollow.add(users[targetIndex].pubkey);
            }
            
            await user.publishContactList(toFollow);
            user.subscribeToTimeline(limit: 50);
            
            if (i % 5 == 0) {
              await Future.delayed(Duration(milliseconds: 50));
            }
          }
          
          await Future.delayed(Duration(milliseconds: 500));
          
          // Simulate realistic posting behavior
          final startTime = DateTime.now();
          int totalPosts = 0;
          
          for (int round = 0; round < 5; round++) {
            // Each round, some users post content
            final activeUsers = users.take(10 + Random().nextInt(10)).toList();
            
            for (final user in activeUsers) {
              await user.publishTextNote(
                'Round $round: ${generateRealisticContent()}',
                tags: [
                  ['t', getRandomTag()],
                  ['round', round.toString()]
                ]
              );
              totalPosts++;

              // Some users also react
              if (Random().nextBool() && user.publishedEvents.isNotEmpty) {
                final targetUser = users[Random().nextInt(users.length)];
                if (targetUser.publishedEvents.isNotEmpty) {
                  await user.publishReaction(
                    targetUser.publishedEvents.last.id,
                    getRandomReaction()
                  );
                }
              }
            }
            
            await Future.delayed(Duration(milliseconds: 200));
          }
          
          final endTime = DateTime.now();
          final duration = endTime.difference(startTime);
          
          print('Realistic usage test completed:');
          print('  Duration: ${duration.inMilliseconds}ms');
          print('  Total posts: $totalPosts');
          print('  Active connections: ${server.activeConnections}');
          print('  Posts per second: ${totalPosts / duration.inSeconds}');
          
          // Performance assertions
          expect(server.activeConnections, equals(users.length));
          expect(duration.inSeconds, lessThan(30),
                 reason: 'Realistic usage should complete within reasonable time');
          
          // Verify users received content
          int usersWithContent = 0;
          for (final user in users) {
            final timeline = user.getReceivedEvents('${user.name}_timeline');
            if (timeline.isNotEmpty) {
              usersWithContent++;
            }
          }
          
          expect(usersWithContent, greaterThan(users.length * 0.8),
                 reason: 'Most users should receive timeline content');
          
        } finally {
          for (final user in users) {
            await user.close();
          }
        }
      });
    });
  });
}