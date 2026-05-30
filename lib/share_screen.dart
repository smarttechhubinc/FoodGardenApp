import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import 'main_layout.dart';

class ShareScreen extends StatefulWidget {
  final VoidCallback? onShareSuccess;

  const ShareScreen({super.key, this.onShareSuccess});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> with SingleTickerProviderStateMixin {
  final _itemNameController = TextEditingController();
  final _pickupInstructionsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationSearchController = TextEditingController();

  int _quantity = 3;
  String _selectedCategory = 'Vegetables';
  String _selectedUnit = 'lbs';
  bool _isLoading = false;

  // Image related
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _isUploadingImage = false;
  String? _uploadedImageUrl;

  // AI auto-fill
  bool _isAnalyzingImage = false;
  bool _autoFillDone = false;

  // Location related
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _isLoadingLocation = false;
  bool _locationSelected = false;
  String? _locationError;

  static const LatLng _defaultLocation = LatLng(6.5244, 3.3792);

  final List<String> categories = ['Vegetables', 'Fruits', 'Herbs', 'Seeds', 'Other'];
  final List<String> units = ['lbs', 'kg', 'oz', 'pieces', 'bunches'];

  final ApiService _apiService = ApiService();

  // Animation for the auto-fill banner
  late AnimationController _bannerController;
  late Animation<double> _bannerAnimation;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bannerAnimation = CurvedAnimation(parent: _bannerController, curve: Curves.easeOut);
    _clearForm();
    _initializeLocation();
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _pickupInstructionsController.dispose();
    _descriptionController.dispose();
    _locationSearchController.dispose();
    _mapController?.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  // ─────────────── AI Image Analysis ───────────────

Future<void> _analyzeImageAndAutoFill(Uint8List imageBytes) async {
  setState(() {
    _isAnalyzingImage = true;
    _autoFillDone = false;
  });

  try {
    // Get auth token
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    
    if (token == null) {
      print('No auth token available');
      setState(() => _isAnalyzingImage = false);
      return;
    }

    final base64Image = base64Encode(imageBytes);
    
    // Call YOUR backend instead of Claude directly
    final response = await http.post(
      Uri.parse('${_apiService.apiBaseUrl}/api/ai/analyze-image'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'imageBase64': base64Image,
        'contentType': 'image/jpeg',
      }),
    );

    print('📥 AI Analysis Response Status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    final result = jsonDecode(response.body);
    
    if (result['success'] == true && mounted) {
      final data = result['data'];
      final name = (data['name'] as String? ?? '').trim();
      final description = (data['description'] as String? ?? '').trim();
      final category = (data['category'] as String? ?? '').trim();

      if (name.isNotEmpty) {
        print('✅ AI identified: $name (Category: $category)');
        setState(() {
          _itemNameController.text = name;
          _descriptionController.text = description;
          if (categories.contains(category)) {
            _selectedCategory = category;
          }
          _autoFillDone = true;
        });
        _bannerController.forward(from: 0);
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _bannerController.reverse();
        });
      } else {
        print('❌ AI could not identify produce in image');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not identify produce. Please fill in the details manually.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      print('❌ AI Analysis failed: ${result['error']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI analysis failed: ${result['error'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  } catch (e) {
    print('❌ AI image analysis error: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to analyze image: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _isAnalyzingImage = false);
  }
}

  // ─────────────── Location ───────────────

  Future<void> _initializeLocation() async {
    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Tap the map to select a location.';
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permissions denied. Tap the map to select a location.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permanently denied. Tap the map to select a location.';
          _isLoadingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      ).timeout(const Duration(seconds: 15));

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _locationSelected = true;
      });

      await _getAddressFromLatLng(position.latitude, position.longitude);

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 15),
      );
    } catch (e) {
      setState(() {
        _locationError = 'Could not get your location. Tap the map to select a location.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _getAddressFromLatLng(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> parts = [];
        if (place.street?.isNotEmpty == true) parts.add(place.street!);
        if (place.subLocality?.isNotEmpty == true) parts.add(place.subLocality!);
        if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
        if (place.administrativeArea?.isNotEmpty == true) parts.add(place.administrativeArea!);
        if (place.country?.isNotEmpty == true) parts.add(place.country!);

        final address = parts.join(', ');
        if (mounted) {
          setState(() {
            _selectedAddress = address.isNotEmpty
                ? address
                : '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
            _locationSearchController.text = _selectedAddress!;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedAddress = '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
          _locationSearchController.text = _selectedAddress!;
        });
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });
    try {
      List<Location> locations = await locationFromAddress(query)
          .timeout(const Duration(seconds: 10));
      if (locations.isNotEmpty) {
        Location location = locations.first;
        setState(() {
          _selectedLocation = LatLng(location.latitude, location.longitude);
          _locationSelected = true;
        });
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(location.latitude, location.longitude), 15),
        );
        await _getAddressFromLatLng(location.latitude, location.longitude);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not found. Try a different search or tap the map.'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error searching location. Please try again.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_selectedLocation != null) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(_selectedLocation!, 15));
    }
  }

  void _onMapTap(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _locationSelected = true;
      _locationError = null;
    });
    _getAddressFromLatLng(location.latitude, location.longitude);
    _mapController?.animateCamera(CameraUpdate.newLatLng(location));
  }

  // ─────────────── Image Picker ───────────────

Future<void> _pickImage() async {
  final ImagePicker picker = ImagePicker();
  final XFile? image = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 800,
    maxHeight: 800,
    imageQuality: 70, // Reduced quality to 70% for smaller size
  );

  if (image != null && mounted) {
    final bytes = await image.readAsBytes();
    final sizeInMB = bytes.length / (1024 * 1024);
    print('📸 Image size: ${sizeInMB.toStringAsFixed(2)}MB');
    
    if (sizeInMB > 5) {
      // Image still too large, compress more
      final compressedBytes = await _compressImageFurther(image);
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = compressedBytes;
        _uploadedImageUrl = null;
        _autoFillDone = false;
      });
      await _analyzeImageAndAutoFill(compressedBytes);
    } else {
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
        _uploadedImageUrl = null;
        _autoFillDone = false;
      });
      await _analyzeImageAndAutoFill(bytes);
    }
  }
}

Future<Uint8List> _compressImageFurther(XFile image) async {
  // You can use flutter_image_compress package for better compression
  // For now, just read with lower quality
  final ImagePicker picker = ImagePicker();
  final XFile? compressed = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 600,
    maxHeight: 600,
    imageQuality: 50,
  );
  if (compressed != null) {
    return await compressed.readAsBytes();
  }
  return await image.readAsBytes();
}

  Future<String?> _uploadImage() async {
    if (_selectedImage == null || _selectedImageBytes == null) return null;
    if (mounted) setState(() => _isUploadingImage = true);
    try {
      final base64Image = base64Encode(_selectedImageBytes!);
      final result = await _apiService.uploadImageWeb(base64Image, _selectedImage!.name);
      if (result['success'] == true) {
        if (mounted) setState(() => _uploadedImageUrl = result['imageUrl']);
        return result['imageUrl'];
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to upload image'), backgroundColor: Colors.red),
          );
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // ─────────────── Form ───────────────

  void _clearForm() {
    _itemNameController.clear();
    _descriptionController.clear();
    _pickupInstructionsController.clear();
    if (mounted) {
      setState(() {
        _quantity = 3;
        _selectedCategory = 'Vegetables';
        _selectedUnit = 'lbs';
        _selectedImage = null;
        _selectedImageBytes = null;
        _uploadedImageUrl = null;
        _isLoading = false;
        _isUploadingImage = false;
        _autoFillDone = false;
      });
    }
  }

  String _mapCategory(String category) {
    switch (category.toLowerCase()) {
      case 'vegetables': return 'vegetable';
      case 'fruits': return 'fruit';
      case 'herbs': return 'herb';
      case 'flowers': return 'flower';
      case 'seeds': return 'other';
      default: return category.toLowerCase();
    }
  }

  Future<void> _shareItem() async {
    if (_itemNameController.text.trim().isEmpty) {
      _showError('Please enter an item name');
      return;
    }
    if (!_locationSelected || _selectedLocation == null) {
      _showError('Please select a pickup location on the map');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
        if (imageUrl == null) {
          setState(() => _isLoading = false);
          return;
        }
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;

      final itemData = {
        'name': _itemNameController.text.trim(),
        'category': _mapCategory(_selectedCategory),
        'quantity': _quantity,
        'quantity_unit': _selectedUnit,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'pickup_instructions': _pickupInstructionsController.text.trim().isEmpty ? null : _pickupInstructionsController.text.trim(),
        'image_url': imageUrl,
        'location_text': _selectedAddress ?? user?['location'] ?? 'Unknown location',
        'latitude': _selectedLocation?.latitude,
        'longitude': _selectedLocation?.longitude,
      };

      final result = await _apiService.createSharedItem(itemData);

      if (result['success'] == true && mounted) {
        widget.onShareSuccess?.call();
        _clearForm();
      } else if (mounted) {
        _showError(result['error'] ?? 'Failed to share item');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  // ─────────────── BUILD ───────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  _buildTopBar(isDarkMode),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildImageUploader(isDarkMode),
                        // Auto-fill banner
                        FadeTransition(
                          opacity: _bannerAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.3),
                              end: Offset.zero,
                            ).animate(_bannerAnimation),
                            child: _autoFillDone
                                ? _buildAutoFillBanner(isDarkMode)
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildProduceDetailsCard(isDarkMode),
                        const SizedBox(height: 16),
                        _buildLogisticsCard(isDarkMode),
                        const SizedBox(height: 16),
                        _buildLocationCard(isDarkMode),
                        const SizedBox(height: 16),
                        _buildSustainabilityTip(isDarkMode),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomCTA(isDarkMode),
          ],
        ),
      ),
    );
  }

  // ─────────────── Auto-fill Banner ───────────────

  Widget _buildAutoFillBanner(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF39AC86).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF39AC86),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI auto-filled your details!',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF39AC86),
                  ),
                ),
                Text(
                  'Review and edit below if needed.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode ? Colors.white60 : const Color(0xFF5C8A7A),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _bannerController.reverse(),
            child: Icon(Icons.close, size: 16, color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A)),
          ),
        ],
      ),
    );
  }

  // ─────────────── Image Uploader ───────────────

  Widget _buildImageUploader(bool isDarkMode) {
    return GestureDetector(
      onTap: (_isUploadingImage || _isAnalyzingImage) ? null : _pickImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _selectedImageBytes != null
              ? Colors.transparent
              : const Color(0xFF39AC86).withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _selectedImageBytes != null
                ? const Color(0xFF39AC86).withOpacity(0.4)
                : const Color(0xFF39AC86).withOpacity(0.3),
            width: 2,
          ),
        ),
        child: _selectedImageBytes != null
            ? _buildImagePreview(isDarkMode)
            : _buildImagePlaceholder(isDarkMode),
      ),
    );
  }

  Widget _buildImagePreview(bool isDarkMode) {
    return Stack(
      children: [
        // Image
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            _selectedImageBytes!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),

        // AI analyzing overlay
        if (_isAnalyzingImage)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.black.withOpacity(0.55),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'AI is identifying your produce...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 120,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF39AC86)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Top-right actions
        if (!_isAnalyzingImage)
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                // Re-analyze button
                GestureDetector(
                  onTap: () => _analyzeImageAndAutoFill(_selectedImageBytes!),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF39AC86).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('Re-scan', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                // Remove button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImage = null;
                      _selectedImageBytes = null;
                      _uploadedImageUrl = null;
                      _autoFillDone = false;
                    });
                    _bannerController.reverse();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),

        // Bottom label when done
        if (!_isAnalyzingImage && _autoFillDone)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF39AC86), size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Produce identified • Tap to change photo',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePlaceholder(bool isDarkMode) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF39AC86).withOpacity(0.2),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(Icons.eco, color: Color(0xFF39AC86), size: 48),
        ),
        const SizedBox(height: 16),
        const Text(
          'Capture the Harvest',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Add a photo — AI will auto-fill the name & description for you',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode ? const Color(0xFFA0C4B8) : const Color(0xFF5C8A7A),
          ),
        ),
        const SizedBox(height: 8),
        // AI badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF39AC86).withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF39AC86), size: 12),
              SizedBox(width: 5),
              Text(
                'AI-powered auto-fill',
                style: TextStyle(fontSize: 11, color: Color(0xFF39AC86), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF39AC86),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_a_photo, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Upload Photo', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────── Top Bar ───────────────

  Widget _buildTopBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onShareSuccess?.call(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.close, color: Colors.black87, size: 24),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Share Your Surplus',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.centerRight,
              child: const Text(
                'Help',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF39AC86)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Produce Details Card ───────────────

  Widget _buildProduceDetailsCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Produce Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isAnalyzingImage)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39AC86)),
                      ),
                      SizedBox(width: 6),
                      Text('AI filling...', style: TextStyle(fontSize: 11, color: Color(0xFF39AC86), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Item Name with AI indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Item Name',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                    ),
                  ),
                  if (_autoFillDone) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: Color(0xFF39AC86)),
                          SizedBox(width: 3),
                          Text('AI filled', style: TextStyle(fontSize: 9, color: Color(0xFF39AC86), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _autoFillDone
                        ? const Color(0xFF39AC86).withOpacity(0.4)
                        : const Color(0xFF39AC86).withOpacity(0.1),
                    width: _autoFillDone ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _itemNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Heirloom Roma Tomatoes',
                    hintStyle: TextStyle(color: const Color(0xFF5C8A7A).withOpacity(0.6)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    suffixIcon: _isAnalyzingImage
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39AC86)),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Description with AI indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Description (Optional)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                    ),
                  ),
                  if (_autoFillDone) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: Color(0xFF39AC86)),
                          SizedBox(width: 3),
                          Text('AI filled', style: TextStyle(fontSize: 9, color: Color(0xFF39AC86), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _autoFillDone
                        ? const Color(0xFF39AC86).withOpacity(0.4)
                        : const Color(0xFF39AC86).withOpacity(0.1),
                    width: _autoFillDone ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe your produce...',
                    hintStyle: TextStyle(color: const Color(0xFF5C8A7A).withOpacity(0.6)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Category Chips
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                    ),
                  ),
                  if (_autoFillDone) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: Color(0xFF39AC86)),
                          SizedBox(width: 3),
                          Text('AI filled', style: TextStyle(fontSize: 9, color: Color(0xFF39AC86), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = _selectedCategory == category;
                    return Container(
                      margin: EdgeInsets.only(right: index < categories.length - 1 ? 8 : 0),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: isSelected,
                        selectedColor: const Color(0xFF39AC86),
                        backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFEAF1EE),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDarkMode ? Colors.white : const Color(0xFF101816)),
                        ),
                        onSelected: (selected) => setState(() => _selectedCategory = category),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────── Logistics Card ───────────────

  Widget _buildLogisticsCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quantity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('How much can you share?', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
                ],
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() { if (_quantity > 1) _quantity--; }),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.remove, color: Color(0xFF39AC86), size: 24),
                    ),
                  ),
                  Row(
                    children: [
                      Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      DropdownButton<String>(
                        value: _selectedUnit,
                        items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                        onChanged: (v) => setState(() => _selectedUnit = v!),
                        underline: Container(),
                        icon: const Icon(Icons.arrow_drop_down),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _quantity++),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add, color: Color(0xFF39AC86), size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFF39AC86).withOpacity(0.05), height: 1),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick-up Instructions',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : const Color(0xFF101816)),
              ),
              const SizedBox(height: 8),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.1)),
                ),
                child: TextField(
                  controller: _pickupInstructionsController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'e.g. Left in a basket on the porch bench. Help yourself!',
                    hintStyle: TextStyle(color: const Color(0xFF5C8A7A).withOpacity(0.6)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────── Location Card ───────────────

  Widget _buildLocationCard(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFF39AC86), size: 20),
              const SizedBox(width: 8),
              const Text('Pickup Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isLoadingLocation)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39AC86)))
              else
                GestureDetector(
                  onTap: _getCurrentLocation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF39AC86).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.my_location, color: Color(0xFF39AC86), size: 16),
                        SizedBox(width: 4),
                        Text('Use My Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF39AC86))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Search field
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.1)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search, color: Color(0xFF5C8A7A), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _locationSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search for an address',
                      hintStyle: TextStyle(color: const Color(0xFF5C8A7A).withOpacity(0.6)),
                      border: InputBorder.none,
                    ),
                    onSubmitted: _searchLocation,
                  ),
                ),
                if (_locationSearchController.text.isNotEmpty)
                  IconButton(
                    onPressed: () => setState(() => _locationSearchController.clear()),
                    icon: const Icon(Icons.clear, color: Color(0xFF5C8A7A), size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Map
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: CameraPosition(
                      target: _selectedLocation ?? _defaultLocation,
                      zoom: 12,
                    ),
                    onTap: _onMapTap,
                    markers: _selectedLocation != null
                        ? {
                            Marker(
                              markerId: const MarkerId('selected-location'),
                              position: _selectedLocation!,
                              draggable: true,
                              onDragEnd: _onMapTap,
                            ),
                          }
                        : {},
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                  ),
                  if (_isLoadingLocation)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(child: CircularProgressIndicator(color: Color(0xFF39AC86))),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedAddress != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF39AC86).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF39AC86), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedAddress!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_locationError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_locationError!, style: const TextStyle(color: Colors.orange, fontSize: 12), textAlign: TextAlign.center),
            ),
          if (_selectedLocation == null && _locationError == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Tap on the map to select your pickup location',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white38 : const Color(0xFF808080), fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────── Sustainability Tip ───────────────

  Widget _buildSustainabilityTip(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE38B6D).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE38B6D).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco, color: Color(0xFFE38B6D), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Harvest Tip', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFE38B6D))),
                const SizedBox(height: 4),
                Text(
                  "By sharing your surplus, you're preventing approximately 1.5kg of methane emissions from landfill waste!",
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.white.withOpacity(0.8) : const Color(0xFF101816).withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Bottom CTA ───────────────

  Widget _buildBottomCTA(bool isDarkMode) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF212C28).withOpacity(0.8)
              : const Color(0xFFF9F8F6).withOpacity(0.8),
          border: Border(top: BorderSide(color: const Color(0xFF39AC86).withOpacity(0.05))),
        ),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: _isLoading ? Colors.grey : const Color(0xFF39AC86),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _isLoading ? null : _shareItem,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _isLoading
                    ? [const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))]
                    : [
                        const Icon(Icons.celebration, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Text('Post to Marketplace', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}








// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:provider/provider.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import '../services/api_service.dart';
// import '../providers/auth_provider.dart';
// import 'main_layout.dart';

// class ShareScreen extends StatefulWidget {
//   final VoidCallback? onShareSuccess;
  
//   const ShareScreen({super.key, this.onShareSuccess});

//   @override
//   State<ShareScreen> createState() => _ShareScreenState();
// }

// class _ShareScreenState extends State<ShareScreen> {
//   final _itemNameController = TextEditingController();
//   final _pickupInstructionsController = TextEditingController();
//   final _descriptionController = TextEditingController();
//   final _locationSearchController = TextEditingController();
  
//   int _quantity = 3;
//   String _selectedCategory = 'Vegetables';
//   String _selectedUnit = 'lbs';
//   bool _isLoading = false;
  
//   // Image related
//   XFile? _selectedImage;
//   Uint8List? _selectedImageBytes;
//   bool _isUploadingImage = false;
//   String? _uploadedImageUrl;
  
//   // Location related
//   GoogleMapController? _mapController;
//   LatLng? _selectedLocation;
//   String? _selectedAddress;
//   bool _isLoadingLocation = false;
//   bool _locationSelected = false;
//   String? _locationError;
  
//   // Initial camera position (default to a central location)
//   static const LatLng _defaultLocation = LatLng(6.5244, 3.3792); // Lagos, Nigeria
  
//   final List<String> categories = ['Vegetables', 'Fruits', 'Herbs', 'Seeds', 'Other'];
//   final List<String> units = ['lbs', 'kg', 'oz', 'pieces', 'bunches'];
  
//   final ApiService _apiService = ApiService();

//   @override
//   void initState() {
//     super.initState();
//     _clearForm();
//     _initializeLocation();
//   }

//   @override
//   void dispose() {
//     _itemNameController.dispose();
//     _pickupInstructionsController.dispose();
//     _descriptionController.dispose();
//     _locationSearchController.dispose();
//     _mapController?.dispose();
//     super.dispose();
//   }

//   Future<void> _initializeLocation() async {
//     // Try to get current location, but don't block if it fails
//     await _getCurrentLocation();
//   }

//   Future<void> _getCurrentLocation() async {
//     setState(() {
//       _isLoadingLocation = true;
//       _locationError = null;
//     });

//     try {
//       // Check if location services are enabled
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         setState(() {
//           _locationError = 'Location services are disabled. Please enable them or tap on the map to select a location.';
//           _isLoadingLocation = false;
//         });
//         return;
//       }

//       // Check permissions
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           setState(() {
//             _locationError = 'Location permissions are denied. Please tap on the map to select a location.';
//             _isLoadingLocation = false;
//           });
//           return;
//         }
//       }
      
//       if (permission == LocationPermission.deniedForever) {
//         setState(() {
//           _locationError = 'Location permissions are permanently denied. Please tap on the map to select a location.';
//           _isLoadingLocation = false;
//         });
//         return;
//       }

//       // Get current position with timeout
//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 10),
//       ).timeout(const Duration(seconds: 15));

//       setState(() {
//         _selectedLocation = LatLng(position.latitude, position.longitude);
//         _locationSelected = true;
//       });

//       // Get address from coordinates
//       await _getAddressFromLatLng(position.latitude, position.longitude);
      
//       // Move camera to current location
//       _mapController?.animateCamera(
//         CameraUpdate.newLatLngZoom(
//           LatLng(position.latitude, position.longitude),
//           15,
//         ),
//       );

//     } catch (e) {
//       print('Error getting location: $e');
//       setState(() {
//         _locationError = 'Could not get your location. Please tap on the map to select a location.';
//       });
      
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Could not get your location. Please tap on the map to select a location.'),
//             backgroundColor: Colors.orange,
//             duration: const Duration(seconds: 3),
//           ),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoadingLocation = false;
//         });
//       }
//     }
//   }

//   Future<void> _getAddressFromLatLng(double latitude, double longitude) async {
//     try {
//       List<Placemark> placemarks = await placemarkFromCoordinates(
//         latitude, 
//         longitude,
//       ).timeout(const Duration(seconds: 5));
      
//       if (placemarks.isNotEmpty && placemarks.first != null) {
//         Placemark place = placemarks.first;
        
//         // Build address string safely
//         List<String> addressParts = [];
        
//         if (place.street != null && place.street!.isNotEmpty) 
//           addressParts.add(place.street!);
//         if (place.subLocality != null && place.subLocality!.isNotEmpty) 
//           addressParts.add(place.subLocality!);
//         if (place.locality != null && place.locality!.isNotEmpty) 
//           addressParts.add(place.locality!);
//         if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) 
//           addressParts.add(place.administrativeArea!);
//         if (place.postalCode != null && place.postalCode!.isNotEmpty) 
//           addressParts.add(place.postalCode!);
//         if (place.country != null && place.country!.isNotEmpty) 
//           addressParts.add(place.country!);
        
//         String address = addressParts.join(', ');
        
//         if (address.isNotEmpty && mounted) {
//           setState(() {
//             _selectedAddress = address;
//             _locationSearchController.text = address;
//           });
//         } else if (mounted) {
//           // Fallback to coordinates if no address found
//           setState(() {
//             _selectedAddress = '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
//             _locationSearchController.text = _selectedAddress!;
//           });
//         }
//       } else if (mounted) {
//         // Fallback to coordinates
//         setState(() {
//           _selectedAddress = '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
//           _locationSearchController.text = _selectedAddress!;
//         });
//       }
//     } catch (e) {
//       print('Error getting address: $e');
//       if (mounted) {
//         // Fallback to coordinates
//         setState(() {
//           _selectedAddress = '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
//           _locationSearchController.text = _selectedAddress!;
//         });
//       }
//     }
//   }

//   Future<void> _searchLocation(String query) async {
//     if (query.isEmpty) return;

//     setState(() {
//       _isLoadingLocation = true;
//       _locationError = null;
//     });

//     try {
//       List<Location> locations = await locationFromAddress(query)
//           .timeout(const Duration(seconds: 10));
      
//       if (locations.isNotEmpty && locations.first != null) {
//         Location location = locations.first;
        
//         if (mounted) {
//           setState(() {
//             _selectedLocation = LatLng(location.latitude, location.longitude);
//             _locationSelected = true;
//           });
//         }
        
//         _mapController?.animateCamera(
//           CameraUpdate.newLatLngZoom(
//             LatLng(location.latitude, location.longitude),
//             15,
//           ),
//         );
        
//         // Get the actual address for this location
//         await _getAddressFromLatLng(location.latitude, location.longitude);
        
//       } else if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Location not found. Please try a different search or tap on the map.'),
//             backgroundColor: Colors.orange,
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error searching location: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Error searching location. Please try again or tap on the map.'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoadingLocation = false;
//         });
//       }
//     }
//   }

//   void _onMapCreated(GoogleMapController controller) {
//     _mapController = controller;
//     if (_selectedLocation != null) {
//       controller.animateCamera(
//         CameraUpdate.newLatLngZoom(_selectedLocation!, 15),
//       );
//     }
//   }

//   void _onMapTap(LatLng location) {
//     if (mounted) {
//       setState(() {
//         _selectedLocation = location;
//         _locationSelected = true;
//         _locationError = null;
//       });
//     }
    
//     _getAddressFromLatLng(location.latitude, location.longitude);
    
//     // Add a marker by updating the map
//     _mapController?.animateCamera(
//       CameraUpdate.newLatLng(location),
//     );
//   }

//   void _clearForm() {
//     _itemNameController.clear();
//     _descriptionController.clear();
//     _pickupInstructionsController.clear();
//     if (mounted) {
//       setState(() {
//         _quantity = 3;
//         _selectedCategory = 'Vegetables';
//         _selectedUnit = 'lbs';
//         _selectedImage = null;
//         _selectedImageBytes = null;
//         _uploadedImageUrl = null;
//         _isLoading = false;
//         _isUploadingImage = false;
//         // Don't clear location as user might want to keep it
//       });
//     }
//   }

//   Future<void> _pickImage() async {
//     final ImagePicker picker = ImagePicker();
//     final XFile? image = await picker.pickImage(
//       source: ImageSource.gallery,
//       maxWidth: 800,
//       maxHeight: 800,
//       imageQuality: 85,
//     );
    
//     if (image != null && mounted) {
//       final bytes = await image.readAsBytes();
//       setState(() {
//         _selectedImage = image;
//         _selectedImageBytes = bytes;
//         _uploadedImageUrl = null;
//       });
//     }
//   }

//   Future<String?> _uploadImage() async {
//     if (_selectedImage == null || _selectedImageBytes == null) return null;
    
//     if (mounted) {
//       setState(() {
//         _isUploadingImage = true;
//       });
//     }
    
//     try {
//       final base64Image = base64Encode(_selectedImageBytes!);
//       final fileName = _selectedImage!.name;

//       final result = await _apiService.uploadImageWeb(base64Image, fileName);
      
//       if (result['success'] == true) {
//         final imageUrl = result['imageUrl'];
//         if (mounted) {
//           setState(() {
//             _uploadedImageUrl = imageUrl;
//           });
//         }
//         return imageUrl;
//       } else {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(result['error'] ?? 'Failed to upload image'),
//               backgroundColor: Colors.red,
//             ),
//           );
//         }
//         return null;
//       }
//     } catch (e) {
//       print('❌ Upload image error: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Error uploading image: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//       return null;
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isUploadingImage = false;
//         });
//       }
//     }
//   }

//   String _mapCategory(String category) {
//     switch(category.toLowerCase()) {
//       case 'vegetables': return 'vegetable';
//       case 'fruits': return 'fruit';
//       case 'herbs': return 'herb';
//       case 'flowers': return 'flower';
//       case 'seeds': return 'other';
//       default: return category.toLowerCase();
//     }
//   }

//   Future<void> _shareItem() async {
//     // Validate
//     if (_itemNameController.text.trim().isEmpty) {
//       _showError('Please enter an item name');
//       return;
//     }

//     if (!_locationSelected || _selectedLocation == null) {
//       _showError('Please select a pickup location on the map');
//       return;
//     }

//     if (mounted) {
//       setState(() {
//         _isLoading = true;
//       });
//     }

//     try {
//       // Upload image if selected
//       String? imageUrl;
//       if (_selectedImage != null) {
//         imageUrl = await _uploadImage();
//         if (imageUrl == null && mounted) {
//           setState(() {
//             _isLoading = false;
//           });
//           return;
//         }
//       }

//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final user = authProvider.currentUser;

//       final itemData = {
//         'name': _itemNameController.text.trim(),
//         'category': _mapCategory(_selectedCategory),
//         'quantity': _quantity,
//         'quantity_unit': _selectedUnit,
//         'description': _descriptionController.text.trim().isEmpty 
//             ? null 
//             : _descriptionController.text.trim(),
//         'pickup_instructions': _pickupInstructionsController.text.trim().isEmpty
//             ? null
//             : _pickupInstructionsController.text.trim(),
//         'image_url': imageUrl,
//         'location_text': _selectedAddress ?? user?['location'] ?? 'Unknown location',
//         'latitude': _selectedLocation?.latitude,
//         'longitude': _selectedLocation?.longitude,
//       };

//       print('📤 Sharing item with location: $itemData');
      
//       final result = await _apiService.createSharedItem(itemData);

//       if (result['success'] == true && mounted) {
//         // Call the success callback to navigate home
//         widget.onShareSuccess?.call();
        
//         // Clear the form for next time
//         _clearForm();
//       } else if (mounted) {
//         _showError(result['error'] ?? 'Failed to share item');
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       print('❌ Share error: $e');
//       if (mounted) {
//         _showError('Error: $e');
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   void _showError(String message) {
//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(message),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//       body: SafeArea(
//         bottom: false,
//         child: Stack(
//           children: [
//             SingleChildScrollView(
//               child: Column(
//                 children: [
//                   // Top App Bar
//                   _buildTopBar(isDarkMode),
                  
//                   // Main Content
//                   Padding(
//                     padding: const EdgeInsets.all(16),
//                     child: Column(
//                       children: [
//                         // Hero Photo Uploader
//                         _buildImageUploader(isDarkMode),

//                         const SizedBox(height: 24),

//                         // Produce Details Card
//                         _buildProduceDetailsCard(isDarkMode),

//                         const SizedBox(height: 16),

//                         // Quantity & Logistics Card
//                         _buildLogisticsCard(isDarkMode),

//                         const SizedBox(height: 16),

//                         // Location Card with Map
//                         _buildLocationCard(isDarkMode),

//                         const SizedBox(height: 16),

//                         // Sustainability Tip
//                         _buildSustainabilityTip(isDarkMode),

//                         const SizedBox(height: 100),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Sticky Bottom CTA
//             _buildBottomCTA(isDarkMode),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Row(
//         children: [
//           // Close Button
//           GestureDetector(
//             onTap: () {
//               widget.onShareSuccess?.call();
//             },
//             child: Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//                 borderRadius: BorderRadius.circular(20),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withOpacity(0.05),
//                     blurRadius: 20,
//                     offset: const Offset(0, 4),
//                   ),
//                 ],
//               ),
//               child: const Icon(
//                 Icons.close,
//                 color: Colors.black87,
//                 size: 24,
//               ),
//             ),
//           ),
//           // Title
//           Expanded(
//             child: Center(
//               child: Text(
//                 'Share Your Surplus',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                 ),
//               ),
//             ),
//           ),
//           // Help Button
//           SizedBox(
//             width: 40,
//             child: Align(
//               alignment: Alignment.centerRight,
//               child: Text(
//                 'Help',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                   color: const Color(0xFF39AC86),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildLocationCard(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 20,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               const Icon(
//                 Icons.location_on,
//                 color: Color(0xFF39AC86),
//                 size: 20,
//               ),
//               const SizedBox(width: 8),
//               const Text(
//                 'Pickup Location',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const Spacer(),
//               if (_isLoadingLocation)
//                 const SizedBox(
//                   width: 20,
//                   height: 20,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2,
//                     color: Color(0xFF39AC86),
//                   ),
//                 ),
//               if (!_isLoadingLocation)
//                 GestureDetector(
//                   onTap: _getCurrentLocation,
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 12,
//                       vertical: 6,
//                     ),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF39AC86).withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: const Row(
//                       children: [
//                         Icon(
//                           Icons.my_location,
//                           color: Color(0xFF39AC86),
//                           size: 16,
//                         ),
//                         SizedBox(width: 4),
//                         Text(
//                           'Use My Location',
//                           style: TextStyle(
//                             fontSize: 12,
//                             fontWeight: FontWeight.bold,
//                             color: Color(0xFF39AC86),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//             ],
//           ),
          
//           const SizedBox(height: 16),

//           // Location Search Field
//           Container(
//             height: 48,
//             decoration: BoxDecoration(
//               color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//               borderRadius: BorderRadius.circular(12),
//               border: Border.all(
//                 color: const Color(0xFF39AC86).withOpacity(0.1),
//               ),
//             ),
//             child: Row(
//               children: [
//                 const SizedBox(width: 16),
//                 const Icon(
//                   Icons.search,
//                   color: Color(0xFF5C8A7A),
//                   size: 20,
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: TextField(
//                     controller: _locationSearchController,
//                     decoration: InputDecoration(
//                       hintText: 'Search for an address',
//                       hintStyle: TextStyle(
//                         color: const Color(0xFF5C8A7A).withOpacity(0.6),
//                       ),
//                       border: InputBorder.none,
//                     ),
//                     onSubmitted: _searchLocation,
//                   ),
//                 ),
//                 if (_locationSearchController.text.isNotEmpty)
//                   IconButton(
//                     onPressed: () {
//                       setState(() {
//                         _locationSearchController.clear();
//                       });
//                     },
//                     icon: const Icon(
//                       Icons.clear,
//                       color: Color(0xFF5C8A7A),
//                       size: 18,
//                     ),
//                   ),
//               ],
//             ),
//           ),

//           const SizedBox(height: 16),

//           // Map Container
//           Container(
//             height: 200,
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(12),
//               border: Border.all(
//                 color: const Color(0xFF39AC86).withOpacity(0.2),
//               ),
//             ),
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(12),
//               child: Stack(
//                 children: [
//                   GoogleMap(
//                     onMapCreated: _onMapCreated,
//                     initialCameraPosition: CameraPosition(
//                       target: _selectedLocation ?? _defaultLocation,
//                       zoom: 12,
//                     ),
//                     onTap: _onMapTap,
//                     markers: _selectedLocation != null
//                         ? {
//                             Marker(
//                               markerId: const MarkerId('selected-location'),
//                               position: _selectedLocation!,
//                               draggable: true,
//                               onDragEnd: (newPosition) {
//                                 _onMapTap(newPosition);
//                               },
//                             ),
//                           }
//                         : {},
//                     myLocationEnabled: true,
//                     myLocationButtonEnabled: false,
//                     zoomControlsEnabled: false,
//                     mapToolbarEnabled: false,
//                     compassEnabled: false,
//                   ),
//                   if (_isLoadingLocation)
//                     Container(
//                       color: Colors.black.withOpacity(0.3),
//                       child: const Center(
//                         child: CircularProgressIndicator(
//                           color: Color(0xFF39AC86),
//                         ),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ),

//           const SizedBox(height: 12),

//           // Selected Address Display
//           if (_selectedAddress != null)
//             Container(
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.05),
//                 borderRadius: BorderRadius.circular(12),
//                 border: Border.all(
//                   color: const Color(0xFF39AC86).withOpacity(0.2),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   const Icon(
//                     Icons.check_circle,
//                     color: Color(0xFF39AC86),
//                     size: 16,
//                   ),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       _selectedAddress!,
//                       style: const TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.w500,
//                       ),
//                       maxLines: 2,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//           if (_locationError != null)
//             Padding(
//               padding: const EdgeInsets.all(12),
//               child: Text(
//                 _locationError!,
//                 style: const TextStyle(
//                   color: Colors.orange,
//                   fontSize: 12,
//                 ),
//                 textAlign: TextAlign.center,
//               ),
//             ),

//           if (_selectedLocation == null && _locationError == null)
//             Padding(
//               padding: const EdgeInsets.all(16),
//               child: Center(
//                 child: Text(
//                   'Tap on the map to select your pickup location',
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
//                     fontStyle: FontStyle.italic,
//                   ),
//                   textAlign: TextAlign.center,
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildImageUploader(bool isDarkMode) {
//     return GestureDetector(
//       onTap: _isUploadingImage ? null : _pickImage,
//       child: Container(
//         padding: const EdgeInsets.all(24),
//         decoration: BoxDecoration(
//           color: const Color(0xFF39AC86).withOpacity(0.05),
//           borderRadius: BorderRadius.circular(16),
//           border: Border.all(
//             color: const Color(0xFF39AC86).withOpacity(0.3),
//             width: 2,
//           ),
//         ),
//         child: _selectedImageBytes != null
//             ? Stack(
//                 alignment: Alignment.topRight,
//                 children: [
//                   ClipRRect(
//                     borderRadius: BorderRadius.circular(12),
//                     child: Image.memory(
//                       _selectedImageBytes!,
//                       height: 150,
//                       width: double.infinity,
//                       fit: BoxFit.cover,
//                     ),
//                   ),
//                   GestureDetector(
//                     onTap: () {
//                       setState(() {
//                         _selectedImage = null;
//                         _selectedImageBytes = null;
//                         _uploadedImageUrl = null;
//                       });
//                     },
//                     child: Container(
//                       margin: const EdgeInsets.all(8),
//                       padding: const EdgeInsets.all(4),
//                       decoration: BoxDecoration(
//                         color: Colors.black.withOpacity(0.5),
//                         shape: BoxShape.circle,
//                       ),
//                       child: const Icon(
//                         Icons.close,
//                         color: Colors.white,
//                         size: 16,
//                       ),
//                     ),
//                   ),
//                 ],
//               )
//             : Column(
//                 children: [
//                   Container(
//                     width: 80,
//                     height: 80,
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF39AC86).withOpacity(0.2),
//                       borderRadius: BorderRadius.circular(40),
//                     ),
//                     child: _isUploadingImage
//                         ? const CircularProgressIndicator(color: Color(0xFF39AC86))
//                         : const Icon(
//                             Icons.eco,
//                             color: Color(0xFF39AC86),
//                             size: 48,
//                           ),
//                   ),
//                   const SizedBox(height: 16),
//                   const Text(
//                     'Capture the Harvest',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Add a photo of your produce to attract neighbors',
//                     textAlign: TextAlign.center,
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: isDarkMode 
//                           ? const Color(0xFFA0C4B8) 
//                           : const Color(0xFF5C8A7A),
//                     ),
//                   ),
//                   const SizedBox(height: 24),
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 24,
//                       vertical: 12,
//                     ),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF39AC86),
//                       borderRadius: BorderRadius.circular(12),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withOpacity(0.05),
//                           blurRadius: 20,
//                           offset: const Offset(0, 4),
//                         ),
//                       ],
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         const Icon(
//                           Icons.add_a_photo,
//                           color: Colors.white,
//                           size: 20,
//                         ),
//                         const SizedBox(width: 8),
//                         const Text(
//                           'Upload Photo',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 14,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//       ),
//     );
//   }

//   Widget _buildProduceDetailsCard(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 20,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Produce Details',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 16),

//           // Item Name Field
//           _buildTextField(
//             isDarkMode,
//             controller: _itemNameController,
//             label: 'Item Name',
//             hint: 'e.g. Heirloom Roma Tomatoes',
//           ),

//           const SizedBox(height: 16),

//           // Description Field
//           _buildTextField(
//             isDarkMode,
//             controller: _descriptionController,
//             label: 'Description (Optional)',
//             hint: 'Describe your produce...',
//             maxLines: 3,
//           ),

//           const SizedBox(height: 16),

//           // Category Chips
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Category',
//                 style: TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.w600,
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                 ),
//               ),
//               const SizedBox(height: 8),
//               SizedBox(
//                 height: 36,
//                 child: ListView.builder(
//                   scrollDirection: Axis.horizontal,
//                   itemCount: categories.length,
//                   itemBuilder: (context, index) {
//                     final category = categories[index];
//                     final isSelected = _selectedCategory == category;
                    
//                     return Container(
//                       margin: EdgeInsets.only(
//                         right: index < categories.length - 1 ? 8 : 0,
//                       ),
//                       child: ChoiceChip(
//                         label: Text(category),
//                         selected: isSelected,
//                         selectedColor: const Color(0xFF39AC86),
//                         backgroundColor: isDarkMode 
//                             ? const Color(0xFF212C28) 
//                             : const Color(0xFFEAF1EE),
//                         labelStyle: TextStyle(
//                           color: isSelected 
//                               ? Colors.white 
//                               : (isDarkMode ? Colors.white : const Color(0xFF101816)),
//                         ),
//                         onSelected: (selected) {
//                           setState(() {
//                             _selectedCategory = category;
//                           });
//                         },
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildLogisticsCard(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 20,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           // Quantity Stepper
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Quantity',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   Text(
//                     'How much can you share?',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Color(0xFF5C8A7A),
//                     ),
//                   ),
//                 ],
//               ),
//               Row(
//                 children: [
//                   // Decrease Button
//                   GestureDetector(
//                     onTap: () {
//                       setState(() {
//                         if (_quantity > 1) _quantity--;
//                       });
//                     },
//                     child: Container(
//                       width: 40,
//                       height: 40,
//                       decoration: BoxDecoration(
//                         color: Colors.transparent,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: const Icon(
//                         Icons.remove,
//                         color: Color(0xFF39AC86),
//                         size: 24,
//                       ),
//                     ),
//                   ),
//                   // Quantity Display with Unit Dropdown
//                   Row(
//                     children: [
//                       Text(
//                         '$_quantity',
//                         style: const TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       const SizedBox(width: 4),
//                       DropdownButton<String>(
//                         value: _selectedUnit,
//                         items: units.map((unit) {
//                           return DropdownMenuItem(
//                             value: unit,
//                             child: Text(unit),
//                           );
//                         }).toList(),
//                         onChanged: (value) {
//                           setState(() {
//                             _selectedUnit = value!;
//                           });
//                         },
//                         underline: Container(),
//                         icon: const Icon(Icons.arrow_drop_down),
//                       ),
//                     ],
//                   ),
//                   // Increase Button
//                   GestureDetector(
//                     onTap: () {
//                       setState(() {
//                         _quantity++;
//                       });
//                     },
//                     child: Container(
//                       width: 40,
//                       height: 40,
//                       decoration: BoxDecoration(
//                         color: Colors.transparent,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: const Icon(
//                         Icons.add,
//                         color: Color(0xFF39AC86),
//                         size: 24,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),

//           const SizedBox(height: 16),

//           // Divider
//           Divider(
//             color: isDarkMode 
//                 ? Colors.white.withOpacity(0.05) 
//                 : const Color(0xFF39AC86).withOpacity(0.05),
//             height: 1,
//           ),

//           const SizedBox(height: 16),

//           // Pick-up Instructions
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Pick-up Instructions',
//                 style: TextStyle(
//                   fontSize: 14,
//                   fontWeight: FontWeight.w600,
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                 ),
//               ),
//               const SizedBox(height: 8),
//               Container(
//                 height: 100,
//                 decoration: BoxDecoration(
//                   color: isDarkMode 
//                       ? const Color(0xFF212C28) 
//                       : const Color(0xFFF9F8F6),
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                   ),
//                 ),
//                 child: TextField(
//                   controller: _pickupInstructionsController,
//                   maxLines: 4,
//                   decoration: InputDecoration(
//                     hintText: 'e.g. Left in a basket on the porch bench. Help yourself!',
//                     hintStyle: TextStyle(
//                       color: const Color(0xFF5C8A7A).withOpacity(0.6),
//                     ),
//                     border: InputBorder.none,
//                     contentPadding: const EdgeInsets.all(16),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSustainabilityTip(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: const Color(0xFFE38B6D).withOpacity(0.1),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(
//           color: const Color(0xFFE38B6D).withOpacity(0.2),
//         ),
//       ),
//       child: Row(
//         children: [
//           const Icon(
//             Icons.eco,
//             color: Color(0xFFE38B6D),
//             size: 24,
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Harvest Tip',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: const Color(0xFFE38B6D),
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   "By sharing your surplus, you're preventing approximately 1.5kg of methane emissions from landfill waste!",
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode 
//                         ? Colors.white.withOpacity(0.8) 
//                         : const Color(0xFF101816).withOpacity(0.8),
//                     height: 1.5,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildBottomCTA(bool isDarkMode) {
//     return Positioned(
//       bottom: 0,
//       left: 0,
//       right: 0,
//       child: Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: isDarkMode 
//               ? const Color(0xFF212C28).withOpacity(0.8)
//               : const Color(0xFFF9F8F6).withOpacity(0.8),
//           border: Border(
//             top: BorderSide(
//               color: const Color(0xFF39AC86).withOpacity(0.05),
//             ),
//           ),
//         ),
//         child: Container(
//           width: double.infinity,
//           height: 56,
//           decoration: BoxDecoration(
//             color: _isLoading ? Colors.grey : const Color(0xFF39AC86),
//             borderRadius: BorderRadius.circular(12),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.05),
//                 blurRadius: 20,
//                 offset: const Offset(0, 4),
//               ),
//             ],
//           ),
//           child: Material(
//             color: Colors.transparent,
//             child: InkWell(
//               borderRadius: BorderRadius.circular(12),
//               onTap: _isLoading ? null : _shareItem,
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: _isLoading
//                     ? [
//                         const SizedBox(
//                           width: 24,
//                           height: 24,
//                           child: CircularProgressIndicator(
//                             strokeWidth: 2,
//                             color: Colors.white,
//                           ),
//                         ),
//                       ]
//                     : [
//                         const Icon(
//                           Icons.celebration,
//                           color: Colors.white,
//                           size: 20,
//                         ),
//                         const SizedBox(width: 8),
//                         const Text(
//                           'Post to Marketplace',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTextField(
//     bool isDarkMode, {
//     required TextEditingController controller,
//     required String label,
//     required String hint,
//     int maxLines = 1,
//   }) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           label,
//           style: TextStyle(
//             fontSize: 14,
//             fontWeight: FontWeight.w600,
//             color: isDarkMode ? Colors.white : const Color(0xFF101816),
//           ),
//         ),
//         const SizedBox(height: 6),
//         Container(
//           decoration: BoxDecoration(
//             color: isDarkMode 
//                 ? const Color(0xFF212C28) 
//                 : const Color(0xFFF9F8F6),
//             borderRadius: BorderRadius.circular(12),
//             border: Border.all(
//               color: const Color(0xFF39AC86).withOpacity(0.1),
//             ),
//           ),
//           child: TextField(
//             controller: controller,
//             maxLines: maxLines,
//             decoration: InputDecoration(
//               hintText: hint,
//               hintStyle: TextStyle(
//                 color: const Color(0xFF5C8A7A).withOpacity(0.6),
//               ),
//               border: InputBorder.none,
//               contentPadding: const EdgeInsets.all(16),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }




