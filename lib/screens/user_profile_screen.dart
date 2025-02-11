import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'signup_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../widgets/video_player_widget.dart';
import '../services/video_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;  // The ID of the user whose profile to show
  
  const UserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _videoService = VideoService();
  final _supabase = Supabase.instance.client;
  bool? _isLoggedIn;
  Map<String, dynamic>? _profile;
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _taglineController = TextEditingController();
  List<Map<String, dynamic>>? _posts;
  bool _isOwnProfile = true;
  bool _isFollowing = false;
  List<Map<String, dynamic>>? _followers;
  List<Map<String, dynamic>>? _following;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLoginState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _taglineController.dispose();
    if (_isOwnProfile) {
      VideoService().cleanup();  // Only clean up video cache when leaving own profile
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLoginState();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context)?.addScopedWillPopCallback(() async {
      _checkLoginState();
      return true;
    });
  }

  Future<void> _checkLoginState() async {
    final loggedIn = await _authService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
      });
      
      if (loggedIn) {
        // Get current user's profile to compare IDs
        final currentProfile = await _authService.getProfile();
        if (mounted) {
          setState(() {
            _isOwnProfile = currentProfile != null && widget.userId == currentProfile['id'];
          });
        }
      } else {
        setState(() {
          _isOwnProfile = false;
        });
      }
      // Always fetch the profile data
      _fetchProfile();
    }
  }

  Future<void> _fetchProfile() async {
    final profile = await _authService.getUserProfile(widget.userId);
      
    if (mounted) {
      setState(() {
        _profile = profile;
        if (!_isEditing && _isOwnProfile) {
          _usernameController.text = profile?['username'] ?? '';
          _taglineController.text = profile?['tagline'] ?? '';
        }
      });
      _fetchPosts();
      if (!_isOwnProfile) {
        _checkFollowingStatus();
      }
      _fetchFollowCounts();
    }
  }

  Future<void> _checkFollowingStatus() async {
    if (widget.userId != null) {
      final isFollowing = await _authService.isFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }
    }
  }

  Future<void> _fetchFollowCounts() async {
    if (_profile != null) {
      final followers = await _authService.getFollowers(widget.userId);
      final following = await _authService.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _followers = followers;
          _following = following;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    try {
      if (_isFollowing) {
        await _authService.unfollowUser(widget.userId);
      } else {
        await _authService.followUser(widget.userId);
      }
      await _fetchProfile();
      await _checkFollowingStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Logout',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.logout();
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _profile = null;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    _formKey.currentState!.save();

    try {
      await _authService.updateProfile(
        tagline: _taglineController.text.trim(),
      );
      await _fetchProfile();
      if (mounted) {
        setState(() {
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isOwnProfile ? 'Profile' : (_profile?['username'] != null ? '@${_profile!['username']}' : 'Profile'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: _isLoggedIn! && _isOwnProfile
            ? [
                if (_isEditing)
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.white),
                    onPressed: _saveProfile,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: _logout,
                ),
              ]
            : null,
      ),
      body: _profile == null ? _buildLoadingView() : _buildProfileView(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildProfileView() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchProfile();
        await _fetchPosts();
        if (!_isOwnProfile && _isLoggedIn!) {
          await _checkFollowingStatus();
        }
      },
      color: Colors.white,
      backgroundColor: Colors.grey[900],
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildProfilePicture(_isEditing && _isOwnProfile),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${_profile!['username']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined ${DateTime.parse(_profile!['created_at']).toString().split(' ')[0]}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isOwnProfile && _isLoggedIn!)
                    TextButton(
                      onPressed: _toggleFollow,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        backgroundColor: _isFollowing ? Colors.transparent : Colors.white,
                        side: BorderSide(
                          color: _isFollowing ? Colors.white : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        _isFollowing ? 'Following' : 'Follow',
                        style: TextStyle(
                          color: _isFollowing ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isEditing)
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _taglineController,
                        style: const TextStyle(color: Colors.white70),
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        maxLines: null,
                      ),
                    ],
                  ),
                )
              else
                Text(
                  _profile!['tagline'] ?? 'No bio yet',
                  style: TextStyle(
                    color: _profile!['tagline'] != null ? Colors.white70 : Colors.white38,
                    fontSize: 16,
                    fontStyle: _profile!['tagline'] != null ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('Posts', _posts?.length.toString() ?? '0'),
                  _buildStatColumn('Following', _profile!['following_count']?.toString() ?? '0'),
                  _buildStatColumn('Followers', _profile!['follower_count']?.toString() ?? '0'),
                ],
              ),
              const SizedBox(height: 24),
              // Add Post Button - only show on own profile when logged in
              if (_isOwnProfile && _isLoggedIn!) ...[
                Center(
                  child: _buildAddPostButton(),
                ),
                const SizedBox(height: 24),
              ],
              _buildPostsGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostsGrid() {
    if (_posts == null) {
      // Initial loading
      return const SizedBox(
        height: 100,  // Give it some height so the spinner is visible
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (_posts!.isEmpty) {
      // No posts state
      return SizedBox(
        height: 200,  // Give empty state some height
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'No posts yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _posts!.length,
      itemBuilder: (context, index) {
        final post = _posts![index];
        final isVideo = post['media_type'] == 'video';
        // Only use thumbnail URL for videos, and only if it exists
        final displayUrl = isVideo ? post['thumbnail_url'] : post['storage_path'];

        if (displayUrl == null || displayUrl.isEmpty) {
          return Container(
            color: Colors.grey[900],
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library,
                    color: Colors.white24,
                    size: 32,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Processing',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showPostDetails(post),
          onLongPress: () => _showDeleteConfirmation(post),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.grey[900],
                child: Image.network(
                  displayUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey[900],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded / 
                                    loadingProgress.expectedTotalBytes!
                                  : null,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white24),
                            ),
                            if (isVideo)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Icon(
                                  Icons.play_circle_outline,
                                  color: Colors.white24,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
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
              // Video indicator overlay
              if (isVideo)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPostDetails(Map<String, dynamic> post) async {
    final isVideo = post['media_type'] == 'video';
    
    if (isVideo) {
      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => WillPopScope(
          onWillPop: () async {
            Navigator.of(context).pop();
            return false;
          },
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                VideoPlayerWidget(
                  key: ValueKey('video-dialog-${post['id']}'),
                  url: post['storage_path'],
                  autoPlay: true,
                  looping: true,
                  showOverlay: false,
                  onTap: () => Navigator.of(context).pop(),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Handle image posts
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Image.network(
                post['storage_path'],
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showDeleteConfirmation(Map<String, dynamic> post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Post',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this post?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _authService.deletePost(
          post['id'],
          post['storage_path'],
        );
        await _fetchPosts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting post: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _addNewPost() async {
    final ImagePicker picker = ImagePicker();
    
    try {
      // Show media type picker
      final mediaType = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Add Post',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: Colors.white),
                title: const Text(
                  'Photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.video_library, color: Colors.white),
                title: const Text(
                  'Video',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(context, 'video'),
              ),
            ],
          ),
        ),
      );

      if (mediaType == null) return;
      if (!mounted) return;

      if (mediaType == 'image') {
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );

        if (image == null) return;
        if (!mounted) return;

        final imageBytes = await image.readAsBytes();
        await _authService.uploadPost(imageBytes);
        await _fetchPosts();
      } else {
        final XFile? video = await picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 5),
        );

        if (video == null) return;
        if (!mounted) return;

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
        });

        try {
          final videoUrl = await _authService.uploadVideo(video.path);

          await _fetchPosts();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Post uploaded successfully')),
            );
          }
        } catch (e) {
          if (mounted) {
            if (e.toString().contains('cancelled')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upload cancelled')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Upload failed: ${e.toString()}')),
              );
            }
          }
        } finally {
          if (mounted) {
            setState(() {
              _isUploading = false;
              _uploadProgress = 0.0;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating post: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _fetchPosts() async {
    final posts = await _authService.getUserPosts(userId: widget.userId);
      
    if (mounted) {
      setState(() {
        _posts = posts;
      });
    }
  }

  Widget _buildProfilePicture(bool isEditing) {
    final hasProfilePic = _profile != null && 
                         _profile!['profile_pic_url'] != null && 
                         _profile!['profile_pic_url'].isNotEmpty;

    return GestureDetector(
      onTap: isEditing ? _selectProfilePicture : null,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              shape: BoxShape.circle,
              image: hasProfilePic
                  ? DecorationImage(
                      image: NetworkImage(_profile!['profile_pic_url']),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasProfilePic
                ? const Icon(
                    Icons.person,
                    color: Colors.white54,
                    size: 40,
                  )
                : null,
          ),
          if (isEditing)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return GestureDetector(
      onTap: () {
        if (label == 'Followers' && _followers != null) {
          _showUserList(_followers!, 'Followers');
        } else if (label == 'Following' && _following != null) {
          _showUserList(_following!, 'Following');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserList(List<Map<String, dynamic>> users, String title) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = title == 'Followers' 
                  ? users[index]['follower'] 
                  : users[index]['following'];
                return ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[800],
                      image: user['profile_pic_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(user['profile_pic_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: user['profile_pic_url'] == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.white54,
                            size: 24,
                          )
                        : null,
                  ),
                  title: Text(
                    '@${user['username']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context); // Close the modal
                    if (user['id'] != null) {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => 
                            UserProfileScreen(userId: user['id']),
                          transitionsBuilder: (context, animation, secondaryAnimation, child) {
                            const begin = Offset(1.0, 0.0);
                            const end = Offset.zero;
                            const curve = Curves.easeOutExpo;
                            var tween = Tween(begin: begin, end: end)
                                .chain(CurveTween(curve: curve));
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
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectProfilePicture() async {
    final ImagePicker picker = ImagePicker();
    
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Select Image Source',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_profile != null && _profile!['profile_pic_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(context, null),
              ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (source == null) {
      // User selected "Remove Photo" or cancelled
      if (_profile != null && _profile!['profile_pic_url'] != null) {
        try {
          await _authService.deleteProfilePicture(_profile!['profile_pic_url']);
          await _fetchProfile();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error removing profile picture: ${e.toString()}')),
            );
          }
        }
      }
      return;
    }

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 512, // Reasonable size for profile pictures
        maxHeight: 512,
        imageQuality: 85, // Good quality but not too large
      );

      if (image == null) return;

      final imageBytes = await image.readAsBytes();
      await _authService.uploadProfilePicture(imageBytes);
      await _fetchProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile picture: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildAddPostButton() {
    if (_isUploading) {
      return Column(
        children: [
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              _videoService.cancelUpload();
            },
            icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
            label: const Text(
              'Cancel Upload',
              style: TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      );
    }

    return TextButton.icon(
      onPressed: _addNewPost,
      icon: const Icon(Icons.add_circle, color: Colors.white, size: 28),
      label: const Text(
        'Add Post',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
} 