import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:youtube_api/youtube_api.dart';
import '../services/youtube_service.dart';
import '../services/video_player_service.dart';
import '../main.dart'; // For our theme colors
import 'dart:async';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final _youtubeService = YoutubeService();
  List<YouTubeVideo> _videos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      final videos = await _youtubeService.getCatShorts();
      setState(() {
        _videos = videos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(MeowColors.voidAccent),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error loading videos: $_error',
              style: const TextStyle(color: MeowColors.voidAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadVideos,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return const Center(
        child: Text(
          'No videos found 😿',
          style: TextStyle(color: MeowColors.voidAccent),
        ),
      );
    }

    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        return VideoCard(video: _videos[index]);
      },
    );
  }
}

class VideoCard extends StatefulWidget {
  final YouTubeVideo video;

  const VideoCard({
    super.key,
    required this.video,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  final _videoPlayerService = YoutubePlayerService();
  bool _showOverlay = false;
  bool _needsBackground = false;
  double _backgroundScale = 1.0;
  ImageProvider? _processedBackground;

  @override
  void initState() {
    super.initState();
    _prepareBackground();
  }

  Future<void> _prepareBackground() async {
    // Load and decode the image
    final imageProvider = NetworkImage(widget.video.thumbnail.high.url ?? '');
    final imageStream = imageProvider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();
    
    final listener = ImageStreamListener((info, _) {
      completer.complete(info.image);
    });
    
    imageStream.addListener(listener);
    final image = await completer.future;
    imageStream.removeListener(listener);

    // Create a picture recorder and canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Draw the image with blur and color adjustments
    final paint = Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0)
      ..colorFilter = const ColorFilter.matrix([
        0.9, 0, 0, 0, 0,
        0, 0.9, 0, 0, 0,
        0, 0, 0.9, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    
    canvas.drawImage(image, Offset.zero, paint);
    
    // Convert to an image
    final processedImage = await recorder.endRecording()
        .toImage(image.width, image.height);
    final byteData = await processedImage.toByteData(format: ui.ImageByteFormat.png);
    
    if (mounted && byteData != null) {
      setState(() {
        _processedBackground = MemoryImage(byteData.buffer.asUint8List());
      });
    }
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
    if (widget.video.id != null) {
      _videoPlayerService.togglePlayback(widget.video.id!);
    }
  }

  @override
  void dispose() {
    _videoPlayerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleOverlay,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Static pre-processed background
            if (_needsBackground && _processedBackground != null)
              Transform.scale(
                scale: _backgroundScale,
                child: Image(
                  image: _processedBackground!,
                  fit: BoxFit.cover,
                ),
              ),

            // Main video
            if (widget.video.id != null)
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16, // Vertical aspect ratio for Shorts
                  child: _videoPlayerService.buildPlayer(
                    widget.video.id!,
                    showControls: _showOverlay,
                  ),
                ),
              )
            else
              Image.network(
                widget.video.thumbnail.high.url ?? '',
                fit: BoxFit.cover,
              ),
            
            // Overlay elements (only show when _showOverlay is true)
            if (_showOverlay) ...[
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
              
              // Video metadata
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.video.channelTitle ?? 'Unknown Channel',
                      style: const TextStyle(
                        color: MeowColors.voidAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.video.title ?? 'Untitled Video',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 