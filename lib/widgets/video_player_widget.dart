import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../services/video_service.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String url;
  final bool autoPlay;
  final bool looping;
  final bool showOverlay;
  final VoidCallback? onTap;

  const VideoPlayerWidget({
    super.key,
    required this.url,
    this.autoPlay = true,
    this.looping = true,
    this.showOverlay = false,
    this.onTap,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.url != widget.url) {
      _disposeControllers();
      _initializePlayer();
    }
    
    if (widget.showOverlay != oldWidget.showOverlay) {
      if (widget.showOverlay) {
        _videoPlayerController?.pause();
      } else if (widget.autoPlay && _isInitialized && !_hasError) {
        _videoPlayerController?.play();
      }
    }
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _chewieController = null;
    if (_videoPlayerController != null) {
      _videoPlayerController!.dispose();
    }
    _videoPlayerController = null;
    _isInitialized = false;
    _hasError = false;
  }

  Future<void> _initializePlayer() async {
    try {
      final controller = await VideoPreloadManager().getController(widget.url);
      if (controller != null && mounted) {
        setState(() {
          _videoPlayerController = controller;
          _initializeChewieController();
          _isInitialized = true;
          _hasError = false;
        });
      } else {
        throw Exception('Failed to initialize video controller');
      }
    } catch (e) {
      print('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitialized = false;
        });
      }
    }
  }

  void _initializeChewieController() {
    if (_videoPlayerController == null) return;
    
    _chewieController?.dispose();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: widget.autoPlay && !_hasError,
      looping: widget.looping,
      showControls: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      autoInitialize: false,
      allowMuting: false,
      allowPlaybackSpeedChanging: false,
      showOptions: false,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white24,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(
                'Error loading video: $errorMessage',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.white24,
                size: 48,
              ),
              SizedBox(height: 8),
              Text(
                'Error playing video',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Colors.black,
        child: _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }
} 