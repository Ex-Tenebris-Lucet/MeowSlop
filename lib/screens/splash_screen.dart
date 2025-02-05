import 'package:flutter/material.dart';
import '../services/device_service.dart';
import 'video_feed_screen.dart';

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
      duration: const Duration(seconds: 1), // Full second for movement
      vsync: this,
    );

    // Use a more dramatic acceleration curve
    _positionAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInExpo, // Much stronger acceleration
    ).drive(Tween<double>(
      begin: 0.0,
      end: -1, // Move up by 70% of screen height
    ));

    // Sync fade with the movement
    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn), // Fade out earlier in the animation
    ).drive(Tween<double>(
      begin: 1.0,
      end: 0.0,
    ));

    // One second static display
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _startAnimation = true);
        _controller.forward().then((_) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const VideoFeedScreen(),
            ),
          );
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