import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'video_player_service.dart';

class CustomVideoPlayerService implements VideoPlayerService {
  final _yt = YoutubeExplode();
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, String> _videoUrls = {};  // Cache stream URLs

  @override
  Widget buildPlayer(String videoId, {bool showControls = false}) {
    return FutureBuilder<VideoPlayerController>(
      future: _getController(videoId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Error in player build: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Failed to load video',
                  style: TextStyle(color: Colors.red),
                ),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    // Clear cached data and retry
                    _videoUrls.remove(videoId);
                    _controllers.remove(videoId);
                    // Force rebuild
                    (context as Element).markNeedsBuild();
                  },
                  child: Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading video...'),
              ],
            ),
          );
        }

        final controller = snapshot.data!;
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              // Add a gesture detector for tap-to-play/pause
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => togglePlayback(videoId),
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              // Show loading indicator while buffering
              if (controller.value.isBuffering)
                Container(
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              // Show video progress indicator when controls are enabled
              if (showControls)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.black45,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<String> _fetchVideoUrlWithRetry(String videoId, {int maxAttempts = 3}) async {
    int attempts = 0;
    while (attempts < maxAttempts) {
      try {
        attempts++;
        print('Attempt $attempts to fetch video stream');
        
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final streamInfo = manifest.muxed.withHighestBitrate();
        
        print('Stream fetch successful on attempt $attempts');
        return streamInfo.url.toString();
      } catch (e) {
        print('Attempt $attempts failed: $e');
        if (attempts == maxAttempts) {
          print('All retry attempts exhausted');
          rethrow;
        }
        // Wait before retrying, with exponential backoff
        await Future.delayed(Duration(seconds: attempts * 2));
      }
    }
    throw Exception('Failed to fetch video URL after $maxAttempts attempts');
  }

  Future<VideoPlayerController> _getController(String videoId) async {
    if (_controllers.containsKey(videoId)) {
      return _controllers[videoId]!;
    }

    // Get stream URL if we don't have it cached
    if (!_videoUrls.containsKey(videoId)) {
      try {
        _videoUrls[videoId] = await _fetchVideoUrlWithRetry(videoId);
      } catch (e, stackTrace) {
        print('Error getting video stream: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      }
    }

    try {
      print('Initializing video controller');
      // Create and initialize controller
      final controller = VideoPlayerController.network(
        _videoUrls[videoId]!,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Referer': 'https://youtube.com',
          'Origin': 'https://youtube.com',
          'Sec-Fetch-Dest': 'video',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'cross-site',
        },
      );

      print('Waiting for controller initialization');
      await controller.initialize();
      print('Controller initialized successfully');
      
      controller.setLooping(true);
      controller.play();

      _controllers[videoId] = controller;
      return controller;
    } catch (e, stackTrace) {
      print('Error initializing video controller: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  void togglePlayback(String videoId) {
    final controller = _controllers[videoId];
    if (controller != null) {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    }
  }

  @override
  bool isPlaying(String videoId) {
    return _controllers[videoId]?.value.isPlaying ?? false;
  }

  void _releaseController(String videoId) {
    _controllers[videoId]?.dispose();
    _controllers.remove(videoId);
    _videoUrls.remove(videoId);
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _videoUrls.clear();
    _yt.close();
  }
} 