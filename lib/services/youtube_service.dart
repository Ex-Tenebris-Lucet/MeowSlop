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
      query: 'trending cats',
      tags: ['cats', 'viral cats', 'popular cats'],
    );
  }

  Future<List<YouTubeVideo>> getVoidCatVideos() async {
    return searchCatVideos(
      query: 'void cats black cats',
      tags: ['void cat', 'black cat', 'ninja cat'],
    );
  }
} 