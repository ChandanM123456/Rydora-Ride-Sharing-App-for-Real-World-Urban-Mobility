// lib/services/local_storage_service.dart
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._internal();
  factory LocalStorageService() => _instance;
  LocalStorageService._internal();

  // In-memory storage for face encodings
  Map<String, List<double>> _faceEncodings = {};
  Map<String, String> _userImages = {}; // user_id -> image_path
  Map<String, Map<String, dynamic>> _userFaceData = {}; // Store complete face data

  // Configurable verification threshold (30%, 40%, 50%, 60%)
  double _verificationThreshold = 0.5; // Default to 50%

  // Initialize service
  Future<void> initialize() async {
    await _loadEncodingsFromFile();
    await _loadThresholdPreference();
  }

  // Load threshold from shared preferences
  Future<void> _loadThresholdPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _verificationThreshold = prefs.getDouble('verification_threshold') ?? 0.5;
      print('Loaded verification threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%');
    } catch (e) {
      print('Error loading threshold preference: $e');
    }
  }

  // Save threshold to shared preferences
  Future<void> _saveThresholdPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('verification_threshold', _verificationThreshold);
    } catch (e) {
      print('Error saving threshold preference: $e');
    }
  }

  // Set verification threshold (30, 40, 50, 60)
  Future<void> setVerificationThreshold(int thresholdPercent) async {
    if (thresholdPercent >= 30 && thresholdPercent <= 60) {
      _verificationThreshold = thresholdPercent / 100.0;
      await _saveThresholdPreference();
      print('Verification threshold set to: $thresholdPercent%');
    } else {
      print('Invalid threshold. Must be between 30 and 60 percent.');
    }
  }

  // Get current threshold
  double get verificationThreshold => _verificationThreshold;
  int get verificationThresholdPercent => (_verificationThreshold * 100).round();

  // Extract face features using enhanced LBP algorithm
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

  // Enhanced LBP feature extraction with histogram
  List<double> _extractEnhancedLBPFeatures(img.Image image) {
    List<double> features = [];

    // Divide image into 8x8 blocks for better localization
    const blockSize = 8;
    const gridX = 12; // 100/8 ≈ 12
    const gridY = 12;

    // Extract LBP for each block
    for (int by = 0; by < gridY; by++) {
      for (int bx = 0; bx < gridX; bx++) {
        final blockHistogram = _computeLBPForBlock(image, bx, by, blockSize);
        features.addAll(blockHistogram);
      }
    }

    // Add global image statistics
    features.addAll(_computeGlobalFeatures(image));

    return features;
  }

  // Compute LBP histogram for a block
  List<double> _computeLBPForBlock(img.Image image, int blockX, int blockY, int blockSize) {
    final histogram = List<double>.filled(256, 0.0);
    int pixelCount = 0;

    final startX = blockX * blockSize;
    final startY = blockY * blockSize;
    final endX = min((blockX + 1) * blockSize, image.width - 1);
    final endY = min((blockY + 1) * blockSize, image.height - 1);

    for (int y = startY + 1; y < endY - 1; y++) {
      for (int x = startX + 1; x < endX - 1; x++) {
        final lbpValue = _computeLBPValue(image, x, y);
        histogram[lbpValue]++;
        pixelCount++;
      }
    }

    // Normalize histogram with Laplace smoothing
    if (pixelCount > 0) {
      for (int i = 0; i < histogram.length; i++) {
        histogram[i] = (histogram[i] + 0.1) / (pixelCount + 0.1 * 256);
      }
    }

    return histogram;
  }

  // Compute LBP value for a pixel
  int _computeLBPValue(img.Image image, int x, int y) {
    final center = image.getPixel(x, y).luminance;
    int lbp = 0;

    // 3x3 neighborhood coordinates (8 points around center)
    final neighbors = [
      image.getPixel(x-1, y-1).luminance, // top-left
      image.getPixel(x, y-1).luminance,   // top
      image.getPixel(x+1, y-1).luminance, // top-right
      image.getPixel(x+1, y).luminance,   // right
      image.getPixel(x+1, y+1).luminance, // bottom-right
      image.getPixel(x, y+1).luminance,   // bottom
      image.getPixel(x-1, y+1).luminance, // bottom-left
      image.getPixel(x-1, y).luminance,   // left
    ];

    // Set bits for neighbors brighter than center
    for (int i = 0; i < neighbors.length; i++) {
      if (neighbors[i] >= center) {
        lbp |= (1 << i);
      }
    }

    return lbp;
  }

  // Compute global image features
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

  // Enhanced verification with configurable threshold
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

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          matchedUserId = entry.key;
        }
      }

      // Use configurable threshold
      final isMatch = matchedUserId != null && bestSimilarity > _verificationThreshold;

      return {
        'success': true,
        'match': isMatch,
        'user_id': matchedUserId,
        'confidence': bestSimilarity,
        'all_similarities': allSimilarities,
        'threshold_used': _verificationThreshold,
        'feature_length': liveEncoding.length,
        'verification_timestamp': DateTime.now().toIso8601String(),
        'threshold_percent': verificationThresholdPercent,
      };
    } catch (e) {
      return {
        'success': false,
        'match': false,
        'error': 'Verification failed: $e',
      };
    }
  }

  // Test verification with different thresholds (for debugging)
  Future<Map<String, dynamic>> testVerificationWithThresholds(File imageFile) async {
    try {
      final liveEncoding = extractFaceFeatures(imageFile);
      Map<String, double> allSimilarities = {};
      Map<String, bool> matchesAtThresholds = {};

      double bestSimilarity = 0.0;
      String? bestMatchUserId;

      // Compare with all stored encodings
      for (final entry in _faceEncodings.entries) {
        final similarity = _cosineSimilarity(liveEncoding, entry.value);
        allSimilarities[entry.key] = similarity;

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestMatchUserId = entry.key;
        }
      }

      // Test different thresholds
      final thresholds = [0.3, 0.4, 0.5, 0.6];
      for (final threshold in thresholds) {
        matchesAtThresholds['${(threshold * 100).toInt()}%'] =
            bestMatchUserId != null && bestSimilarity > threshold;
      }

      return {
        'success': true,
        'best_similarity': bestSimilarity,
        'best_match_user': bestMatchUserId,
        'all_similarities': allSimilarities,
        'matches_at_thresholds': matchesAtThresholds,
        'current_threshold': _verificationThreshold,
        'feature_length': liveEncoding.length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Test verification failed: $e',
      };
    }
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

  // Save encodings to JSON file
  Future<void> _saveEncodingsToFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final encodingsFile = File('${appDir.path}/face_encodings_enhanced.json');

      // Convert to JSON-serializable format
      final encodingsData = {
        'encodings': _faceEncodings.map((key, value) => MapEntry(key, value)),
        'user_images': _userImages,
        'user_face_data': _userFaceData,
        'metadata': {
          'total_users': _faceEncodings.length,
          'created_at': DateTime.now().toIso8601String(),
          'version': '2.0.0',
          'threshold': _verificationThreshold,
        },
      };

      await encodingsFile.writeAsString(json.encode(encodingsData));
      print('Enhanced face encodings saved to: ${encodingsFile.path}');
      print('Total users registered: ${_faceEncodings.length}');
      print('Current threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%');
    } catch (e) {
      print('Error saving encodings: $e');
    }
  }

  // Load encodings from file
  Future<void> _loadEncodingsFromFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Try to load enhanced version first, fall back to legacy
      final enhancedFile = File('${appDir.path}/face_encodings_enhanced.json');
      final legacyFile = File('${appDir.path}/face_encodings.json');

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

      // Load threshold if available
      if (data['metadata'] != null && data['metadata']['threshold'] != null) {
        _verificationThreshold = data['metadata']['threshold'];
      }

      print('Loaded ${_faceEncodings.length} face encodings');
      print('Current threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%');

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

  // NEW: Clear all existing face data and start fresh
  Future<void> clearAllFaceData() async {
    try {
      _faceEncodings.clear();
      _userImages.clear();
      _userFaceData.clear();

      final appDir = await getApplicationDocumentsDirectory();

      // Delete all encoding files
      final enhancedFile = File('${appDir.path}/face_encodings_enhanced.json');
      final legacyFile = File('${appDir.path}/face_encodings.json');
      final oldEncodingsFile = File('${appDir.path}/encodings.json');

      if (await enhancedFile.exists()) await enhancedFile.delete();
      if (await legacyFile.exists()) await legacyFile.delete();
      if (await oldEncodingsFile.exists()) await oldEncodingsFile.delete();

      // Delete all face images
      final facesDir = Directory('${appDir.path}/faces');
      if (await facesDir.exists()) {
        await facesDir.delete(recursive: true);
      }

      // Clear threshold preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('verification_threshold');
      _verificationThreshold = 0.5;

      print('🗑️ All existing face data cleared successfully');
      print('🔄 Ready for fresh face registration with new images');
    } catch (e) {
      print('❌ Error clearing face data: $e');
      throw Exception('Failed to clear face data: $e');
    }
  }

  // NEW: Force re-registration with quality check
  Future<Map<String, dynamic>> forceReRegisterFace(String userId, List<File> imageFiles) async {
    try {
      // Clear existing data first
      await clearAllFaceData();

      // Register with new images
      final result = await registerFaceWithMultipleImages(userId, imageFiles);

      if (result['success'] == true) {
        print('✅ Successfully re-registered face with ${imageFiles.length} new images');
        print('📊 New registration quality: ${result['registration_quality']}');
      }

      return result;
    } catch (e) {
      return {
        'success': false,
        'error': 'Force re-registration failed: $e',
      };
    }
  }

  // NEW: Check if face data needs improvement
  bool needsFaceDataImprovement(String userId) {
    final quality = getRegistrationQuality(userId);
    return quality < 0.6; // Consider improving if quality is below 60%
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
      'current_threshold': '${verificationThresholdPercent}%',
      'average_quality': _calculateAverageQuality(),
      'needs_improvement': _faceEncodings.keys.any((userId) => needsFaceDataImprovement(userId)),
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

      final legacyFile = File('${appDir.path}/face_encodings.json');
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

  // Get available threshold options
  List<int> getAvailableThresholds() {
    return [30, 40, 50, 60];
  }

  // Test current setup with sample data
  Future<Map<String, dynamic>> testCurrentSetup() async {
    return {
      'total_users': _faceEncodings.length,
      'current_threshold': '${verificationThresholdPercent}%',
      'average_quality': _calculateAverageQuality(),
      'available_thresholds': getAvailableThresholds(),
      'recommended_threshold': _getRecommendedThreshold(),
      'needs_re_registration': _faceEncodings.keys.any((userId) => needsFaceDataImprovement(userId)),
    };
  }

  int _getRecommendedThreshold() {
    final avgQuality = _calculateAverageQuality();
    if (avgQuality > 0.7) return 50; // High quality -> medium threshold
    if (avgQuality > 0.5) return 40; // Medium quality -> lower threshold
    return 30; // Low quality -> lowest threshold
  }

  // NEW: Diagnostic method to check face recognition health
  Future<Map<String, dynamic>> runDiagnostics(String userId) async {
    final stats = await getStorageStats();
    final userData = getUserFaceData(userId);

    return {
      'user_registered': isUserRegistered(userId),
      'registration_quality': getRegistrationQuality(userId),
      'number_of_samples': userData?['number_of_samples'] ?? 0,
      'feature_length': userData?['feature_length'] ?? 0,
      'current_threshold': '${verificationThresholdPercent}%',
      'recommended_threshold': '${_getRecommendedThreshold()}%',
      'total_users': stats['total_users'],
      'average_quality': stats['average_quality'],
      'needs_improvement': needsFaceDataImprovement(userId),
      'suggestion': _getImprovementSuggestion(userId),
    };
  }

  String _getImprovementSuggestion(String userId) {
    if (!isUserRegistered(userId)) {
      return 'Register your face with 3+ high-quality images in good lighting.';
    }

    final quality = getRegistrationQuality(userId);
    final samples = _userFaceData[userId]?['number_of_samples'] ?? 0;

    if (quality < 0.5) {
      return 'Face data quality is poor. Consider re-registering with better images.';
    } else if (quality < 0.7 && samples < 3) {
      return 'Add more face samples (3+ recommended) for better accuracy.';
    } else if (quality < 0.7) {
      return 'Try re-registering in better lighting conditions.';
    } else {
      return 'Face data quality is good. No action needed.';
    }
  }
}