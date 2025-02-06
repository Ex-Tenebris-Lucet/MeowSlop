import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// Abstract interface for video players
abstract class VideoPlayerService {
  Widget buildPlayer(String videoId, {bool showControls = false});
  void dispose();
  void togglePlayback(String videoId);
  bool isPlaying(String videoId);
}

// Current implementation using youtube_player_flutter
class YoutubePlayerService implements VideoPlayerService {
  final Map<String, YoutubePlayerController> _controllers = {};
  
  @override
  Widget buildPlayer(String videoId, {bool showControls = false}) {
    // Create controller if it doesn't exist
    if (!_controllers.containsKey(videoId)) {
      _controllers[videoId] = YoutubePlayerController(
        initialVideoId: videoId,
        flags: YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          loop: true,
          enableCaption: false,
          hideControls: !showControls,
          forceHD: true,
          useHybridComposition: true,
          showLiveFullscreenButton: false,
          hideThumbnail: true,
        ),
      );
    } else {
      // Update controls visibility
      _controllers[videoId]!.updateValue(
        _controllers[videoId]!.value.copyWith(
          playerState: _controllers[videoId]!.value.playerState,
          isControlsVisible: showControls,
        ),
      );
    }
    
    return YoutubePlayer(
      controller: _controllers[videoId]!,
      showVideoProgressIndicator: showControls,
      progressIndicatorColor: Colors.white,
      progressColors: const ProgressBarColors(
        playedColor: Colors.white,
        handleColor: Colors.white,
        bufferedColor: Colors.white54,
        backgroundColor: Colors.black45,
      ),
      thumbnail: Container(), // Empty thumbnail to keep showing video frame
      bottomActions: showControls ? null : const [], // Show default controls when showControls is true
    );
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
  
  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
}

// Future implementation placeholder for custom video player
class CustomVideoPlayerService implements VideoPlayerService {
  @override
  Widget buildPlayer(String videoId, {bool showControls = false}) {
    // TODO: Implement custom video player
    throw UnimplementedError();
  }
  
  @override
  void togglePlayback(String videoId) {
    // TODO: Implement playback control
    throw UnimplementedError();
  }
  
  @override
  bool isPlaying(String videoId) {
    // TODO: Implement playback state
    throw UnimplementedError();
  }
  
  @override
  void dispose() {
    // TODO: Implement cleanup
  }
} 