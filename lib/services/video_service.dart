import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class VideoService {
  static const int _targetSizeMB = 10; // Target size in MB
  static const double _minCompressionRatio = 0.5; // Minimum compression ratio
  static const String _videoBucket = 'post_media';
  static const String _thumbnailBucket = 'post_thumbnails';
  
  final _supabase = Supabase.instance.client;

  Future<CompressedVideoInfo?> compressVideo(String videoPath) async {
    try {
      final inputFile = File(videoPath);
      final inputSize = await inputFile.length();
      final inputSizeMB = inputSize / (1024 * 1024);

      // Generate thumbnail first
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 50,
        position: -1, // -1 means center of video
      );

      // If video is already small enough, return original
      if (inputSizeMB <= _targetSizeMB) {
        return CompressedVideoInfo(
          path: videoPath,
          thumbnailPath: thumbnailFile.path,
        );
      }

      // Start compression with medium quality
      final MediaInfo? result = await VideoCompress.compressVideo(
        videoPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false, // Keep original file
        includeAudio: true,
      );

      if (result == null || result.file == null) {
        throw Exception('Compression failed: No output file');
      }

      final outputSize = await result.file!.length();
      final compressionRatio = outputSize / inputSize;

      // If compression isn't effective enough, try again with lower quality
      if (compressionRatio > _minCompressionRatio && outputSize > _targetSizeMB * 1024 * 1024) {
        await VideoCompress.cancelCompression();
        final MediaInfo? secondAttempt = await VideoCompress.compressVideo(
          videoPath,
          quality: VideoQuality.LowQuality,
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 24,
        );

        if (secondAttempt == null || secondAttempt.file == null) {
          throw Exception('Second compression attempt failed');
        }

        return CompressedVideoInfo(
          path: secondAttempt.file!.path,
          thumbnailPath: thumbnailFile.path,
        );
      }

      return CompressedVideoInfo(
        path: result.file!.path,
        thumbnailPath: thumbnailFile.path,
      );
    } catch (e) {
      print('Error compressing video: $e');
      await VideoCompress.cancelCompression();
      return null;
    }
  }

  Future<VideoUploadResult?> uploadVideo(CompressedVideoInfo videoInfo, String userId) async {
    try {
      final videoFileName = '${userId}/${DateTime.now().millisecondsSinceEpoch}_video.mp4';
      final thumbnailFileName = '${userId}/${DateTime.now().millisecondsSinceEpoch}_thumb.jpg';

      // Upload video
      await _supabase.storage.from(_videoBucket).uploadBinary(
        videoFileName,
        File(videoInfo.path).readAsBytesSync(),
        fileOptions: const FileOptions(
          contentType: 'video/mp4',
          upsert: true,
        ),
      );

      // Upload thumbnail
      await _supabase.storage.from(_thumbnailBucket).uploadBinary(
        thumbnailFileName,
        File(videoInfo.thumbnailPath).readAsBytesSync(),
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      // Get public URLs
      final videoUrl = _supabase.storage.from(_videoBucket).getPublicUrl(videoFileName);
      final thumbnailUrl = _supabase.storage.from(_thumbnailBucket).getPublicUrl(thumbnailFileName);

      return VideoUploadResult(
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
      );
    } catch (e) {
      print('Error uploading video: $e');
      return null;
    }
  }

  Future<void> deleteVideo(String videoUrl, String thumbnailUrl) async {
    try {
      // Extract paths from URLs
      final videoPath = _getPathFromUrl(videoUrl, _videoBucket);
      final thumbnailPath = _getPathFromUrl(thumbnailUrl, _thumbnailBucket);

      // Delete both files
      await Future.wait([
        _supabase.storage.from(_videoBucket).remove([videoPath]),
        _supabase.storage.from(_thumbnailBucket).remove([thumbnailPath]),
      ]);
    } catch (e) {
      print('Error deleting video: $e');
      rethrow;
    }
  }

  String _getPathFromUrl(String url, String bucket) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    return pathSegments.sublist(pathSegments.indexOf(bucket) + 1).join('/');
  }

  Future<void> cleanup() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (e) {
      print('Error cleaning up video cache: $e');
    }
  }
}

class CompressedVideoInfo {
  final String path;
  final String thumbnailPath;

  CompressedVideoInfo({
    required this.path,
    required this.thumbnailPath,
  });
}

class VideoUploadResult {
  final String videoUrl;
  final String thumbnailUrl;

  VideoUploadResult({
    required this.videoUrl,
    required this.thumbnailUrl,
  });
}

class VideoPreloadManager {
  static final VideoPreloadManager _instance = VideoPreloadManager._internal();
  factory VideoPreloadManager() => _instance;
  VideoPreloadManager._internal();

  final Map<String, _PreloadedVideo> _preloadedVideos = {};
  final Set<String> _currentlyPreloading = {};
  int _currentIndex = 0;
  static const int _preloadAhead = 2;
  static const int _maxCachedVideos = 3;

  Future<void> updateCurrentIndex(int index, List<Map<String, dynamic>> posts) async {
    if (_currentIndex == index) return;
    _currentIndex = index;

    try {
      final neededUrls = <String>{};
      if (index >= 0 && index < posts.length && posts[index]['media_type'] == 'video') {
        final videoUrl = posts[index]['storage_path'];
        if (videoUrl != null && videoUrl.isNotEmpty) {
          neededUrls.add(videoUrl);
        }
      }
      for (var i = index + 1; i < posts.length && i <= index + _preloadAhead; i++) {
        if (posts[i]['media_type'] == 'video') {
          final videoUrl = posts[i]['storage_path'];
          if (videoUrl != null && videoUrl.isNotEmpty) {
            neededUrls.add(videoUrl);
          }
        }
      }

      final urlsToRemove = _preloadedVideos.keys.where((url) => !neededUrls.contains(url)).toList();
      for (final url in urlsToRemove) {
        await _disposeVideo(url);
      }

      for (final url in neededUrls) {
        if (!_preloadedVideos.containsKey(url) && !_currentlyPreloading.contains(url)) {
          await _preloadVideo(url);
          break;
        }
      }
    } catch (e) {
      print('Error updating preloaded videos: $e');
    }
  }

  Future<void> _preloadVideo(String url) async {
    if (_currentlyPreloading.contains(url)) return;
    if (_preloadedVideos.length >= _maxCachedVideos) return;
    
    try {
      _currentlyPreloading.add(url);
      
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      
      _preloadedVideos[url] = _PreloadedVideo(
        controller: controller,
        timestamp: DateTime.now(),
        aspectRatio: controller.value.aspectRatio,  // Store the aspect ratio
      );
    } catch (e) {
      print('Error preloading video $url: $e');
    } finally {
      _currentlyPreloading.remove(url);
    }
  }

  Future<VideoPlayerController?> getController(String url) async {
    try {
      // First try to get a preloaded controller
      final video = _preloadedVideos[url];
      if (video != null) {
        try {
          // Check if the preloaded controller is still valid
          if (video.controller.value.isInitialized) {
            return video.controller;
          }
        } catch (e) {
          print('Error checking preloaded controller: $e');
          // Controller is invalid, remove it
          await _disposeVideo(url);
        }
      }

      // Create a new controller
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      // Initialize with retry logic
      bool initialized = false;
      int retryCount = 0;
      const maxRetries = 2;

      while (!initialized && retryCount < maxRetries) {
        try {
          await controller.initialize();
          initialized = true;
        } catch (e) {
          print('Error initializing controller (attempt ${retryCount + 1}): $e');
          retryCount++;
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      }

      if (!initialized) {
        await controller.dispose();
        return null;
      }

      await controller.setLooping(true);
      await controller.setVolume(1.0);
      
      return controller;
    } catch (e) {
      print('Error in getController: $e');
      return null;
    }
  }

  Future<void> _disposeVideo(String url) async {
    final video = _preloadedVideos.remove(url);
    if (video != null) {
      try {
        await video.controller.pause();
        await Future.delayed(const Duration(milliseconds: 50));
        await video.controller.dispose();
      } catch (e) {
        print('Error disposing video controller: $e');
      }
    }
  }

  Future<void> dispose() async {
    final urls = List<String>.from(_preloadedVideos.keys);
    for (final url in urls) {
      await _disposeVideo(url);
    }
    _preloadedVideos.clear();
    _currentlyPreloading.clear();
  }
}

class _PreloadedVideo {
  final VideoPlayerController controller;
  final DateTime timestamp;
  final double? aspectRatio;  // Store the aspect ratio

  _PreloadedVideo({
    required this.controller,
    required this.timestamp,
    this.aspectRatio,
  });
} 