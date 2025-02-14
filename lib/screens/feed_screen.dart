import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/video_service.dart';
import 'user_profile_screen.dart';
import 'login_screen.dart';
import '../widgets/video_player_widget.dart';
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
  bool _isLoading = true;
  bool _useTagPreferences = false;
  final _pageController = PageController();
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _updateSystemUI();
    _initializeFeed();
  }

  Future<void> _initializeFeed() async {
    try {
      setState(() => _isLoading = true);
      
      final posts = await _authService.getFullFeedList(
        useTagPreferences: _useTagPreferences
      );
      
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });

      if (_posts.isNotEmpty) {
        _videoPreloadManager.updateCurrentIndex(0, _posts);
      }
    } catch (e) {
      print('Error initializing feed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading feed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _refreshFeed() async {
    try {
      final posts = await _authService.getFullFeedList(
        useTagPreferences: _useTagPreferences
      );
      
      if (!mounted) return;
      setState(() => _posts = posts);

      if (_posts.isNotEmpty) {
        _videoPreloadManager.updateCurrentIndex(0, _posts);
      }
    } catch (e) {
      print('Error refreshing feed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing feed: ${e.toString()}')),
        );
      }
    }
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

    if (_posts.isEmpty) {
      return _buildEmptyState();
    }

    return _buildFeedView();
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
              onPressed: _initializeFeed,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedView() {
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
              // We're near the end, but no need to load more posts
              // since we have the full list
            }
            _videoPreloadManager.updateCurrentIndex(index, _posts);
            _setOverlay(false);
          },
          itemCount: _posts.length,  // Set explicit count since we have the full list
          itemBuilder: (context, index) => _buildPostItem(index),
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
        Container(
          color: Colors.black,
          child: VideoPlayerWidget(
            url: videoUrl,
            autoPlay: true,
            looping: true,
            showOverlay: _showOverlay,
          ),
        ),
        
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
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _useTagPreferences ? Icons.auto_awesome : Icons.shuffle,
                          color: Colors.white,
                        ),
                        onPressed: _refreshFeed,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _refreshFeed,
                      ),
                      IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                        onPressed: () => _navigateToProfile(),
                      ),
                    ],
                  ),
                ),
                // Creator Info
                Positioned(
                  left: 16,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (creator['id'] != null) {
                        _navigateToProfile(creator['id'] as String);
                      }
                    },
                    child: Row(
                      children: [
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
            ) : null,
          ),
        ),
      ],
    );
  }
} 