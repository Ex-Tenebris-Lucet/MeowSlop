# S3 Migration Audit & Action Plan

## 🚨 Critical Fixes (Do First)

1. **Remove Legacy Bucket References**
   - File: `lib/services/auth_service.dart`
   - Remove lines:
     ```dart
     static const String _profilePicsBucket = 'profile_pictures';
     static const String _postMediaBucket = 'post_media';
     ```
   - All media should use `S3Service.bucket` with path prefixes

2. **Video Deletion CORS Policy**
   - Verify S3 bucket CORS configuration allows:
     ```xml
     <AllowedMethod>DELETE</AllowedMethod>
     ```

## 🔧 Important Corrections

3. **Content Type Handling**
   - File: `lib/services/s3_service.dart`
   - Update image uploads to be explicit:
     ```dart
     contentType: filePath.endsWith('.png') 
       ? 'image/png'
       : 'image/jpeg'
     ```

4. **URL Format Validation**
   - For non-standard AWS regions (e.g., us-east-2), confirm URL pattern:
     ```dart
     'https://${bucket}.s3.${_awsRegion}.amazonaws.com/$s3Key'
     ```

## 🛡️ Security Enhancements

5. **Signature Validation**
   - File: `lib/services/s3_service.dart`
   - Add empty payload verification:
     ```dart
     if (payload == null && bytes.isNotEmpty) {
       throw Exception('Payload mismatch');
     }
     ```

6. **Access Controls**
   - Add bucket policy requiring authenticated access for writes:
     ```json
     "Condition": {
       "StringEquals": {
         "aws:SecureTransport": "true"
       }
     }
     ```

## 🚀 Performance Improvements

7. **Cache Control Headers**
   - File: `lib/services/s3_service.dart`
   - Add to upload headers:
     ```dart
     'Cache-Control': 'public, max-age=31536000' // 1 year
     ```

8. **Upload Retry Logic**
   - Wrap HTTP calls in retry wrapper:
     ```dart
     Future<http.Response> _putWithRetry(Uri uri, Map<String,String> headers, Uint8List bytes) async {
       for (var i = 0; i < 3; i++) {
         try {
           return await http.put(uri, headers: headers, body: bytes)
             .timeout(Duration(seconds: 30));
         } catch (_) {
           if (i == 2) rethrow;
           await Future.delayed(Duration(seconds: 1 << i));
         }
       }
       throw Exception('Upload failed after retries');
     }
     ```

## 🔄 Architectural Considerations

9. **Pre-Signed URL Strategy**
   - Consider moving signature generation to backend:
   - Add endpoint: `POST /api/s3-signature` 
   - Returns pre-signed URL with short TTL

10. **Asset Versioning**
    - Add version parameter to filenames:
    ```dart
    final s3Key = '$prefix/$timestamp-${_fileVersion}-$fileName';
    ```
    - Helps bust CDN/proxy caches

## ✅ Validation Checklist

1. [ ] All media uses `meowslop` bucket with path prefixes
2. [ ] S3 CORS policy allows DELETE from app domains
3. [ ] Bucket policy requires authenticated writes
4. [ ] Content-Type headers match actual file types
5. [ ] Cache headers added to S3 uploads
6. [ ] Retry logic implemented for all S3 operations
7. [ ] Legacy bucket references removed from codebase
8. [ ] URL format validated against AWS region

## ⏭️ Recommended Implementation Order

1. Critical Fixes → Security → Performance → Architecture
