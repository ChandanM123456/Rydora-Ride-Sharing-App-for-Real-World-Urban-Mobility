// rider_app/lib/rider_details_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io'; // For File class
import 'dart:math'; // For mathematical operations like min

import 'package:firebase_auth/firebase_auth.dart'; // To get current user UID
import 'package:cloud_firestore/cloud_firestore.dart'; // To interact with Firestore
import 'package:firebase_storage/firebase_storage.dart'; // For Firebase Storage
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // For picking images
import 'package:rider_app/home_page.dart'; // Import HomePage for navigation

class RiderDetailsPage extends StatefulWidget {
  const RiderDetailsPage({super.key});

  @override
  State<RiderDetailsPage> createState() => _RiderDetailsPageState();
}

class _RiderDetailsPageState extends State<RiderDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _vehicleTypeController = TextEditingController();
  final TextEditingController _vehiclePlateController = TextEditingController();
  final TextEditingController _aadhaarController = TextEditingController(); // Aadhaar Number
  final TextEditingController _addressController = TextEditingController(); // Address
  final TextEditingController _dlNumberController = TextEditingController(); // DL Number

  File? _aadhaarImage; // To store selected Aadhaar card image file locally
  String? _currentAadhaarImageUrl; // To store existing Aadhaar image URL from Firestore

  File? _dlImage; // To store selected Driving License image file locally
  String? _currentDlImageUrl; // To store existing DL image URL from Firestore

  List<File> _faceImages = []; // NEW: To store selected Face Photos image files locally
  List<String> _currentFaceImageUrls = []; // NEW: To store existing Face Photo image URLs from Firestore

  final ImagePicker _picker = ImagePicker(); // Image picker instance

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Load existing rider details when the page opens to pre-fill fields
    _loadRiderDetails();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleTypeController.dispose();
    _vehiclePlateController.dispose();
    _aadhaarController.dispose();
    _addressController.dispose();
    _dlNumberController.dispose();
    super.dispose();
  }

  /// Loads existing rider details from Firestore, including image URLs.
  Future<void> _loadRiderDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Only load if a user is logged in

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('riders').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _nameController.text = data['name'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _vehicleTypeController.text = data['vehicleType'] ?? '';
        _vehiclePlateController.text = data['vehiclePlate'] ?? '';
        _aadhaarController.text = data['aadhaarNumber'] ?? '';
        _addressController.text = data['address'] ?? '';
        _dlNumberController.text = data['dlNumber'] ?? '';

        // Load existing image URLs for display
        _currentAadhaarImageUrl = data['aadhaarImageUrl'];
        _currentDlImageUrl = data['dlImageUrl'];

        // Load multiple face image URLs
        _currentFaceImageUrls = List<String>.from(data['profileImageUrls'] ?? []);
        setState(() {}); // Update UI to show loaded images (if any)
      }
    } catch (e) {
      print('Error loading rider details: $e');
      _showMessage('Failed to load existing details.', Colors.red);
    }
  }

  /// Function to pick a single image from gallery or camera.
  /// Used for Aadhaar and DL, where only one image is expected.
  Future<void> _pickSingleImage(ImageSource source, Function(File?) setImage, Function(String?) setImageUrl) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 50); // imageQuality for smaller size
    if (pickedFile != null) {
      setState(() {
        setImage(File(pickedFile.path)); // Set the picked file to the respective local state variable
        setImageUrl(null); // Clear any existing image URL, as a new local file is selected
      });
    } else {
      _showMessage('No image selected.', Colors.orange);
    }
  }

  /// Function to capture a face photo specifically from the camera.
  /// This will add to a list of face photos.
  Future<void> _captureFacePhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _faceImages.add(File(pickedFile.path));
        // Clear existing URLs if new photos are being added, implies a re-enrollment
        _currentFaceImageUrls.clear();
      });
      _showMessage('Face photo captured!', Colors.green);
    } else {
      _showMessage('No face photo captured.', Colors.orange);
    }
  }

  /// Function to upload a single image to Firebase Storage and return its URL.
  Future<String?> _uploadImageToFirebaseStorage(File? imageFile, String folderPath, String fileName) async {
    if (imageFile == null) return null; // No file to upload

    try {
      final storageRef = FirebaseStorage.instance.ref().child(folderPath).child(fileName);
      await storageRef.putFile(imageFile);
      final downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Firebase Storage upload error for $fileName: $e');
      _showMessage('Failed to upload $fileName: ${e.toString()}', Colors.red);
      return null; // Return null if upload fails
    }
  }

  /// Saves all rider details, including uploading all selected images, to Firestore.
  Future<void> _saveRiderDetails() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true; // Show loading indicator
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showMessage('User not logged in. Please log in again.', Colors.redAccent);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Initialize image URLs. These will be populated by Firebase Storage upload or retain existing.
      String? finalAadhaarImageUrl = _currentAadhaarImageUrl;
      String? finalDlImageUrl = _currentDlImageUrl;
      List<String> finalFaceImageUrls = List.from(_currentFaceImageUrls); // Preserve existing if no new ones captured

      // Upload Aadhaar image if a new one is selected
      if (_aadhaarImage != null) {
        finalAadhaarImageUrl = await _uploadImageToFirebaseStorage(
          _aadhaarImage,
          'rider_documents/${user.uid}', // Specific folder per user
          'aadhaar_${DateTime.now().millisecondsSinceEpoch}.jpg', // Unique filename
        );
      } else if (_currentAadhaarImageUrl == null) {
        // If no new image and no existing URL, ensure it's null
        finalAadhaarImageUrl = null;
      }

      // Upload Driving License image if a new one is selected
      if (_dlImage != null) {
        finalDlImageUrl = await _uploadImageToFirebaseStorage(
          _dlImage,
          'rider_documents/${user.uid}', // Specific folder per user
          'driving_license_${DateTime.now().millisecondsSinceEpoch}.jpg', // Unique filename
        );
      } else if (_currentDlImageUrl == null) {
        // If no new image and no existing URL, ensure it's null
        finalDlImageUrl = null;
      }

      // NEW: Upload all captured Face Photos
      if (_faceImages.isNotEmpty) {
        finalFaceImageUrls.clear(); // Clear existing if new photos are taken
        for (int i = 0; i < _faceImages.length; i++) {
          final imageUrl = await _uploadImageToFirebaseStorage(
            _faceImages[i],
            'rider_face_profiles/${user.uid}', // Dedicated folder for face profiles
            'face_photo_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          if (imageUrl != null) {
            finalFaceImageUrls.add(imageUrl);
          }
        }
      } else if (_currentFaceImageUrls.isEmpty) {
        // If no new images and no existing URLs, ensure it's empty
        finalFaceImageUrls.clear();
      }

      try {
        // Save all details including image URLs to Firestore
        await FirebaseFirestore.instance.collection('riders').doc(user.uid).set({
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'vehicleType': _vehicleTypeController.text.trim(),
          'vehiclePlate': _vehiclePlateController.text.trim(),
          'aadhaarNumber': _aadhaarController.text.trim(),
          'address': _addressController.text.trim(),
          'dlNumber': _dlNumberController.text.trim(),
          'aadhaarImageUrl': finalAadhaarImageUrl, // Stores URL from Storage
          'dlImageUrl': finalDlImageUrl, // Stores URL from Storage
          'profileImageUrls': finalFaceImageUrls, // Stores LIST of URLs of face photos
          'email': user.email,
          'uid': user.uid,
          'lastUpdated': FieldValue.serverTimestamp(), // Timestamp for when details were saved
        }, SetOptions(merge: true)); // Use merge: true to update fields without overwriting the whole document

        _showMessage('Rider details saved successfully!', Colors.green);
        // After saving, navigate the user to the Home Page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } catch (e) {
        _showMessage('Failed to save details: ${e.toString()}', Colors.redAccent);
        print('Firestore save error: $e'); // Log detailed error
      } finally {
        setState(() {
          _isLoading = false; // Hide loading indicator
        });
      }
    }
  }

  // Helper function to display snackbar messages
  void _showMessage(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Details'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(Icons.person_pin, size: 80, color: Colors.blueAccent.shade700),
                const SizedBox(height: 24.0),
                Text(
                  'Tell us more about yourself and your vehicle!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),

                _buildTextField(_nameController, 'Full Name', Icons.person),
                const SizedBox(height: 16.0),
                _buildTextField(_phoneController, 'Phone Number', Icons.phone,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 16.0),
                _buildTextField(_vehicleTypeController, 'Vehicle Type (e.g., Motorcycle, Car)',
                    Icons.two_wheeler),
                const SizedBox(height: 16.0),
                _buildTextField(_vehiclePlateController, 'Vehicle Plate Number', Icons.credit_card),
                const SizedBox(height: 16.0),

                // New fields: Aadhaar Number and Address
                _buildTextField(_aadhaarController, 'Aadhaar Number', Icons.credit_card,
                    keyboardType: TextInputType.number, minLength: 12, maxLength: 12),
                const SizedBox(height: 16.0),
                _buildTextField(_addressController, 'Full Address', Icons.home,
                    keyboardType: TextInputType.multiline, maxLines: 3),
                const SizedBox(height: 16.0),
                _buildTextField(_dlNumberController, 'Driving License Number', Icons.badge),
                const SizedBox(height: 24.0),

                // NEW: Face Photo Image Picker Section for multiple photos
                _buildFacePhotoPicker(context),
                const SizedBox(height: 24.0),

                // Aadhaar Image Picker Section (single photo)
                _buildSingleImagePicker(
                  context,
                  _aadhaarImage,
                  _currentAadhaarImageUrl, // Pass existing URL
                  'Aadhaar Card Picture',
                      (file) => setState(() => _aadhaarImage = file),
                      (url) => setState(() => _currentAadhaarImageUrl = url),
                ),
                const SizedBox(height: 24.0),

                // Driving License Image Picker Section (single photo)
                _buildSingleImagePicker(
                  context,
                  _dlImage,
                  _currentDlImageUrl, // Pass existing URL
                  'Driving License Picture',
                      (file) => setState(() => _dlImage = file),
                      (url) => setState(() => _currentDlImageUrl = url),
                ),
                const SizedBox(height: 32.0),

                _isLoading
                    ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                    ))
                    : ElevatedButton(
                  onPressed: _saveRiderDetails,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    elevation: 5,
                  ),
                  child: const Text(
                    'Save Details',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget to build consistent text input fields
  Widget _buildTextField(TextEditingController controller, String label, IconData icon,
      {TextInputType keyboardType = TextInputType.text,
        int? minLength,
        int? maxLength,
        int? maxLines = 1}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength, // Max length for text input
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15.0)),
        filled: true,
        fillColor: Colors.blueGrey[50],
        // Only show counter if maxLength is set and text is not empty
        counterText: (maxLength != null && controller.text.isNotEmpty) ? '${controller.text.length}/$maxLength' : null,
      ),
      validator: (value) {
        if (value == null || value.isEmpty && label != 'Full Address') {
          // Address can be optional initially
          return 'Please enter $label';
        }
        if (minLength != null && value != null && value.length < minLength) {
          return '$label must be at least $minLength characters long.';
        }
        if (maxLength != null && value != null && value.length > maxLength) {
          return '$label cannot exceed $maxLength characters.';
        }
        return null;
      },
    );
  }

  // Helper widget for single image picking sections (Aadhaar, DL)
  Widget _buildSingleImagePicker(
      BuildContext context,
      File? imageFile,
      String? imageUrl, // For displaying existing image from URL
      String label,
      Function(File?) setImage,
      Function(String?) setImageUrl, // To clear image URL when new file is picked or cleared
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[700],
          ),
        ),
        const SizedBox(height: 8.0),
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(15.0),
            border: Border.all(color: Colors.blueAccent.shade100, width: 2),
          ),
          child: imageFile != null // If a new local file is selected
              ? ClipRRect(
            borderRadius: BorderRadius.circular(15.0),
            child: Image.file(
              imageFile,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          )
              : imageUrl != null && imageUrl.isNotEmpty // If no local file, but an existing URL exists
              ? ClipRRect(
            borderRadius: BorderRadius.circular(15.0),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 40, color: Colors.red),
                    Text('Failed to load image'),
                  ],
                ),
              ),
            ),
          )
              : Center(
            // If neither local file nor existing URL
            child: Text(
              'No image selected',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _pickSingleImage(ImageSource.camera, setImage, setImageUrl),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Camera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.shade100,
                foregroundColor: Colors.blueGrey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _pickSingleImage(ImageSource.gallery, setImage, setImageUrl),
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.shade100,
                foregroundColor: Colors.blueGrey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            // Only show clear button if an image is selected (either local or from URL)
            if (imageFile != null || (imageUrl != null && imageUrl.isNotEmpty))
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    setImage(null); // Clear local file
                    setImageUrl(null); // Clear URL
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade100,
                  foregroundColor: Colors.blueGrey[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // NEW: Helper widget for Face Photo picking section (multiple photos, camera only)
  Widget _buildFacePhotoPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Face Photos (for Verification)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[700],
          ),
        ),
        const SizedBox(height: 8.0),
        Container(
          height: 150,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(15.0),
            border: Border.all(color: Colors.blueAccent.shade100, width: 2),
          ),
          child: _faceImages.isNotEmpty || _currentFaceImageUrls.isNotEmpty
              ? ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _faceImages.length + _currentFaceImageUrls.length,
            itemBuilder: (context, index) {
              Widget imageWidget;
              if (index < _faceImages.length) {
                // Display newly captured local files
                imageWidget = Image.file(
                  _faceImages[index],
                  fit: BoxFit.cover,
                );
              } else {
                // Display existing uploaded image URLs
                final urlIndex = index - _faceImages.length;
                imageWidget = Image.network(
                  _currentFaceImageUrls[urlIndex],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 20, color: Colors.red),
                        Text('Failed to load'),
                      ],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(4.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.0),
                  child: SizedBox(
                    width: 140, // Fixed width for thumbnails
                    height: 140,
                    child: imageWidget,
                  ),
                ),
              );
            },
          )
              : Center(
            child: Text(
              'No face photos captured yet.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _captureFacePhoto, // Use the new capture function
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture Face Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent.shade100,
                foregroundColor: Colors.blueGrey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (_faceImages.isNotEmpty || _currentFaceImageUrls.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _faceImages.clear(); // Clear all local files
                    _currentFaceImageUrls.clear(); // Clear all stored URLs (implies re-enrollment)
                  });
                  _showMessage('All face photos cleared.', Colors.orange);
                },
                icon: const Icon(Icons.delete_forever),
                label: const Text('Clear All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade100,
                  foregroundColor: Colors.blueGrey[900],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8.0),
        Text(
          'Capture 3-5 photos from different angles for better verification.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
