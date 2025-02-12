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
      // Get post details to check if it's a video
      final post = await _supabase
        .from('media_items')
        .select()
        .eq('id', postId)
        .single();

      // Delete the post record first
      await _supabase
        .from('media_items')
        .delete()
        .match({'id': postId});

      // Then delete the files from S3
      if (post['media_type'] == 'video' && post['thumbnail_url'] != null) {
        // If it's a video, use VideoService to delete both video and thumbnail
        await _videoService.deleteVideo(mediaUrl, post['thumbnail_url']);
      } else {
        // For images, just delete the media file
        await _s3Service.deleteFile(mediaUrl);
      }
    } catch (e) {
      debugPrint('Error deleting post: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRandomPosts({int limit = 10}) async {
    try {
      // Get ALL posts with their profile info
      final response = await _supabase
        .from('media_items')
        .select('''
          *,
          profiles:owner_id (
            id,
            username,
            profile_pic_url
          )
        ''')
        .order('created_at', ascending: false);  // Keep chronological order as fallback
      
      if (response == null) return [];
      
      // Shuffle all posts
      final allPosts = List<Map<String, dynamic>>.from(response);
      allPosts.shuffle();
      
      // Return only the requested number
      return allPosts.take(limit).toList();
    } catch (e) {
      debugPrint('Error getting random posts: $e');
      return [];
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
} 