import 'package:flutter/material.dart';
import '../services/device_service.dart';
import 'video_feed_screen.dart';
import '../services/giphy_service.dart';

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

  @override
  void initState() {
    super.initState();
    
    // Setup the animations
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

    // Start GIF loading in background without awaiting
    GiphyService().getGifs(limit: 50);  // Start loading GIFs in background
    
    // Start animation after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _startAnimation = true);
        _controller.forward().then((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const VideoFeedScreen(),
              ),
            );
          }
        });
      }
    });
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
                  'MeowSlop',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFE66D), // Cat eye color
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

class CatLoadingPainter extends CustomPainter {
  final Animation<double> animation;

  CatLoadingPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFE66D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * animation.value;

    // Draw cat ears (simple triangles for now)
    final path = Path()
      ..moveTo(center.dx - 15, center.dy)
      ..lineTo(center.dx - 5, center.dy - 20)
      ..lineTo(center.dx + 5, center.dy)
      ..moveTo(center.dx + 15, center.dy)
      ..lineTo(center.dx + 25, center.dy - 20)
      ..lineTo(center.dx + 35, center.dy);

    canvas.drawPath(path, paint);
    canvas.drawCircle(center, 20, paint);
  }

  @override
  bool shouldRepaint(CatLoadingPainter oldDelegate) => true;
} 