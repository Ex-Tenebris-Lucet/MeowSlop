# Tag-Based Recommendation System

## Phase 1: View Time Tracking

### Database Schema Additions
```sql
-- Simplified initial version
CREATE TABLE tag_affinities (
    user_id UUID REFERENCES auth.users(id),
    tag_id UUID REFERENCES tags(id),
    affinity_score INTEGER DEFAULT 0,  -- Simple integer score, easier to reason about
    PRIMARY KEY (user_id, tag_id)  -- No need for separate id, this is a natural key
);


-- Create indexes for performance
CREATE INDEX idx_tag_affinities_user ON tag_affinities(user_id);
CREATE INDEX idx_tag_affinities_score ON tag_affinities(affinity_score DESC);
```

### Implementation Steps
1. Modify VideoPlayerWidget to track:
   - Time spent watching
   - Whether video was completed
   - Skip events
   - Rewatch events

2. Create ViewTimeService to:
   - Buffer view events locally
   - Batch upload to Supabase periodically
   - Handle offline/online state

## Phase 2: Tag Affinity Calculation

### Core Algorithm
1. For each view record:
   - Base score = view_seconds / total_length
   - Multipliers:
     - Completed video: 1.5x
     - Rewatched: 2x
     - Skipped quickly: -0.5x

2. For each tag on viewed content:
   - Distribute view score across tags
   - Weight recent views higher
   - Decay old affinity scores gradually

### Implementation
1. Create Edge Function for affinity updates:
   ```typescript
   // Run periodically or on view record updates
   function updateTagAffinities(userId: string) {
     // Get recent view records
     // Calculate scores per tag
     // Update tag_affinities table
     // Apply time decay to old scores
   }
   ```

2. Create AffinityService in app for:
   - Caching user affinities
   - Predicting interest in new content
   - Suggesting tags for content creation

## Phase 3: Feed Customization

### Ranking Algorithm
1. For each potential feed item:
   ```typescript
   score = baseScore + 
          (tagAffinitySum * 0.4) +
          (freshness * 0.3) +
          (popularity * 0.2) +
          (random * 0.1)
   ```

2. Implementation:
   - Modify FeedService to use scores
   - Add weighted randomness
   - Keep some diversity in recommendations
   - Cache scores for performance

### UI Updates
1. Add feedback mechanisms:
   - "More like this" button
   - "Not interested" option
   - Tag-based filters

## Phase 4: AI Content Generation

### Tag-Based Generation
1. Create generation service:
   ```typescript
   interface GenerationPrompt {
     preferredTags: string[];
     styleReference: string;
     targetLength: number;
   }
   ```

2. Implementation steps:
   - Use top affinity tags as prompts
   - Reference highly-viewed content
   - Start with image generation
   - Expand to short video clips
   - Add style transfer options

### Content Pipeline
1. Generation flow:
   - Analyze user preferences
   - Generate content variations
   - Test with similar users
   - Refine based on feedback

2. Quality control:
   - Human review queue
   - Automated content filters
   - User reporting system

## Technical Considerations

### Performance
- Index heavily on user_id and created_at
- Partition view_records by time
- Cache affinity scores
- Batch process updates

### Privacy
- Allow opting out of tracking
- Clear data after set period
- Anonymize for analysis
- Local processing when possible

### Scaling
- Shard by user_id
- Cache aggressively
- Background processing
- Rate limit generations

## Future Enhancements
1. Collaborative filtering
2. Content clustering
3. A/B testing framework
4. Seasonal adjustments
5. Cross-user recommendations

## Success Metrics
- View time increases
- Return rate
- Content diversity
- Generation quality
- User satisfaction
