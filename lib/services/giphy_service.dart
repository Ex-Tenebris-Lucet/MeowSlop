import 'package:flutter/material.dart';
import 'dart:async';

class GiphyGif {
  final String id;
  final String title;
  final String url;
  final String previewUrl;
  final double aspectRatio;
  ImageProvider? _preloadedImage;

  GiphyGif({
    required this.id,
    required this.title,
    required this.url,
    required this.previewUrl,
    required this.aspectRatio,
  });

  // Preload the image
  Future<void> preload(BuildContext context) async {
    try {
      _preloadedImage = NetworkImage(url);
      await precacheImage(_preloadedImage!, context);
      print('Preloaded GIF: $title');
    } catch (e) {
      print('Error preloading GIF: $e');
    }
  }

  ImageProvider get image => _preloadedImage ?? NetworkImage(url);

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    try {
      final images = json['images'] as Map<String, dynamic>;
      
      // For the main display, prefer downsized or original gif
      final original = (images['downsized'] ?? images['original']) as Map<String, dynamic>;
      
      // For preview, use fixed_height or preview_gif
      final preview = (images['fixed_height'] ?? images['preview_gif']) as Map<String, dynamic>;

      return GiphyGif(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Untitled GIF',
        url: original['url']?.toString() ?? '',
        previewUrl: preview['url']?.toString() ?? '',
        aspectRatio: double.parse(original['width']?.toString() ?? '1') / 
                    double.parse(original['height']?.toString() ?? '1'),
      );
    } catch (e, stackTrace) {
      print('Error parsing GIF JSON: $e');
      print('JSON structure: $json');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}

class GiphyService {
  // Singleton pattern
  static GiphyService? _instance;
  factory GiphyService() {
    _instance ??= GiphyService._internal();
    return _instance!;
  }
  
  GiphyService._internal();
  
  // More conservative rate limiting
  static const Duration _minCallInterval = Duration(seconds: 40); // Ensures we stay under 100 calls/hour
  DateTime _lastApiCall = DateTime.now();

  Future<void> _waitForRateLimit() async {
    final timeSinceLastCall = DateTime.now().difference(_lastApiCall);
    if (timeSinceLastCall < _minCallInterval) {
      await Future.delayed(_minCallInterval - timeSinceLastCall);
    }
    _lastApiCall = DateTime.now();
  }

  Future<List<GiphyGif>> getGifs({int limit = 3, int startIndex = 0}) async {
    return []; // Service disabled
  }

  // Helper to preload a GIF
  Future<void> preloadGif(GiphyGif gif, BuildContext context) async {
    try {
      await gif.preload(context);
    } catch (e) {
      print('Error preloading GIF: $e');
    }
  }
} 