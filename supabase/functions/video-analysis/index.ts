// videoAnalysis.ts edge function
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { RekognitionClient, StartLabelDetectionCommand, GetLabelDetectionCommand } from "npm:@aws-sdk/client-rekognition";

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

const rekognition = new RekognitionClient({
  region: Deno.env.get('AWS_REGION')!,
  credentials: {
    accessKeyId: Deno.env.get('AWS_ACCESS_KEY_ID')!,
    secretAccessKey: Deno.env.get('AWS_SECRET_ACCESS_KEY')!
  }
});

async function startAnalysis(bucket: string, videoKey: string) {
  try {
    const startCommand = new StartLabelDetectionCommand({
      Video: { 
        S3Object: { 
          Bucket: bucket, 
          Name: videoKey 
        } 
      },
      MinConfidence: 70  // Only return labels with 70%+ confidence
    });
    
    const { JobId } = await rekognition.send(startCommand);
    return JobId;
  } catch (error) {
    console.error('Error starting video analysis:', error);
    throw error;
  }
}

async function getResults(jobId: string) {
  try {
    const getCommand = new GetLabelDetectionCommand({
      JobId: jobId
    });
    
    const response = await rekognition.send(getCommand);
    return response.Labels;
  } catch (error) {
    console.error('Error getting video analysis results:', error);
    throw error;
  }
}

async function pollForCompletion(jobId: string, maxAttempts = 10) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const getCommand = new GetLabelDetectionCommand({ JobId: jobId });
    const response = await rekognition.send(getCommand);
    
    if (response.JobStatus === 'SUCCEEDED') {
      return response.Labels;
    }
    
    if (response.JobStatus === 'FAILED') {
      throw new Error('Video analysis failed');
    }
    
    // Exponential backoff
    await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
  }
  
  throw new Error('Timeout waiting for video analysis');
}

async function processLabels(labels: any[]) {
  const uniqueTags = new Set<string>();
  
  labels.forEach(item => {
    if (item.Label?.Name) {
      uniqueTags.add(item.Label.Name.toLowerCase());
    }
  });

  const tagIds = [];
  
  // Process each unique tag
  for (const tagName of uniqueTags) {
    // Try to insert the tag first
    const { data: insertedTag, error: insertError } = await supabase
      .from('tags')
      .upsert({ name: tagName })
      .select('id')
      .single();
      
    if (insertError) {
      console.error(`Error upserting tag ${tagName}:`, insertError);
      continue;
    }
    
    tagIds.push(insertedTag.id);
  }
  
  return tagIds;
}

async function tagSingleMedia(mediaId: string) {
  try {
    // Get media info from database
    const { data: mediaItem, error } = await supabase
      .from('media_items')
      .select('*')
      .eq('id', mediaId)
      .single();
    
    if (error || !mediaItem) throw new Error('Media not found');

    // Skip if already analyzed
    const { data: existingTags } = await supabase
      .from('media_item_tags')
      .select('tag_id')
      .eq('media_item_id', mediaId);
    
    if (existingTags?.length > 0) {
      console.log(`Media ${mediaId} already tagged, skipping`);
      return { skipped: true };
    }

    // Extract S3 info from storage_path
    const url = new URL(mediaItem.storage_path);
    const bucket = url.hostname.split('.')[0];
    const videoKey = url.pathname.substring(1); // Remove leading slash

    // Start Rekognition job
    const jobId = await startAnalysis(bucket, videoKey);
    const labels = await pollForCompletion(jobId);
    const tagIds = await processLabels(labels);
    
    // Create media_item_tags entries
    const mediaItemTags = tagIds.map(tagId => ({
      media_item_id: mediaId,
      tag_id: tagId
    }));
    
    const { error: tagLinkError } = await supabase
      .from('media_item_tags')
      .insert(mediaItemTags);
      
    if (tagLinkError) {
      throw new Error(`Failed to link tags: ${tagLinkError.message}`);
    }

    return { 
      success: true, 
      mediaId, 
      tagCount: tagIds.length 
    };
  } catch (error) {
    console.error(`Error tagging media ${mediaId}:`, error);
    return { error: error.message, mediaId };
  }
}

// Main handler
serve(async (req) => {
  try {
    const { mediaId, batchProcess } = await req.json();

    if (batchProcess) {
      // Get all untagged media
      const { data: untaggedMedia } = await supabase
        .from('media_items')
        .select('id')
        .not('id', 'in', (
          supabase.from('media_item_tags')
            .select('media_item_id')
        ));

      const results = [];
      for (const item of untaggedMedia || []) {
        results.push(await tagSingleMedia(item.id));
        // Small delay to avoid rate limits
        await new Promise(r => setTimeout(r, 1000));
      }

      return new Response(
        JSON.stringify({ success: true, results }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    } else {
      // Tag single media
      const result = await tagSingleMedia(mediaId);
      return new Response(
        JSON.stringify(result),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
