$headers = @{
    "Authorization" = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppbnVuZnV0ZGJlZ2F6dm9qZGF3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczODkzODIzNCwiZXhwIjoyMDU0NTE0MjM0fQ.6P_TpsbRi_g6Ll5wZvspka6AoEvDrE0d-gTy46vuJMg"
    "Content-Type" = "application/json"
}

$body = '{"batchProcess": true}'
$uri = "https://zinunfutdbegazvojdaw.functions.supabase.co/video-analysis"

Write-Host "Sending request to process untagged videos..."
$response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body
Write-Host "Response received:"
$response.Content 