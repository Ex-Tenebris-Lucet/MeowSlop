import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 's3_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  final Map<String, String> _cachedVideoPaths = {};
  final Map<String, DateTime> _lastAccessTimes = {};
  final Map<String, int> _fileSizes = {};
  static const int _maxCacheSizeBytes = 50 * 1024 * 1024; // 50 MB
  int _currentCacheSize = 0;
  Timer? _cleanupTimer;
  bool _preloadingEnabled = false;
  bool _isDisposed = false;

  void setPaused(bool paused) {
    _preloadingEnabled = !paused;
  }

  void updateCurrentIndex(int index, List<Map<String, dynamic>> posts) {
    if (!_preloadingEnabled || _isDisposed) return;
    
    // Preload videos for the next few posts
    for (var i = index; i < posts.length && i < index + 5; i++) {
      final post = posts[i];
      if (post['media_type'] == 'video' && post['storage_path'] != null) {
        preloadVideo(post['storage_path']);
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _preloadingEnabled = false;
    _cleanupTimer?.cancel();
    _cleanupAllCache();
  }

  Future<int> _getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      debugPrint('Error getting file size: $e');
    }
    return 0;
  }

  Future<void> _cleanupAllCache() async {
    for (var filePath in _cachedVideoPaths.values) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error cleaning up cached file: $e');
      }
    }
    _cachedVideoPaths.clear();
    _lastAccessTimes.clear();
    _fileSizes.clear();
    _currentCacheSize = 0;
  }

  Future<String?> getCachedVideoPath(String url) async {
    if (!_cachedVideoPaths.containsKey(url)) return null;
    
    _lastAccessTimes[url] = DateTime.now();
    final path = _cachedVideoPaths[url];
    
    // Verify file still exists
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        return path;
      } else {
        // File was deleted externally, remove from cache
        _removeFromCache(url);
      }
    }
    return null;
  }

  void _removeFromCache(String url) {
    final size = _fileSizes.remove(url) ?? 0;
    _currentCacheSize -= size;
    _cachedVideoPaths.remove(url);
    _lastAccessTimes.remove(url);
  }

  Future<void> preloadVideo(String url) async {
    if (!_preloadingEnabled || _isDisposed) return;
    
    if (_cachedVideoPaths.containsKey(url)) {
      _lastAccessTimes[url] = DateTime.now();
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = url.split('/').last;
      final filePath = '${tempDir.path}/$fileName';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final fileSize = response.bodyBytes.length;
        
        // Clean up cache if needed before adding new file
        while (_currentCacheSize + fileSize > _maxCacheSizeBytes && _cachedVideoPaths.isNotEmpty) {
          await _removeOldestCache();
        }

        // Only proceed if we can fit the new file
        if (fileSize <= _maxCacheSizeBytes) {
          await File(filePath).writeAsBytes(response.bodyBytes);
          _cachedVideoPaths[url] = filePath;
          _lastAccessTimes[url] = DateTime.now();
          _fileSizes[url] = fileSize;
          _currentCacheSize += fileSize;
        }
      }

      _startCleanupTimer();
    } catch (e) {
      debugPrint('Error preloading video: $e');
    }
  }

  Future<void> _removeOldestCache() async {
    if (_cachedVideoPaths.isEmpty) return;

    final oldestUrl = _lastAccessTimes.entries
        .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
        .key;

    final filePath = _cachedVideoPaths[oldestUrl];
    if (filePath != null) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error removing cached file: $e');
      }
    }

    _removeFromCache(oldestUrl);
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _cleanupStaleCache();
    });
  }

  Future<void> _cleanupStaleCache() async {
    final now = DateTime.now();
    const staleThreshold = Duration(hours: 1);
    
    final staleUrls = _lastAccessTimes.entries
        .where((entry) => now.difference(entry.value) > staleThreshold)
        .map((entry) => entry.key)
        .toList();

    for (final url in staleUrls) {
      final filePath = _cachedVideoPaths[url];
      if (filePath != null) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error cleaning up stale cache: $e');
        }
      }
      _removeFromCache(url);
    }
  }
} 