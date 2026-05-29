import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'messages_screen.dart';
import 'chat_screen.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> productData;

  const ProductDetailsScreen({
    super.key,
    required this.productData,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final ApiService _apiService = ApiService();

  // Location related
  GoogleMapController? _mapController;
  LatLng? _pickupLocation;
  LatLng? _userLocation;
  double? _distanceInKm;
  bool _isLoadingLocation = true;
  String? _locationError;
  String? _locationAddress;
  
  // Hardiness Zone
  String? _hardinessZone;
  bool _isLoadingZone = false;
  Map<String, dynamic> _zoneInfo = {};

  // Product data
  late Map<String, dynamic> _productData;
  int _currentQuantity;
  bool _isRequesting = false;
  bool _hasExistingRequest = false;
  String? _existingRequestStatus;
  int? _existingRequestQuantity;

  // Hardiness zones data
  final Map<String, Map<String, dynamic>> _hardinessZones = {
    'Zone 1': {'tempRange': 'Below -50°F', 'color': '#2C3E5C', 'emoji': '❄️', 'description': 'Extreme cold, very short growing season'},
    'Zone 2': {'tempRange': '-50°F to -40°F', 'color': '#3E5A8A', 'emoji': '❄️', 'description': 'Very cold, short growing season'},
    'Zone 3': {'tempRange': '-40°F to -30°F', 'color': '#4F7AB3', 'emoji': '🌡️', 'description': 'Cold winters, moderate summers'},
    'Zone 4': {'tempRange': '-30°F to -20°F', 'color': '#609CD9', 'emoji': '🌡️', 'description': 'Cold climate, good for hardy vegetables'},
    'Zone 5': {'tempRange': '-20°F to -10°F', 'color': '#71BDFF', 'emoji': '🌿', 'description': 'Temperate, diverse growing options'},
    'Zone 6': {'tempRange': '-10°F to 0°F', 'color': '#8ACC66', 'emoji': '🌿', 'description': 'Mild winters, long growing season'},
    'Zone 7': {'tempRange': '0°F to 10°F', 'color': '#A5D95E', 'emoji': '☀️', 'description': 'Warm, excellent for fruit trees'},
    'Zone 8': {'tempRange': '10°F to 20°F', 'color': '#BFF055', 'emoji': '☀️', 'description': 'Warm, subtropical plants thrive'},
    'Zone 9': {'tempRange': '20°F to 30°F', 'color': '#D9FF4C', 'emoji': '🌴', 'description': 'Hot, year-round growing possible'},
    'Zone 10': {'tempRange': '30°F to 40°F', 'color': '#F2F242', 'emoji': '🌴', 'description': 'Tropical, year-round gardening'},
  };

  _ProductDetailsScreenState() : _currentQuantity = 0;

  @override
  void initState() {
    super.initState();
    _productData = widget.productData;
    _currentQuantity = _productData['quantity'] ?? 0;
    _initializeLocation();
    _checkExistingRequest();
  }

  Future<void> _checkExistingRequest() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) return;

      final result = await _apiService.getUserProductRequest(_productData['id']);

      if (result['success'] == true && result['request'] != null) {
        final request = result['request'];
        setState(() {
          _hasExistingRequest = true;
          _existingRequestStatus = request['status'];
          _existingRequestQuantity = request['quantity'];
        });
      }
    } catch (e) {
      print('Error checking existing request: $e');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    final latitude = _productData['latitude'];
    final longitude = _productData['longitude'];

    if (latitude != null && longitude != null) {
      setState(() {
        _pickupLocation = LatLng(latitude.toDouble(), longitude.toDouble());
      });
      await _getAddressFromCoordinates(latitude.toDouble(), longitude.toDouble());
      await _getHardinessZone(latitude.toDouble(), longitude.toDouble());
    }

    await _getUserLocation();
  }

  Future<void> _getHardinessZone(double lat, double lng) async {
    setState(() {
      _isLoadingZone = true;
    });

    try {
      // Calculate zone based on latitude (simplified)
      String zoneName;
      if (lat > 60) zoneName = 'Zone 1';
      else if (lat > 55) zoneName = 'Zone 2';
      else if (lat > 50) zoneName = 'Zone 3';
      else if (lat > 45) zoneName = 'Zone 4';
      else if (lat > 40) zoneName = 'Zone 5';
      else if (lat > 35) zoneName = 'Zone 6';
      else if (lat > 30) zoneName = 'Zone 7';
      else if (lat > 25) zoneName = 'Zone 8';
      else if (lat > 20) zoneName = 'Zone 9';
      else zoneName = 'Zone 10';

      setState(() {
        _hardinessZone = zoneName;
        _zoneInfo = _hardinessZones[zoneName]!;
        _isLoadingZone = false;
      });
    } catch (e) {
      print('Error getting hardiness zone: $e');
      setState(() {
        _isLoadingZone = false;
      });
    }
  }

  Future<void> _getAddressFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[];

        if (place.street != null && place.street!.isNotEmpty) parts.add(place.street!);
        if (place.subLocality != null && place.subLocality!.isNotEmpty) parts.add(place.subLocality!);
        if (place.locality != null && place.locality!.isNotEmpty) parts.add(place.locality!);
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) parts.add(place.administrativeArea!);
        if (place.postalCode != null && place.postalCode!.isNotEmpty) parts.add(place.postalCode!);

        setState(() {
          _locationAddress = parts.isNotEmpty ? parts.join(', ') : 'Pickup location';
        });
      }
    } catch (e) {
      print('Error getting address: $e');
      setState(() {
        _locationAddress = _productData['location_text'] ?? 'Pickup location';
      });
    }
  }

  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permissions are permanently denied';
          _isLoadingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      if (_pickupLocation != null && _userLocation != null) {
        _calculateDistance();
        _animateCameraToShowBoth();
      } else if (_pickupLocation != null) {
        _animateCameraToPickup();
      }
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _locationError = 'Could not get your location';
      });
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _calculateDistance() {
    if (_pickupLocation == null || _userLocation == null) return;

    double distanceInMeters = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      _pickupLocation!.latitude,
      _pickupLocation!.longitude,
    );

    setState(() {
      _distanceInKm = distanceInMeters / 1000;
    });
  }

  void _animateCameraToShowBoth() {
    if (_mapController == null) return;
    if (_pickupLocation == null || _userLocation == null) return;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        _pickupLocation!.latitude < _userLocation!.latitude
            ? _pickupLocation!.latitude
            : _userLocation!.latitude,
        _pickupLocation!.longitude < _userLocation!.longitude
            ? _pickupLocation!.longitude
            : _userLocation!.longitude,
      ),
      northeast: LatLng(
        _pickupLocation!.latitude > _userLocation!.latitude
            ? _pickupLocation!.latitude
            : _userLocation!.latitude,
        _pickupLocation!.longitude > _userLocation!.longitude
            ? _pickupLocation!.longitude
            : _userLocation!.longitude,
      ),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _animateCameraToPickup() {
    if (_mapController == null || _pickupLocation == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(_pickupLocation!, 15),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_pickupLocation != null && _userLocation != null) {
      _animateCameraToShowBoth();
    } else if (_pickupLocation != null) {
      _animateCameraToPickup();
    }
  }

  Future<void> _openInMaps() async {
    if (_pickupLocation == null) return;

    final url =
        'https://www.google.com/maps/search/?api=1&query=${_pickupLocation!.latitude},${_pickupLocation!.longitude}';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open maps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showRequestDialog() {
    int requestedQuantity = 1;
    final TextEditingController messageController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'Request Produce',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Send a request to the gardener',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _productData['image_url'] ?? '',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey[200],
                            child: const Icon(Icons.eco, color: Color(0xFF39AC86)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _productData['name'] ?? 'Fresh Produce',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$_currentQuantity ${_productData['quantity_unit'] ?? 'units'} available',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF39AC86),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Quantity (Max 3)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (requestedQuantity > 1) {
                            setSheetState(() {
                              requestedQuantity--;
                            });
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.remove, color: Color(0xFF39AC86)),
                        ),
                      ),
                      Text(
                        '$requestedQuantity',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (requestedQuantity < 3 && requestedQuantity < _currentQuantity) {
                            setSheetState(() {
                              requestedQuantity++;
                            });
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Color(0xFF39AC86)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'Message (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Add a message to the gardener...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _sendRequest(requestedQuantity, messageController.text);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF39AC86),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Send Request',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Center(
                  child: Text(
                    'Maximum 3 items per request',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendRequest(int quantity, String message) async {
    setState(() {
      _isRequesting = true;
    });

    try {
      final result = await _apiService.createProductRequest(
        productId: _productData['id'],
        quantity: quantity,
        message: message,
      );

      if (result['success'] == true) {
        final chatId = result['chat']['id'];
        final request = result['request'];

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUser = authProvider.currentUser;
        final ownerId = _productData['user_id'];
        final ownerName = _productData['users']?['name'] ?? 'Gardener';
        final ownerImage = _productData['users']?['profile_image_url'] ?? '';

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                itemName: _productData['name'] ?? 'Produce',
                userName: ownerName,
                userImage: ownerImage,
                productId: _productData['id'],
                productStatus: _productData['status'],
                quantity: _currentQuantity,
                recipientId: ownerId,
                chatId: chatId,
                requestData: {
                  'id': request['id'],
                  'quantity': quantity,
                  'status': 'pending',
                  'message': message,
                },
              ),
            ),
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent! Waiting for gardener to accept.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(result['error'] ?? 'Failed to send request');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isRequesting = false;
      });
    }
  }

  void _navigateToMessages() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final ownerId = _productData['user_id'];

    if (currentUser != null && ownerId != null) {
      if (currentUser['id'] == ownerId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This is your own listing'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MessagesScreen(
            recipientId: ownerId,
            recipientName: _productData['users']?['name'] ?? 'Gardener',
            recipientImage: _productData['users']?['profile_image_url'],
            productId: _productData['id'],
            productName: _productData['name'],
            productStatus: _productData['status'],
            productQuantity: _currentQuantity,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to send messages'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  String _getDistanceText() {
    if (_distanceInKm == null) return 'Distance unknown';
    if (_distanceInKm! < 1) {
      return '${(_distanceInKm! * 1000).toStringAsFixed(0)} m away';
    }
    return '${_distanceInKm!.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final imageUrl = _productData['image_url'] ??
        (_productData['imageUrl'] ??
            'https://lh3.googleusercontent.com/aida-public/AB6AXuDpxtSHzBQyEV3GHn4NJkaTgBDJvhkEmCPE_fYJKhG9nq3CdJ8RU3QCqpXLtCOQ0icow0WTwxn7XXJ8jSbNHXkXZMVCyyETaL_dqDF1qohnoQyLQCJNBbBZzouqvthS4kIwmme_0n_kylD71ANsa-Skd2viP8puRco7WpiL_tDd4IaJGiS7hwFo3XL2PzoEIb37olQn2rW5s9WWiek2L7tIkKyg_AWACHrxMui4OL7w74QJq0LtcyXVlPEXyZ64Nk_redTn5MvsYrCs');

    final name = _productData['name'] ?? 'Fresh Produce';
    final description = _productData['description'] ?? 'Freshly harvested from a local garden.';
    final quantityUnit = _productData['quantity_unit'] ?? 'lbs';
    final itemLeftText = _currentQuantity == 0 ? 'Claimed' : '$_currentQuantity $quantityUnit left';

    final userData = _productData['users'] ?? {};
    final userName = userData['name'] ?? 'Local Gardener';
    final userImage = userData['profile_image_url'] ?? '';

    bool isOwner = false;
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      isOwner = currentUser['id'] == _productData['user_id'];
    }

    bool canRequest = !isOwner && _currentQuantity > 0 && !_hasExistingRequest;
    String buttonText = '';
    Color buttonColor = const Color(0xFF39AC86);
    bool buttonEnabled = false;

    if (isOwner) {
      buttonText = 'Your Listing';
      buttonColor = Colors.grey;
      buttonEnabled = false;
    } else if (_hasExistingRequest) {
      if (_existingRequestStatus == 'pending') {
        buttonText =
            'Request Pending (${_existingRequestQuantity ?? ''} ${_existingRequestQuantity == 1 ? 'item' : 'items'})';
        buttonColor = Colors.orange;
        buttonEnabled = false;
      } else if (_existingRequestStatus == 'accepted') {
        buttonText = 'Request Accepted! Contact Gardener';
        buttonColor = const Color(0xFF39AC86);
        buttonEnabled = true;
      } else if (_existingRequestStatus == 'declined') {
        buttonText = 'Request Declined';
        buttonColor = Colors.red;
        buttonEnabled = false;
      } else {
        buttonText = 'Already Requested';
        buttonColor = Colors.grey;
        buttonEnabled = false;
      }
    } else if (_currentQuantity == 0) {
      buttonText = 'All Claimed';
      buttonColor = Colors.grey;
      buttonEnabled = false;
    } else {
      buttonText = 'Request Produce';
      buttonColor = const Color(0xFF39AC86);
      buttonEnabled = true;
    }

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF1A2421) : const Color(0xFFF9F8F6),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Hero Image
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFF39AC86).withOpacity(0.1),
                            child: const Center(
                              child: Icon(
                                Icons.eco,
                                size: 64,
                                color: Color(0xFF39AC86),
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.5),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Info Card
                Container(
                  margin: const EdgeInsets.fromLTRB(16, -80, 16, 0),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: isDarkMode
                          ? const Color(0xFF3A4A44)
                          : const Color(0xFFF0F2F1),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF39AC86).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _productData['status'] == 'available' && _currentQuantity > 0
                                    ? 'Freshly Harvested'
                                    : _productData['status'] ?? 'Available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF39AC86),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Text(
                              itemLeftText,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _currentQuantity == 0
                                    ? Colors.grey
                                    : const Color(0xFFE59866),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : const Color(0xFF101816),
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildTag('Organic', Icons.eco),
                              const SizedBox(width: 8),
                              _buildTag('Pesticide Free', Icons.check_circle),
                              const SizedBox(width: 8),
                              _buildTag('Today', Icons.schedule),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(
                          color: isDarkMode
                              ? const Color(0xFF3A4A44)
                              : const Color(0xFFF0F2F1),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _navigateToMessages,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFF39AC86).withOpacity(0.3),
                                    width: 2,
                                  ),
                                  image: userImage.isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(userImage),
                                          fit: BoxFit.cover,
                                          onError: (exception, stackTrace) {},
                                        )
                                      : null,
                                ),
                                child: userImage.isEmpty
                                    ? const Icon(Icons.person, color: Color(0xFF39AC86))
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    userName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF101816),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '4.9 ★ (120 shares)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF5C8A7A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: _navigateToMessages,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? const Color(0xFF2D3A35)
                                      : const Color(0xFFF9F8F6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Message',
                                  style: TextStyle(
                                    color: Color(0xFF39AC86),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Garden Story
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.menu_book,
                            color: Color(0xFF39AC86),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Garden Story',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : const Color(0xFF101816),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode
                              ? const Color(0xFFA1B8B0)
                              : const Color(0xFF5C8A7A),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // NEW: Hardiness Zone Card (Transparent/Sleek)
                if (_hardinessZone != null && !_isLoadingZone)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))).withOpacity(0.15),
                          Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))).withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              _zoneInfo['emoji'],
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _hardinessZone!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF39AC86),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'GROWS HERE',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _zoneInfo['description'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _zoneInfo['tempRange'],
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(int.parse(_zoneInfo['color'].replaceFirst('#', '0xFF'))),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Pickup Location Section (with human-readable address)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFF39AC86),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Pickup Location',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF101816),
                                ),
                              ),
                            ],
                          ),
                          if (_distanceInKm != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF39AC86).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _getDistanceText(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF39AC86),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Human-readable address card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF39AC86).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF39AC86).withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF39AC86).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.location_pin,
                                color: Color(0xFF39AC86),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pickup Address',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF39AC86),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _locationAddress ?? 'Loading address...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                                      height: 1.3,
                                    ),
                                  ),
                                  if (_productData['pickup_instructions'] != null) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 14,
                                          color: const Color(0xFFE59866),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _productData['pickup_instructions'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: const Color(0xFFE59866),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),

                      // Map
                      Container(
                        height: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF39AC86).withOpacity(0.3),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              if (_pickupLocation != null)
                                GoogleMap(
                                  onMapCreated: _onMapCreated,
                                  initialCameraPosition: CameraPosition(
                                    target: _pickupLocation!,
                                    zoom: 14,
                                  ),
                                  markers: {
                                    if (_pickupLocation != null)
                                      Marker(
                                        markerId: const MarkerId('pickup-location'),
                                        position: _pickupLocation!,
                                        infoWindow: InfoWindow(
                                          title: 'Pickup Location',
                                          snippet: _locationAddress,
                                        ),
                                        icon: BitmapDescriptor.defaultMarkerWithHue(
                                          BitmapDescriptor.hueGreen,
                                        ),
                                      ),
                                    if (_userLocation != null)
                                      Marker(
                                        markerId: const MarkerId('user-location'),
                                        position: _userLocation!,
                                        infoWindow: const InfoWindow(
                                          title: 'Your Location',
                                        ),
                                        icon: BitmapDescriptor.defaultMarkerWithHue(
                                          BitmapDescriptor.hueBlue,
                                        ),
                                      ),
                                  },
                                  myLocationEnabled: true,
                                  myLocationButtonEnabled: false,
                                  zoomControlsEnabled: true,
                                  compassEnabled: true,
                                  mapToolbarEnabled: false,
                                )
                              else
                                Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Text('Location not available'),
                                  ),
                                ),

                              if (_isLoadingLocation)
                                Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF39AC86),
                                    ),
                                  ),
                                ),

                              // Map Controls
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Column(
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        onPressed: () {
                                          _mapController?.animateCamera(
                                            CameraUpdate.zoomIn(),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.add,
                                          color: Color(0xFF39AC86),
                                          size: 20,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        onPressed: () {
                                          _mapController?.animateCamera(
                                            CameraUpdate.zoomOut(),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.remove,
                                          color: Color(0xFF39AC86),
                                          size: 20,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        onPressed: _getUserLocation,
                                        icon: const Icon(
                                          Icons.my_location,
                                          color: Color(0xFF39AC86),
                                          size: 20,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Get Directions Button
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: _openInMaps,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF39AC86),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.directions,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Get Directions',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_locationError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _locationError!,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),

          // Top Navigation Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const Text(
                    'Produce Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? const Color(0xFF3A4A44)
                        : const Color(0xFFF0F2F1),
                  ),
                ),
              ),
              child: GestureDetector(
                onTap: buttonEnabled
                    ? (_existingRequestStatus == 'accepted'
                        ? _navigateToMessages
                        : _showRequestDialog)
                    : null,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: _isRequesting ? Colors.grey : buttonColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: buttonEnabled
                        ? [
                            BoxShadow(
                              color: buttonColor.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _isRequesting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            buttonText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF39AC86).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF39AC86),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF39AC86),
            ),
          ),
        ],
      ),
    );
  }
}







// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:provider/provider.dart';
// import 'messages_screen.dart';
// import 'chat_screen.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class ProductDetailsScreen extends StatefulWidget {
//   final Map<String, dynamic> productData;

//   const ProductDetailsScreen({
//     super.key,
//     required this.productData,
//   });

//   @override
//   State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
// }

// class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
//   final ApiService _apiService = ApiService();

//   // Location related
//   GoogleMapController? _mapController;
//   LatLng? _pickupLocation;
//   LatLng? _userLocation;
//   double? _distanceInKm;
//   bool _isLoadingLocation = true;
//   String? _locationError;
//   String? _locationAddress;

//   // Product data
//   late Map<String, dynamic> _productData;
//   int _currentQuantity;
//   bool _isRequesting = false;
//   bool _hasExistingRequest = false;
//   String? _existingRequestStatus;
//   int? _existingRequestQuantity;

//   _ProductDetailsScreenState() : _currentQuantity = 0;

//   @override
//   void initState() {
//     super.initState();
//     _productData = widget.productData;
//     _currentQuantity = _productData['quantity'] ?? 0;
//     _initializeLocation();
//     _checkExistingRequest();
//   }

//   Future<void> _checkExistingRequest() async {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUser = authProvider.currentUser;

//       if (currentUser == null) return;

//       final result = await _apiService.getUserProductRequest(_productData['id']);

//       if (result['success'] == true && result['request'] != null) {
//         final request = result['request'];
//         setState(() {
//           _hasExistingRequest = true;
//           _existingRequestStatus = request['status'];
//           _existingRequestQuantity = request['quantity'];
//         });
//       }
//     } catch (e) {
//       print('Error checking existing request: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _mapController?.dispose();
//     super.dispose();
//   }

//   Future<void> _initializeLocation() async {
//     final latitude = _productData['latitude'];
//     final longitude = _productData['longitude'];

//     if (latitude != null && longitude != null) {
//       setState(() {
//         _pickupLocation = LatLng(latitude.toDouble(), longitude.toDouble());
//       });
//       await _getAddressFromCoordinates(latitude.toDouble(), longitude.toDouble());
//     }

//     await _getUserLocation();
//   }

//   Future<void> _getAddressFromCoordinates(double lat, double lng) async {
//     try {
//       List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
//       if (placemarks.isNotEmpty) {
//         final place = placemarks.first;
//         final parts = <String>[];

//         if (place.street != null && place.street!.isNotEmpty) parts.add(place.street!);
//         if (place.subLocality != null && place.subLocality!.isNotEmpty) parts.add(place.subLocality!);
//         if (place.locality != null && place.locality!.isNotEmpty) parts.add(place.locality!);
//         if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) parts.add(place.administrativeArea!);

//         setState(() {
//           _locationAddress = parts.isNotEmpty ? parts.join(', ') : 'Pickup location';
//         });
//       }
//     } catch (e) {
//       print('Error getting address: $e');
//       setState(() {
//         _locationAddress = _productData['location_text'] ?? 'Pickup location';
//       });
//     }
//   }

//   Future<void> _getUserLocation() async {
//     setState(() {
//       _isLoadingLocation = true;
//       _locationError = null;
//     });

//     try {
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//       }

//       if (permission == LocationPermission.deniedForever) {
//         setState(() {
//           _locationError = 'Location permissions are permanently denied';
//           _isLoadingLocation = false;
//         });
//         return;
//       }

//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 10),
//       );

//       setState(() {
//         _userLocation = LatLng(position.latitude, position.longitude);
//       });

//       if (_pickupLocation != null && _userLocation != null) {
//         _calculateDistance();
//         _animateCameraToShowBoth();
//       } else if (_pickupLocation != null) {
//         _animateCameraToPickup();
//       }
//     } catch (e) {
//       print('Error getting location: $e');
//       setState(() {
//         _locationError = 'Could not get your location';
//       });
//     } finally {
//       setState(() {
//         _isLoadingLocation = false;
//       });
//     }
//   }

//   void _calculateDistance() {
//     if (_pickupLocation == null || _userLocation == null) return;

//     double distanceInMeters = Geolocator.distanceBetween(
//       _userLocation!.latitude,
//       _userLocation!.longitude,
//       _pickupLocation!.latitude,
//       _pickupLocation!.longitude,
//     );

//     setState(() {
//       _distanceInKm = distanceInMeters / 1000;
//     });
//   }

//   void _animateCameraToShowBoth() {
//     if (_mapController == null) return;
//     if (_pickupLocation == null || _userLocation == null) return;

//     LatLngBounds bounds = LatLngBounds(
//       southwest: LatLng(
//         _pickupLocation!.latitude < _userLocation!.latitude
//             ? _pickupLocation!.latitude
//             : _userLocation!.latitude,
//         _pickupLocation!.longitude < _userLocation!.longitude
//             ? _pickupLocation!.longitude
//             : _userLocation!.longitude,
//       ),
//       northeast: LatLng(
//         _pickupLocation!.latitude > _userLocation!.latitude
//             ? _pickupLocation!.latitude
//             : _userLocation!.latitude,
//         _pickupLocation!.longitude > _userLocation!.longitude
//             ? _pickupLocation!.longitude
//             : _userLocation!.longitude,
//       ),
//     );

//     _mapController!.animateCamera(
//       CameraUpdate.newLatLngBounds(bounds, 50),
//     );
//   }

//   void _animateCameraToPickup() {
//     if (_mapController == null || _pickupLocation == null) return;
//     _mapController!.animateCamera(
//       CameraUpdate.newLatLngZoom(_pickupLocation!, 15),
//     );
//   }

//   void _onMapCreated(GoogleMapController controller) {
//     _mapController = controller;
//     if (_pickupLocation != null && _userLocation != null) {
//       _animateCameraToShowBoth();
//     } else if (_pickupLocation != null) {
//       _animateCameraToPickup();
//     }
//   }

//   Future<void> _openInMaps() async {
//     if (_pickupLocation == null) return;

//     final url =
//         'https://www.google.com/maps/search/?api=1&query=${_pickupLocation!.latitude},${_pickupLocation!.longitude}';
//     final uri = Uri.parse(url);

//     if (await canLaunchUrl(uri)) {
//       await launchUrl(uri);
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Could not open maps'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   void _showRequestDialog() {
//     int requestedQuantity = 1;
//     final TextEditingController messageController = TextEditingController();

//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) => StatefulBuilder(
//         builder: (context, setSheetState) {
//           return Padding(
//             padding: EdgeInsets.only(
//               bottom: MediaQuery.of(context).viewInsets.bottom,
//               left: 24,
//               right: 24,
//               top: 24,
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Center(
//                   child: Text(
//                     'Request Produce',
//                     style: TextStyle(
//                       fontSize: 20,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 const Center(
//                   child: Text(
//                     'Send a request to the gardener',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.grey,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 24),

//                 // Product info
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(8),
//                         child: Image.network(
//                           _productData['image_url'] ?? '',
//                           width: 50,
//                           height: 50,
//                           fit: BoxFit.cover,
//                           errorBuilder: (context, error, stack) => Container(
//                             width: 50,
//                             height: 50,
//                             color: Colors.grey[200],
//                             child: const Icon(Icons.eco, color: Color(0xFF39AC86)),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               _productData['name'] ?? 'Fresh Produce',
//                               style: const TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             Text(
//                               '$_currentQuantity ${_productData['quantity_unit'] ?? 'units'} available',
//                               style: const TextStyle(
//                                 fontSize: 12,
//                                 color: Color(0xFF39AC86),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 const SizedBox(height: 20),

//                 // Quantity selector
//                 const Text(
//                   'Quantity (Max 3)',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   decoration: BoxDecoration(
//                     border: Border.all(color: Colors.grey[300]!),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       GestureDetector(
//                         onTap: () {
//                           if (requestedQuantity > 1) {
//                             setSheetState(() {
//                               requestedQuantity--;
//                             });
//                           }
//                         },
//                         child: Container(
//                           width: 40,
//                           height: 40,
//                           decoration: BoxDecoration(
//                             color: Colors.grey[200],
//                             shape: BoxShape.circle,
//                           ),
//                           child: const Icon(Icons.remove, color: Color(0xFF39AC86)),
//                         ),
//                       ),
//                       Text(
//                         '$requestedQuantity',
//                         style: const TextStyle(
//                           fontSize: 24,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       GestureDetector(
//                         onTap: () {
//                           if (requestedQuantity < 3 && requestedQuantity < _currentQuantity) {
//                             setSheetState(() {
//                               requestedQuantity++;
//                             });
//                           }
//                         },
//                         child: Container(
//                           width: 40,
//                           height: 40,
//                           decoration: BoxDecoration(
//                             color: Colors.grey[200],
//                             shape: BoxShape.circle,
//                           ),
//                           child: const Icon(Icons.add, color: Color(0xFF39AC86)),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 const SizedBox(height: 20),

//                 // Message
//                 const Text(
//                   'Message (Optional)',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 TextField(
//                   controller: messageController,
//                   maxLines: 3,
//                   decoration: InputDecoration(
//                     hintText: 'Add a message to the gardener...',
//                     border: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                 ),

//                 const SizedBox(height: 24),

//                 Row(
//                   children: [
//                     Expanded(
//                       child: OutlinedButton(
//                         onPressed: () => Navigator.pop(context),
//                         style: OutlinedButton.styleFrom(
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                         ),
//                         child: const Text('Cancel'),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: ElevatedButton(
//                         onPressed: () async {
//                           Navigator.pop(context);
//                           await _sendRequest(requestedQuantity, messageController.text);
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: const Color(0xFF39AC86),
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                         ),
//                         child: const Text(
//                           'Send Request',
//                           style: TextStyle(fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),

//                 const SizedBox(height: 16),

//                 Center(
//                   child: Text(
//                     'Maximum 3 items per request',
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: Colors.grey[600],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Future<void> _sendRequest(int quantity, String message) async {
//     setState(() {
//       _isRequesting = true;
//     });

//     try {
//       final result = await _apiService.createProductRequest(
//         productId: _productData['id'],
//         quantity: quantity,
//         message: message,
//       );

//       if (result['success'] == true) {
//         final chatId = result['chat']['id'];
//         final request = result['request'];

//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         final currentUser = authProvider.currentUser;
//         final ownerId = _productData['user_id'];
//         final ownerName = _productData['users']?['name'] ?? 'Gardener';
//         final ownerImage = _productData['users']?['profile_image_url'] ?? '';

//         if (mounted) {
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => ChatScreen(
//                 itemName: _productData['name'] ?? 'Produce',
//                 userName: ownerName,
//                 userImage: ownerImage,
//                 productId: _productData['id'],
//                 productStatus: _productData['status'],
//                 quantity: _currentQuantity,
//                 recipientId: ownerId,
//                 chatId: chatId,
//                 requestData: {
//                   'id': request['id'],
//                   'quantity': quantity,
//                   'status': 'pending',
//                   'message': message,
//                 },
//               ),
//             ),
//           );
//         }

//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Request sent! Waiting for gardener to accept.'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       } else {
//         throw Exception(result['error'] ?? 'Failed to send request');
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to send request: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       setState(() {
//         _isRequesting = false;
//       });
//     }
//   }

//   void _navigateToMessages() {
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;
//     final ownerId = _productData['user_id'];

//     if (currentUser != null && ownerId != null) {
//       if (currentUser['id'] == ownerId) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('This is your own listing'),
//             backgroundColor: Colors.orange,
//           ),
//         );
//         return;
//       }

//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => MessagesScreen(
//             recipientId: ownerId,
//             recipientName: _productData['users']?['name'] ?? 'Gardener',
//             recipientImage: _productData['users']?['profile_image_url'],
//             productId: _productData['id'],
//             productName: _productData['name'],
//             productStatus: _productData['status'],
//             productQuantity: _currentQuantity,
//           ),
//         ),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please login to send messages'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//     }
//   }

//   String _getDistanceText() {
//     if (_distanceInKm == null) return 'Distance unknown';
//     if (_distanceInKm! < 1) {
//       return '${(_distanceInKm! * 1000).toStringAsFixed(0)} m away';
//     }
//     return '${_distanceInKm!.toStringAsFixed(1)} km away';
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     final imageUrl = _productData['image_url'] ??
//         (_productData['imageUrl'] ??
//             'https://lh3.googleusercontent.com/aida-public/AB6AXuDpxtSHzBQyEV3GHn4NJkaTgBDJvhkEmCPE_fYJKhG9nq3CdJ8RU3QCqpXLtCOQ0icow0WTwxn7XXJ8jSbNHXkXZMVCyyETaL_dqDF1qohnoQyLQCJNBbBZzouqvthS4kIwmme_0n_kylD71ANsa-Skd2viP8puRco7WpiL_tDd4IaJGiS7hwFo3XL2PzoEIb37olQn2rW5s9WWiek2L7tIkKyg_AWACHrxMui4OL7w74QJq0LtcyXVlPEXyZ64Nk_redTn5MvsYrCs');

//     final name = _productData['name'] ?? 'Fresh Produce';
//     final description = _productData['description'] ?? 'Freshly harvested from a local garden.';
//     final quantityUnit = _productData['quantity_unit'] ?? 'lbs';
//     final itemLeftText = _currentQuantity == 0 ? 'Claimed' : '$_currentQuantity $quantityUnit left';

//     final userData = _productData['users'] ?? {};
//     final userName = userData['name'] ?? 'Local Gardener';
//     final userImage = userData['profile_image_url'] ?? '';

//     bool isOwner = false;
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUser = authProvider.currentUser;
//     if (currentUser != null) {
//       isOwner = currentUser['id'] == _productData['user_id'];
//     }

//     bool canRequest = !isOwner && _currentQuantity > 0 && !_hasExistingRequest;
//     String buttonText = '';
//     Color buttonColor = const Color(0xFF39AC86);
//     bool buttonEnabled = false;

//     if (isOwner) {
//       buttonText = 'Your Listing';
//       buttonColor = Colors.grey;
//       buttonEnabled = false;
//     } else if (_hasExistingRequest) {
//       if (_existingRequestStatus == 'pending') {
//         buttonText =
//             'Request Pending (${_existingRequestQuantity ?? ''} ${_existingRequestQuantity == 1 ? 'item' : 'items'})';
//         buttonColor = Colors.orange;
//         buttonEnabled = false;
//       } else if (_existingRequestStatus == 'accepted') {
//         buttonText = 'Request Accepted! Contact Gardener';
//         buttonColor = const Color(0xFF39AC86);
//         buttonEnabled = true;
//       } else if (_existingRequestStatus == 'declined') {
//         buttonText = 'Request Declined';
//         buttonColor = Colors.red;
//         buttonEnabled = false;
//       } else {
//         buttonText = 'Already Requested';
//         buttonColor = Colors.grey;
//         buttonEnabled = false;
//       }
//     } else if (_currentQuantity == 0) {
//       buttonText = 'All Claimed';
//       buttonColor = Colors.grey;
//       buttonEnabled = false;
//     } else {
//       buttonText = 'Request Produce';
//       buttonColor = const Color(0xFF39AC86);
//       buttonEnabled = true;
//     }

//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF1A2421) : const Color(0xFFF9F8F6),
//       body: Stack(
//         children: [
//           SingleChildScrollView(
//             child: Column(
//               children: [
//                 SizedBox(
//                   height: MediaQuery.of(context).size.height * 0.45,
//                   width: double.infinity,
//                   child: Stack(
//                     fit: StackFit.expand,
//                     children: [
//                       Image.network(
//                         imageUrl,
//                         fit: BoxFit.cover,
//                         errorBuilder: (context, error, stackTrace) {
//                           return Container(
//                             color: const Color(0xFF39AC86).withOpacity(0.1),
//                             child: const Center(
//                               child: Icon(
//                                 Icons.eco,
//                                 size: 64,
//                                 color: Color(0xFF39AC86),
//                               ),
//                             ),
//                           );
//                         },
//                       ),
//                       Container(
//                         decoration: BoxDecoration(
//                           gradient: LinearGradient(
//                             begin: Alignment.topCenter,
//                             end: Alignment.bottomCenter,
//                             colors: [
//                               Colors.transparent,
//                               Colors.black.withOpacity(0.5),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 Container(
//                   margin: const EdgeInsets.fromLTRB(16, -80, 16, 0),
//                   decoration: BoxDecoration(
//                     color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
//                     borderRadius: BorderRadius.circular(16),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.black.withOpacity(0.1),
//                         blurRadius: 20,
//                         offset: const Offset(0, 4),
//                       ),
//                     ],
//                     border: Border.all(
//                       color: isDarkMode
//                           ? const Color(0xFF3A4A44)
//                           : const Color(0xFFF0F2F1),
//                     ),
//                   ),
//                   child: Padding(
//                     padding: const EdgeInsets.all(24),
//                     child: Column(
//                       children: [
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Container(
//                               padding: const EdgeInsets.symmetric(
//                                 horizontal: 12,
//                                 vertical: 6,
//                               ),
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                 borderRadius: BorderRadius.circular(20),
//                               ),
//                               child: Text(
//                                 _productData['status'] == 'available' && _currentQuantity > 0
//                                     ? 'Freshly Harvested'
//                                     : _productData['status'] ?? 'Available',
//                                 style: const TextStyle(
//                                   fontSize: 12,
//                                   fontWeight: FontWeight.bold,
//                                   color: Color(0xFF39AC86),
//                                   letterSpacing: 0.5,
//                                 ),
//                               ),
//                             ),
//                             Text(
//                               itemLeftText,
//                               style: TextStyle(
//                                 fontSize: 18,
//                                 fontWeight: FontWeight.bold,
//                                 color: _currentQuantity == 0
//                                     ? Colors.grey
//                                     : const Color(0xFFE59866),
//                               ),
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 16),
//                         Text(
//                           name,
//                           style: TextStyle(
//                             fontSize: 28,
//                             fontWeight: FontWeight.bold,
//                             color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                             height: 1.2,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                         const SizedBox(height: 20),
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: Row(
//                             children: [
//                               _buildTag('Organic', Icons.eco),
//                               const SizedBox(width: 8),
//                               _buildTag('Pesticide Free', Icons.check_circle),
//                               const SizedBox(width: 8),
//                               _buildTag('Today', Icons.schedule),
//                             ],
//                           ),
//                         ),
//                         const SizedBox(height: 24),
//                         Divider(
//                           color: isDarkMode
//                               ? const Color(0xFF3A4A44)
//                               : const Color(0xFFF0F2F1),
//                         ),
//                         const SizedBox(height: 20),
//                         Row(
//                           children: [
//                             GestureDetector(
//                               onTap: _navigateToMessages,
//                               child: Container(
//                                 width: 48,
//                                 height: 48,
//                                 decoration: BoxDecoration(
//                                   borderRadius: BorderRadius.circular(24),
//                                   border: Border.all(
//                                     color: const Color(0xFF39AC86).withOpacity(0.3),
//                                     width: 2,
//                                   ),
//                                   image: userImage.isNotEmpty
//                                       ? DecorationImage(
//                                           image: NetworkImage(userImage),
//                                           fit: BoxFit.cover,
//                                           onError: (exception, stackTrace) {},
//                                         )
//                                       : null,
//                                 ),
//                                 child: userImage.isEmpty
//                                     ? const Icon(Icons.person, color: Color(0xFF39AC86))
//                                     : null,
//                               ),
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     userName,
//                                     style: TextStyle(
//                                       fontSize: 16,
//                                       fontWeight: FontWeight.bold,
//                                       color: isDarkMode
//                                           ? Colors.white
//                                           : const Color(0xFF101816),
//                                     ),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   const Text(
//                                     '4.9 ★ (120 shares)',
//                                     style: TextStyle(
//                                       fontSize: 12,
//                                       color: Color(0xFF5C8A7A),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                             GestureDetector(
//                               onTap: _navigateToMessages,
//                               child: Container(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 16,
//                                   vertical: 10,
//                                 ),
//                                 decoration: BoxDecoration(
//                                   color: isDarkMode
//                                       ? const Color(0xFF2D3A35)
//                                       : const Color(0xFFF9F8F6),
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                                 child: const Text(
//                                   'Message',
//                                   style: TextStyle(
//                                     color: Color(0xFF39AC86),
//                                     fontSize: 14,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),

//                 // Garden Story section
//                 Container(
//                   padding: const EdgeInsets.all(24),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           const Icon(
//                             Icons.menu_book,
//                             color: Color(0xFF39AC86),
//                             size: 20,
//                           ),
//                           const SizedBox(width: 8),
//                           Text(
//                             'Garden Story',
//                             style: TextStyle(
//                               fontSize: 18,
//                               fontWeight: FontWeight.bold,
//                               color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 16),
//                       Text(
//                         description,
//                         style: TextStyle(
//                           fontSize: 16,
//                           color: isDarkMode
//                               ? const Color(0xFFA1B8B0)
//                               : const Color(0xFF5C8A7A),
//                           height: 1.5,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 // Pickup Location section
//                 Container(
//                   padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(
//                             children: [
//                               const Icon(
//                                 Icons.location_on,
//                                 color: Color(0xFF39AC86),
//                                 size: 20,
//                               ),
//                               const SizedBox(width: 8),
//                               Text(
//                                 'Pickup Location',
//                                 style: TextStyle(
//                                   fontSize: 18,
//                                   fontWeight: FontWeight.bold,
//                                   color: isDarkMode
//                                       ? Colors.white
//                                       : const Color(0xFF101816),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           if (_distanceInKm != null)
//                             Container(
//                               padding: const EdgeInsets.symmetric(
//                                 horizontal: 12,
//                                 vertical: 6,
//                               ),
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                 borderRadius: BorderRadius.circular(20),
//                               ),
//                               child: Text(
//                                 _getDistanceText(),
//                                 style: const TextStyle(
//                                   fontSize: 12,
//                                   color: Color(0xFF39AC86),
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                             ),
//                         ],
//                       ),
//                       const SizedBox(height: 8),
//                       if (_locationAddress != null)
//                         Container(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 12,
//                             vertical: 8,
//                           ),
//                           decoration: BoxDecoration(
//                             color: const Color(0xFF39AC86).withOpacity(0.05),
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           child: Row(
//                             children: [
//                               const Icon(
//                                 Icons.location_city,
//                                 size: 16,
//                                 color: Color(0xFF39AC86),
//                               ),
//                               const SizedBox(width: 8),
//                               Expanded(
//                                 child: Text(
//                                   _locationAddress!,
//                                   style: const TextStyle(
//                                     fontSize: 14,
//                                     color: Color(0xFF5C8A7A),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       const SizedBox(height: 16),
//                       Container(
//                         height: 300,
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(16),
//                           border: Border.all(
//                             color: const Color(0xFF39AC86).withOpacity(0.3),
//                           ),
//                         ),
//                         child: ClipRRect(
//                           borderRadius: BorderRadius.circular(16),
//                           child: Stack(
//                             children: [
//                               if (_pickupLocation != null)
//                                 GoogleMap(
//                                   onMapCreated: _onMapCreated,
//                                   initialCameraPosition: CameraPosition(
//                                     target: _pickupLocation!,
//                                     zoom: 14,
//                                   ),
//                                   markers: {
//                                     if (_pickupLocation != null)
//                                       Marker(
//                                         markerId: const MarkerId('pickup-location'),
//                                         position: _pickupLocation!,
//                                         infoWindow: InfoWindow(
//                                           title: 'Pickup Location',
//                                           snippet: _locationAddress,
//                                         ),
//                                         icon: BitmapDescriptor.defaultMarkerWithHue(
//                                           BitmapDescriptor.hueGreen,
//                                         ),
//                                       ),
//                                     if (_userLocation != null)
//                                       Marker(
//                                         markerId: const MarkerId('user-location'),
//                                         position: _userLocation!,
//                                         infoWindow: const InfoWindow(
//                                           title: 'Your Location',
//                                         ),
//                                         icon: BitmapDescriptor.defaultMarkerWithHue(
//                                           BitmapDescriptor.hueBlue,
//                                         ),
//                                       ),
//                                   },
//                                   myLocationEnabled: true,
//                                   myLocationButtonEnabled: false,
//                                   zoomControlsEnabled: true,
//                                   compassEnabled: true,
//                                   mapToolbarEnabled: false,
//                                 )
//                               else
//                                 Container(
//                                   color: Colors.grey[300],
//                                   child: const Center(
//                                     child: Text('Location not available'),
//                                   ),
//                                 ),

//                               if (_isLoadingLocation)
//                                 Container(
//                                   color: Colors.black.withOpacity(0.3),
//                                   child: const Center(
//                                     child: CircularProgressIndicator(
//                                       color: Color(0xFF39AC86),
//                                     ),
//                                   ),
//                                 ),

//                               Positioned(
//                                 top: 8,
//                                 right: 8,
//                                 child: Column(
//                                   children: [
//                                     Container(
//                                       margin: const EdgeInsets.only(bottom: 4),
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: () {
//                                           _mapController?.animateCamera(
//                                             CameraUpdate.zoomIn(),
//                                           );
//                                         },
//                                         icon: const Icon(
//                                           Icons.add,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                     Container(
//                                       margin: const EdgeInsets.only(bottom: 4),
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: () {
//                                           _mapController?.animateCamera(
//                                             CameraUpdate.zoomOut(),
//                                           );
//                                         },
//                                         icon: const Icon(
//                                           Icons.remove,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                     Container(
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: _getUserLocation,
//                                         icon: const Icon(
//                                           Icons.my_location,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),

//                               Positioned(
//                                 bottom: 8,
//                                 right: 8,
//                                 child: GestureDetector(
//                                   onTap: _openInMaps,
//                                   child: Container(
//                                     padding: const EdgeInsets.symmetric(
//                                       horizontal: 16,
//                                       vertical: 8,
//                                     ),
//                                     decoration: BoxDecoration(
//                                       color: const Color(0xFF39AC86),
//                                       borderRadius: BorderRadius.circular(20),
//                                       boxShadow: [
//                                         BoxShadow(
//                                           color: Colors.black.withOpacity(0.2),
//                                           blurRadius: 8,
//                                           offset: const Offset(0, 2),
//                                         ),
//                                       ],
//                                     ),
//                                     child: const Row(
//                                       mainAxisSize: MainAxisSize.min,
//                                       children: [
//                                         Icon(
//                                           Icons.directions,
//                                           color: Colors.white,
//                                           size: 16,
//                                         ),
//                                         SizedBox(width: 4),
//                                         Text(
//                                           'Get Directions',
//                                           style: TextStyle(
//                                             color: Colors.white,
//                                             fontSize: 12,
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                       if (_locationError != null) ...[
//                         const SizedBox(height: 8),
//                         Text(
//                           _locationError!,
//                           style: const TextStyle(
//                             color: Colors.orange,
//                             fontSize: 12,
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 100),
//               ],
//             ),
//           ),

//           // Top nav bar
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                   colors: [
//                     Colors.black.withOpacity(0.4),
//                     Colors.transparent,
//                   ],
//                 ),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   GestureDetector(
//                     onTap: () => Navigator.pop(context),
//                     child: Container(
//                       width: 40,
//                       height: 40,
//                       decoration: BoxDecoration(
//                         color: Colors.black.withOpacity(0.5),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: const Icon(
//                         Icons.arrow_back_ios_new,
//                         color: Colors.white,
//                         size: 20,
//                       ),
//                     ),
//                   ),
//                   const Text(
//                     'Produce Details',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 0.5,
//                     ),
//                   ),
//                   Container(
//                     width: 40,
//                     height: 40,
//                     decoration: BoxDecoration(
//                       color: Colors.black.withOpacity(0.5),
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: const Icon(
//                       Icons.share,
//                       color: Colors.white,
//                       size: 20,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),

//           // Bottom action button
//           Positioned(
//             bottom: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
//                 border: Border(
//                   top: BorderSide(
//                     color: isDarkMode
//                         ? const Color(0xFF3A4A44)
//                         : const Color(0xFFF0F2F1),
//                   ),
//                 ),
//               ),
//               child: GestureDetector(
//                 onTap: buttonEnabled
//                     ? (_existingRequestStatus == 'accepted'
//                         ? _navigateToMessages
//                         : _showRequestDialog)
//                     : null,
//                 child: Container(
//                   height: 56,
//                   decoration: BoxDecoration(
//                     color: _isRequesting ? Colors.grey : buttonColor,
//                     borderRadius: BorderRadius.circular(12),
//                     boxShadow: buttonEnabled
//                         ? [
//                             BoxShadow(
//                               color: buttonColor.withOpacity(0.3),
//                               blurRadius: 10,
//                               offset: const Offset(0, 4),
//                             ),
//                           ]
//                         : null,
//                   ),
//                   child: Center(
//                     child: _isRequesting
//                         ? const SizedBox(
//                             width: 24,
//                             height: 24,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2,
//                               color: Colors.white,
//                             ),
//                           )
//                         : Text(
//                             buttonText,
//                             style: const TextStyle(
//                               color: Colors.white,
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTag(String text, IconData icon) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       decoration: BoxDecoration(
//         color: const Color(0xFF39AC86).withOpacity(0.1),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Row(
//         children: [
//           Icon(
//             icon,
//             color: const Color(0xFF39AC86),
//             size: 16,
//           ),
//           const SizedBox(width: 6),
//           Text(
//             text,
//             style: const TextStyle(
//               fontSize: 12,
//               fontWeight: FontWeight.w600,
//               color: Color(0xFF39AC86),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }











// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:provider/provider.dart';
// import 'messages_screen.dart';
// import 'chat_screen.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class ProductDetailsScreen extends StatefulWidget {
//   final Map<String, dynamic> productData;

//   const ProductDetailsScreen({
//     super.key,
//     required this.productData,
//   });

//   @override
//   State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
// }

// class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
//   final ApiService _apiService = ApiService();
  
//   // Location related
//   GoogleMapController? _mapController;
//   LatLng? _pickupLocation;
//   LatLng? _userLocation;
//   double? _distanceInKm;
//   bool _isLoadingLocation = true;
//   String? _locationError;
//   String? _locationAddress;
  
//   // Product data
//   late Map<String, dynamic> _productData;
//   int _currentQuantity;
//   bool _isRequesting = false;
//   bool _hasExistingRequest = false;
//   String? _existingRequestStatus;
//   int? _existingRequestQuantity;

//   _ProductDetailsScreenState() : _currentQuantity = 0;

//   @override
//   void initState() {
//     super.initState();
//     _productData = widget.productData;
//     _currentQuantity = _productData['quantity'] ?? 0;
//     _initializeLocation();
//     _getAddressFromCoordinates();
//     _checkExistingRequest();
//   }

//   Future<void> _checkExistingRequest() async {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUser = authProvider.currentUser;
      
//       if (currentUser == null) return;
      
//       final result = await _apiService.getUserProductRequest(_productData['id']);
      
//       if (result['success'] == true && result['request'] != null) {
//         final request = result['request'];
//         setState(() {
//           _hasExistingRequest = true;
//           _existingRequestStatus = request['status'];
//           _existingRequestQuantity = request['quantity'];
//         });
//       }
//     } catch (e) {
//       print('Error checking existing request: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _mapController?.dispose();
//     super.dispose();
//   }

//   Future<void> _initializeLocation() async {
//     final latitude = _productData['latitude'];
//     final longitude = _productData['longitude'];
    
//     if (latitude != null && longitude != null) {
//       setState(() {
//         _pickupLocation = LatLng(latitude.toDouble(), longitude.toDouble());
//       });
//     }
    
//     await _getUserLocation();
//   }

//   Future<void> _getAddressFromCoordinates() async {
//     final latitude = _productData['latitude'];
//     final longitude = _productData['longitude'];
    
//     if (latitude != null && longitude != null) {
//       setState(() {
//         _locationAddress = _productData['location_text'] ?? 'Pickup location';
//       });
//     }
//   }

//   Future<void> _getUserLocation() async {
//     setState(() {
//       _isLoadingLocation = true;
//       _locationError = null;
//     });

//     try {
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//       }
      
//       if (permission == LocationPermission.deniedForever) {
//         setState(() {
//           _locationError = 'Location permissions are permanently denied';
//           _isLoadingLocation = false;
//         });
//         return;
//       }

//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 10),
//       );

//       setState(() {
//         _userLocation = LatLng(position.latitude, position.longitude);
//       });

//       if (_pickupLocation != null && _userLocation != null) {
//         _calculateDistance();
//         _animateCameraToShowBoth();
//       } else if (_pickupLocation != null) {
//         _animateCameraToPickup();
//       }

//     } catch (e) {
//       print('Error getting location: $e');
//       setState(() {
//         _locationError = 'Could not get your location';
//       });
//     } finally {
//       setState(() {
//         _isLoadingLocation = false;
//       });
//     }
//   }

//   void _calculateDistance() {
//     if (_pickupLocation == null || _userLocation == null) return;

//     double distanceInMeters = Geolocator.distanceBetween(
//       _userLocation!.latitude,
//       _userLocation!.longitude,
//       _pickupLocation!.latitude,
//       _pickupLocation!.longitude,
//     );

//     setState(() {
//       _distanceInKm = distanceInMeters / 1000;
//     });
//   }

//   void _animateCameraToShowBoth() {
//     if (_mapController == null) return;
//     if (_pickupLocation == null || _userLocation == null) return;

//     LatLngBounds bounds = LatLngBounds(
//       southwest: LatLng(
//         _pickupLocation!.latitude < _userLocation!.latitude 
//             ? _pickupLocation!.latitude 
//             : _userLocation!.latitude,
//         _pickupLocation!.longitude < _userLocation!.longitude 
//             ? _pickupLocation!.longitude 
//             : _userLocation!.longitude,
//       ),
//       northeast: LatLng(
//         _pickupLocation!.latitude > _userLocation!.latitude 
//             ? _pickupLocation!.latitude 
//             : _userLocation!.latitude,
//         _pickupLocation!.longitude > _userLocation!.longitude 
//             ? _pickupLocation!.longitude 
//             : _userLocation!.longitude,
//       ),
//     );

//     _mapController!.animateCamera(
//       CameraUpdate.newLatLngBounds(bounds, 50),
//     );
//   }

//   void _animateCameraToPickup() {
//     if (_mapController == null || _pickupLocation == null) return;
//     _mapController!.animateCamera(
//       CameraUpdate.newLatLngZoom(_pickupLocation!, 15),
//     );
//   }

//   void _onMapCreated(GoogleMapController controller) {
//     _mapController = controller;
//     if (_pickupLocation != null && _userLocation != null) {
//       _animateCameraToShowBoth();
//     } else if (_pickupLocation != null) {
//       _animateCameraToPickup();
//     }
//   }

//   Future<void> _openInMaps() async {
//     if (_pickupLocation == null) return;

//     final url = 'https://www.google.com/maps/search/?api=1&query=${_pickupLocation!.latitude},${_pickupLocation!.longitude}';
//     final uri = Uri.parse(url);
    
//     if (await canLaunchUrl(uri)) {
//       await launchUrl(uri);
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Could not open maps'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   void _showRequestDialog() {
//     int requestedQuantity = 1;
//     final TextEditingController messageController = TextEditingController();
    
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) => StatefulBuilder(
//         builder: (context, setSheetState) {
//           return Padding(
//             padding: EdgeInsets.only(
//               bottom: MediaQuery.of(context).viewInsets.bottom,
//               left: 24,
//               right: 24,
//               top: 24,
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Center(
//                   child: Text(
//                     'Request Produce',
//                     style: TextStyle(
//                       fontSize: 20,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 const Center(
//                   child: Text(
//                     'Send a request to the gardener',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.grey,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 24),
                
//                 // Product info
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       ClipRRect(
//                         borderRadius: BorderRadius.circular(8),
//                         child: Image.network(
//                           _productData['image_url'] ?? '',
//                           width: 50,
//                           height: 50,
//                           fit: BoxFit.cover,
//                           errorBuilder: (context, error, stack) => Container(
//                             width: 50,
//                             height: 50,
//                             color: Colors.grey[200],
//                             child: const Icon(Icons.eco, color: Color(0xFF39AC86)),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               _productData['name'] ?? 'Fresh Produce',
//                               style: const TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             Text(
//                               '${_currentQuantity} ${_productData['quantity_unit'] ?? 'units'} available',
//                               style: const TextStyle(
//                                 fontSize: 12,
//                                 color: Color(0xFF39AC86),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
                
//                 const SizedBox(height: 20),
                
//                 // Quantity selector
//                 const Text(
//                   'Quantity (Max 3)',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                   decoration: BoxDecoration(
//                     border: Border.all(color: Colors.grey[300]!),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       GestureDetector(
//                         onTap: () {
//                           if (requestedQuantity > 1) {
//                             setSheetState(() {
//                               requestedQuantity--;
//                             });
//                           }
//                         },
//                         child: Container(
//                           width: 40,
//                           height: 40,
//                           decoration: BoxDecoration(
//                             color: Colors.grey[200],
//                             shape: BoxShape.circle,
//                           ),
//                           child: const Icon(Icons.remove, color: Color(0xFF39AC86)),
//                         ),
//                       ),
//                       Text(
//                         '$requestedQuantity',
//                         style: const TextStyle(
//                           fontSize: 24,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       GestureDetector(
//                         onTap: () {
//                           if (requestedQuantity < 3 && requestedQuantity < _currentQuantity) {
//                             setSheetState(() {
//                               requestedQuantity++;
//                             });
//                           }
//                         },
//                         child: Container(
//                           width: 40,
//                           height: 40,
//                           decoration: BoxDecoration(
//                             color: Colors.grey[200],
//                             shape: BoxShape.circle,
//                           ),
//                           child: const Icon(Icons.add, color: Color(0xFF39AC86)),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
                
//                 const SizedBox(height: 20),
                
//                 // Message
//                 const Text(
//                   'Message (Optional)',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 TextField(
//                   controller: messageController,
//                   maxLines: 3,
//                   decoration: InputDecoration(
//                     hintText: 'Add a message to the gardener...',
//                     border: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                 ),
                
//                 const SizedBox(height: 24),
                
//                 Row(
//                   children: [
//                     Expanded(
//                       child: OutlinedButton(
//                         onPressed: () => Navigator.pop(context),
//                         style: OutlinedButton.styleFrom(
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                         ),
//                         child: const Text('Cancel'),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: ElevatedButton(
//                         onPressed: () async {
//                           Navigator.pop(context);
//                           await _sendRequest(requestedQuantity, messageController.text);
//                         },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: const Color(0xFF39AC86),
//                           padding: const EdgeInsets.symmetric(vertical: 14),
//                         ),
//                         child: const Text(
//                           'Send Request',
//                           style: TextStyle(fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
                
//                 const SizedBox(height: 16),
                
//                 // Info text
//                 Center(
//                   child: Text(
//                     'Maximum 3 items per request',
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: Colors.grey[600],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Future<void> _sendRequest(int quantity, String message) async {
//     setState(() {
//       _isRequesting = true;
//     });

//     try {
//       final result = await _apiService.createProductRequest(
//         productId: _productData['id'],
//         quantity: quantity,
//         message: message,
//       );

//       if (result['success'] == true) {
//         // Get the chat ID from the response
//         final chatId = result['chat']['id'];
//         final request = result['request'];
        
//         // Navigate to chat with request card
//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         final currentUser = authProvider.currentUser;
//         final ownerId = _productData['user_id'];
//         final ownerName = _productData['users']?['name'] ?? 'Gardener';
//         final ownerImage = _productData['users']?['profile_image_url'] ?? '';
        
//         if (mounted) {
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => ChatScreen(
//                 itemName: _productData['name'] ?? 'Produce',
//                 userName: ownerName,
//                 userImage: ownerImage,
//                 productId: _productData['id'],
//                 productStatus: _productData['status'],
//                 quantity: _currentQuantity,
//                 recipientId: ownerId,
//                 chatId: chatId,
//                 requestData: {
//                   'id': request['id'],
//                   'quantity': quantity,
//                   'status': 'pending',
//                   'message': message,
//                 },
//               ),
//             ),
//           );
//         }
        
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Request sent! Waiting for gardener to accept.'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       } else {
//         throw Exception(result['error'] ?? 'Failed to send request');
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to send request: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       setState(() {
//         _isRequesting = false;
//       });
//     }
//   }

//   void _navigateToMessages() {
//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;
//     final ownerId = _productData['user_id'];
    
//     if (currentUser != null && ownerId != null) {
//       if (currentUser['id'] == ownerId) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('This is your own listing'),
//             backgroundColor: Colors.orange,
//           ),
//         );
//         return;
//       }
      
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => MessagesScreen(
//             recipientId: ownerId,
//             recipientName: _productData['users']?['name'] ?? 'Gardener',
//             recipientImage: _productData['users']?['profile_image_url'],
//             productId: _productData['id'],
//             productName: _productData['name'],
//             productStatus: _productData['status'],
//             productQuantity: _currentQuantity,
//           ),
//         ),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please login to send messages'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//     }
//   }

//   String _getDistanceText() {
//     if (_distanceInKm == null) return 'Distance unknown';
//     if (_distanceInKm! < 1) {
//       return '${(_distanceInKm! * 1000).toStringAsFixed(0)} m away';
//     }
//     return '${_distanceInKm!.toStringAsFixed(1)} km away';
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     final imageUrl = _productData['image_url'] ?? 
//                      (_productData['imageUrl'] ?? 
//                      'https://lh3.googleusercontent.com/aida-public/AB6AXuDpxtSHzBQyEV3GHn4NJkaTgBDJvhkEmCPE_fYJKhG9nq3CdJ8RU3QCqpXLtCOQ0icow0WTwxn7XXJ8jSbNHXkXZMVCyyETaL_dqDF1qohnoQyLQCJNBbBZzouqvthS4kIwmme_0n_kylD71ANsa-Skd2viP8puRco7WpiL_tDd4IaJGiS7hwFo3XL2PzoEIb37olQn2rW5s9WWiek2L7tIkKyg_AWACHrxMui4OL7w74QJq0LtcyXVlPEXyZ64Nk_redTn5MvsYrCs');
    
//     final name = _productData['name'] ?? 'Fresh Produce';
//     final description = _productData['description'] ?? 'Freshly harvested from a local garden.';
//     final quantityUnit = _productData['quantity_unit'] ?? 'lbs';
//     final itemLeftText = _currentQuantity == 0 ? 'Claimed' : '$_currentQuantity $quantityUnit left';
    
//     final userData = _productData['users'] ?? {};
//     final userName = userData['name'] ?? 'Local Gardener';
//     final userImage = userData['profile_image_url'] ?? '';
    
//     // Determine button state
//     bool isOwner = false;
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUser = authProvider.currentUser;
//     if (currentUser != null) {
//       isOwner = currentUser['id'] == _productData['user_id'];
//     }
    
//     bool canRequest = !isOwner && _currentQuantity > 0 && !_hasExistingRequest;
//     String buttonText = '';
//     Color buttonColor = const Color(0xFF39AC86);
//     bool buttonEnabled = false;
    
//     if (isOwner) {
//       buttonText = 'Your Listing';
//       buttonColor = Colors.grey;
//       buttonEnabled = false;
//     } else if (_hasExistingRequest) {
//       if (_existingRequestStatus == 'pending') {
//         buttonText = 'Request Pending (${_existingRequestQuantity ?? ''} ${_existingRequestQuantity == 1 ? 'item' : 'items'})';
//         buttonColor = Colors.orange;
//         buttonEnabled = false;
//       } else if (_existingRequestStatus == 'accepted') {
//         buttonText = 'Request Accepted! Contact Gardener';
//         buttonColor = const Color(0xFF39AC86);
//         buttonEnabled = true;
//       } else if (_existingRequestStatus == 'declined') {
//         buttonText = 'Request Declined';
//         buttonColor = Colors.red;
//         buttonEnabled = false;
//       } else {
//         buttonText = 'Already Requested';
//         buttonColor = Colors.grey;
//         buttonEnabled = false;
//       }
//     } else if (_currentQuantity == 0) {
//       buttonText = 'All Claimed';
//       buttonColor = Colors.grey;
//       buttonEnabled = false;
//     } else {
//       buttonText = 'Request Produce';
//       buttonColor = const Color(0xFF39AC86);
//       buttonEnabled = true;
//     }
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF1A2421) : const Color(0xFFF9F8F6),
//       body: Stack(
//         children: [
//           SingleChildScrollView(
//             child: Column(
//               children: [
//                 SizedBox(
//                   height: MediaQuery.of(context).size.height * 0.45,
//                   width: double.infinity,
//                   child: Stack(
//                     fit: StackFit.expand,
//                     children: [
//                       Image.network(
//                         imageUrl,
//                         fit: BoxFit.cover,
//                         errorBuilder: (context, error, stackTrace) {
//                           return Container(
//                             color: const Color(0xFF39AC86).withOpacity(0.1),
//                             child: const Center(
//                               child: Icon(
//                                 Icons.eco,
//                                 size: 64,
//                                 color: Color(0xFF39AC86),
//                               ),
//                             ),
//                           );
//                         },
//                       ),
//                       Container(
//                         decoration: BoxDecoration(
//                           gradient: LinearGradient(
//                             begin: Alignment.topCenter,
//                             end: Alignment.bottomCenter,
//                             colors: [
//                               Colors.transparent,
//                               Colors.black.withOpacity(0.5),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 Container(
//                   margin: const EdgeInsets.fromLTRB(16, -80, 16, 0),
//                   decoration: BoxDecoration(
//                     color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
//                     borderRadius: BorderRadius.circular(16),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.black.withOpacity(0.1),
//                         blurRadius: 20,
//                         offset: const Offset(0, 4),
//                       ),
//                     ],
//                     border: Border.all(
//                       color: isDarkMode 
//                           ? const Color(0xFF3A4A44) 
//                           : const Color(0xFFF0F2F1),
//                     ),
//                   ),
//                   child: Padding(
//                     padding: const EdgeInsets.all(24),
//                     child: Column(
//                       children: [
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Container(
//                               padding: const EdgeInsets.symmetric(
//                                 horizontal: 12,
//                                 vertical: 6,
//                               ),
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                 borderRadius: BorderRadius.circular(20),
//                               ),
//                               child: Text(
//                                 _productData['status'] == 'available' && _currentQuantity > 0
//                                     ? 'Freshly Harvested' 
//                                     : _productData['status'] ?? 'Available',
//                                 style: const TextStyle(
//                                   fontSize: 12,
//                                   fontWeight: FontWeight.bold,
//                                   color: Color(0xFF39AC86),
//                                   letterSpacing: 0.5,
//                                 ),
//                               ),
//                             ),
//                             Text(
//                               itemLeftText,
//                               style: TextStyle(
//                                 fontSize: 18,
//                                 fontWeight: FontWeight.bold,
//                                 color: _currentQuantity == 0 
//                                     ? Colors.grey 
//                                     : const Color(0xFFE59866),
//                               ),
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 16),
//                         Text(
//                           name,
//                           style: TextStyle(
//                             fontSize: 28,
//                             fontWeight: FontWeight.bold,
//                             color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                             height: 1.2,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                         const SizedBox(height: 20),
//                         SingleChildScrollView(
//                           scrollDirection: Axis.horizontal,
//                           child: Row(
//                             children: [
//                               _buildTag('Organic', Icons.eco),
//                               const SizedBox(width: 8),
//                               _buildTag('Pesticide Free', Icons.check_circle),
//                               const SizedBox(width: 8),
//                               _buildTag('Today', Icons.schedule),
//                             ],
//                           ),
//                         ),
//                         const SizedBox(height: 24),
//                         Divider(
//                           color: isDarkMode 
//                               ? const Color(0xFF3A4A44) 
//                               : const Color(0xFFF0F2F1),
//                         ),
//                         const SizedBox(height: 20),
//                         Row(
//                           children: [
//                             GestureDetector(
//                               onTap: _navigateToMessages,
//                               child: Container(
//                                 width: 48,
//                                 height: 48,
//                                 decoration: BoxDecoration(
//                                   borderRadius: BorderRadius.circular(24),
//                                   border: Border.all(
//                                     color: const Color(0xFF39AC86).withOpacity(0.3),
//                                     width: 2,
//                                   ),
//                                   image: userImage.isNotEmpty
//                                       ? DecorationImage(
//                                           image: NetworkImage(userImage),
//                                           fit: BoxFit.cover,
//                                           onError: (exception, stackTrace) {},
//                                         )
//                                       : null,
//                                 ),
//                                 child: userImage.isEmpty 
//                                     ? const Icon(Icons.person, color: Color(0xFF39AC86))
//                                     : null,
//                               ),
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     userName,
//                                     style: TextStyle(
//                                       fontSize: 16,
//                                       fontWeight: FontWeight.bold,
//                                       color: isDarkMode 
//                                           ? Colors.white 
//                                           : const Color(0xFF101816),
//                                     ),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   const Text(
//                                     '4.9 ★ (120 shares)',
//                                     style: TextStyle(
//                                       fontSize: 12,
//                                       color: Color(0xFF5C8A7A),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                             GestureDetector(
//                               onTap: _navigateToMessages,
//                               child: Container(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 16,
//                                   vertical: 10,
//                                 ),
//                                 decoration: BoxDecoration(
//                                   color: isDarkMode 
//                                       ? const Color(0xFF2D3A35) 
//                                       : const Color(0xFFF9F8F6),
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                                 child: const Text(
//                                   'Message',
//                                   style: TextStyle(
//                                     color: Color(0xFF39AC86),
//                                     fontSize: 14,
//                                     fontWeight: FontWeight.bold,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),

//                 Container(
//                   padding: const EdgeInsets.all(24),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           const Icon(
//                             Icons.menu_book,
//                             color: Color(0xFF39AC86),
//                             size: 20,
//                           ),
//                           const SizedBox(width: 8),
//                           Text(
//                             'Garden Story',
//                             style: TextStyle(
//                               fontSize: 18,
//                               fontWeight: FontWeight.bold,
//                               color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 16),
//                       Text(
//                         description,
//                         style: TextStyle(
//                           fontSize: 16,
//                           color: isDarkMode 
//                               ? const Color(0xFFA1B8B0) 
//                               : const Color(0xFF5C8A7A),
//                           height: 1.5,
//                         ),
//                       ),
//                       const SizedBox(height: 24),
//                       Container(
//                         padding: const EdgeInsets.all(16),
//                         decoration: BoxDecoration(
//                           color: const Color(0xFF39AC86).withOpacity(0.05),
//                           borderRadius: BorderRadius.circular(16),
//                           border: Border.all(
//                             color: const Color(0xFF39AC86).withOpacity(0.1),
//                           ),
//                         ),
//                         child: Row(
//                           children: [
//                             Container(
//                               width: 40,
//                               height: 40,
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.2),
//                                 borderRadius: BorderRadius.circular(20),
//                               ),
//                               child: const Icon(
//                                 Icons.public,
//                                 color: Color(0xFF39AC86),
//                                 size: 20,
//                               ),
//                             ),
//                             const SizedBox(width: 16),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   const Text(
//                                     'Sustainability Impact',
//                                     style: TextStyle(
//                                       fontSize: 14,
//                                       fontWeight: FontWeight.bold,
//                                       color: Color(0xFF39AC86),
//                                     ),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   const Text(
//                                     'Sourcing this locally saves ~1.2kg of CO2 transport emissions.',
//                                     style: TextStyle(
//                                       fontSize: 12,
//                                       color: Color(0xFF39AC86),
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       if (_productData['pickup_instructions'] != null) ...[
//                         const SizedBox(height: 20),
//                         Container(
//                           padding: const EdgeInsets.all(16),
//                           decoration: BoxDecoration(
//                             color: const Color(0xFFE59866).withOpacity(0.05),
//                             borderRadius: BorderRadius.circular(16),
//                             border: Border.all(
//                               color: const Color(0xFFE59866).withOpacity(0.1),
//                             ),
//                           ),
//                           child: Row(
//                             children: [
//                               Container(
//                                 width: 40,
//                                 height: 40,
//                                 decoration: BoxDecoration(
//                                   color: const Color(0xFFE59866).withOpacity(0.2),
//                                   borderRadius: BorderRadius.circular(20),
//                                 ),
//                                 child: const Icon(
//                                   Icons.info_outline,
//                                   color: Color(0xFFE59866),
//                                   size: 20,
//                                 ),
//                               ),
//                               const SizedBox(width: 16),
//                               Expanded(
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     const Text(
//                                       'Pickup Instructions',
//                                       style: TextStyle(
//                                         fontSize: 14,
//                                         fontWeight: FontWeight.bold,
//                                         color: Color(0xFFE59866),
//                                       ),
//                                     ),
//                                     const SizedBox(height: 4),
//                                     Text(
//                                       _productData['pickup_instructions'],
//                                       style: const TextStyle(
//                                         fontSize: 12,
//                                         color: Color(0xFFE59866),
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ),

//                 Container(
//                   padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(
//                             children: [
//                               const Icon(
//                                 Icons.location_on,
//                                 color: Color(0xFF39AC86),
//                                 size: 20,
//                               ),
//                               const SizedBox(width: 8),
//                               Text(
//                                 'Pickup Location',
//                                 style: TextStyle(
//                                   fontSize: 18,
//                                   fontWeight: FontWeight.bold,
//                                   color: isDarkMode 
//                                       ? Colors.white 
//                                       : const Color(0xFF101816),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           if (_distanceInKm != null)
//                             Container(
//                               padding: const EdgeInsets.symmetric(
//                                 horizontal: 12,
//                                 vertical: 6,
//                               ),
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                 borderRadius: BorderRadius.circular(20),
//                               ),
//                               child: Text(
//                                 _getDistanceText(),
//                                 style: const TextStyle(
//                                   fontSize: 12,
//                                   color: Color(0xFF39AC86),
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                             ),
//                         ],
//                       ),
//                       const SizedBox(height: 8),
//                       if (_locationAddress != null)
//                         Container(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 12,
//                             vertical: 8,
//                           ),
//                           decoration: BoxDecoration(
//                             color: const Color(0xFF39AC86).withOpacity(0.05),
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           child: Row(
//                             children: [
//                               const Icon(
//                                 Icons.location_city,
//                                 size: 16,
//                                 color: Color(0xFF39AC86),
//                               ),
//                               const SizedBox(width: 8),
//                               Expanded(
//                                 child: Text(
//                                   _locationAddress!,
//                                   style: const TextStyle(
//                                     fontSize: 14,
//                                     color: Color(0xFF5C8A7A),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       const SizedBox(height: 16),
//                       Container(
//                         height: 300,
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(16),
//                           border: Border.all(
//                             color: const Color(0xFF39AC86).withOpacity(0.3),
//                           ),
//                         ),
//                         child: ClipRRect(
//                           borderRadius: BorderRadius.circular(16),
//                           child: Stack(
//                             children: [
//                               if (_pickupLocation != null)
//                                 GoogleMap(
//                                   onMapCreated: _onMapCreated,
//                                   initialCameraPosition: CameraPosition(
//                                     target: _pickupLocation!,
//                                     zoom: 14,
//                                   ),
//                                   markers: {
//                                     if (_pickupLocation != null)
//                                       Marker(
//                                         markerId: const MarkerId('pickup-location'),
//                                         position: _pickupLocation!,
//                                         infoWindow: InfoWindow(
//                                           title: 'Pickup Location',
//                                           snippet: _locationAddress,
//                                         ),
//                                         icon: BitmapDescriptor.defaultMarkerWithHue(
//                                           BitmapDescriptor.hueGreen,
//                                         ),
//                                       ),
//                                     if (_userLocation != null)
//                                       Marker(
//                                         markerId: const MarkerId('user-location'),
//                                         position: _userLocation!,
//                                         infoWindow: const InfoWindow(
//                                           title: 'Your Location',
//                                         ),
//                                         icon: BitmapDescriptor.defaultMarkerWithHue(
//                                           BitmapDescriptor.hueBlue,
//                                         ),
//                                       ),
//                                   },
//                                   myLocationEnabled: true,
//                                   myLocationButtonEnabled: false,
//                                   zoomControlsEnabled: true,
//                                   compassEnabled: true,
//                                   mapToolbarEnabled: false,
//                                 )
//                               else
//                                 Container(
//                                   color: Colors.grey[300],
//                                   child: const Center(
//                                     child: Text('Location not available'),
//                                   ),
//                                 ),
                              
//                               if (_isLoadingLocation)
//                                 Container(
//                                   color: Colors.black.withOpacity(0.3),
//                                   child: const Center(
//                                     child: CircularProgressIndicator(
//                                       color: Color(0xFF39AC86),
//                                     ),
//                                   ),
//                                 ),
//                               Positioned(
//                                 top: 8,
//                                 right: 8,
//                                 child: Column(
//                                   children: [
//                                     Container(
//                                       margin: const EdgeInsets.only(bottom: 4),
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: () {
//                                           _mapController?.animateCamera(
//                                             CameraUpdate.zoomIn(),
//                                           );
//                                         },
//                                         icon: const Icon(
//                                           Icons.add,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                     Container(
//                                       margin: const EdgeInsets.only(bottom: 4),
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: () {
//                                           _mapController?.animateCamera(
//                                             CameraUpdate.zoomOut(),
//                                           );
//                                         },
//                                         icon: const Icon(
//                                           Icons.remove,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                     Container(
//                                       decoration: BoxDecoration(
//                                         color: Colors.white,
//                                         borderRadius: BorderRadius.circular(8),
//                                         boxShadow: [
//                                           BoxShadow(
//                                             color: Colors.black.withOpacity(0.1),
//                                             blurRadius: 4,
//                                             offset: const Offset(0, 2),
//                                           ),
//                                         ],
//                                       ),
//                                       child: IconButton(
//                                         onPressed: _getUserLocation,
//                                         icon: const Icon(
//                                           Icons.my_location,
//                                           color: Color(0xFF39AC86),
//                                           size: 20,
//                                         ),
//                                         padding: const EdgeInsets.all(8),
//                                         constraints: const BoxConstraints(),
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                               Positioned(
//                                 bottom: 8,
//                                 right: 8,
//                                 child: GestureDetector(
//                                   onTap: _openInMaps,
//                                   child: Container(
//                                     padding: const EdgeInsets.symmetric(
//                                       horizontal: 16,
//                                       vertical: 8,
//                                     ),
//                                     decoration: BoxDecoration(
//                                       color: const Color(0xFF39AC86),
//                                       borderRadius: BorderRadius.circular(20),
//                                       boxShadow: [
//                                         BoxShadow(
//                                           color: Colors.black.withOpacity(0.2),
//                                           blurRadius: 8,
//                                           offset: const Offset(0, 2),
//                                         ),
//                                       ],
//                                     ),
//                                     child: const Row(
//                                       mainAxisSize: MainAxisSize.min,
//                                       children: [
//                                         Icon(
//                                           Icons.directions,
//                                           color: Colors.white,
//                                           size: 16,
//                                         ),
//                                         SizedBox(width: 4),
//                                         Text(
//                                           'Get Directions',
//                                           style: TextStyle(
//                                             color: Colors.white,
//                                             fontSize: 12,
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                       if (_locationError != null) ...[
//                         const SizedBox(height: 8),
//                         Text(
//                           _locationError!,
//                           style: const TextStyle(
//                             color: Colors.orange,
//                             fontSize: 12,
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 100),
//               ],
//             ),
//           ),
//           Positioned(
//             top: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   begin: Alignment.topCenter,
//                   end: Alignment.bottomCenter,
//                   colors: [
//                     Colors.black.withOpacity(0.4),
//                     Colors.transparent,
//                   ],
//                 ),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   GestureDetector(
//                     onTap: () => Navigator.pop(context),
//                     child: Container(
//                       width: 40,
//                       height: 40,
//                       decoration: BoxDecoration(
//                         color: Colors.black.withOpacity(0.5),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: const Icon(
//                         Icons.arrow_back_ios_new,
//                         color: Colors.white,
//                         size: 20,
//                       ),
//                     ),
//                   ),
//                   const Text(
//                     'Produce Details',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 0.5,
//                     ),
//                   ),
//                   Container(
//                     width: 40,
//                     height: 40,
//                     decoration: BoxDecoration(
//                       color: Colors.black.withOpacity(0.5),
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: const Icon(
//                       Icons.share,
//                       color: Colors.white,
//                       size: 20,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           Positioned(
//             bottom: 0,
//             left: 0,
//             right: 0,
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF25322E) : Colors.white,
//                 border: Border(
//                   top: BorderSide(
//                     color: isDarkMode 
//                         ? const Color(0xFF3A4A44) 
//                         : const Color(0xFFF0F2F1),
//                   ),
//                 ),
//               ),
//               child: GestureDetector(
//                 onTap: buttonEnabled ? (_existingRequestStatus == 'accepted' ? _navigateToMessages : _showRequestDialog) : null,
//                 child: Container(
//                   height: 56,
//                   decoration: BoxDecoration(
//                     color: _isRequesting ? Colors.grey : buttonColor,
//                     borderRadius: BorderRadius.circular(12),
//                     boxShadow: buttonEnabled ? [
//                       BoxShadow(
//                         color: buttonColor.withOpacity(0.3),
//                         blurRadius: 10,
//                         offset: const Offset(0, 4),
//                       ),
//                     ] : null,
//                   ),
//                   child: Center(
//                     child: _isRequesting
//                         ? const SizedBox(
//                             width: 24,
//                             height: 24,
//                             child: CircularProgressIndicator(
//                               strokeWidth: 2,
//                               color: Colors.white,
//                             ),
//                           )
//                         : Text(
//                             buttonText,
//                             style: const TextStyle(
//                               color: Colors.white,
//                               fontSize: 16,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTag(String text, IconData icon) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       decoration: BoxDecoration(
//         color: const Color(0xFF39AC86).withOpacity(0.1),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Row(
//         children: [
//           Icon(
//             icon,
//             color: const Color(0xFF39AC86),
//             size: 16,
//           ),
//           const SizedBox(width: 6),
//           Text(
//             text,
//             style: const TextStyle(
//               fontSize: 12,
//               fontWeight: FontWeight.w600,
//               color: Color(0xFF39AC86),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }










