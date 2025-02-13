import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { createClient } from '@supabase/supabase-js';
import ffmpeg from 'fluent-ffmpeg';
import OpenAI from 'openai';
import type { ChatCompletionContentPart } from 'openai/resources/chat/completions';
import * as fs from 'fs';
import { promises as fsPromises } from 'fs';
import path from 'path';
import dotenv from 'dotenv';

// Load env vars
dotenv.config();

// Initialize clients
const s3 = new S3Client({
  region: process.env.AWS_REGION!,
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!
  }
});

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY!
});

// Create temp directory for our frames
const TEMP_DIR = path.join(process.cwd(), 'tmp');

async function ensureTempDir() {
  try {
    await fsPromises.mkdir(TEMP_DIR, { recursive: true });
  } catch (error) {
    console.error('Error creating temp directory:', error);
    throw error;
  }
}

async function downloadFromS3(bucket: string, key: string): Promise<string> {
  await ensureTempDir(); // Make sure temp directory exists
  const localPath = path.join(TEMP_DIR, path.basename(key));
  
  console.log(`Downloading from S3: s3://${bucket}/${key}`);
  console.log(`Saving to: ${localPath}`);
  
  try {
    const response = await s3.send(new GetObjectCommand({
      Bucket: bucket,
      Key: key
    }));

    if (!response.Body) throw new Error('No body in S3 response');
    
    console.log('S3 response received, content length:', response.ContentLength);

    const writeStream = fs.createWriteStream(localPath);
    await new Promise((resolve, reject) => {
      // @ts-ignore - TypeScript doesn't know about pipe
      response.Body.pipe(writeStream)
        .on('finish', () => {
          console.log('File write complete');
          resolve(null);
        })
        .on('error', (err: Error) => {
          console.error('Error writing file:', err);
          reject(err);
        });
    });

    // Verify the downloaded file
    const stats = await fsPromises.stat(localPath);
    console.log(`Downloaded file size: ${Math.round(stats.size / 1024)}KB`);
    
    return localPath;
  } catch (error) {
    console.error('Error downloading from S3:', error);
    throw error;
  }
}

async function extractFrames(videoPath: string): Promise<string[]> {
  const frameDir = path.join(TEMP_DIR, 'frames');
  await fsPromises.mkdir(frameDir, { recursive: true });
  
  // Verify video file exists and has content
  try {
    const stats = await fsPromises.stat(videoPath);
    if (stats.size === 0) {
      throw new Error('Video file is empty');
    }
  } catch (error) {
    console.error('Error checking video file:', error);
    throw error;
  }

  return new Promise((resolve, reject) => {
    console.log('Starting FFmpeg process...');
    const command = ffmpeg(videoPath)
      .outputOptions([
        '-vf', 'fps=1/2',     // One frame every 2 seconds
        '-vframes', '15',      // Maximum 15 frames
        '-q:v', '2'           // High quality (2-31, lower is better)
      ])
      .output(path.join(frameDir, 'frame-%03d.jpg'));

    command.on('end', async () => {
      try {
        const files = await fsPromises.readdir(frameDir);
        const framePaths = files.map(f => path.join(frameDir, f));
        console.log(`Extracted ${framePaths.length} frames`);
        resolve(framePaths);
      } catch (err) {
        console.error('Error reading frame directory:', err);
        resolve([]);
      }
    });

    command.on('error', (err) => {
      console.error('FFmpeg error:', err);
      reject(err);
    });

    command.run();
  });
}

async function analyzeFrames(framePaths: string[]): Promise<string[]> {
  const frameBase64s = await Promise.all(
    framePaths.map(async (path) => {
      const buffer = await fsPromises.readFile(path);
      return buffer.toString('base64');
    })
  );

  if (frameBase64s.length === 0) {
    console.error('No frames were extracted from the video');
    return [];
  }

  const messageContent: ChatCompletionContentPart[] = [
    { 
      type: "text", 
      text: "Analyze these video frames and generate descriptive tags. If you cannot see any images, please respond with 'NO_IMAGES_VISIBLE'. If you can see the images but they appear corrupted or unclear, respond with 'IMAGES_CORRUPTED'.\n\nIf you can see the images clearly, respond ONLY with relevant comma-separated tags. Tags can be single words or hyphenated phrases describing:\n- Specific actions or activities you see\n- Distinct objects, people, or animals\n- The actual environment and setting\n- Any clear emotions or mood\n- Significant events or changes between frames"
    },
    ...frameBase64s.map(base64 => ({
      type: "image_url" as const,
      image_url: {
        url: `data:image/jpeg;base64,${base64}`
      }
    }))
  ];

  const response = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      {
        role: "user",
        content: messageContent
      }
    ],
    max_tokens: 500
  });

  const responseText = response.choices[0].message.content?.trim() || '';
  
  if (!responseText || responseText === 'NO_IMAGES_VISIBLE' || responseText === 'IMAGES_CORRUPTED') {
    console.error('Failed to analyze frames:', responseText || 'No response');
    return [];
  }

  return responseText
    .split(',')
    .map((tag: string) => tag.trim().toLowerCase())
    .filter((tag: string) => /^[a-z]+(-[a-z]+)*$/.test(tag));
}

async function processVideo(mediaId: string) {
  try {
    console.log(`\nStarting to process video ${mediaId}`);
    const { data: mediaItem, error: mediaError } = await supabase
      .from('media_items')
      .select(`*, media_item_tags(tag_id, tags(name))`)
      .eq('id', mediaId)
      .single();
    
    if (mediaError || !mediaItem) {
      console.log('Media not found:', mediaError);
      throw new Error('Media not found');
    }

    if (mediaItem.media_item_tags?.length > 0) {
      console.log(`Skipping video ${mediaId} - already has ${mediaItem.media_item_tags.length} tags`);
      return { skipped: true, reason: 'already_tagged' };
    }

    console.log('Media item found:', {
      id: mediaItem.id,
      path: mediaItem.storage_path,
      type: mediaItem.media_type
    });

    const url = new URL(mediaItem.storage_path);
    const bucket = url.hostname.split('.')[0];
    const videoKey = decodeURIComponent(url.pathname.substring(1));

    console.log('Downloading from bucket:', bucket);
    console.log('Video key:', videoKey);

    const videoPath = await downloadFromS3(bucket, videoKey);
    const framePaths = await extractFrames(videoPath);
    const tags = await analyzeFrames(framePaths);

    console.log('\nRaw tags from model:', tags);
    let successfulTags = 0;

    for (const tagName of tags) {
      console.log(`\nProcessing tag: "${tagName}"`);
      const { data: insertedTag, error: insertError } = await supabase
        .from('tags')
        .upsert({ name: tagName })
        .select('id')
        .single();
        
      if (insertError) {
        console.error('Error upserting tag:', insertError);
        continue;
      }
      if (!insertedTag) {
        console.error('No tag ID returned from upsert');
        continue;
      }
      
      const { error: linkError } = await supabase
        .from('media_item_tags')
        .insert({
          media_item_id: mediaId,
          tag_id: insertedTag.id
        });

      if (linkError) {
        console.error('Error linking tag:', linkError);
      } else {
        successfulTags++;
        console.log(`Successfully added tag: "${tagName}" (${successfulTags}/${tags.length})`);
      }
    }

    // Cleanup
    await fsPromises.rm(videoPath);
    await Promise.all(framePaths.map(p => fsPromises.rm(p)));

    return { success: true, mediaId, tagCount: successfulTags, tags };
  } catch (error) {
    console.error(`Error processing video ${mediaId}:`, error);
    return { error: error instanceof Error ? error.message : String(error), mediaId };
  }
}

async function processBatch(limit: number = 1) {
  try {
    console.log('\nQuerying for untagged videos...');
    // First get all video IDs that have tags
    const { data: taggedIds } = await supabase
      .from('media_item_tags')
      .select('media_item_id');

    const taggedIdSet = new Set(taggedIds?.map(t => t.media_item_id) || []);
    
    // Then get videos that aren't in that set
    const { data: untaggedMedia, error } = await supabase
      .from('media_items')
      .select('id, storage_path')
      .eq('media_type', 'video')
      .filter('id', 'not.in', `(${Array.from(taggedIdSet).join(',')})`)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.error('Query error:', error);
      throw error;
    }
    
    console.log('\nFound untagged videos:', untaggedMedia?.length || 0);
    if (untaggedMedia && untaggedMedia.length > 0) {
      console.log('First untagged video:', {
        id: untaggedMedia[0].id,
        path: untaggedMedia[0].storage_path
      });
    }

    const results = [];
    for (const item of untaggedMedia || []) {
      console.log(`\nProcessing video ${item.id} (${item.storage_path})...`);
      results.push(await processVideo(item.id));
      await new Promise(r => setTimeout(r, 1000));
    }

    return results;
  } catch (error) {
    console.error('Error in batch processing:', error);
    throw error;
  } finally {
    // Final cleanup
    try {
      await fsPromises.rm(TEMP_DIR, { recursive: true, force: true });
    } catch (error) {
      console.error('Error cleaning up temp directory:', error);
    }
  }
}

// Run it!
processBatch()
  .then(results => {
    console.log('\nBatch processing complete!');
    console.log(JSON.stringify(results, null, 2));
  })
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  }); 