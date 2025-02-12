import 'package:flutter/material.dart';
import '../services/device_service.dart';
import '../services/supabase_service.dart';
import '../services/video_service.dart';
import 'feed_screen.dart';
// import '../services/giphy_service.dart';  // Commented out Giphy service

class SplashScreen extends StatefulWidget {
  final DeviceService deviceService;
  
  const SplashScreen({super.key, required this.deviceService});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;
  late Animation<double> _opacityAnimation;
  bool _startAnimation = false;
  final _feedPreloader = FeedPreloader();

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startLoadingAndAnimate();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _positionAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInExpo,
    ).drive(Tween<double>(
      begin: 0.0,
      end: -1,
    ));

    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    ).drive(Tween<double>(
      begin: 1.0,
      end: 0.0,
    ));
  }

  Future<void> _startLoadingAndAnimate() async {
    // Start preloading immediately
    _feedPreloader.startPreloading();
    
    try {
      // Run connection test in parallel with preloading
      final success = await SupabaseService().testConnection();
      print('Supabase connection test: ${success ? 'PASSED' : 'FAILED'}');
    } catch (e) {
      print('Error testing connection: $e');
    }

    try {
      // Wait for first post to be ready
      final firstPost = await _feedPreloader.getFirstPost();
      
      if (mounted) {
        setState(() => _startAnimation = true);
        await _controller.forward();
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => FeedScreen(preloadedPosts: firstPost),
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading initial post: $e');
      if (mounted) {
        // Still transition to feed screen, it will handle the error state
        setState(() => _startAnimation = true);
        await _controller.forward();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const FeedScreen(),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _startAnimation ? 
                MediaQuery.of(context).size.height * _positionAnimation.value : 0),
              child: Opacity(
                opacity: _startAnimation ? _opacityAnimation.value : 1.0,
                child: const Text(
                  'MeoẅSlop',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFE66D), // Cat eye color
                    fontFamily: 'CherryBombOne',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
