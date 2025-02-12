import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/video_service.dart';
import 'user_profile_screen.dart';
import 'login_screen.dart';
import '../widgets/video_player_widget.dart';
import 'dart:io';
import 'package:visibility_detector/visibility_detector.dart';

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
  final List<Map<String, dynamic>>? preloadedPosts;
  
  const FeedScreen({
    super.key,
    this.preloadedPosts,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _authService = AuthService();
  final _videoPreloadManager = VideoPreloadManager();
  List<Map<String, dynamic>> _posts = [];
  Future<void>? _loadingFuture;
  final _pageController = PageController();
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _updateSystemUI();
    
    if (widget.preloadedPosts != null && widget.preloadedPosts!.isNotEmpty) {
      _posts = widget.preloadedPosts!;
      _videoPreloadManager.updateCurrentIndex(0, _posts);
      _loadingFuture = _loadMorePosts();
    } else {
      _loadingFuture = _loadInitialPosts();
    }
  }

  Future<void> _loadInitialPosts() async {
    final posts = await _authService.getRandomPosts(limit: 10);
    if (!mounted) return;
    setState(() => _posts = posts);
    _videoPreloadManager.updateCurrentIndex(0, _posts);
  }

  Future<void> _loadMorePosts() async {
    if (_loadingFuture != null) return;

    _loadingFuture = _authService.getRandomPosts(limit: 5).then((newPosts) {
      if (!mounted) return;
      setState(() => _posts.addAll(newPosts));
      _loadingFuture = null;
    });
  }

  void _updateSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: _showOverlay ? SystemUiOverlay.values : [SystemUiOverlay.bottom],
    );
  }

  void _setOverlay(bool show) {
    if (_showOverlay == show) return;
    final tapTime = DateTime.now().millisecondsSinceEpoch;
    print('TAP: Overlay tap registered at $tapTime');  // Debug log
    setState(() {
      _showOverlay = show;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: show ? SystemUiOverlay.values : [SystemUiOverlay.bottom],
      );
    });
    print('TAP: State updated at ${DateTime.now().millisecondsSinceEpoch}, delta: ${DateTime.now().millisecondsSinceEpoch - tapTime}ms');  // Debug log
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoPreloadManager.dispose();
    super.dispose();
  }

  Future<void> _navigateToProfile([String? creatorId]) async {
    if (creatorId == null) {
      final currentProfile = await _authService.getProfile();
      if (currentProfile != null && mounted) {
        creatorId = currentProfile['id'] as String;
      }
    }
    if (creatorId != null && mounted) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
            UserProfileScreen(userId: creatorId!),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _posts.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        if (_posts.isEmpty) {
          return _buildEmptyState();
        }

        return _buildFeedView(snapshot.connectionState == ConnectionState.waiting);
      },
    );
  }

  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => _navigateToProfile(),
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
              style: TextStyle(color: Colors.white70, fontSize: 18),
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

  Widget _buildFeedView(bool isLoading) {
    return Scaffold(
      body: ScrollConfiguration(
        behavior: SnappyScrollBehavior(),
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          pageSnapping: true,
          physics: const PageScrollPhysics(),
          onPageChanged: (index) {
            if (index >= _posts.length - 3) {
              _loadMorePosts();
            }
            _videoPreloadManager.updateCurrentIndex(index, _posts);
            _setOverlay(false);  // Direct state set, no toggle
          },
          itemBuilder: (context, index) {
            if (index >= _posts.length) {
              return Center(
                child: isLoading
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
            
            return _buildPostItem(index);
          },
        ),
      ),
    );
  }

  Widget _buildPostItem(int index) {
    final post = _posts[index];
    final creator = post['profiles'] as Map<String, dynamic>? ?? {};
    final videoUrl = post['storage_path'] as String?;
    
    if (videoUrl == null || videoUrl.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(
            Icons.error_outline,
            color: Colors.white24,
            size: 48,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video layer (just plays/pauses based on overlay state)
        Container(
          color: Colors.black,
          child: VideoPlayerWidget(
            url: videoUrl,
            autoPlay: true,
            looping: true,
            showOverlay: _showOverlay,
          ),
        ),
        
        // Interactive layer (always present, toggles between transparent and visible)
        GestureDetector(
          onTap: () => _setOverlay(!_showOverlay),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(_showOverlay ? 0.7 : 0.0),
                ],
                stops: const [0.7, 1.0],
              ),
            ),
            child: _showOverlay ? Stack(
              children: [
                // Menu Button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    onPressed: () async {
                      final isLoggedIn = await _authService.isLoggedIn();
                      if (!isLoggedIn) {
                        if (!mounted) return;
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => 
                              const LoginScreen(),
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
                        return;
                      }
                      await _navigateToProfile();
                    },
                  ),
                ),
                // Creator Info
                Positioned(
                  left: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,  // Make sure profile tap works reliably
                    onTap: () {
                      if (creator['id'] != null) {
                        _navigateToProfile(creator['id'] as String);
                      }
                    },
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
                ),
              ],
            ) : null,  // No UI when overlay is "invisible"
          ),
        ),
      ],
    );
  }
} 