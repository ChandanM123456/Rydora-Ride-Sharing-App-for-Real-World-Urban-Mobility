// rider_app/lib/pages/face.dart

import 'package:flutter/material.dart';

class FaceVerificationPage extends StatefulWidget {
  @override
  _FaceVerificationPageState createState() => _FaceVerificationPageState();
}

class _FaceVerificationPageState extends State<FaceVerificationPage> {
  bool _isVerifying = false;
  bool _verificationSuccess = false;
  bool _showCamera = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Face Verification'),
        backgroundColor: const Color(0xFF6200EA),
        elevation: 0,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6200EA), Color(0xFFBB86FC)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header Icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(
                  Icons.face_retouching_natural,
                  size: 60,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 30),

              // Title
              const Text(
                'Rider Identity Verification',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 15),

              // Description
              const Text(
                'Please verify your identity to continue with the ride. This ensures passenger safety and ride authenticity.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Camera Preview Area
              if (_showCamera)
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Stack(
                    children: [
                      // Simulated camera feed
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.grey[800]!, Colors.grey[600]!],
                          ),
                        ),
                        child: const Icon(
                          Icons.face,
                          size: 80,
                          color: Colors.white54,
                        ),
                      ),

                      // Face overlay guide
                      Container(
                        margin: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.green, width: 3),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.photo_camera,
                    size: 80,
                    color: Colors.white54,
                  ),
                ),

              const SizedBox(height: 30),

              // Verification Status
              if (_isVerifying)
                Column(
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Verifying your identity...',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Simulated verification process
                    LinearProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                      backgroundColor: Colors.white.withOpacity(0.3),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ],
                ),

              if (_verificationSuccess)
                Column(
                  children: [
                    const Icon(
                      Icons.verified,
                      size: 80,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Identity Verified Successfully!',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'You can now proceed with the ride',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: const Text(
                        'Continue to OTP',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

              const Spacer(),

              // Action Buttons
              if (!_isVerifying && !_verificationSuccess)
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _startVerificationProcess();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF6200EA),
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        'Start Face Verification',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: () {
                        // Simulate successful verification for demo
                        _simulateVerificationSuccess();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Demo: Simulate Success',
                        style: TextStyle(fontSize: 14, decoration: TextDecoration.underline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        // Simulate failed verification for demo
                        _simulateVerificationFailure();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(
                        'Demo: Simulate Failure',
                        style: TextStyle(fontSize: 14, decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _startVerificationProcess() {
    setState(() {
      _showCamera = true;
      _isVerifying = true;
    });

    // Simulate verification process
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _isVerifying = false;
        _verificationSuccess = true;
      });
    });
  }

  void _simulateVerificationSuccess() {
    setState(() {
      _showCamera = true;
      _isVerifying = true;
    });

    // Simulate successful verification after delay
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isVerifying = false;
        _verificationSuccess = true;
      });
    });
  }

  void _simulateVerificationFailure() {
    setState(() {
      _showCamera = true;
      _isVerifying = true;
    });

    // Simulate failed verification after delay
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isVerifying = false;
        _verificationSuccess = false;
      });

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face verification failed. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );

      // Return to previous screen after delay
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pop(context, false);
      });
    });
  }
}