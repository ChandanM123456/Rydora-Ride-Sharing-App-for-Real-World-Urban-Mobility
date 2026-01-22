// lib/pages/face_verification.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/local_storage_service.dart';

class FaceVerificationPage extends StatefulWidget {
  final String? userId;

  const FaceVerificationPage({super.key, this.userId});

  @override
  State<FaceVerificationPage> createState() => _FaceVerificationPageState();
}

class _FaceVerificationPageState extends State<FaceVerificationPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _verificationSuccess = false;
  bool _verificationFailed = false;
  String _status = 'Position your face in the frame';
  Map<String, dynamic>? _verificationResult;
  double _confidence = 0.0;
  int _captureProgress = 0;
  int _totalCaptures = 3;
  int _verificationAttempts = 0;
  final int _maxVerificationAttempts = 3;

  // Get effective user ID
  String get _effectiveUserId {
    return widget.userId ?? 'default_user';
  }

  bool get _isUserRegistered {
    return LocalStorageService().isUserRegistered(_effectiveUserId);
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeStorage();
    _checkFaceHealth(); // Check face data quality on start
  }

  Future<void> _initializeStorage() async {
    await LocalStorageService().initialize();

    // Update status based on registration
    if (mounted) {
      setState(() {
        _status = _isUserRegistered
            ? 'Ready for verification'
            : 'Register your face first';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        _showError('No cameras available');
        return;
      }

      final frontCamera = _cameras!.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      _showError('Failed to initialize camera: $e');
    }
  }

  // NEW: Check face data health
  Future<void> _checkFaceHealth() async {
    try {
      final diagnostics = await LocalStorageService().runDiagnostics(_effectiveUserId);
      print('🔍 Face Health Check:');
      print('   - Registered: ${diagnostics['user_registered']}');
      print('   - Quality: ${(diagnostics['registration_quality'] * 100).toStringAsFixed(1)}%');
      print('   - Samples: ${diagnostics['number_of_samples']}');
      print('   - Suggestion: ${diagnostics['suggestion']}');

      if (diagnostics['needs_improvement'] == true) {
        _showMessage('⚠️ ${diagnostics['suggestion']}', Colors.orange, duration: 5);
      }
    } catch (e) {
      print('Error checking face health: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showMessage(String message, Color color, {int duration = 3}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: Duration(seconds: duration),
        ),
      );
    }
  }

  // NEW: Clear and re-register face data
  Future<void> _clearAndReRegister() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Face Data?'),
        content: const Text('This will DELETE all existing face encodings and allow you to register new, higher quality images. This should fix low confidence issues.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear & Re-register'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _status = 'Clearing old face data...';
        });

        await LocalStorageService().clearAllFaceData();

        _showSuccess('✅ Old data cleared! Please register with 3+ high-quality images.');

        // Refresh the page
        if (mounted) {
          setState(() {
            _status = 'Register your face first';
            _verificationResult = null;
          });
        }
      } catch (e) {
        _showError('Failed to clear data: $e');
      }
    }
  }

  // NEW: Enhanced registration with better guidance
  Future<void> _registerFace() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _verificationSuccess = false;
      _verificationFailed = false;
      _captureProgress = 0;
      _status = '🔧 Capturing multiple images for better accuracy...';
    });

    try {
      List<File> capturedImages = [];

      // Capture multiple images from different angles
      for (int i = 0; i < _totalCaptures; i++) {
        if (!mounted) break;

        // Update progress and instructions
        setState(() {
          _captureProgress = i + 1;
          _status = '📸 Capture $_captureProgress/$_totalCaptures - ${_getCaptureInstruction(i)}';
        });

        // Wait a moment for user to adjust position
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 2000));
          _showMessage(_getCaptureTip(i), Colors.blue, duration: 2);
        }

        // Check if face is properly positioned
        if (!await _isFaceProperlyPositioned()) {
          _showError('Please position your face properly in the circle');
          setState(() { _isProcessing = false; });
          return;
        }

        // Capture image
        final imageFile = await _controller!.takePicture();

        // Validate image quality
        final isValid = await LocalStorageService().validateImageQuality(File(imageFile.path));
        if (!isValid) {
          _showError('Image quality is poor. Please ensure good lighting.');
          setState(() { _isProcessing = false; });
          return;
        }

        capturedImages.add(File(imageFile.path));
      }

      if (!mounted) return;

      setState(() {
        _status = '🔄 Processing ${capturedImages.length} images...';
      });

      // Register with multiple images
      final result = await LocalStorageService().registerFaceWithMultipleImages(
        _effectiveUserId,
        capturedImages,
      );

      setState(() {
        _isProcessing = false;
      });

      if (result['success'] == true) {
        final quality = (result['registration_quality'] * 100);
        setState(() {
          _verificationSuccess = true;
          _status = '✅ Registration Successful! Quality: ${quality.toStringAsFixed(1)}%';
        });

        _showSuccess('Face registered successfully! Quality: ${quality.toStringAsFixed(1)}%');

        // Auto-return after success
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        _showError('Registration failed: ${result['error']}');
        setState(() {
          _verificationFailed = true;
          _status = 'Registration Failed';
        });
      }
    } catch (e) {
      _showError('Registration error: $e');
      setState(() {
        _isProcessing = false;
        _verificationFailed = true;
        _status = 'Registration failed';
      });
    }
  }

  String _getCaptureInstruction(int index) {
    switch (index) {
      case 1:
        return 'Slightly turn your head left';
      case 2:
        return 'Slightly turn your head right';
      default:
        return 'Look straight ahead';
    }
  }

  String _getCaptureTip(int index) {
    switch (index) {
      case 1:
        return '💡 Tip: Turn your head about 15 degrees to the left';
      case 2:
        return '💡 Tip: Turn your head about 15 degrees to the right';
      default:
        return '💡 Tip: Keep your face centered and well-lit';
    }
  }

  Future<bool> _isFaceProperlyPositioned() async {
    // Simple check - you can enhance this with actual face detection
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  // NEW: Enhanced verification with multiple attempts and auto-threshold adjustment
  Future<void> _verifyFace() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _verificationSuccess = false;
      _verificationFailed = false;
      _verificationAttempts++;
      _status = 'Capturing image...';
    });

    try {
      // Capture image
      final imageFile = await _controller!.takePicture();

      // Validate image quality
      final isValid = await LocalStorageService().validateImageQuality(File(imageFile.path));
      if (!isValid) {
        _showError('Image quality is poor. Please ensure good lighting.');
        setState(() { _isProcessing = false; });
        return;
      }

      setState(() {
        _status = 'Extracting face features...';
      });

      // Verify face
      final result = await LocalStorageService().verifyFace(File(imageFile.path));

      setState(() {
        _isProcessing = false;
        _verificationResult = result;
      });

      final confidence = (result['confidence'] ?? 0) * 100;
      final currentThreshold = LocalStorageService().verificationThresholdPercent;

      if (result['success'] == true && result['match'] == true) {
        setState(() {
          _verificationSuccess = true;
          _confidence = confidence;
          _status = '✅ Verification Successful!';
        });

        _showSuccess('Face verified successfully! Confidence: ${confidence.toStringAsFixed(1)}%');

        // Auto-return after success
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        setState(() {
          _verificationSuccess = false;
          _verificationFailed = true;
          _status = 'Verification Failed';
        });

        // NEW: Auto-adjust threshold if confidence is close
        if (confidence > currentThreshold - 10 && confidence < currentThreshold) {
          _showMessage('🔄 Confidence close to threshold. Try adjusting lighting and retry.', Colors.orange);
        }

        if (result['error'] != null) {
          _showError('Verification failed: ${result['error']}');
        } else {
          _showError('Face not recognized. Confidence: ${confidence.toStringAsFixed(1)}% (Threshold: ${currentThreshold}%)');

          // NEW: Suggest solutions based on confidence level
          if (confidence < 20) {
            _showMessage('💡 Try re-registering with better quality images', Colors.orange, duration: 4);
          } else if (confidence < 40) {
            _showMessage('💡 Improve lighting and ensure clear face view', Colors.orange, duration: 4);
          }
        }

        // NEW: Auto-lower threshold after multiple failures
        if (_verificationAttempts >= 2 && currentThreshold > 30) {
          final newThreshold = currentThreshold - 10;
          await LocalStorageService().setVerificationThreshold(newThreshold);
          _showMessage('🔧 Auto-adjusted threshold to $newThreshold% for easier verification', Colors.blue, duration: 4);
        }
      }
    } catch (e) {
      _showError('Verification error: $e');
      setState(() {
        _isProcessing = false;
        _verificationSuccess = false;
        _verificationFailed = true;
        _status = 'Verification failed';
      });
    }
  }

  // NEW: Quick test verification with different thresholds
  Future<void> _testVerification() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Running comprehensive test...';
    });

    try {
      final imageFile = await _controller!.takePicture();
      final testResult = await LocalStorageService().testVerificationWithThresholds(File(imageFile.path));

      setState(() {
        _isProcessing = false;
        _verificationResult = testResult;
      });

      if (testResult['success'] == true) {
        final bestSimilarity = (testResult['best_similarity'] ?? 0) * 100;
        final matches = testResult['matches_at_thresholds'] as Map<String, dynamic>;

        String testResults = 'Test Results:\n';
        matches.forEach((threshold, matches) {
          testResults += '  $threshold: ${matches ? '✅' : '❌'}\n';
        });

        _showMessage('Best similarity: ${bestSimilarity.toStringAsFixed(1)}%\n$testResults',
            bestSimilarity > 50 ? Colors.green : Colors.orange,
            duration: 6);
      }
    } catch (e) {
      _showError('Test failed: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showVerificationDetails() {
    if (_verificationResult == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('User: ${_verificationResult!['user_id'] ?? 'Unknown'}'),
              Text('Match: ${_verificationResult!['match']}'),
              Text('Confidence: ${((_verificationResult!['confidence'] ?? 0) * 100).toStringAsFixed(1)}%'),
              Text('Threshold: ${((_verificationResult!['threshold_used'] ?? 0) * 100).toStringAsFixed(1)}%'),
              Text('Attempt: $_verificationAttempts/$_maxVerificationAttempts'),
              const SizedBox(height: 10),
              Text('Features: ${_verificationResult!['feature_length']} dimensions'),
              const SizedBox(height: 10),
              if (_verificationResult!['all_similarities'] != null) ...[
                const Text('Similarity Scores:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...(_verificationResult!['all_similarities'] as Map<String, dynamic>)
                    .entries
                    .map((entry) => Text('${entry.key}: ${(entry.value * 100).toStringAsFixed(1)}%'))
                    .toList(),
              ],
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _showThresholdSettings,
                child: const Text('Adjust Threshold Settings'),
              ),
              const SizedBox(height: 5),
              OutlinedButton(
                onPressed: _testVerification,
                child: const Text('Run Comprehensive Test'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showThresholdSettings() {
    Navigator.of(context).pop(); // Close details dialog first

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification Threshold'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set the confidence threshold for verification:'),
            const SizedBox(height: 16),
            ...LocalStorageService().getAvailableThresholds().map((threshold) {
              final isCurrent = LocalStorageService().verificationThresholdPercent == threshold;
              return ListTile(
                leading: Radio<int>(
                  value: threshold,
                  groupValue: LocalStorageService().verificationThresholdPercent,
                  onChanged: (value) {
                    if (value != null) {
                      LocalStorageService().setVerificationThreshold(value);
                      Navigator.of(context).pop();
                      setState(() {});
                    }
                  },
                ),
                title: Text('$threshold%'),
                subtitle: Text(_getThresholdDescription(threshold)),
                trailing: isCurrent ? const Icon(Icons.check, color: Colors.green) : null,
              );
            }).toList(),
            const SizedBox(height: 16),
            Text(
              'Current: ${LocalStorageService().verificationThresholdPercent}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _getThresholdDescription(LocalStorageService().verificationThresholdPercent),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            const Text(
              '💡 Lower thresholds make verification easier but less secure.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getThresholdDescription(int threshold) {
    switch (threshold) {
      case 30:
        return 'Easiest - More false positives';
      case 40:
        return 'Easy - Balanced security';
      case 50:
        return 'Medium - Good security';
      case 60:
        return 'Hard - Maximum security';
      default:
        return 'Standard security';
    }
  }

  void _retryVerification() {
    setState(() {
      _isProcessing = false;
      _verificationSuccess = false;
      _verificationFailed = false;
      _captureProgress = 0;
      _status = _isUserRegistered ? 'Ready for verification' : 'Register your face first';
      _verificationResult = null;
      _confidence = 0.0;
    });
  }

  void _cancelVerification() {
    Navigator.of(context).pop(false);
  }

  Widget _buildCameraPreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _verificationSuccess ? Colors.green :
          _verificationFailed ? Colors.red :
          _isProcessing ? Colors.orange :
          _isUserRegistered ? Colors.blue : Colors.amber,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isCameraInitialized && _controller != null)
              CameraPreview(_controller!)
            else
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Initializing camera...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

            // Face overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _verificationSuccess ? Colors.green :
                        _verificationFailed ? Colors.red :
                        _isProcessing ? Colors.orange :
                        _isUserRegistered ? Colors.blue : Colors.amber,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(125),
                    ),
                  ),
                ),
              ),
            ),

            // NEW: Quality indicators
            if (_isUserRegistered && !_isProcessing && !_verificationSuccess && !_verificationFailed)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates,
                        color: Colors.yellow[300],
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Ensure good lighting',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

            // Capture progress overlay
            if (_isProcessing && !_isUserRegistered && _captureProgress > 0)
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Column(
                    children: [
                      Text(
                        'Capture Progress: $_captureProgress/$_totalCaptures',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: _captureProgress / _totalCaptures,
                        backgroundColor: Colors.grey,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ],
                  ),
                ),
              ),

            // Processing overlay
            if (_isProcessing)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isUserRegistered ? 'Verifying...' : 'Processing...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      if (!_isUserRegistered) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Image $_captureProgress/$_totalCaptures',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Success overlay
            if (_verificationSuccess)
              Container(
                color: Colors.green.withOpacity(0.8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 80,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'VERIFIED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Failed overlay
            if (_verificationFailed)
              Container(
                color: Colors.red.withOpacity(0.8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 80,
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'NOT RECOGNIZED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Positioning tips
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getPositioningTip(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPositioningTip() {
    if (_isProcessing) {
      if (!_isUserRegistered && _captureProgress > 0) {
        return _getCaptureInstruction(_captureProgress - 1);
      }
      return 'Processing... Please wait';
    } else if (!_isUserRegistered) {
      return 'We will capture $_totalCaptures images from different angles for better accuracy';
    } else {
      return 'Position your face in the circle with good lighting';
    }
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            Icons.face_retouching_natural,
            size: 60,
            color: _verificationSuccess ? Colors.green :
            _verificationFailed ? Colors.red :
            _isProcessing ? Colors.orange :
            _isUserRegistered ? Colors.blue : Colors.amber,
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(
              fontSize: 18,
              color: _verificationSuccess ? Colors.green :
              _verificationFailed ? Colors.red :
              _isProcessing ? Colors.orange : Colors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'User: $_effectiveUserId',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isUserRegistered ? 'Status: Registered' : 'Status: Not Registered',
            style: TextStyle(
              color: _isUserRegistered ? Colors.green : Colors.amber,
              fontSize: 14,
            ),
          ),
          if (_verificationSuccess) ...[
            const SizedBox(height: 8),
            Text(
              'Confidence: ${_confidence.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (_verificationFailed && _verificationResult != null) ...[
            const SizedBox(height: 8),
            Text(
              'Best match: ${((_verificationResult!['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Threshold: ${((_verificationResult!['threshold_used'] ?? 0.6) * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12,
              ),
            ),
            if (_verificationAttempts > 1) ...[
              const SizedBox(height: 4),
              Text(
                'Attempt: $_verificationAttempts/$_maxVerificationAttempts',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          // Threshold indicator
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.security, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Threshold: ${LocalStorageService().verificationThresholdPercent}%',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _showThresholdSettings,
                  child: const Icon(Icons.settings, size: 14, color: Colors.blue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Register Button (if user not registered)
          if (!_isUserRegistered && !_isProcessing && !_verificationSuccess && !_verificationFailed)
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _registerFace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Register Face (3 Images)',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '💡 Tip: Use good lighting and capture from different angles',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),

          // Verify Button (if user is registered)
          if (_isUserRegistered && !_isProcessing && !_verificationSuccess && !_verificationFailed)
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyFace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Verify Face',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // NEW: Additional action buttons for registered users
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testVerification,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Test',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearAndReRegister,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Re-register',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

          // Processing Button
          if (_isProcessing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isUserRegistered ? 'Verifying...' : 'Registering... ($_captureProgress/$_totalCaptures)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          // Success Button
          if (_verificationSuccess)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isUserRegistered ? 'Continue' : 'Done',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          // Retry Button (on failure)
          if (_verificationFailed)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _retryVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isUserRegistered ? 'Try Again' : 'Retry Registration',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showThresholdSettings,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Adjust Threshold',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearAndReRegister,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Re-register',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

          const SizedBox(height: 12),

          // Details Button (only for verification)
          if (_verificationResult != null && !_isProcessing && _isUserRegistered)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _showVerificationDetails,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white70),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View Details',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Status Info
          if (!_isUserRegistered && !_isProcessing && !_verificationSuccess)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Text(
                    'Multi-image registration for better accuracy',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'We will capture 3 images from different angles',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Cancel Button
          TextButton(
            onPressed: _cancelVerification,
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
            _isUserRegistered ? 'Face Verification' : 'Face Registration',
            style: const TextStyle(color: Colors.white)
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _cancelVerification,
        ),
        actions: [
          // Threshold settings
          IconButton(
            icon: const Icon(Icons.security, color: Colors.white),
            onPressed: _showThresholdSettings,
            tooltip: 'Threshold Settings',
          ),
          // Health check
          IconButton(
            icon: const Icon(Icons.health_and_safety, color: Colors.white),
            onPressed: _checkFaceHealth,
            tooltip: 'Check Face Health',
          ),
          if (_verificationResult != null && !_isProcessing && _isUserRegistered)
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: _showVerificationDetails,
              tooltip: 'Verification Details',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                child: _buildHeaderSection(),
              ),
            ),

            // Camera Preview
            Expanded(
              child: _buildCameraPreview(),
            ),

            // Action Buttons
            SizedBox(
              height: 220,
              child: SingleChildScrollView(
                child: _buildActionButtons(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}