import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 's3_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'package:video_player/video_player.dart';

class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();
  
  final _s3Service = S3Service();
  final _supabase = Supabase.instance.client;
  bool _isCancelled = false;
  double _uploadProgress = 0.0;
  
  double get uploadProgress => _uploadProgress;
  
  void cancelUpload() {
    _isCancelled = true;
    _s3Service.cancelUpload();
  }

  void _resetCancellation() {
    _isCancelled = false;
  }

  Future<String> compressVideo(String videoPath) async {
    _resetCancellation();
    try {
      final result = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (result == null || result.path == null) {
        throw Exception('Video compression failed');
      }

      return result.path!;
    } catch (e) {
      debugPrint('Error compressing video: $e');
      throw Exception('Failed to compress video: $e');
    }
  }

  Future<String> generateThumbnail(String videoPath) async {
    try {
      final thumbnail = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 50,
        position: -1,  // -1 means center of video
      );
      return thumbnail.path;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      throw Exception('Failed to generate thumbnail: $e');
    }
  }

  Future<Map<String, String>> uploadVideo(String videoPath, String? thumbnailPath, {Function(double)? onProgress}) async {
    _resetCancellation();
    if (_isCancelled) throw Exception('Upload cancelled');
    _uploadProgress = 0.0;

    String videoUrl = '';
    String thumbnailUrl = '';
    
    try {
      // Generate thumbnail if not provided
      final actualThumbnailPath = thumbnailPath ?? await generateThumbnail(videoPath);
      
      // Start with video upload (70% of progress)
      videoUrl = await _s3Service.uploadFile(
        filePath: videoPath,
        prefix: S3Service.videoPath,
        contentType: 'video/mp4',
        onProgress: (progress) {
          _uploadProgress = progress * 0.7;
          onProgress?.call(_uploadProgress);
        },
      );

      if (_isCancelled) throw Exception('Upload cancelled');

      // Then upload thumbnail (30% of progress)
      thumbnailUrl = await _s3Service.uploadFile(
        filePath: actualThumbnailPath,
        prefix: S3Service.thumbnailPath,
        contentType: 'image/jpeg',
        onProgress: (progress) {
          _uploadProgress = 0.7 + (progress * 0.3);
          onProgress?.call(_uploadProgress);
        },
      );

      return {
        'video_url': videoUrl,
        'thumbnail_url': thumbnailUrl,
      };
    } catch (e) {
      // Clean up any uploaded files if we fail
      if (videoUrl.isNotEmpty) {
        try {
          await _s3Service.deleteFile(videoUrl);
        } catch (e) {
          debugPrint('Error cleaning up video: $e');
        }
      }
      rethrow;
    }
  }

  Future<void> deleteVideo(String videoUrl, String thumbnailUrl) async {
    try {
      await Future.wait([
        _s3Service.deleteFile(videoUrl),
        _s3Service.deleteFile(thumbnailUrl),
      ]);
    } catch (e) {
      debugPrint('Error deleting video: $e');
      rethrow;
    }
  }

  Future<void> cleanup() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (e) {
      debugPrint('Error cleaning up video cache: $e');
    }
  }

  Future<void> triggerVideoAnalysis(String mediaId) async {
    try {
      final response = await _supabase.functions.invoke(
        'video-analysis',
        body: {'mediaId': mediaId},
      );
      
      if (response.status != 200) {
        debugPrint('Video analysis failed: ${response.data}');
      }
    } catch (e) {
      debugPrint('Error triggering video analysis: $e');
      // Don't throw - we don't want to break the upload if analysis fails
    }
  }
}

class VideoPreloadManager {
  static final VideoPreloadManager _instance = VideoPreloadManager._internal();
  factory VideoPreloadManager() => _instance;
  VideoPreloadManager._internal();

  final Map<String, VideoPlayerController> _preloadedControllers = {};
  static const int _preloadAheadCount = 2;
  static const int _maxCachedVideos = 7;

  // Track current preload state
  String? _currentlyPreloading;
  final _preloadQueue = <String>[];

  bool isPreloadedController(String url) => _preloadedControllers.containsKey(url);

  void updateCurrentIndex(int index, List<Map<String, dynamic>> posts) {
    _cleanOldCache(index, posts);
    
    // Clear existing queue and build new one in priority order
    _preloadQueue.clear();
    for (var i = index + 1; i < posts.length && i <= index + _preloadAheadCount; i++) {
      final post = posts[i];
      if (post['media_type'] == 'video' && post['storage_path'] != null) {
        final url = post['storage_path'];
        // Only queue if not already loaded or currently loading
        if (!_preloadedControllers.containsKey(url) && url != _currentlyPreloading) {
          _preloadQueue.add(url);
        }
      }
    }
    
    // Start processing queue if not already doing so
    _processPreloadQueue();
  }

  void _cleanOldCache(int currentIndex, List<Map<String, dynamic>> posts) {
    // Get list of URLs that we want to keep
    final urlsToKeep = <String>{};
    
    // Keep current and next few videos
    for (var i = currentIndex; i < posts.length && i <= currentIndex + _preloadAheadCount; i++) {
      final post = posts[i];
      if (post['media_type'] == 'video' && post['storage_path'] != null) {
        urlsToKeep.add(post['storage_path']);
      }
    }

    // Clean up old controllers
    _preloadedControllers.removeWhere((url, controller) {
      if (!urlsToKeep.contains(url)) {
        controller.dispose();
        return true;
      }
      return false;
    });
  }

  Future<void> _processPreloadQueue() async {
    // If already loading or queue empty, do nothing
    if (_currentlyPreloading != null || _preloadQueue.isEmpty) return;
    
    try {
      // Take next URL to preload
      _currentlyPreloading = _preloadQueue.removeAt(0);
      debugPrint('Starting preload of video: ${_currentlyPreloading}');
      
      await preloadVideo(_currentlyPreloading!);
      
      // Clear current and process next
      _currentlyPreloading = null;
      _processPreloadQueue();
    } catch (e) {
      debugPrint('Error in preload queue processing: $e');
      _currentlyPreloading = null;
      _processPreloadQueue();  // Continue with next even if one fails
    }
  }

  Future<void> preloadVideo(String url) async {
    // Skip if already preloaded
    if (_preloadedControllers.containsKey(url)) return;

    // Clean old videos if we're at limit
    while (_preloadedControllers.length >= _maxCachedVideos) {
      final oldestUrl = _preloadedControllers.keys.first;
      final controller = _preloadedControllers.remove(oldestUrl);
      await controller?.dispose();
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await controller.initialize();
      _preloadedControllers[url] = controller;
      debugPrint('Successfully preloaded video: $url');
    } catch (e) {
      debugPrint('Error preloading video: $e');
      rethrow;  // Rethrow so _processPreloadQueue can handle it
    }
  }

  VideoPlayerController? getPreloadedController(String url) {
    return _preloadedControllers[url];
  }

  void dispose() {
    _preloadQueue.clear();
    _currentlyPreloading = null;
    for (var controller in _preloadedControllers.values) {
      controller.dispose();
    }
    _preloadedControllers.clear();
  }
}

class FeedPreloader {
  static final FeedPreloader _instance = FeedPreloader._internal();
  factory FeedPreloader() => _instance;
  FeedPreloader._internal();

  final _authService = AuthService();
  Future<List<Map<String, dynamic>>>? _firstPostFuture;
  Future<List<Map<String, dynamic>>>? _remainingPostsFuture;

  void startPreloading() {
    _firstPostFuture = _authService.getRandomPosts(limit: 1);
    _remainingPostsFuture = _authService.getRandomPosts(limit: 9);
  }

  Future<List<Map<String, dynamic>>> getFirstPost() => 
    _firstPostFuture ?? _authService.getRandomPosts(limit: 1);
    
  Future<List<Map<String, dynamic>>> getRemainingPosts() => 
    _remainingPostsFuture ?? _authService.getRandomPosts(limit: 9);
} 