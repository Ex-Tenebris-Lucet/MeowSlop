import 'package:youtube_api/youtube_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class YoutubeService {
  late YoutubeAPI _yt;
  
  YoutubeService() {
    final apiKey = dotenv.env['YOUTUBE_API_KEY'];
    if (apiKey == null) throw Exception('YouTube API key not found in environment');
    _yt = YoutubeAPI(apiKey, maxResults: 50, type: "video");
  }

  Future<List<YouTubeVideo>> searchCatVideos({
    String query = 'cute cats',
    List<String> tags = const ['cats', 'kittens', 'funny cats'],
  }) async {
    try {
      // Combine query with tags for better results
      final searchQuery = '$query ${tags.join(' ')}';
      final videos = await _yt.search(searchQuery);
      
      // Filter out any non-cat content (basic filtering)
      return videos.where((video) {
        final title = video.title.toLowerCase() ?? '';
        final description = video.description?.toLowerCase() ?? '';
        return tags.any((tag) => 
          title.contains(tag.toLowerCase()) || 
          description.contains(tag.toLowerCase())
        );
      }).toList();
    } catch (e) {
      print('Error fetching cat videos: $e');
      return [];
    }
  }

  Future<List<YouTubeVideo>> getTrendingCatVideos() async {
    return searchCatVideos(
      query: '#shorts trending cats',
      tags: ['cats', 'viral cats', 'popular cats', 'shorts'],
    );
  }

  Future<List<YouTubeVideo>> getVoidCatVideos() async {
    return searchCatVideos(
      query: '#shorts void cats black cats',
      tags: ['void cat', 'black cat', 'ninja cat', 'shorts'],
    );
  }

  Future<List<YouTubeVideo>> getCatShorts() async {
    return searchCatVideos(
      query: '#shorts cat shorts',
      tags: ['cats', 'shorts', 'viral cats'],
    ).then((videos) {
      // Try to filter for actual Shorts (usually < 60s and vertical aspect ratio)
      return videos.where((video) {
        final duration = video.duration ?? '';
        // Parse duration string (usually in format "0:58" or "1:30")
        final parts = duration.split(':');
        if (parts.length != 2) return true; // Include if we can't parse duration
        
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        final totalSeconds = minutes * 60 + seconds;
        
        return totalSeconds <= 60; // Only include videos <= 60 seconds
      }).toList();
    });
  }
} 