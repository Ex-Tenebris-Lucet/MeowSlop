import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'video_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _profilePicsBucket = 'profile_pictures';
  static const String _postMediaBucket = 'post_media';

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

    // Generate a unique file path for the image
    final filePath = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    // Upload the image
    await _supabase
      .storage
      .from(_profilePicsBucket)
      .uploadBinary(
        filePath,
        imageBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

    // Get the public URL
    final imageUrl = _supabase
      .storage
      .from(_profilePicsBucket)
      .getPublicUrl(filePath);

    // Update the profile with the new image URL
    await updateProfile(profilePicUrl: imageUrl);

    return imageUrl;
  }

  Future<void> deleteProfilePicture(String imageUrl) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    try {
      // Extract the file path from the URL
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final filePath = pathSegments.sublist(pathSegments.indexOf(_profilePicsBucket) + 1).join('/');

      // Delete the file
      await _supabase
        .storage
        .from(_profilePicsBucket)
        .remove([filePath]);

      // Update profile to remove the image URL
      await updateProfile(profilePicUrl: null);
    } catch (e) {
      print('Error deleting profile picture: $e');
      // If we can't delete the file, at least remove it from the profile
      await updateProfile(profilePicUrl: null);
    }
  }

  Future<List<Map<String, dynamic>>> getUserPosts() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      print('Fetching posts for user: ${user.id}');  // Debug log

      final response = await _supabase
        .from('media_items')
        .select('*')  // Explicitly select all columns
        .eq('owner_id', user.id)
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

    // Generate a unique file path
    final filePath = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.${mediaType == 'image' ? 'jpg' : 'mp4'}';

    // Upload the media
    await _supabase
      .storage
      .from(_postMediaBucket)
      .uploadBinary(
        filePath,
        mediaBytes,
        fileOptions: FileOptions(
          contentType: mediaType == 'image' ? 'image/jpeg' : 'video/mp4',
          upsert: true,
        ),
      );

    // Get the public URL
    final mediaUrl = _supabase
      .storage
      .from(_postMediaBucket)
      .getPublicUrl(filePath);

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

    final videoService = VideoService();
    
    // Compress video and generate thumbnail
    final compressedVideo = await videoService.compressVideo(videoPath);
    if (compressedVideo == null) {
      throw Exception('Failed to compress video');
    }

    // Upload video and thumbnail
    final uploadResult = await videoService.uploadVideo(compressedVideo, user.id);
    if (uploadResult == null) {
      throw Exception('Failed to upload video');
    }

    // Create the post record
    await _supabase
      .from('media_items')
      .insert({
        'storage_path': uploadResult.videoUrl,
        'thumbnail_url': uploadResult.thumbnailUrl,
        'media_type': 'video',
        'owner_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      });

    return uploadResult.videoUrl;
  }

  @override
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

      if (post['media_type'] == 'video' && post['thumbnail_url'] != null) {
        // If it's a video, use VideoService to delete both video and thumbnail
        final videoService = VideoService();
        await videoService.deleteVideo(mediaUrl, post['thumbnail_url']);
      } else {
        // For images, just delete the media file
        final uri = Uri.parse(mediaUrl);
        final pathSegments = uri.pathSegments;
        final filePath = pathSegments.sublist(pathSegments.indexOf(_postMediaBucket) + 1).join('/');

        await _supabase
          .storage
          .from(_postMediaBucket)
          .remove([filePath]);
      }

      // Delete the post record
      await _supabase
        .from('media_items')
        .delete()
        .match({'id': postId});
    } catch (e) {
      print('Error deleting post: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRandomPosts({int limit = 10}) async {
    try {
      // First, get all post IDs
      final idResponse = await _supabase
        .from('media_items')
        .select('id')
        .limit(500); // Limit the pool size for performance
      
      if (idResponse == null || idResponse.isEmpty) {
        return [];
      }

      // Convert to list and shuffle
      final postIds = List<String>.from(idResponse.map((row) => row['id']));
      postIds.shuffle();

      // Take only the number of IDs we need
      final selectedIds = postIds.take(limit).toList();

      // Now fetch the full post data for just these IDs
      final response = await _supabase
        .from('media_items')
        .select('''
          *,
          profiles:owner_id (
            username,
            profile_pic_url
          )
        ''')
        .in_('id', selectedIds);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching random posts: $e');
      return [];
    }
  }
} 