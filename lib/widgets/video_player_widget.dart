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

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;
  bool _isDisposed = false;
  bool _showDebugInfo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _videoPlayerController?.pause();
    }
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.url != widget.url) {
      _disposeControllers();
      _retryCount = 0;
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
    if (_isDisposed) return;
    
    _chewieController?.dispose();
    _chewieController = null;
    if (_videoPlayerController != null) {
      _videoPlayerController!.pause().then((_) {
        if (mounted && !_isDisposed) {
          _videoPlayerController!.dispose();
          _videoPlayerController = null;
          _isInitialized = false;
          _hasError = false;
        }
      });
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposed) return;
    
    try {
      // Try to get a preloaded controller first
      var controller = await VideoPreloadManager().getController(widget.url);
      
      // If no preloaded controller, create a new one
      if (controller == null) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
        
        // Add listener for network errors
        controller.addListener(() {
          if (!mounted || _isDisposed) return;
          
          final playerValue = controller?.value;
          if (playerValue != null && playerValue.hasError && !_hasError) {
            setState(() {
              _hasError = true;
              if (_retryCount < _maxRetries) {
                _retryCount++;
                Future.delayed(Duration(milliseconds: 500 * _retryCount), () {
                  if (mounted && !_isDisposed) {
                    _initializePlayer();
                  }
                });
              }
            });
          }
        });
        
        await controller.initialize();
        await controller.setLooping(true);
      }

      if (!mounted || _isDisposed) {
        controller.dispose();
        return;
      }

      setState(() {
        _videoPlayerController = controller;
        _initializeChewieController();
        _isInitialized = true;
        _hasError = false;
        _retryCount = 0;
      });
    } catch (e) {
      print('Error initializing video player: $e');
      if (mounted && !_isDisposed) {
        if (_retryCount < _maxRetries) {
          _retryCount++;
          print('Retrying video initialization (attempt $_retryCount)');
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

  void _initializeChewieController() {
    if (_videoPlayerController == null) return;
    
    _chewieController?.dispose();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: widget.autoPlay && !_hasError,
      looping: widget.looping,
      showControls: false,
      autoInitialize: false,
      allowMuting: false,
      allowPlaybackSpeedChanging: false,
      showOptions: false,
      errorBuilder: (context, errorMessage) {
        // Attempt to recover from Chewie errors
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _retryCount < _maxRetries) {
            _retryCount++;
            _initializePlayer();
          }
        });
        
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

  void _toggleDebugInfo() {
    setState(() {
      _showDebugInfo = !_showDebugInfo;
    });
  }

  String _getDebugInfo() {
    if (_videoPlayerController == null) return 'No controller';
    final value = _videoPlayerController!.value;
    return '''
    Size: ${value.size.width.toInt()}x${value.size.height.toInt()}
    Aspect Ratio: ${value.aspectRatio.toStringAsFixed(2)}
    Position: ${value.position.inSeconds}s
    Duration: ${value.duration.inSeconds}s
    Playing: ${value.isPlaying}
    Buffered: ${value.buffered.length}
    URL: ${widget.url}
    ''';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
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
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: _chewieController != null
          ? Chewie(controller: _chewieController!)
          : const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disposeControllers();
    super.dispose();
  }
} 