import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/video_service.dart';
import 'package:visibility_detector/visibility_detector.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool showOverlay;
  final bool autoPlay;
  final bool looping;
  final VoidCallback? onTap;

  const VideoPlayerWidget({
    super.key,
    required this.url,
    this.showOverlay = false,
    this.autoPlay = true,
    this.looping = true,
    this.onTap,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      final preloadManager = VideoPreloadManager();
      final preloadedController = preloadManager.getPreloadedController(widget.url);
      
      if (preloadedController != null && preloadedController.value.isInitialized) {
        if (!mounted) return;
        setState(() {
          _controller = preloadedController;
          _controller!.setLooping(true);
        });
        return;
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
        ),
      );

      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _controller = controller;
        controller.setLooping(true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.white24, size: 48),
            const SizedBox(height: 8),
            Text(
              'Error playing video\n$_error',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
        ),
      );
    }

    // Handle overlay changes directly
    if (widget.showOverlay) {
      _controller?.pause();
    } else {
      _controller?.play();
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: VideoPlayer(_controller!),
      ),
    );
  }

  @override
  void dispose() {
    if (_controller != null && !VideoPreloadManager().isPreloadedController(widget.url)) {
      _controller?.dispose();
    }
    super.dispose();
  }
}