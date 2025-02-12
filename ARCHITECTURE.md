# ReelAI Architecture Overview

## Dependencies
video_player: ^2.8.1
video_compress: ^3.1.2
supabase_flutter: ^1.10.25
visibility_detector: ^0.4.0+2
image_picker: ^1.0.4

## Critical Constraints
- Short videos (<10MB, few seconds)
- Mobile-first, performance critical
- Clean up resources aggressively
- No global state/flags

## Core Patterns

### Feed
Load: 10 initial -> Show -> Load 5 more near end
View: Current visible + Next 2 preloaded
State: Derive from data, not flags
Clean: Dispose when out of view

### Video
Upload: Raw -> Compress -> Thumbnail -> S3 -> DB
Play: Preload -> Init -> Play -> Clean
Errors: Fail fast, clear messages, auto-recover
Preload: Next 2 videos -> Initialize controllers -> Clean old
State: Declarative (derived from visibility + overlay)

### Data Structure
Post {
  requires: creator_id -> Profile
  contains: storage_path -> S3
  optional: thumbnail_url
}

Profile {
  requires: id, username
  contains: posts[]
  optional: profile_pic_url
}

### Resource Rules
Videos:
- Load when needed
- Preload next 2 controllers
- Max 4 cached controllers
- Pause when < 50% visible or overlay shown
- Play when visible and no overlay
- Dispose non-preloaded on unmount

Images:
- Load on demand
- Use Flutter cache

### Key Functions
Video:
compress(raw) -> optimized
upload(video) -> {url, thumb}
preload(url) -> controller
cleanOldCache() -> void

Feed:
loadPosts(limit) -> posts[]
updateIndex(i) -> preload(i+1,i+2)

Profile:
getProfile(id) -> profile
updateProfile(data) -> profile

### Common Pitfalls
- Over-caching videos
- Complex state flags
- Manual visibility tracking
- Holding resources too long
- Multiple controllers for same URL
- Playing invisible videos
- Imperative state management

### Error Handling
Network -> Retry with backoff
Video -> Show error + retry
Upload -> Clean partials
Cache full -> Remove oldest

## Core Functionality

```plaintext
User Flow:
1. Open App -> Splash Screen -> Feed Screen
2. Scroll through short-form videos/images
3. Tap to play/pause video
4. Navigate to profiles
5. Login/Upload content if authenticated

Content Flow:
Video -> Compress -> Generate Thumbnail -> Upload to S3 -> Store in Supabase -> Feed

Feed Mechanics:
- Vertical scrolling with snap behavior
- Load 10 initial posts
- Load 5 more when near end
- Simple preload next 2 videos
```

## Key Components

### Screens
- **Feed Screen**
  - Main content viewer
  - Handles post loading/pagination
  - Manages UI overlay
  - Navigation to profiles/login

- **Profile Screen**
  - View/edit profile
  - Manage posts
  - Follow/unfollow users
  - Upload new content

### Core Services
- **Video Service**
  - Compression
  - Thumbnail generation
  - Upload management
  - Basic caching

- **Auth Service**
  - User authentication
  - Profile management
  - Post management
  - Follow/unfollow

### Core Functions

#### Video Management
- `compressVideo`: Optimize video for storage/playback
- `generateThumbnail`: Create preview image from video
- `uploadVideo`: Handle video upload with progress
- `preloadVideo`: Cache next videos for smooth playback
- `deleteVideo`: Clean up video and thumbnail

#### Feed Management
- `loadInitialPosts`: Get first batch of content
- `loadMorePosts`: Pagination for infinite scroll
- `updateCurrentIndex`: Track current post position
- `toggleOverlay`: Show/hide UI elements

#### Profile Management
- `getProfile`: Fetch user profile data
- `updateProfile`: Modify user information
- `getUserPosts`: Get posts by user
- `followUser`/`unfollowUser`: Social connections
- `uploadProfilePicture`: Update avatar

#### Authentication
- `isLoggedIn`: Check auth status
- `login`/`logout`: Handle user sessions
- `getRandomPosts`: Feed content for any user

### Data Flow
```plaintext
Post Creation:
User -> Select Video -> Compress -> Generate Thumbnail -> Upload -> Database

Post Viewing:
Database -> Load Posts -> Display in Feed -> Preload Next Videos

Profile:
User -> Auth Check -> Load Profile Data -> Display/Edit
```

### Core Data Types
```plaintext
Post:
  - Basic: id, creator_id, media_type, created_at
  - Media: storage_path, thumbnail_url
  - Relations: profile (creator info)

Profile:
  - Identity: id, username, created_at
  - Social: follower_count, following_count
  - Media: profile_pic_url, posts

VideoFile:
  - Source: raw video from user
  - Processed: compressed video, thumbnail
  - Upload: video_url, thumbnail_url
```

### State Management
- Keep it simple
- Minimize flags/global state
- Use widget lifecycle
- Let Flutter handle visibility
- Derive state from data when possible

### Performance Considerations
- Preload next 2 videos only
- Basic caching for current session
- Clean up resources on dispose
- Minimize unnecessary rebuilds

## Development Guidelines
1. Avoid complex state management
2. No premature optimization
3. Let platform handle what it's good at
4. Keep dependencies minimal
5. Fail gracefully, recover automatically
6. Clear error messages for users

## Testing Strategy
- Unit tests for services
- Widget tests for core components
- Integration tests for main flows
- Manual testing for video playback

## Future Considerations
- Progressive loading for slow connections
- Better error recovery
- Smarter preloading based on usage patterns
- Analytics for user behavior 