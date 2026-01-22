// lib/services/face_encoding_service.dart
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

class FaceEncodingService {
  static final FaceEncodingService _instance = FaceEncodingService._internal();
  factory FaceEncodingService() => _instance;
  FaceEncodingService._internal();

  // Store face encodings in memory and file
  Map<String, List<double>> _faceEncodings = {};
  Map<String, String> _userImages = {}; // user_id -> image_path
  Map<String, Map<String, dynamic>> _userFaceData = {}; // Enhanced user data storage

  // Initialize from saved encodings
  Future<void> initialize() async {
    await _loadEncodingsFromFile();
  }

  // Extract face features (enhanced algorithm)
  List<double> extractFaceFeatures(File imageFile) {
    try {
      final image = img.decodeImage(imageFile.readAsBytesSync())!;

      // Convert to grayscale
      final grayImage = img.grayscale(image);

      // Resize to standard size for consistent features
      final resized = img.copyResize(grayImage, width: 100, height: 100);

      // Extract enhanced LBP features
      return _extractEnhancedLBPFeatures(resized);
    } catch (e) {
      throw Exception('Face feature extraction failed: $e');
    }
  }

  // Enhanced LBP feature extraction with better normalization
  List<double> _extractEnhancedLBPFeatures(img.Image image) {
    List<double> features = [];

    // Divide image into 8x8 blocks
    const blockSize = 8;
    const gridX = 12; // 100/8 ≈ 12
    const gridY = 12;

    for (int by = 0; by < gridY; by++) {
      for (int bx = 0; bx < gridX; bx++) {
        final blockHistogram = _computeEnhancedLBPForBlock(image, bx, by, blockSize);
        features.addAll(blockHistogram);
      }
    }

    // Add global image features for better discrimination
    features.addAll(_computeGlobalFeatures(image));

    return features;
  }

  List<double> _computeEnhancedLBPForBlock(img.Image image, int blockX, int blockY, int blockSize) {
    final histogram = List<double>.filled(256, 0.0);
    int pixelCount = 0;

    final startX = blockX * blockSize;
    final startY = blockY * blockSize;
    final endX = min((blockX + 1) * blockSize, image.width - 1);
    final endY = min((blockY + 1) * blockSize, image.height - 1);

    // Process inner pixels to avoid boundary issues
    for (int y = startY + 1; y < endY - 1; y++) {
      for (int x = startX + 1; x < endX - 1; x++) {
        final lbpValue = _computeLBPValue(image, x, y);
        histogram[lbpValue]++;
        pixelCount++;
      }
    }

    // Normalize histogram with smoothing
    if (pixelCount > 0) {
      for (int i = 0; i < histogram.length; i++) {
        histogram[i] = (histogram[i] + 0.1) / (pixelCount + 0.1 * 256); // Laplace smoothing
      }
    }

    return histogram;
  }

  List<double> _computeGlobalFeatures(img.Image image) {
    List<double> globalFeatures = [];

    double sum = 0.0;
    double squaredSum = 0.0;
    int pixelCount = image.width * image.height;

    // Calculate mean and standard deviation
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final luminance = image.getPixel(x, y).luminance.toDouble();
        sum += luminance;
        squaredSum += luminance * luminance;
      }
    }

    final mean = sum / pixelCount;
    final variance = (squaredSum / pixelCount) - (mean * mean);
    final stdDev = sqrt(max(variance, 0.0));

    globalFeatures.add(mean / 255.0);    // Normalized mean
    globalFeatures.add(stdDev / 255.0);  // Normalized standard deviation

    return globalFeatures;
  }

  int _computeLBPValue(img.Image image, int x, int y) {
    final center = image.getPixel(x, y).luminance;
    int lbp = 0;

    // 3x3 neighborhood (8-point LBP)
    final neighbors = [
      image.getPixel(x-1, y-1).luminance, image.getPixel(x, y-1).luminance, image.getPixel(x+1, y-1).luminance,
      image.getPixel(x-1, y).luminance,                                   image.getPixel(x+1, y).luminance,
      image.getPixel(x-1, y+1).luminance, image.getPixel(x, y+1).luminance, image.getPixel(x+1, y+1).luminance,
    ];

    for (int i = 0; i < neighbors.length; i++) {
      if (neighbors[i] >= center) {
        lbp |= (1 << i);
      }
    }

    return lbp;
  }

  // Enhanced registration with multiple images
  Future<Map<String, dynamic>> registerFaceWithMultipleImages(String userId, List<File> imageFiles) async {
    try {
      if (imageFiles.isEmpty) {
        return {'success': false, 'error': 'No images provided'};
      }

      List<List<double>> allEncodings = [];
      List<String> savedImagePaths = [];

      // Process each image
      for (int i = 0; i < imageFiles.length; i++) {
        // Validate image quality before processing
        final isValid = await _validateImageQuality(imageFiles[i]);
        if (!isValid) {
          return {
            'success': false,
            'error': 'Image ${i + 1} quality is poor. Please ensure good lighting and clear face view.'
          };
        }

        final encoding = extractFaceFeatures(imageFiles[i]);
        allEncodings.add(encoding);

        // Save each image
        final appDir = await getApplicationDocumentsDirectory();
        final userDir = Directory('${appDir.path}/faces/$userId');
        await userDir.create(recursive: true);

        final imagePath = '${userDir.path}/face_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await imageFiles[i].copy(imagePath);
        savedImagePaths.add(imagePath);
      }

      // Calculate average encoding for better accuracy
      final averageEncoding = _calculateAverageEncoding(allEncodings);

      // Store in memory
      _faceEncodings[userId] = averageEncoding;
      _userImages[userId] = savedImagePaths.first;
      _userFaceData[userId] = {
        'encoding': averageEncoding,
        'all_encodings': allEncodings,
        'image_paths': savedImagePaths,
        'registered_at': DateTime.now().toIso8601String(),
        'feature_length': averageEncoding.length,
        'number_of_samples': imageFiles.length,
        'registration_quality': _calculateRegistrationQuality(allEncodings),
      };

      // Save to persistent storage
      await _saveEncodingsToFile();

      return {
        'success': true,
        'message': 'Face registered successfully with ${imageFiles.length} images',
        'user_id': userId,
        'feature_length': averageEncoding.length,
        'samples_count': imageFiles.length,
        'registration_quality': _userFaceData[userId]!['registration_quality'],
        'image_paths': savedImagePaths,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Registration failed: $e',
      };
    }
  }

  // Original single image registration (for backward compatibility)
  Future<Map<String, dynamic>> registerFace(String userId, File imageFile) async {
    return await registerFaceWithMultipleImages(userId, [imageFile]);
  }

  // Calculate average of multiple encodings
  List<double> _calculateAverageEncoding(List<List<double>> allEncodings) {
    if (allEncodings.isEmpty) return [];

    final int length = allEncodings.first.length;
    final List<double> average = List<double>.filled(length, 0.0);

    for (final encoding in allEncodings) {
      for (int i = 0; i < length; i++) {
        average[i] += encoding[i];
      }
    }

    for (int i = 0; i < length; i++) {
      average[i] /= allEncodings.length;
    }

    return average;
  }

  // Calculate registration quality based on encoding consistency
  double _calculateRegistrationQuality(List<List<double>> allEncodings) {
    if (allEncodings.length <= 1) return 0.5; // Default for single image

    double totalSimilarity = 0.0;
    int comparisonCount = 0;

    for (int i = 0; i < allEncodings.length; i++) {
      for (int j = i + 1; j < allEncodings.length; j++) {
        totalSimilarity += _cosineSimilarity(allEncodings[i], allEncodings[j]);
        comparisonCount++;
      }
    }

    return totalSimilarity / comparisonCount;
  }

  // Enhanced verification with better matching
  Future<Map<String, dynamic>> verifyFace(File imageFile) async {
    try {
      // Extract features from input image
      final liveEncoding = extractFaceFeatures(imageFile);

      double bestSimilarity = 0.0;
      String? matchedUserId;
      Map<String, double> allSimilarities = {};

      // Compare with all stored encodings
      for (final entry in _faceEncodings.entries) {
        final similarity = _cosineSimilarity(liveEncoding, entry.value);
        allSimilarities[entry.key] = similarity;

        // Use dynamic threshold based on registration quality
        final dynamicThreshold = _getDynamicThreshold(entry.key);

        if (similarity > bestSimilarity && similarity > dynamicThreshold) {
          bestSimilarity = similarity;
          matchedUserId = entry.key;
        }
      }

      final isMatch = matchedUserId != null;

      return {
        'success': true,
        'match': isMatch,
        'user_id': matchedUserId,
        'confidence': bestSimilarity,
        'all_similarities': allSimilarities,
        'threshold_used': _getDynamicThreshold(matchedUserId ?? ''),
        'feature_length': liveEncoding.length,
        'verification_timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Verification failed: $e',
        'match': false,
      };
    }
  }

  // Dynamic threshold based on registration quality
  double _getDynamicThreshold(String userId) {
    final userData = _userFaceData[userId];
    if (userData != null && userData['registration_quality'] != null) {
      final double quality = userData['registration_quality'];
      // Lower threshold for higher quality registrations
      if (quality > 0.8) return 0.55; // High quality
      if (quality > 0.6) return 0.58; // Medium quality
    }
    return 0.6; // Default threshold for low quality or unknown
  }

  // Image quality validation
  Future<bool> _validateImageQuality(File imageFile) async {
    try {
      final image = img.decodeImage(imageFile.readAsBytesSync())!;

      // Check image dimensions
      if (image.width < 100 || image.height < 100) {
        return false;
      }

      // Check brightness (simple luminance check)
      final grayImage = img.grayscale(image);
      double totalLuminance = 0;
      int pixelCount = 0;

      for (int y = 0; y < grayImage.height; y++) {
        for (int x = 0; x < grayImage.width; x++) {
          totalLuminance += grayImage.getPixel(x, y).luminance;
          pixelCount++;
        }
      }

      final averageLuminance = totalLuminance / pixelCount;

      // Acceptable luminance range (avoid too dark or too bright)
      return averageLuminance >= 40 && averageLuminance <= 200;
    } catch (e) {
      return false;
    }
  }

  // Public method for image quality validation
  Future<bool> validateImageQuality(File imageFile) async {
    return await _validateImageQuality(imageFile);
  }

  // Enhanced cosine similarity calculation
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return 0.0;
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0.0;

    final similarity = dotProduct / (sqrt(normA) * sqrt(normB));

    // Apply non-linear scaling to better separate matches from non-matches
    return _applySimilarityScaling(similarity);
  }

  // Non-linear scaling for better discrimination
  double _applySimilarityScaling(double similarity) {
    // Square the similarity to amplify differences
    return similarity * similarity;
  }

  // Enhanced save encodings to file
  Future<void> _saveEncodingsToFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final encodingsFile = File('${appDir.path}/face_encodings_enhanced.json');

      // Convert encodings to JSON-serializable format
      final encodingsData = {
        'encodings': _faceEncodings.map((key, value) => MapEntry(key, value)),
        'user_images': _userImages,
        'user_face_data': _userFaceData,
        'metadata': {
          'total_users': _faceEncodings.length,
          'created_at': DateTime.now().toIso8601String(),
          'version': '2.0.0',
          'algorithm': 'Enhanced_LBP',
        },
      };

      await encodingsFile.writeAsString(json.encode(encodingsData));
      print('Enhanced encodings saved to: ${encodingsFile.path}');
      print('Total users registered: ${_faceEncodings.length}');
    } catch (e) {
      print('Error saving encodings: $e');
    }
  }

  // Enhanced load encodings from file
  Future<void> _loadEncodingsFromFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Try to load enhanced version first, fall back to legacy
      final enhancedFile = File('${appDir.path}/face_encodings_enhanced.json');
      final legacyFile = File('${appDir.path}/encodings.json');

      File encodingsFile;
      if (await enhancedFile.exists()) {
        encodingsFile = enhancedFile;
        print('Loading enhanced face encodings...');
      } else if (await legacyFile.exists()) {
        encodingsFile = legacyFile;
        print('Loading legacy face encodings...');
      } else {
        print('No existing face encodings file found');
        return;
      }

      final data = json.decode(await encodingsFile.readAsString());

      _faceEncodings = (data['encodings'] as Map<String, dynamic>).map(
              (key, value) => MapEntry(key, List<double>.from(value))
      );

      _userImages = Map<String, String>.from(data['user_images'] ?? {});

      // Load enhanced data if available
      if (data['user_face_data'] != null) {
        _userFaceData = Map<String, Map<String, dynamic>>.from(data['user_face_data']);
      } else {
        // Convert legacy data to enhanced format
        for (final userId in _faceEncodings.keys) {
          _userFaceData[userId] = {
            'encoding': _faceEncodings[userId],
            'image_paths': [_userImages[userId] ?? ''],
            'registered_at': DateTime.now().toIso8601String(),
            'feature_length': _faceEncodings[userId]!.length,
            'number_of_samples': 1,
            'registration_quality': 0.5,
          };
        }
      }

      print('Loaded ${_faceEncodings.length} face encodings');

      // Verify file integrity
      await _verifyStoredFiles();
    } catch (e) {
      print('Error loading encodings: $e');
      // Reset on critical error
      _faceEncodings = {};
      _userImages = {};
      _userFaceData = {};
    }
  }

  // Verify that all stored image files still exist
  Future<void> _verifyStoredFiles() async {
    int missingFiles = 0;
    final usersToRemove = <String>[];

    for (final entry in _userImages.entries) {
      final file = File(entry.value);
      if (!await file.exists()) {
        print('Missing image file for user ${entry.key}: ${entry.value}');
        missingFiles++;
        usersToRemove.add(entry.key);
      }
    }

    // Remove users with missing files
    for (final userId in usersToRemove) {
      _faceEncodings.remove(userId);
      _userImages.remove(userId);
      _userFaceData.remove(userId);
    }

    if (missingFiles > 0) {
      print('Removed $missingFiles users with missing image files');
      await _saveEncodingsToFile();
    }
  }

  // Get all registered users
  List<String> getRegisteredUsers() {
    return _faceEncodings.keys.toList();
  }

  // Get user face data
  Map<String, dynamic>? getUserFaceData(String userId) {
    return _userFaceData[userId];
  }

  // Check if user is registered
  bool isUserRegistered(String userId) {
    return _faceEncodings.containsKey(userId);
  }

  // Get registration quality for a user
  double getRegistrationQuality(String userId) {
    final data = _userFaceData[userId];
    return data?['registration_quality'] ?? 0.0;
  }

  // Delete user face data
  Future<bool> deleteUserFace(String userId) async {
    try {
      // Remove from memory
      _faceEncodings.remove(userId);
      _userImages.remove(userId);
      _userFaceData.remove(userId);

      // Delete all image files for this user
      final appDir = await getApplicationDocumentsDirectory();
      final userDir = Directory('${appDir.path}/faces/$userId');
      if (await userDir.exists()) {
        await userDir.delete(recursive: true);
      }

      // Save updated encodings
      await _saveEncodingsToFile();

      print('Deleted face data for user: $userId');
      return true;
    } catch (e) {
      print('Error deleting user face: $e');
      return false;
    }
  }

  // Get storage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    final appDir = await getApplicationDocumentsDirectory();
    final facesDir = Directory('${appDir.path}/faces');
    int totalImages = 0;
    int totalSize = 0;

    if (await facesDir.exists()) {
      final entities = await facesDir.list(recursive: true).toList();
      final imageFiles = entities.whereType<File>();
      totalImages = imageFiles.length;

      for (final file in imageFiles) {
        totalSize += await file.length();
      }
    }

    return {
      'total_users': _faceEncodings.length,
      'total_images': totalImages,
      'total_size_bytes': totalSize,
      'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      'storage_path': appDir.path,
      'average_quality': _calculateAverageQuality(),
    };
  }

  double _calculateAverageQuality() {
    if (_userFaceData.isEmpty) return 0.0;

    double totalQuality = 0.0;
    for (final data in _userFaceData.values) {
      totalQuality += data['registration_quality'] ?? 0.0;
    }

    return totalQuality / _userFaceData.length;
  }

  // Clear all face data (reset)
  Future<void> clearAllData() async {
    try {
      _faceEncodings.clear();
      _userImages.clear();
      _userFaceData.clear();

      final appDir = await getApplicationDocumentsDirectory();
      final encodingsFile = File('${appDir.path}/face_encodings_enhanced.json');
      if (await encodingsFile.exists()) {
        await encodingsFile.delete();
      }

      final legacyFile = File('${appDir.path}/encodings.json');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }

      final facesDir = Directory('${appDir.path}/faces');
      if (await facesDir.exists()) {
        await facesDir.delete(recursive: true);
      }

      print('All face data cleared');
    } catch (e) {
      print('Error clearing data: $e');
    }
  }

  // Migrate legacy data to enhanced format
  Future<void> migrateLegacyData() async {
    final appDir = await getApplicationDocumentsDirectory();
    final legacyFile = File('${appDir.path}/encodings.json');

    if (await legacyFile.exists()) {
      print('Migrating legacy data to enhanced format...');
      await _loadEncodingsFromFile(); // This will automatically migrate
      print('Migration completed');
    }
  }
}