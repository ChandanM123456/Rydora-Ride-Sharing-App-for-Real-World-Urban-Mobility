// lib/pages/face_registration.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/local_storage_service.dart';

class FaceRegistrationPage extends StatefulWidget {
  final String? userId;

  const FaceRegistrationPage({super.key, this.userId});

  @override
  State<FaceRegistrationPage> createState() => _FaceRegistrationPageState();
}

class _FaceRegistrationPageState extends State<FaceRegistrationPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isRegistering = false;
  bool _registrationSuccess = false;
  bool _registrationFailed = false;
  String _status = 'Position your face for registration';
  String _effectiveUserId = '';
  int _captureProgress = 0;
  int _totalCaptures = 3;
  Map<String, dynamic>? _registrationResult;

  @override
  void initState() {
    super.initState();
    _effectiveUserId = widget.userId ?? 'default_user';
    _initializeCamera();
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
        ResolutionPreset.high, // Higher resolution for better quality
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

  Future<bool> _isFaceProperlyPositioned() async {
    // Simple check - you can enhance this with actual face detection
    setState(() {
      _status = 'Checking face position...';
    });

    await Future.delayed(const Duration(milliseconds: 500));

    // For now, return true - implement proper face detection later
    return true;
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

  Future<void> _registerFace() async {
    if (_isRegistering) return;

    setState(() {
      _isRegistering = true;
      _registrationSuccess = false;
      _registrationFailed = false;
      _captureProgress = 0;
      _status = 'Capturing multiple images for better accuracy...';
    });

    try {
      List<File> capturedImages = [];

      // Capture multiple images from different angles
      for (int i = 0; i < _totalCaptures; i++) {
        if (!mounted) break;

        // Update progress and instructions
        setState(() {
          _captureProgress = i + 1;
          _status = 'Capture $_captureProgress/$_totalCaptures - ${_getCaptureInstruction(i)}';
        });

        // Wait a moment for user to adjust position
        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }

        // Check if face is properly positioned
        if (!await _isFaceProperlyPositioned()) {
          _showError('Please position your face properly in the circle');
          setState(() { _isRegistering = false; });
          return;
        }

        // Capture image
        final imageFile = await _controller!.takePicture();

        // Validate image quality
        final isValid = await LocalStorageService().validateImageQuality(File(imageFile.path));
        if (!isValid) {
          _showError('Image $_captureProgress quality is poor. Please ensure good lighting and clear face view.');
          setState(() { _isRegistering = false; });
          return;
        }

        capturedImages.add(File(imageFile.path));
      }

      if (!mounted) return;

      setState(() {
        _status = 'Processing ${capturedImages.length} images...';
      });

      // Register with multiple images
      final result = await LocalStorageService().registerFaceWithMultipleImages(
        _effectiveUserId,
        capturedImages,
      );

      setState(() {
        _isRegistering = false;
        _registrationResult = result;
      });

      if (result['success'] == true) {
        setState(() {
          _registrationSuccess = true;
          _status = 'Registration Successful with ${result['samples_count']} images!';
        });

        _showSuccess('Face registered successfully with ${capturedImages.length} images!');

        // Auto-return after success
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        _showError('Registration failed: ${result['error']}');
        setState(() {
          _registrationFailed = true;
          _status = 'Registration Failed';
        });
      }
    } catch (e) {
      _showError('Registration error: $e');
      setState(() {
        _isRegistering = false;
        _registrationFailed = true;
        _status = 'Registration failed';
      });
    }
  }

  void _retryRegistration() {
    setState(() {
      _isRegistering = false;
      _registrationSuccess = false;
      _registrationFailed = false;
      _captureProgress = 0;
      _status = 'Position your face for registration';
      _registrationResult = null;
    });
  }

  void _cancelRegistration() {
    Navigator.of(context).pop(false);
  }

  Widget _buildCameraPreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _registrationSuccess ? Colors.green :
          _registrationFailed ? Colors.red :
          _isRegistering ? Colors.orange : Colors.blue,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (_isCameraInitialized && _controller != null)
              CameraPreview(_controller!)
            else
              const Center(
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

            // Face overlay
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _registrationSuccess ? Colors.green :
                      _registrationFailed ? Colors.red :
                      _isRegistering ? Colors.orange : Colors.white,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),

            // Capture progress overlay
            if (_isRegistering && _captureProgress > 0)
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _registrationSuccess ? Colors.green :
                            _registrationFailed ? Colors.red : Colors.blue
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Processing overlay
            if (_isRegistering)
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
                      const Text(
                        'Processing...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Image $_captureProgress/$_totalCaptures',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Success overlay
            if (_registrationSuccess)
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
                        'REGISTERED',
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
            if (_registrationFailed)
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
                        'REGISTRATION FAILED',
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
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
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
    if (_isRegistering) {
      if (_captureProgress > 0) {
        return _getCaptureInstruction(_captureProgress - 1);
      }
      return 'Processing... Please wait';
    } else if (_registrationSuccess) {
      return 'Registration completed successfully!';
    } else if (_registrationFailed) {
      return 'Registration failed. Please try again.';
    } else {
      return 'We will capture $_totalCaptures images from different angles for better accuracy';
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
            color: _registrationSuccess ? Colors.green :
            _registrationFailed ? Colors.red :
            _isRegistering ? Colors.orange : Colors.blue,
          ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(
              fontSize: 18,
              color: _registrationSuccess ? Colors.green :
              _registrationFailed ? Colors.red :
              _isRegistering ? Colors.orange : Colors.white,
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
          if (_registrationSuccess && _registrationResult != null) ...[
            const SizedBox(height: 8),
            Text(
              'Samples: ${_registrationResult!['samples_count']} images',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quality: ${((_registrationResult!['registration_quality'] ?? 0) * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Register Button
          if (!_isRegistering && !_registrationSuccess && !_registrationFailed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _registerFace,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
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

          // Processing Button
          if (_isRegistering)
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
                  'Registering... ($_captureProgress/$_totalCaptures)',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),

          // Success Button
          if (_registrationSuccess)
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
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),

          // Retry Button (on failure)
          if (_registrationFailed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _retryRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Registration Info
          if (!_isRegistering && !_registrationSuccess && !_registrationFailed)
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
                    'We will capture 3 images from different angles:',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Straight ahead\n2. Slightly left\n3. Slightly right',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Cancel Button
          TextButton(
            onPressed: _cancelRegistration,
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
        title: const Text(
            'Face Registration',
            style: TextStyle(color: Colors.white)
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _cancelRegistration,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Section
            _buildHeaderSection(),

            // Camera Preview
            Expanded(
              child: _buildCameraPreview(),
            ),

            // Action Buttons
            _buildActionButtons(),
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