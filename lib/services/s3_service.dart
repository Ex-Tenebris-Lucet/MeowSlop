import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class S3Service {
  static final S3Service _instance = S3Service._internal();
  factory S3Service() => _instance;
  S3Service._internal();

  // Single bucket name
  static const String bucket = 'meowslop';

  // Path prefixes for different types of content
  static const String videoPath = 'videos';
  static const String thumbnailPath = 'thumbnails';
  static const String profilePath = 'profiles';
  static const String mediaPath = 'media';

  // AWS configuration
  String? _awsRegion;
  String? _awsAccessKeyId;
  String? _awsSecretKey;

  bool _isInitialized = false;
  bool _isCancelled = false;
  double _uploadProgress = 0.0;

  double get uploadProgress => _uploadProgress;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load AWS credentials from .env
      await dotenv.load();
      final region = dotenv.env['AWS_REGION']?.trim();
      final accessKeyId = dotenv.env['AWS_ACCESS_KEY_ID']?.trim();
      final secretKey = dotenv.env['AWS_SECRET_ACCESS_KEY']?.trim();

      debugPrint('AWS Configuration:');
      debugPrint('- Region: $region');
      debugPrint('- Access Key ID: ${accessKeyId?.substring(0, 5)}...');
      debugPrint('- Secret Key: ${secretKey?.substring(0, 5)}...');

      if (region == null || region.isEmpty || 
          accessKeyId == null || accessKeyId.isEmpty || 
          secretKey == null || secretKey.isEmpty) {
        throw Exception('AWS credentials not properly configured in .env file');
      }

      _awsRegion = region;
      _awsAccessKeyId = accessKeyId;
      _awsSecretKey = secretKey;
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing S3 service: $e');
      rethrow;
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  void cancelUpload() {
    _isCancelled = true;
  }

  void _resetCancellation() {
    _isCancelled = false;
  }

  Map<String, String> _getSignedHeaders(
    String method,
    String bucket,
    String key,
    Map<String, String> headers,
    [Uint8List? payload]
  ) {
    if (!_isInitialized || _awsRegion == null || _awsAccessKeyId == null || _awsSecretKey == null) {
      throw Exception('S3 service not properly initialized');
    }

    final awsRegion = _awsRegion!;  // Safe to force unwrap after null check
    final awsAccessKeyId = _awsAccessKeyId!;
    final awsSecretKey = _awsSecretKey!;

    debugPrint('\nGenerating signed headers for S3 request:');
    debugPrint('Method: $method');
    debugPrint('Bucket: $bucket');
    debugPrint('Key: $key');
    debugPrint('Original headers: $headers');

    final timestamp = DateTime.now().toUtc();
    final dateStamp = timestamp.toIso8601String().split('T')[0].replaceAll('-', '');
    final amzDate = '${dateStamp}T${timestamp.toIso8601String().split('T')[1].split('.')[0].replaceAll(':', '')}Z';

    debugPrint('\nTimestamp info:');
    debugPrint('Date stamp: $dateStamp');
    debugPrint('AMZ date: $amzDate');

    final host = '$bucket.s3.$awsRegion.amazonaws.com';
    final payloadHash = payload != null 
      ? sha256.convert(payload).toString()
      : 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; // empty payload hash

    debugPrint('\nRequest details:');
    debugPrint('Host: $host');
    debugPrint('Payload hash: $payloadHash');

    final signedHeaders = {
      'Host': host,
      'X-Amz-Date': amzDate,
      'X-Amz-Content-Sha256': payloadHash,
      ...headers,
    };

    // Sort headers by key for canonical request
    final sortedHeaders = Map.fromEntries(
      signedHeaders.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()))
    );

    debugPrint('\nSorted headers:');
    sortedHeaders.forEach((key, value) => debugPrint('$key: $value'));

    final canonicalHeaders = sortedHeaders.entries
      .map((e) => '${e.key.toLowerCase()}:${e.value.trim()}\n')
      .join();

    final signedHeadersList = sortedHeaders.keys
      .map((key) => key.toLowerCase())
      .toList();
    final signedHeadersString = signedHeadersList.join(';');

    debugPrint('\nCanonical headers:');
    debugPrint(canonicalHeaders);
    debugPrint('Signed headers string: $signedHeadersString');

    final canonicalUri = Uri.encodeFull('/$key');
    final canonicalQueryString = '';

    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeadersString,
      payloadHash,
    ].join('\n');

    debugPrint('\nCanonical request:');
    debugPrint(canonicalRequest);

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      '$dateStamp/$awsRegion/s3/aws4_request',
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    debugPrint('\nString to sign:');
    debugPrint(stringToSign);

    debugPrint('\nCalculating signing key...');
    // Calculate signing key
    final kDate = Hmac(sha256, utf8.encode('AWS4$awsSecretKey')).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(awsRegion)).bytes;
    final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
    final kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    
    final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();
    debugPrint('Signature: $signature');

    final authHeader = 'AWS4-HMAC-SHA256 '
      'Credential=$awsAccessKeyId/$dateStamp/$awsRegion/s3/aws4_request,'
      'SignedHeaders=$signedHeadersString,'
      'Signature=$signature';

    debugPrint('\nAuthorization header:');
    debugPrint(authHeader);

    final finalHeaders = {
      ...sortedHeaders,
      'Authorization': authHeader,
    };

    debugPrint('\nFinal headers:');
    finalHeaders.forEach((key, value) => debugPrint('$key: $value'));

    return finalHeaders;
  }

  Future<String> uploadFile({
    required String filePath,
    required String prefix,
    String? contentType,
    Function(double)? onProgress,
  }) async {
    _resetCancellation(); // Reset at start of new upload
    await _ensureInitialized();
    if (_isCancelled) throw Exception('Upload cancelled');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileName = path.basename(filePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final s3Key = '$prefix/$timestamp-$fileName';

    // Determine content type if not provided
    contentType ??= filePath.toLowerCase().endsWith('.png') 
        ? 'image/png'
        : filePath.toLowerCase().endsWith('.jpg') || filePath.toLowerCase().endsWith('.jpeg')
            ? 'image/jpeg'
            : filePath.toLowerCase().endsWith('.mp4')
                ? 'video/mp4'
                : 'application/octet-stream';

    try {
      debugPrint('\nStarting S3 upload:');
      debugPrint('- Bucket: $bucket');
      debugPrint('- Region: $_awsRegion');
      debugPrint('- Key: $s3Key');
      debugPrint('- File size: ${await file.length()} bytes');

      // Read file as bytes
      final bytes = await file.readAsBytes();
      
      // Prepare headers
      final headers = <String, String>{
        'Content-Length': bytes.length.toString(),
        if (contentType != null) 'Content-Type': contentType,
      };

      // Sign the request
      final signedHeaders = _getSignedHeaders('PUT', bucket, s3Key, headers, bytes);

      // Send the request
      final uri = Uri.parse('https://$bucket.s3.$_awsRegion.amazonaws.com/$s3Key');
      debugPrint('\nSending PUT request to: $uri');
      
      final response = await http.put(
        uri,
        headers: signedHeaders,
        body: bytes,
      );
      
      debugPrint('\nResponse status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');
      
      if (response.statusCode != 200) {
        throw Exception('Upload failed with status ${response.statusCode}');
      }

      // Construct the S3 URL
      final url = uri.toString();
      
      // Wait for file to be available with retries
      final exists = await _waitForFileExistence(url);
      if (!exists) {
        debugPrint('Warning: File uploaded but not immediately available. URL: $url');
        // Don't throw an error, just return the URL since upload was successful
      }

      debugPrint('Upload successful. URL: $url');
      return url;
    } catch (e, stackTrace) {
      debugPrint('Error uploading file to S3:');
      debugPrint('- Error: $e');
      debugPrint('- Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<String> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String prefix,
    String? contentType,
    Function(double)? onProgress,
  }) async {
    _resetCancellation(); // Reset at start of new upload
    await _ensureInitialized();
    if (_isCancelled) throw Exception('Upload cancelled');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final s3Key = '$prefix/$timestamp-$fileName';

    try {
      debugPrint('\nStarting S3 upload from bytes:');
      debugPrint('- Bucket: $bucket');
      debugPrint('- Region: $_awsRegion');
      debugPrint('- Key: $s3Key');
      debugPrint('- Size: ${bytes.length} bytes');
      
      // Prepare headers
      final headers = <String, String>{
        'Content-Length': bytes.length.toString(),
        if (contentType != null) 'Content-Type': contentType,
        'x-amz-acl': 'public-read',  // Make the object publicly readable
      };

      // Sign the request
      final signedHeaders = _getSignedHeaders('PUT', bucket, s3Key, headers, bytes);

      // Send the request
      final uri = Uri.parse('https://$bucket.s3.$_awsRegion.amazonaws.com/$s3Key');
      debugPrint('\nSending PUT request to: $uri');
      
      final response = await http.put(
        uri,
        headers: signedHeaders,
        body: bytes,
      );
      
      debugPrint('\nResponse status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');
      
      if (response.statusCode != 200) {
        throw Exception('Upload failed with status ${response.statusCode}');
      }

      // Construct the S3 URL
      final url = uri.toString();
      
      // Wait for file to be available with retries
      final exists = await _waitForFileExistence(url);
      if (!exists) {
        debugPrint('Warning: File uploaded but not immediately available. URL: $url');
        // Don't throw an error, just return the URL since upload was successful
      }

      debugPrint('Upload successful. URL: $url');
      return url;
    } catch (e, stackTrace) {
      debugPrint('Error uploading bytes to S3:');
      debugPrint('- Error: $e');
      debugPrint('- Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<Map<String, String>> getFileMetadata(String url) async {
    await _ensureInitialized();

    try {
      final uri = Uri.parse(url);
      final bucket = uri.host.split('.')[0];
      final key = uri.path.substring(1);
      
      // Sign the request
      final signedHeaders = _getSignedHeaders('HEAD', bucket, key, {});

      // Send the request
      final response = await http.head(
        uri,
        headers: signedHeaders,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to get metadata with status ${response.statusCode}');
      }

      return response.headers;
    } catch (e) {
      debugPrint('Error getting file metadata from S3: $e');
      rethrow;
    }
  }

  Future<void> deleteFile(String url) async {
    await _ensureInitialized();

    try {
      final uri = Uri.parse(url);
      final bucket = uri.host.split('.')[0];
      final key = uri.path.substring(1);
      
      // Sign the request with proper headers
      final headers = {
        'x-amz-acl': 'public-read',
      };
      final signedHeaders = _getSignedHeaders('DELETE', bucket, key, headers);

      // Send the request
      final response = await http.delete(
        uri,
        headers: signedHeaders,
      );
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        debugPrint('Delete failed with status ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        throw Exception('Delete failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error deleting file from S3: $e');
      rethrow;
    }
  }

  Future<bool> doesFileExist(String url) async {
    await _ensureInitialized();

    try {
      final uri = Uri.parse(url);
      final bucket = uri.host.split('.')[0];
      final key = uri.path.substring(1);
      
      // Sign the request
      final signedHeaders = _getSignedHeaders('HEAD', bucket, key, {});

      // Send the request
      final response = await http.head(
        uri,
        headers: signedHeaders,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error checking file existence in S3: $e');
      return false;
    }
  }

  Future<bool> _waitForFileExistence(String url, {int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final exists = await doesFileExist(url);
      if (exists) return true;
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 1 * attempt)); // Exponential backoff
      }
    }
    return false;
  }
} 