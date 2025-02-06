import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
      // Start loading the image
      await precacheImage(_preloadedImage!, context);
      print('Preloaded GIF: $title');
    } catch (e) {
      print('Error preloading GIF: $e');
    }
  }

  // Get the preloaded image if available
  ImageProvider get image => _preloadedImage ?? NetworkImage(url);

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    try {
      final images = json['images'] as Map<String, dynamic>;
      
      // For the main display, prefer downsized or original gif
      final original = (images['downsized'] ?? images['original']) as Map<String, dynamic>;
      
      // For preview, use fixed_height or preview_gif
      final preview = (images['fixed_height'] ?? images['preview_gif']) as Map<String, dynamic>;

      // Print the structure to debug
      print('Processing GIF: ${json['title']}');
      print('Original image data: $original');
      print('Preview image data: $preview');

      return GiphyGif(
        id: json['id'] as String,
        title: json['title'] as String,
        url: original['url'] as String,  // Use GIF URL, not MP4
        previewUrl: preview['url'] as String,
        aspectRatio: double.parse(original['width'].toString()) / double.parse(original['height'].toString()),
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
  static const String _baseUrl = 'https://api.giphy.com/v1/gifs';
  final String _apiKey;
  final List<GiphyGif> _cache = [];
  
  // Simple constants
  static const int _maxGifsPerRequest = 50;
  static const Duration _minCallInterval = Duration(seconds: 5); // More reasonable rate limit
  
  DateTime _lastApiCall = DateTime.now();
  
  GiphyService() : _apiKey = dotenv.env['GIPHY_API_KEY'] ?? (throw Exception('Giphy API key not found in environment'));

  Future<void> _waitForRateLimit() async {
    final timeSinceLastCall = DateTime.now().difference(_lastApiCall);
    if (timeSinceLastCall < _minCallInterval) {
      await Future.delayed(_minCallInterval - timeSinceLastCall);
    }
    _lastApiCall = DateTime.now();
  }

  // Single method to get GIFs, either from cache or API
  Future<List<GiphyGif>> getGifs({int limit = 3, int startIndex = 0}) async {
    try {
      // Serve from cache if possible
      if (startIndex < _cache.length) {
        return _cache.sublist(
          startIndex,
          min(startIndex + limit, _cache.length)
        );
      }

      // If we need more GIFs, fetch them
      await _waitForRateLimit();
      final gifs = await _searchGifs(limit: _maxGifsPerRequest);
      
      if (gifs.isNotEmpty) {
        _cache.addAll(gifs);
        return _cache.sublist(
          startIndex,
          min(startIndex + limit, _cache.length)
        );
      }
      
      return [];
    } catch (e) {
      print('Error getting GIFs: $e');
      return [];
    }
  }

  Future<List<GiphyGif>> _searchGifs({int limit = 25}) async {
    final searchQueries = [
      'cute cats',
      'funny cats',
      'cat playing',
      'kitten cute',
      'sleepy cat',
      'cat zoomies',
      'cat toe beans',
      'cat loaf',
      'cat stretching',
      'cat purring',
      'playful kitten',
      'cat box',
      'cat nap',
      'cat meow',
    ];

    final query = searchQueries[DateTime.now().millisecondsSinceEpoch % searchQueries.length];

    final url = '$_baseUrl/search?'
      'api_key=$_apiKey'
      '&q=$query'
      '&limit=$limit'
      '&offset=0'
      '&rating=g'
      '&bundle=messaging_non_clips'
      '&lang=en';
    
    print('Fetching GIFs from URL: $url');
    
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      var gifs = await _processGiphyResponse(response.body);
      if (gifs.isNotEmpty) {
        gifs.shuffle();
        return gifs;
      }
      
      // If search fails, try trending
      return getTrendingCatGifs(limit: limit);
    } else {
      print('Error fetching GIFs: ${response.statusCode}');
      return [];
    }
  }

  Future<List<GiphyGif>> getTrendingCatGifs({int limit = 25}) async {
    try {
      final url = '$_baseUrl/trending?'
        'api_key=$_apiKey'
        '&limit=$limit'
        '&offset=0'
        '&rating=g'
        '&bundle=messaging_non_clips'
        '&lang=en';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var gifs = await _processGiphyResponse(response.body, requireCatTerms: true);
        gifs.shuffle();
        return gifs;
      }
      return [];
    } catch (e) {
      print('Error in getTrendingCatGifs: $e');
      return [];
    }
  }

  List<GiphyGif> _processGiphyResponse(String responseBody, {bool requireCatTerms = false}) {
    try {
      final data = json.decode(responseBody);
      print('Raw API response: $data'); // Debug print
      
      if (data == null || !data.containsKey('data')) {
        print('Invalid response format - missing data key');
        return [];
      }

      final List<dynamic> items = data['data'] is List ? data['data'] : [data['data']];
      print('Processing ${items.length} GIFs from response');
      
      if (items.isEmpty) {
        print('No items found in response');
        return [];
      }

      return items.where((item) {
        try {
          if (item == null || item is! Map<String, dynamic>) {
            print('Invalid item format: $item');
            return false;
          }
          return true;
        } catch (e) {
          print('Error processing item: $e');
          return false;
        }
      }).map((item) {
        try {
          return GiphyGif.fromJson(item);
        } catch (e) {
          print('Error creating GiphyGif from item: $e');
          return null;
        }
      }).whereType<GiphyGif>().where((gif) {
        final title = gif.title.toLowerCase();
        
        // Expanded blacklist
        final blacklist = [
          'dead', 'died', 'dying', 'rip', 'sad', 'crying',
          'hurt', 'pain', 'sick', 'injured', 'scary',
          'warning', 'graphic', 'blood', 'fight', 'violent',
        ];
        
        // Must contain at least one positive term
        final positiveTerms = [
          'cute', 'adorable', 'sweet', 'funny', 'happy',
          'playing', 'sleepy', 'silly', 'fluffy', 'tiny',
        ];
        
        final catTerms = ['cat', 'kitten', 'kitty'];
        
        final hasBlacklistedTerm = blacklist.any((term) => title.contains(term));
        final hasPositiveTerm = positiveTerms.any((term) => title.contains(term));
        final hasCatTerm = !requireCatTerms || catTerms.any((term) => title.contains(term));
        
        if (hasBlacklistedTerm) {
          print('Filtered out GIF with title: $title');
        }
        
        return !hasBlacklistedTerm && (hasPositiveTerm || !requireCatTerms) && hasCatTerm;
      }).toList();
    } catch (e, stackTrace) {
      print('Error processing Giphy response: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
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