import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../services/giphy_service.dart';
import '../main.dart';
import 'dart:async';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final _giphyService = GiphyService();
  List<GiphyGif> _gifs = [];
  bool _isLoading = true;
  String? _error;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadGifs();
  }

  Future<void> _loadGifs() async {
    try {
      final gifs = await _giphyService.getGifs(limit: 3);
      
      if (mounted) {
        setState(() {
          _gifs = gifs;
          _isLoading = false;
        });

        // Start preloading next GIF if available
        if (gifs.length > 1) {
          _giphyService.preloadGif(gifs[1], context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreGifs() async {
    try {
      final newGifs = await _giphyService.getGifs(
        startIndex: _gifs.length,
        limit: 3,
      );
      
      if (mounted && newGifs.isNotEmpty) {
        setState(() {
          _gifs.addAll(newGifs);
        });
      }
    } catch (e) {
      print('Error loading more GIFs: $e');
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    
    // Load more GIFs if we're near the end
    if (index >= _gifs.length - 2) {
      _loadMoreGifs();
    }
    
    // Preload next GIF
    if (mounted && index < _gifs.length - 1) {
      _giphyService.preloadGif(_gifs[index + 1], context);
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
    if (_gifs.isEmpty) {
      return Stack(
        children: [
          // Show a static placeholder image or animation
          const Center(
            child: Icon(
              Icons.pets,
              size: 64,
              color: MeowColors.voidAccent,
            ),
          ),
          // Show loading indicator on top
          if (_isLoading)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(MeowColors.voidAccent),
                ),
              ),
            ),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error loading GIFs: $_error',
              style: const TextStyle(color: MeowColors.voidAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGifs,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _gifs.length + 1,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        if (index >= _gifs.length) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(MeowColors.voidAccent),
            ),
          );
        }
        return GifCard(
          gif: _gifs[index],
          isVisible: index == _currentIndex,
        );
      },
    );
  }
}

class GifCard extends StatefulWidget {
  final GiphyGif gif;
  final bool isVisible;

  const GifCard({
    super.key,
    required this.gif,
    required this.isVisible,
  });

  @override
  State<GifCard> createState() => _GifCardState();
}

class _GifCardState extends State<GifCard> {
  bool _showOverlay = false;
  bool _isLoading = true;
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
    _mounted = true;
  }

  @override
  void didUpdateWidget(GifCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      // Card just became visible
      setState(() => _isLoading = true);
    }
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }

  void _setLoading(bool value) {
    if (_mounted) {
      setState(() => _isLoading = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showOverlay = !_showOverlay),
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: Colors.black,
        child: Stack(
          children: [
            // Main GIF
            Positioned.fill(
              child: Image(
                image: widget.gif.image,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _setLoading(false);
                    });
                    return child;
                  }
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(MeowColors.voidAccent),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _setLoading(false);
                  });
                  print('Error loading GIF: $error');
                  return const Center(
                    child: Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                  );
                },
              ),
            ),

            // Loading indicator
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(MeowColors.voidAccent),
                    ),
                  ),
                ),
              ),

            // Overlay elements (only show when _showOverlay is true)
            if (_showOverlay) ...[
              // Gradient overlay
              Positioned.fill(
                child: Container(
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
              ),

              // GIF metadata
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Via Giphy',
                      style: TextStyle(
                        color: MeowColors.voidAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.gif.title,
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