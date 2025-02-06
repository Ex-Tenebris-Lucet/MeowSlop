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
    bool randomize = true,
  }) async {
    try {
      // Combine query with tags for better results
      final searchQuery = '$query ${tags.join(' ')}';
      final videos = await _yt.search(searchQuery);
      
      // Filter out any non-cat content (basic filtering)
      var filteredVideos = videos.where((video) {
        final title = video.title.toLowerCase() ?? '';
        final description = video.description?.toLowerCase() ?? '';
        return tags.any((tag) => 
          title.contains(tag.toLowerCase()) || 
          description.contains(tag.toLowerCase())
        );
      }).toList();

      // Randomize the order if requested
      if (randomize) {
        filteredVideos.shuffle();
      }
      
      return filteredVideos;
    } catch (e) {
      print('Error fetching cat videos: $e');
      return [];
    }
  }

  Future<List<YouTubeVideo>> getTrendingCatVideos() async {
    return searchCatVideos(
      query: '#shorts cats',
      tags: ['cat', 'kitten', 'cats'], // Keep it simple and natural
    );
  }

  Future<List<YouTubeVideo>> getVoidCatVideos() async {
    return searchCatVideos(
      query: '#shorts black cats',
      tags: ['black cat', 'void cat'], // More focused tags
    );
  }

  Future<List<YouTubeVideo>> getCatShorts() async {
    // Mix of different search terms for variety
    final searchTypes = [
      {'query': '#shorts cats', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat compilation', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cats being cats', 'tags': <String>['cat', 'kitten']},
    ];
    
    // Randomly select a search type
    final searchType = searchTypes[DateTime.now().millisecondsSinceEpoch % searchTypes.length];
    
    return searchCatVideos(
      query: searchType['query'] as String,
      tags: (searchType['tags'] as List<String>),
    ).then((videos) {
      // Filter for actual Shorts (usually < 60s)
      return videos.where((video) {
        final duration = video.duration ?? '';
        final parts = duration.split(':');
        if (parts.length != 2) return true;
        
        final minutes = int.tryParse(parts[0]) ?? 0;
        final seconds = int.tryParse(parts[1]) ?? 0;
        final totalSeconds = minutes * 60 + seconds;
        
        return totalSeconds <= 60;
      }).toList();
    });
  }
} 