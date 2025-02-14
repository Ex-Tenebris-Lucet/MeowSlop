import 'package:supabase_flutter/supabase_flutter.dart';
import 'video_service.dart';
import 's3_service.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final VideoService _videoService = VideoService();
  final S3Service _s3Service = S3Service();

  Future<bool> isLoggedIn() async {
    return _supabase.auth.currentSession != null;
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    // Sign up the user
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user != null) {
      // Create profile record
      await _supabase.from('profiles').insert({
        'id': response.user!.id,
        'username': username,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final response = await _supabase
      .from('profiles')
      .select()
      .eq('id', user.id)
      .single();
    
    return response;
  }

  Future<void> updateProfile({
    String? username,
    String? tagline,
    String? profilePicUrl,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final updates = {
      if (username != null) 'username': username,
      if (tagline != null) 'tagline': tagline,
      if (profilePicUrl != null) 'profile_pic_url': profilePicUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _supabase
      .from('profiles')
      .update(updates)
      .eq('id', user.id);
  }

  Future<String> uploadProfilePicture(Uint8List imageBytes) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Upload to S3
    final imageUrl = await _s3Service.uploadBytes(
      bytes: imageBytes,
      fileName: '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      prefix: S3Service.profilePath,
      contentType: 'image/jpeg',
    );

    // Update the profile with the new image URL
    await updateProfile(profilePicUrl: imageUrl);

    return imageUrl;
  }

  Future<void> deleteProfilePicture(String imageUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    try {
      // Delete from S3
      await _s3Service.deleteFile(imageUrl);

      // Update profile to remove the image URL
      await updateProfile(profilePicUrl: null);
    } catch (e) {
      print('Error deleting profile picture: $e');
      // If we can't delete the file, at least remove it from the profile
      await updateProfile(profilePicUrl: null);
    }
  }

  Future<List<Map<String, dynamic>>> getUserPosts({String? userId}) async {
    try {
      final targetUserId = userId ?? _supabase.auth.currentUser?.id;
      if (targetUserId == null) return [];

      print('Fetching posts for user: $targetUserId');  // Debug log

      final response = await _supabase
        .from('media_items')
        .select('*')  // Explicitly select all columns
        .eq('owner_id', targetUserId)
        .order('created_at', ascending: false);
      
      print('Posts response: $response');  // Debug log
      
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching posts: $e');  // Debug log
      return [];  // Return empty list on error instead of throwing
    }
  }

  Future<String> uploadPost(Uint8List mediaBytes, {String mediaType = 'image'}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Upload to S3
    final mediaUrl = await _s3Service.uploadBytes(
      bytes: mediaBytes,
      fileName: '${user.id}_${DateTime.now().millisecondsSinceEpoch}.${mediaType == 'image' ? 'jpg' : 'mp4'}',
      prefix: S3Service.mediaPath,
      contentType: mediaType == 'image' ? 'image/jpeg' : 'video/mp4',
    );

    // Create the post record
    await _supabase
      .from('media_items')
      .insert({
        'storage_path': mediaUrl,
        'media_type': mediaType,
        'owner_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      });

    return mediaUrl;
  }

  Future<String> uploadVideo(String videoPath) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    
    try {
      // Compress video and generate thumbnail
      final compressedVideo = await _videoService.compressVideo(videoPath);
      if (compressedVideo.isEmpty) {
        throw Exception('Failed to compress video');
      }

      // Upload video and thumbnail
      final uploadResult = await _videoService.uploadVideo(
        compressedVideo,
        null,  // Let VideoService generate the thumbnail
        onProgress: (progress) {
          // Handle progress if needed
        },
      );

      final videoUrl = uploadResult['video_url'];
      final thumbnailUrl = uploadResult['thumbnail_url'];
      
      if (videoUrl == null || thumbnailUrl == null) {
        throw Exception('Failed to get URLs from upload result');
      }

      // Create the post in the database
      await _supabase.from('media_items').insert({
        'owner_id': user.id,
        'storage_path': videoUrl,
        'thumbnail_url': thumbnailUrl,
        'media_type': 'video',
        'created_at': DateTime.now().toIso8601String(),
      });

      return videoUrl;
    } catch (e, stackTrace) {
      debugPrint('Error uploading video:');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> deletePost(String postId, String mediaUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    try {
      // Get post details and verify ownership
      final post = await _supabase
        .from('media_items')
        .select('*, owner_id')
        .eq('id', postId)
        .single();

      if (post == null) {
        throw Exception('Post not found');
      }

      // Verify ownership
      if (post['owner_id'] != user.id) {
        throw Exception('Not authorized to delete this post');
      }

      // Store file URLs before deletion
      final storageUrls = <String>[];
      storageUrls.add(mediaUrl);
      if (post['media_type'] == 'video' && post['thumbnail_url'] != null) {
        storageUrls.add(post['thumbnail_url']);
      }

      // Try to delete files first - if this fails, we haven't touched the DB
      try {
        if (post['media_type'] == 'video' && post['thumbnail_url'] != null) {
          await _videoService.deleteVideo(mediaUrl, post['thumbnail_url']);
        } else {
          await _s3Service.deleteFile(mediaUrl);
        }
      } catch (e) {
        debugPrint('Warning: Failed to delete files: $e');
        // Continue with DB deletion even if file deletion fails
        // This prevents posts from being "stuck" if S3 is having issues
      }

      // Now delete from database
      final response = await _supabase
        .from('media_items')
        .delete()
        .match({
          'id': postId,
          'owner_id': user.id  // Extra safety check
        });

      if (response.error != null) {
        throw response.error!.message;
      }

    } catch (e) {
      debugPrint('Error in deletePost: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRandomPosts({int limit = 10, bool useTagPreferences = false}) async {
    try {
      if (!useTagPreferences) {
        // Original random feed logic
        final response = await _supabase
          .from('media_items')
          .select('*, profiles(*)')
          .order('created_at', ascending: false)
          .limit(limit);

        final posts = response is List ? response : 
                     response?.data is List ? response.data : [];
        return List<Map<String, dynamic>>.from(posts);
      }

      // Get current user's tag preferences
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        // Fall back to random if not logged in
        return getRandomPosts(limit: limit, useTagPreferences: false);
      }

      // Get posts with tag affinity scores
      // Add some randomness while still respecting preferences
      final response = await _supabase.rpc(
        'get_personalized_feed',
        params: {
          'current_user_id': userId,
          'posts_limit': limit
        }
      );

      final posts = response is List ? response : 
                   response?.data is List ? response.data : [];

      if (posts.isEmpty) {
        // Fall back to random if no matches
        return getRandomPosts(limit: limit, useTagPreferences: false);
      }

      return List<Map<String, dynamic>>.from(posts);
    } catch (e) {
      print('Error getting posts: $e');
      // Fall back to random on error
      return getRandomPosts(limit: limit, useTagPreferences: false);
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final response = await _supabase
      .from('profiles')
      .select('''
        *,
        follower_count,
        following_count
      ''')
      .eq('id', userId)
      .single();
    
    return response;
  }

  Future<bool> isFollowing(String targetUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final response = await _supabase
      .from('followers')
      .select()
      .eq('follower_id', user.id)
      .eq('following_id', targetUserId)
      .maybeSingle();

    return response != null;
  }

  Future<void> followUser(String targetUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    if (user.id == targetUserId) throw Exception('Cannot follow yourself');

    await _supabase
      .from('followers')
      .insert({
        'follower_id': user.id,
        'following_id': targetUserId,
        'created_at': DateTime.now().toIso8601String(),
      });
  }

  Future<void> unfollowUser(String targetUserId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    await _supabase
      .from('followers')
      .delete()
      .eq('follower_id', user.id)
      .eq('following_id', targetUserId);
  }

  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final response = await _supabase
      .from('followers')
      .select('''
        follower:profiles!follower_id (
          id,
          username,
          profile_pic_url
        )
      ''')
      .eq('following_id', userId)
      .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    final response = await _supabase
      .from('followers')
      .select('''
        following:profiles!following_id (
          id,
          username,
          profile_pic_url
        )
      ''')
      .eq('follower_id', userId)
      .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getFullFeedList({bool useTagPreferences = false}) async {
    try {
      // Get all posts with their tags and profiles in a single query
      final response = await _supabase
        .from('media_items')
        .select('''
          *,
          profiles(*),
          media_item_tags(
            tags(name)
          )
        ''')
        .order('created_at', ascending: false);

      if (response == null) return [];
      
      var posts = List<Map<String, dynamic>>.from(response);
      
      if (useTagPreferences) {
        // Get user's tag preferences
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          final tagPrefs = await _supabase
            .from('tag_affinities')
            .select('tag_id, affinity_score')
            .eq('user_id', userId);

          if (tagPrefs != null) {
            // Create a map of tag scores for quick lookup
            final tagScores = Map.fromEntries(
              (tagPrefs as List).map((t) => MapEntry(t['tag_id'], t['affinity_score'] as int))
            );

            // Sort posts based on matching tags and their scores
            posts.sort((a, b) {
              int scoreA = 0, scoreB = 0;
              
              // Sum up scores for each post's tags
              for (var tagItem in (a['media_item_tags'] as List)) {
                final tagId = tagItem['tag_id'];
                if (tagScores.containsKey(tagId)) {
                  scoreA += tagScores[tagId]!;
                }
              }
              
              for (var tagItem in (b['media_item_tags'] as List)) {
                final tagId = tagItem['tag_id'];
                if (tagScores.containsKey(tagId)) {
                  scoreB += tagScores[tagId]!;
                }
              }
              
              return scoreB.compareTo(scoreA);  // Higher scores first
            });
          }
        }
      } else {
        // For random feed, just shuffle the posts
        posts.shuffle();
      }

      return posts;
    } catch (e) {
      print('Error getting feed list: $e');
      return [];
    }
  }
} 