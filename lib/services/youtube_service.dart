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
    List<String> tags = const ['cats', 'kittens'],
    bool randomize = true,
  }) async {
    try {
      final searchQuery = '$query ${tags.join(' ')}';
      final videos = await _yt.search(searchQuery);
      
      // Much stricter filtering
      var filteredVideos = videos.where((video) {
        final title = video.title?.toLowerCase() ?? '';
        final description = video.description?.toLowerCase() ?? '';
        final channelTitle = video.channelTitle?.toLowerCase() ?? '';

        // Negative filters - skip if these appear
        final blacklist = [
          // Content type filters
          'gacha', 'animation', 'minecraft', 'roblox', 'ai', 'artificial',
          'subscribe', 'follow', 'tiktok compilation', '#shorts compilation',
          'funny compilation', 'try not to laugh', 'satisfying', 'asmr',
          'animation', 'cartoon', '3d', 'cgi', 'subscribe', 'merch',
          
          // Sad/disturbing content filters
          'dead', 'died', 'dying', 'rip', 'rest in peace', 'rainbow bridge',
          'crying', 'sad', 'rescue', 'help', 'emergency', 'sick', 'hospital',
          'vet ', 'surgery', 'injury', 'injured', 'wound', 'hurt', 'pain',
          'abuse', 'abandoned', 'neglect', 'starving', 'suffering',
          'cancer', 'tumor', 'disease', 'infection', 'parasite',
          'warning', 'graphic', 'disturbing', 'heartbreaking',
          'last', 'goodbye', 'memorial', 'memory of', 'in loving memory',
        ];

        // Skip if title contains blacklisted terms
        if (blacklist.any((term) => title.contains(term))) return false;
        if (blacklist.any((term) => description.contains(term))) return false;

        // Additional check for potentially sad content indicators
        final sadIndicators = ['😢', '😭', '💔', '😿', '🙏'];
        if (sadIndicators.any((emoji) => title.contains(emoji))) return false;

        // Skip channels that are likely to post concerning content
        if (channelTitle.contains('rescue') ||
            channelTitle.contains('vet') ||
            channelTitle.contains('emergency') ||
            channelTitle.contains('shelter')) return false;

        // Skip if title is ALL CAPS (usually clickbait)
        if (title == title.toUpperCase() && title.contains(' ')) return false;

        // Skip if title has too many emojis (usually clickbait)
        final emojiCount = RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true)
            .allMatches(title)
            .length;
        if (emojiCount > 3) return false;

        // Must contain happy/positive cat-related terms
        final catTerms = ['cat', 'kitten', 'kitty'];
        final hasPositiveTerms = [
          'playing', 'happy', 'cute', 'funny', 'adorable', 'sweet',
          'playful', 'loving', 'sleepy', 'cozy', 'comfy', 'purring'
        ].any((term) => title.contains(term) || description.contains(term));

        return catTerms.any((term) => 
          title.contains(term) || description.contains(term)
        ) && hasPositiveTerms;
      }).toList();

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
    // Happy cat behaviors only
    final searchTypes = [
      {'query': '#shorts happy cat purring', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts playful cat toys', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts sleepy cat napping', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat playing string', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat cuddles love', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat toe beans', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat loaf relaxing', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat stretching yawn', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat making biscuits', 'tags': <String>['cat', 'kitten']},
      {'query': '#shorts cat box sitting', 'tags': <String>['cat', 'kitten']},
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