import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      // Calculate target bitrate based on desired size
      final info = await VideoCompress.getMediaInfo(videoPath);
      
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