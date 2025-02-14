import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

// Custom track shape for center-based slider coloring
class CenterBasedTrackShape extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final Canvas canvas = context.canvas;

    // Calculate the center point
    final double trackHeight = sliderTheme.trackHeight ?? 4;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    final double trackCenter = trackWidth / 2;
    
    // Create track paint
    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.green;
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.red.withOpacity(0.3);
    
    // Calculate thumb position relative to center
    final double thumbPosition = thumbCenter.dx - trackLeft;
    final double centerPosition = trackLeft + trackCenter;
    
    // Draw the tracks
    if (thumbPosition >= centerPosition) {
      // Positive value (green track)
      canvas.drawRect(
        Rect.fromLTWH(centerPosition, trackTop, thumbPosition - centerPosition, trackHeight),
        activePaint,
      );
      // Draw inactive left side
      canvas.drawRect(
        Rect.fromLTWH(trackLeft, trackTop, centerPosition - trackLeft, trackHeight),
        inactivePaint,
      );
    } else {
      // Negative value (red track)
      canvas.drawRect(
        Rect.fromLTWH(thumbPosition, trackTop, centerPosition - thumbPosition, trackHeight),
        inactivePaint,
      );
      // Draw inactive right side
      canvas.drawRect(
        Rect.fromLTWH(centerPosition, trackTop, trackWidth - centerPosition, trackHeight),
        Paint()..color = Colors.grey[800] ?? Colors.grey,
      );
    }
  }
}

class TagPreferencesScreen extends StatefulWidget {
  const TagPreferencesScreen({super.key});

  @override
  State<TagPreferencesScreen> createState() => _TagPreferencesScreenState();
}

class _TagPreferencesScreenState extends State<TagPreferencesScreen> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();
  List<Map<String, dynamic>> _userTags = [];
  bool _isLoading = true;
  bool _sortByPositive = true;

  @override
  void initState() {
    super.initState();
    _loadUserTags();
  }

  Future<void> _loadUserTags() async {
    try {
      setState(() => _isLoading = true);
      
      final profile = await _authService.getProfile();
      final userId = profile?['id'] as String?;
      
      if (userId == null) {
        setState(() {
          _userTags = [];
          _isLoading = false;
        });
        return;
      }

      // First get the tag affinities - handle any response type
      var affinities = [];
      try {
        final affinityResponse = await _supabase
          .from('tag_affinities')
          .select('tag_id, affinity_score')
          .eq('user_id', userId);
        
        // Handle both response object and direct list cases
        affinities = affinityResponse is List ? affinityResponse : 
                    affinityResponse?.data is List ? affinityResponse.data : [];
      } catch (e) {
        // If anything goes wrong, just treat it as empty
        affinities = [];
      }

      if (affinities.isEmpty) {
        setState(() {
          _userTags = [];
          _isLoading = false;
        });
        return;
      }

      // Then get the tag names
      final tagIds = affinities.map((a) => a['tag_id']).toList();
      
      if (tagIds.isEmpty) {
        setState(() {
          _userTags = [];
          _isLoading = false;
        });
        return;
      }

      var tags = [];
      try {
        final tagsResponse = await _supabase
          .from('tags')
          .select('id, name')
          .in_('id', tagIds);
        
        // Handle both response object and direct list cases
        tags = tagsResponse is List ? tagsResponse :
              tagsResponse?.data is List ? tagsResponse.data : [];
      } catch (e) {
        tags = [];
      }

      if (tags.isEmpty) {
        setState(() {
          _userTags = [];
          _isLoading = false;
        });
        return;
      }

      // Create a map of tag IDs to names
      final tagMap = Map.fromEntries(
        tags.map((t) => MapEntry(t['id'], t['name']))
      );

      setState(() {
        _userTags = affinities.map((item) => {
          'id': item['tag_id'],
          'name': tagMap[item['tag_id']] ?? 'Unknown Tag',
          'affinity_score': item['affinity_score'],
        }).toList();
        _sortTags();
      });
    } catch (e, stackTrace) {
      print('DEBUG: Error in _loadUserTags: $e');
      print('DEBUG: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tags: ${e.toString()}')),
        );
      }
      setState(() {
        _userTags = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _sortTags() {
    _userTags.sort((a, b) {
      if (_sortByPositive) {
        return (b['affinity_score'] as int).compareTo(a['affinity_score'] as int);
      } else {
        return (a['affinity_score'] as int).compareTo(b['affinity_score'] as int);
      }
    });
  }

  Future<void> _updateTagAffinity(String tagId, int score) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (score == 0) {
        // Delete the tag affinity if score is 0
        await _supabase
          .from('tag_affinities')
          .delete()
          .match({
            'user_id': userId,
            'tag_id': tagId,
          });

        setState(() {
          _userTags.removeWhere((tag) => tag['id'] == tagId);
        });
      } else {
        // Update the tag affinity
        await _supabase
          .from('tag_affinities')
          .upsert({
            'user_id': userId,
            'tag_id': tagId,
            'affinity_score': score,
          });

        setState(() {
          final tagIndex = _userTags.indexWhere((tag) => tag['id'] == tagId);
          if (tagIndex >= 0) {
            _userTags[tagIndex]['affinity_score'] = score;
            _sortTags();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating tag: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _showAddTagsSheet() async {
    final selectedTags = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddTagsSheet(),
    );

    if (selectedTags != null && selectedTags.isNotEmpty) {
      for (final tagId in selectedTags) {
        await _updateTagAffinity(tagId, 1);
      }
      await _loadUserTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Tag Preferences',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _sortByPositive ? Icons.arrow_downward : Icons.arrow_upward,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _sortByPositive = !_sortByPositive;
                _sortTags();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _showAddTagsSheet,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : _userTags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No tags yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddTagsSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Tags'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _userTags.length,
                  itemBuilder: (context, index) {
                    final tag = _userTags[index];
                    final score = tag['affinity_score'] as int;
                    final sliderColor = score > 0
                        ? Colors.green
                        : score < 0
                            ? Colors.red
                            : Colors.grey;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tag['name'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    activeTrackColor: score >= 0 ? Colors.green : Colors.red,
                                    inactiveTrackColor: score >= 0 ? Colors.grey[800] : Colors.red.withOpacity(0.3),
                                    thumbColor: sliderColor,
                                    overlayColor: sliderColor.withOpacity(0.2),
                                    trackHeight: 4,
                                    trackShape: CenterBasedTrackShape(),
                                  ),
                                  child: Slider(
                                    min: -100,
                                    max: 100,
                                    value: score.toDouble(),
                                    onChanged: (value) {
                                      setState(() {
                                        _userTags[index]['affinity_score'] = value.round();
                                      });
                                    },
                                    onChangeEnd: (value) {
                                      _updateTagAffinity(
                                        tag['id'] as String,
                                        value.round(),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  score.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: sliderColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class AddTagsSheet extends StatefulWidget {
  const AddTagsSheet({super.key});

  @override
  State<AddTagsSheet> createState() => _AddTagsSheetState();
}

class _AddTagsSheetState extends State<AddTagsSheet> {
  final _supabase = Supabase.instance.client;
  final _authService = AuthService();
  List<Map<String, dynamic>> _availableTags = [];
  final Set<String> _selectedTags = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableTags();
  }

  Future<void> _loadAvailableTags() async {
    try {
      setState(() => _isLoading = true);
      
      final profile = await _authService.getProfile();
      final userId = profile?['id'] as String?;
      
      if (userId == null) {
        setState(() {
          _availableTags = [];
          _isLoading = false;
        });
        return;
      }

      // Get all tags ordered by usage count
      var allTags = [];
      try {
        final tagsResponse = await _supabase
          .from('media_item_tags')
          .select('tag_id, tags(id, name)')
          .order('tag_id', ascending: false);
        
        // Handle both response object and direct list cases
        allTags = tagsResponse is List ? tagsResponse :
                  tagsResponse?.data is List ? tagsResponse.data : [];
      } catch (e) {
        allTags = [];
      }

      if (allTags.isEmpty) {
        setState(() {
          _availableTags = [];
          _isLoading = false;
        });
        return;
      }

      // Then get user's existing tag IDs
      var userTags = [];
      try {
        final userTagsResponse = await _supabase
          .from('tag_affinities')
          .select('tag_id')
          .eq('user_id', userId);

        // Handle both response object and direct list cases
        userTags = userTagsResponse is List ? userTagsResponse :
                   userTagsResponse?.data is List ? userTagsResponse.data : [];
      } catch (e) {
        userTags = [];
      }

      final existingTagIds = userTags.map((t) => t['tag_id'] as String).toSet();

      // Count tag usage
      final tagCounts = <String, int>{};
      for (final tag in allTags) {
        final tagId = tag['tag_id'] as String;
        tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
      }

      // Create unique tag list with counts
      final uniqueTags = <Map<String, dynamic>>{};
      for (final tag in allTags) {
        final tagData = tag['tags'] as Map<String, dynamic>;
        final tagId = tagData['id'] as String;
        if (!existingTagIds.contains(tagId)) {
          uniqueTags.add({
            'id': tagId,
            'name': tagData['name'],
            'count': tagCounts[tagId] ?? 0,
          });
        }
      }

      setState(() {
        _availableTags = uniqueTags.toList()
          ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      });
    } catch (e) {
      print('DEBUG: Error in _loadAvailableTags: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tags: ${e.toString()}')),
        );
      }
      setState(() {
        _availableTags = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Tags',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selectedTags),
                  child: Text(
                    'Done (${_selectedTags.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else if (_availableTags.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No more tags available',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _availableTags.length,
                itemBuilder: (context, index) {
                  final tag = _availableTags[index];
                  final isSelected = _selectedTags.contains(tag['id']);
                  
                  return ListTile(
                    title: Text(
                      tag['name'],
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.circle_outlined, color: Colors.white54),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedTags.remove(tag['id']);
                        } else {
                          _selectedTags.add(tag['id']);
                        }
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
} 