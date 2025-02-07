import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'user_profile_screen.dart';
import '../widgets/video_player_widget.dart';

// Add custom scroll behavior
class SnappyScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const PageScrollPhysics(
      parent: ClampingScrollPhysics(),
    ).applyTo(
      const AlwaysScrollableScrollPhysics(),
    );
  }
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _authService = AuthService();
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;
  final int _initialPostCount = 10;
  final _pageController = PageController(
    viewportFraction: 1.0,
  );
  bool _showOverlay = false;
  final Map<String, ImageProvider> _preloadedImages = {};
  static const _preloadAhead = 3; // Number of images to preload ahead
  static const _maxCacheSize = 20; // Maximum number of images to keep in cache
  final Set<String> _seenPostIds = {}; // Track seen posts to prevent duplicates

  @override
  void initState() {
    super.initState();
    _updateSystemUI();
    _loadInitialPosts();
  }

  Future<void> _loadInitialPosts() async {
    try {
      final posts = await _authService.getRandomPosts(limit: _initialPostCount);
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
          _hasMorePosts = posts.length == _initialPostCount;
          // Track initial post IDs
          _seenPostIds.addAll(posts.map((p) => p['id'].toString()));
        });
        // Preload initial set of images
        _preloadImages(0);
      }
    } catch (e) {
      print('Error loading initial posts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _posts = [];
        });
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMore) return;

    try {
      setState(() => _isLoadingMore = true);
      final newPosts = await _authService.getRandomPosts(limit: 5);
      
      if (mounted) {
        // Filter out any posts we've already seen
        final uniqueNewPosts = newPosts.where((post) {
          final postId = post['id'].toString();
          if (_seenPostIds.contains(postId)) return false;
          _seenPostIds.add(postId);
          return true;
        }).toList();

        setState(() {
          _posts.addAll(uniqueNewPosts);
          _hasMorePosts = uniqueNewPosts.isNotEmpty;
          _isLoadingMore = false;
        });
        
        // Preload images for new posts
        if (uniqueNewPosts.isNotEmpty) {
          _preloadImages(_posts.length - uniqueNewPosts.length);
        }
      }
    } catch (e) {
      print('Error loading more posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _hasMorePosts = false;
        });
      }
    }
  }

  void _preloadImages(int startIndex) {
    // Clean up cache if it's too large
    if (_preloadedImages.length > _maxCacheSize) {
      final keysToRemove = _preloadedImages.keys.take(_preloadedImages.length - _maxCacheSize);
      for (final key in keysToRemove) {
        _preloadedImages.remove(key);
      }
    }

    for (var i = startIndex; i < _posts.length && i < startIndex + _preloadAhead; i++) {
      final post = _posts[i];
      final url = post['storage_path'];
      if (url == null || url.isEmpty) continue;
      
      if (!_preloadedImages.containsKey(url)) {
        try {
          final imageProvider = NetworkImage(url);
          _preloadedImages[url] = imageProvider;
          precacheImage(imageProvider, context).catchError((e) {
            print('Error preloading image: $e');
            _preloadedImages.remove(url);
          });
        } catch (e) {
          print('Error setting up image preload: $e');
        }
      }
    }
  }

  void _updateSystemUI() {
    if (_showOverlay) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: [SystemUiOverlay.bottom],  // Keep navigation buttons visible
      );
    }
  }

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
      _updateSystemUI();
    });
  }

  @override
  void dispose() {
    // Clear image cache
    _preloadedImages.clear();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    // Get the full screen size including system UI
    final fullScreenSize = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (_posts.isEmpty) {
    return Scaffold(
      backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.menu,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const UserProfileScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(1.0, 0.0);
                      const end = Offset.zero;
                      const curve = Curves.easeOutExpo;
                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                      var offsetAnimation = animation.drive(tween);
                      return SlideTransition(
                        position: offsetAnimation,
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 100),
                  ),
                );
              },
            ),
          ],
        ),
      body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'No posts available',
          style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _loadInitialPosts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: ScrollConfiguration(
        behavior: SnappyScrollBehavior(),
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          pageSnapping: true,
          physics: const PageScrollPhysics(),
          onPageChanged: (index) {
            // Add more posts when we're near the end
            if (_hasMorePosts && index >= _posts.length - 3) {
              _loadMorePosts();
            }
            // Preload next set of images
            _preloadImages(index + 1);
            // Hide overlay when scrolling to a new post
            if (_showOverlay) {
              _toggleOverlay();
            }
          },
          itemBuilder: (context, index) {
            // If we somehow scroll past our posts list, show loading or end message
            if (index >= _posts.length) {
              return Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : const Text(
                        'No more posts',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
              );
            }
            
            final post = _posts[index];
            final creator = post['profiles'] as Map<String, dynamic>? ?? {};
            final imageUrl = post['storage_path'] as String?;
            final isVideo = post['media_type'] == 'video';
            final thumbnailUrl = post['thumbnail_url'];
            final displayUrl = isVideo ? (thumbnailUrl ?? imageUrl) : imageUrl;
            
            if (displayUrl == null || displayUrl.isEmpty) {
              return Container(
                color: Colors.grey[900],
                child: const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white24,
                    size: 48,
                  ),
                ),
              );
            }

            return GestureDetector(
              onTapUp: (_) {
                final page = _pageController.page;
                if (page != null && page % 1.0 != 0) {
                  // We're between pages, so snap to nearest
                  _pageController.animateToPage(
                    page.round(),
                    duration: const Duration(milliseconds: 1),
                    curve: Curves.linear,
                  ).then((_) => _toggleOverlay());
                } else {
                  _toggleOverlay();
                }
              },
              child: SizedBox(
                height: fullScreenSize.height,
                width: fullScreenSize.width,
                child: Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    // Post Content
                    Positioned(
                      top: 0,
                      left: 0,
                      width: fullScreenSize.width,
                      height: fullScreenSize.height,
                      child: Container(
                        color: Colors.black,
                        child: isVideo
                            ? VideoPlayerWidget(
                                url: imageUrl!,
                                autoPlay: true,
                                looping: true,
                                showOverlay: _showOverlay,
                                onTap: () {
                                  final page = _pageController.page;
                                  if (page != null && page % 1.0 != 0) {
                                    // We're between pages, so snap to nearest
                                    _pageController.animateToPage(
                                      page.round(),
                                      duration: const Duration(milliseconds: 1),
                                      curve: Curves.linear,
                                    ).then((_) => _toggleOverlay());
                                  } else {
                                    _toggleOverlay();
                                  }
                                },
                              )
                            : Image(
                                image: _preloadedImages[imageUrl] ?? NetworkImage(imageUrl!),
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / 
                                            loadingProgress.expectedTotalBytes!
                                          : null,
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white24),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey[900],
                                  child: const Center(
                                    child: Icon(
                                      Icons.error_outline,
                                      color: Colors.white24,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    
                    // Overlay (only visible when _showOverlay is true)
                    if (_showOverlay)
                      Positioned(
                        top: 0,
                        left: 0,
                        width: fullScreenSize.width,
                        height: fullScreenSize.height,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                              stops: [0.7, 1.0],
                            ),
                          ),
                          child: Stack(
                            children: [
                              // Menu Button
                              Positioned(
                                top: MediaQuery.of(context).padding.top + 16,
                                right: 16,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.menu,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const UserProfileScreen(),
                                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                          const begin = Offset(1.0, 0.0);
                                          const end = Offset.zero;
                                          const curve = Curves.easeOutExpo;
                                          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                                          var offsetAnimation = animation.drive(tween);
                                          return SlideTransition(
                                            position: offsetAnimation,
                                            child: child,
                                          );
                                        },
                                        transitionDuration: const Duration(milliseconds: 100),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Creator Info - Adjust position to account for system UI
                              Positioned(
                                left: 16,
                                bottom: bottomPadding + 16,
                                child: Row(
                                  children: [
                                    // Profile Picture
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.grey[800],
                                        image: creator['profile_pic_url'] != null
                                            ? DecorationImage(
                                                image: NetworkImage(creator['profile_pic_url']),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: creator['profile_pic_url'] == null
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.white54,
                                              size: 24,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    // Username
                                    Text(
                                      '@${creator['username'] ?? 'unknown'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
} 