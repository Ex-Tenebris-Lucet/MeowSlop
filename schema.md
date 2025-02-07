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

-- Disable RLS
alter table profiles disable row level security;
alter table media_items disable row level security;
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