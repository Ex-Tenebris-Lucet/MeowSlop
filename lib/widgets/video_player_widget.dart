import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/video_service.dart';
import 'dart:io';
import 'package:visibility_detector/visibility_detector.dart';

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

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;
  bool _isDisposed = false;
  String? _lastError;
  bool _showDebugInfo = false;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pauseVideo();
    } else if (state == AppLifecycleState.resumed && widget.autoPlay && !widget.showOverlay && _isVisible) {
      _playVideo();
    }
  }

  void _pauseVideo() {
    if (_controller?.value.isPlaying ?? false) {
      _controller?.pause();
    }
  }

  void _playVideo() {
    if (!(_controller?.value.isPlaying ?? true) && _isInitialized && !_hasError && !_isDisposed) {
      _controller?.play();
    }
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.url != widget.url) {
      _disposeController();
      _retryCount = 0;
      _initializePlayer();
    }
    
    if (widget.showOverlay != oldWidget.showOverlay) {
      if (widget.showOverlay) {
        _pauseVideo();
      } else if (widget.autoPlay && _isInitialized && !_hasError && _isVisible) {
        _playVideo();
      }
    }
  }

  Future<void> _disposeController() async {
    if (_isDisposed) return;
    
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    
    try {
      if (controller != null) {
        if (controller.value.isPlaying) {
          await controller.pause();
        }
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('Error disposing controller: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;
    
    await _disposeController();
    
    try {
      var cachedPath = await VideoPreloadManager().getCachedVideoPath(widget.url);
      
      if (cachedPath != null) {
        _controller = VideoPlayerController.file(
          File(cachedPath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        // Start preloading for next time
        VideoPreloadManager().preloadVideo(widget.url);
      }

      await _controller!.initialize();
      _controller!.setLooping(widget.looping);
      
      if (widget.autoPlay && !widget.showOverlay && _isVisible) {
        _controller!.play();
      } else {
        _controller!.pause();
      }

      if (!mounted || _isDisposed) {
        await _controller?.pause();
        await _controller?.dispose();
        return;
      }

      setState(() {
        _isInitialized = true;
        _hasError = false;
        _retryCount = 0;
        _lastError = null;
      });
    } catch (e) {
      debugPrint('Error initializing video player: $e');
      if (mounted && !_isDisposed) {
        _lastError = e.toString();
        if (_retryCount < _maxRetries) {
          _retryCount++;
          debugPrint('Retrying video initialization (attempt $_retryCount)');
          await Future.delayed(Duration(milliseconds: 500 * _retryCount));
          _initializePlayer();
        } else {
          setState(() {
            _hasError = true;
            _isInitialized = false;
          });
        }
      }
    }
  }

  String _getDebugInfo() {
    if (_controller == null) return '';
    final videoSize = _controller!.value.size;
    final viewSize = MediaQuery.of(context).size;
    final aspectRatio = videoSize.width / videoSize.height;
    return '''
    Video: ${videoSize.width.toInt()}x${videoSize.height.toInt()}
    Screen: ${viewSize.width.toInt()}x${viewSize.height.toInt()}
    Ratio: ${aspectRatio.toStringAsFixed(2)}
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video-${widget.url}'),
      onVisibilityChanged: (info) {
        final isVisible = info.visibleFraction > 0.1;
        if (isVisible != _isVisible) {
          setState(() {
            _isVisible = isVisible;
          });
          if (!isVisible) {
            _pauseVideo();
          } else if (widget.autoPlay && !widget.showOverlay) {
            _playVideo();
          }
        }
      },
      child: _buildVideoPlayer(),
    );
  }

  Widget _buildVideoPlayer() {
    if (_hasError) {
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
              'Error playing video${_lastError != null ? '\n$_lastError' : ''}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: () => setState(() => _showDebugInfo = !_showDebugInfo),
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          if (_showDebugInfo)
            Positioned(
              top: 40,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getDebugInfo(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void deactivate() {
    // This is called when the widget is removed from the widget tree
    _pauseVideo();
    super.deactivate();
  }
} 