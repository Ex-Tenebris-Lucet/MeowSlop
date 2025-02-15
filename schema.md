# ReelAI Database Schema

## Overview
The application uses Supabase for both authentication and data storage. This schema outlines the database structure and relationships.

## SQL Setup

```sql
-- Create profiles table
create table if not exists profiles (
  id uuid primary key,  -- matches auth.user.id for logged in users
  username text unique,  -- null for anonymous users
  device_identifier text,  -- for anonymous users
  profile_pic_url text,  -- URL to profile picture in storage
  tagline text,  -- user's personal tagline/bio
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- Create media_items table
create table if not exists media_items (
  id uuid primary key default uuid_generate_v4(),
  title text,
  storage_path text not null,  -- path in storage bucket
  media_type text not null,  -- video, image, etc
  created_at timestamp with time zone default now(),
  owner_id uuid references profiles(id) not null
);

-- New tag system
create table if not exists tags (
    id uuid primary key default uuid_generate_v4(),
    name text not null unique,  -- Ensures each tag exists only once
);

create table if not exists media_item_tags (
    media_item_id uuid references media_items(id) on delete cascade,
    tag_id uuid references tags(id) on delete cascade,
    primary key (media_item_id, tag_id)  -- Ensures unique media-tag combinations
);

-- Add indexes for better query performance on tags
create index if not exists idx_media_item_tags_media_item on media_item_tags(media_item_id);
create index if not exists idx_media_item_tags_tag on media_item_tags(tag_id);
create index if not exists idx_tags_name on tags(name);

-- Create followers table for following functionality
create table if not exists followers (
  follower_id uuid references profiles(id) not null,
  following_id uuid references profiles(id) not null,
  created_at timestamp with time zone default now(),
  primary key (follower_id, following_id),  -- Ensures unique relationships
  check (follower_id != following_id)  -- Prevents self-following
);

-- Add indexes for better query performance
create index if not exists idx_followers_follower on followers(follower_id);
create index if not exists idx_followers_following on followers(following_id);

-- Disable RLS
alter table profiles disable row level security;
alter table media_items disable row level security;
alter table followers disable row level security;

-- Add follower count and following count to profiles for quick access
alter table profiles add column if not exists follower_count integer default 0;
alter table profiles add column if not exists following_count integer default 0;

-- Create function to update follower counts
create or replace function update_follower_counts()
returns trigger as $$
begin
  if (TG_OP = 'INSERT') then
    update profiles set follower_count = follower_count + 1 where id = NEW.following_id;
    update profiles set following_count = following_count + 1 where id = NEW.follower_id;
  elsif (TG_OP = 'DELETE') then
    update profiles set follower_count = follower_count - 1 where id = OLD.following_id;
    update profiles set following_count = following_count - 1 where id = OLD.follower_id;
  end if;
  return null;
end;
$$ language plpgsql;

-- Create trigger to maintain follower counts
create trigger update_follower_counts_trigger
after insert or delete on followers
for each row execute function update_follower_counts();

-- Tag affinity tracking for recommendations
DROP TABLE IF EXISTS tag_affinities;  -- Remove the old table first
CREATE TABLE tag_affinities (
    user_id UUID REFERENCES profiles(id),
    tag_id UUID REFERENCES tags(id),
    affinity_score SMALLINT DEFAULT 0,
    PRIMARY KEY (user_id, tag_id)
);

-- Indexes for performance
CREATE INDEX idx_tag_affinities_user ON tag_affinities(user_id);
CREATE INDEX idx_tag_affinities_score ON tag_affinities(affinity_score DESC);

-- DIS-Enable RLS
alter table tag_affinities disable row level security;

```

## Storage Buckets

### `media` Bucket
- Purpose: Stores user-uploaded media files
- Access: Public read/write
- URL Format: `https://[project-ref].supabase.co/storage/v1/object/public/media/[path]`

### `thumbnails` Bucket
- Purpose: Stores generated thumbnails
- Access: Public read/write
- URL Format: `https://[project-ref].supabase.co/storage/v1/object/public/thumbnails/[path]`

## Usage Patterns

### Anonymous Users
- Profile with `username = null`
- Can view public media
- Cannot upload content
- Device identifier tracks their session

### Authenticated Users
- Profile has non-null username
- Can upload and manage media
- Full access to their content

### Media Management
- Files stored in appropriate bucket
- Database stores only the storage path
- Thumbnails generated and stored separately