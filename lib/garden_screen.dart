import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'add_new_crop.dart';
import 'all_crops_screen.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../services/ai_service.dart';
import 'dart:async';

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key});

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final AIService _aiService = AIService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Data variables
  List<dynamic> _crops = [];
  List<dynamic> _gardens = [];
  Map<String, dynamic>? _userData;

  // Stats
  int _activeCropsCount = 0;
  int _archivedCropsCount = 0;
  int _harvestReadyCount = 0;
  double _sharedThisWeek = 0;
  double _totalYield = 0;

  // Loading states
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Cache
  DateTime? _lastLoadTime;

  // Image cache buster
  int _imageVersion = 0;

  // Weekly harvest data for chart (now functional)
  List<double> _weeklyHarvest = [0, 0, 0, 0, 0, 0, 0];
  final List<String> _weekDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // ── AI Search ──
  bool _showSearchPanel = false;
  bool _isAITyping = false;
  String _aiAnswer = '';
  String _lastQuery = '';
  Timer? _debounce;
  late AnimationController _panelController;
  late Animation<double> _panelAnimation;

  // ── Hardiness Zone with Map ──
  String? _userZone;
  bool _isLoadingZone = true;
  Map<String, dynamic> _hardinessZones = {};
  GoogleMapController? _mapController;
  Set<Marker> _zoneMarkers = {};

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
    );
    _loadGardenData();
    _loadHardinessZone();
    _initAI();

    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _searchController.text.trim().isNotEmpty) {
        _openPanel();
      }
    });
  }

  Future<void> _initAI() async {
    await _aiService.initialize();
  }

  void _openPanel() {
    setState(() => _showSearchPanel = true);
    _panelController.forward();
  }

  void _closePanel() {
    _panelController.reverse().then((_) {
      if (mounted) setState(() => _showSearchPanel = false);
    });
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _closePanel();
      return;
    }
    _openPanel();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (query.trim() != _lastQuery) {
        _askAI(query.trim());
      }
    });
  }

  Future<void> _askAI(String query) async {
    final lowerQ = query.toLowerCase();
    final gardenKeywords = [
      'crop', 'plant', 'garden', 'grow', 'harvest', 'soil', 'water', 'fertiliz',
      'pest', 'disease', 'seed', 'fruit', 'vegetable', 'herb', 'flower', 'farm',
      'compost', 'irrigat', 'prune', 'weed', 'season', 'climate', 'zone',
      'tomato', 'pepper', 'lettuce', 'carrot', 'bean', 'corn', 'potato',
    ];
    final isGardenTopic = gardenKeywords.any((kw) => lowerQ.contains(kw));

    setState(() {
      _isAITyping = true;
      _lastQuery = query;
      _aiAnswer = '';
    });

    if (!isGardenTopic) {
      await Future.delayed(const Duration(milliseconds: 400));
      setState(() {
        _aiAnswer = "🌿 I'm your garden assistant! I can only help with topics related to crops, planting, harvesting, soil, pests, and agriculture. Try asking something like \"How do I grow tomatoes?\" or \"When should I harvest carrots?\"";
        _isAITyping = false;
      });
      return;
    }

    try {
      final response = await _aiService.askQuestion(query);
      setState(() {
        _aiAnswer = response;
        _isAITyping = false;
      });
    } catch (e) {
      setState(() {
        _aiAnswer = 'Sorry, I couldn\'t fetch an answer right now. Please try again.';
        _isAITyping = false;
      });
    }
  }

  // ── Hardiness Zone with Map ──
  Future<void> _loadHardinessZone() async {
    _hardinessZones = _generateZoneData();
    _addZoneMarkers();
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingZone = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _userZone = _getZoneFromCoordinates(position.latitude);
        _isLoadingZone = false;
      });
    } catch (e) {
      setState(() => _isLoadingZone = false);
    }
  }

  void _addZoneMarkers() {
    Set<Marker> markers = {};
    _hardinessZones.forEach((zoneName, zoneData) {
      markers.add(
        Marker(
          markerId: MarkerId(zoneName),
          position: _getZoneCenter(zoneName),
          infoWindow: InfoWindow(
            title: zoneName,
            snippet: zoneData['description'],
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });
    setState(() {
      _zoneMarkers = markers;
    });
  }

  LatLng _getZoneCenter(String zoneName) {
    switch(zoneName) {
      case 'Zone 1': return const LatLng(65, -100);
      case 'Zone 2': return const LatLng(57.5, -100);
      case 'Zone 3': return const LatLng(52.5, -100);
      case 'Zone 4': return const LatLng(47.5, -100);
      case 'Zone 5': return const LatLng(42.5, -100);
      case 'Zone 6': return const LatLng(37.5, -100);
      case 'Zone 7': return const LatLng(32.5, -100);
      case 'Zone 8': return const LatLng(27.5, -100);
      case 'Zone 9': return const LatLng(22.5, -100);
      case 'Zone 10': return const LatLng(10, -100);
      default: return const LatLng(39.8283, -98.5795);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  String _getZoneFromCoordinates(double lat) {
    if (lat > 60) return 'Zone 1';
    if (lat > 55) return 'Zone 2';
    if (lat > 50) return 'Zone 3';
    if (lat > 45) return 'Zone 4';
    if (lat > 40) return 'Zone 5';
    if (lat > 35) return 'Zone 6';
    if (lat > 30) return 'Zone 7';
    if (lat > 25) return 'Zone 8';
    if (lat > 20) return 'Zone 9';
    return 'Zone 10';
  }

  Map<String, dynamic> _generateZoneData() {
    return {
      'Zone 1':  {'tempRange': 'Below -50°F', 'color': const Color(0xFF2C3E5C), 'suitableCrops': ['Potatoes', 'Kale', 'Carrots', 'Turnips'], 'description': 'Extreme cold, very short growing season'},
      'Zone 2':  {'tempRange': '-50°F to -40°F', 'color': const Color(0xFF3E5A8A), 'suitableCrops': ['Potatoes', 'Cabbage', 'Peas', 'Radishes'], 'description': 'Very cold, short growing season'},
      'Zone 3':  {'tempRange': '-40°F to -30°F', 'color': const Color(0xFF4F7AB3), 'suitableCrops': ['Broccoli', 'Cauliflower', 'Lettuce', 'Spinach'], 'description': 'Cold winters, moderate summers'},
      'Zone 4':  {'tempRange': '-30°F to -20°F', 'color': const Color(0xFF609CD9), 'suitableCrops': ['Tomatoes', 'Peppers', 'Beans', 'Corn'], 'description': 'Cold climate, good for hardy vegetables'},
      'Zone 5':  {'tempRange': '-20°F to -10°F', 'color': const Color(0xFF71BDFF), 'suitableCrops': ['Apples', 'Cherries', 'Peaches', 'Grapes'], 'description': 'Temperate, diverse growing options'},
      'Zone 6':  {'tempRange': '-10°F to 0°F',   'color': const Color(0xFF8ACC66), 'suitableCrops': ['Strawberries', 'Blueberries', 'Raspberries'], 'description': 'Mild winters, long growing season'},
      'Zone 7':  {'tempRange': '0°F to 10°F',    'color': const Color(0xFFA5D95E), 'suitableCrops': ['Citrus', 'Figs', 'Pomegranates', 'Olives'], 'description': 'Warm, excellent for fruit trees'},
      'Zone 8':  {'tempRange': '10°F to 20°F',   'color': const Color(0xFFBFF055), 'suitableCrops': ['Avocados', 'Bananas', 'Mangoes', 'Papayas'], 'description': 'Warm, subtropical plants thrive'},
      'Zone 9':  {'tempRange': '20°F to 30°F',   'color': const Color(0xFFD9FF4C), 'suitableCrops': ['Tomatoes', 'Eggplant', 'Okra', 'Sweet Potatoes'], 'description': 'Hot, year-round growing possible'},
      'Zone 10': {'tempRange': '30°F to 40°F',   'color': const Color(0xFFF2F242), 'suitableCrops': ['Pineapples', 'Coconuts', 'Tropical Fruits'], 'description': 'Tropical, year-round gardening'},
    };
  }

  // ── Garden Data ──
  Future<void> _loadGardenData({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _lastLoadTime != null &&
        DateTime.now().difference(_lastLoadTime!) < const Duration(minutes: 2)) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    await _fetchGardenData();
    setState(() {
      _isLoading = false;
      _lastLoadTime = DateTime.now();
    });
  }

  Future<void> _refreshGardenData() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _imageVersion++;
    });
    await _fetchGardenData();
    setState(() {
      _isRefreshing = false;
      _lastLoadTime = DateTime.now();
    });
  }

  Future<void> _fetchGardenData() async {
    try {
      final authProvider = context.read<AuthProvider>();
      _userData = authProvider.currentUser;

      final cropsResult = await _apiService.getUserCrops();
      if (cropsResult['success'] == true) {
        final allCrops = cropsResult['crops'] ?? [];
        
        // Separate active and archived crops
        final activeCrops = allCrops.where((c) => c['is_archived'] != true).toList();
        final archivedCrops = allCrops.where((c) => c['is_archived'] == true).toList();
        
        // Calculate weekly harvest (last 7 days)
        final now = DateTime.now();
        final weeklyData = List.filled(7, 0.0);
        
        for (var crop in allCrops) {
          if (crop['status'] == 'harvest' && crop['harvested_at'] != null) {
            try {
              final harvestDate = DateTime.parse(crop['harvested_at']);
              final daysAgo = now.difference(harvestDate).inDays;
              if (daysAgo >= 0 && daysAgo < 7) {
                final quantity = (crop['quantity'] as num?)?.toDouble() ?? 0;
                weeklyData[daysAgo] += quantity;
              }
            } catch (e) {
              // If no harvest date, use created_at or ignore
            }
          }
        }
        
        setState(() {
          _crops = activeCrops; // Only show active crops in main list
          _activeCropsCount = activeCrops.length;
          _archivedCropsCount = archivedCrops.length;
          _harvestReadyCount = activeCrops.where((c) => 
            c['status'] == 'harvest' || (c['progress'] ?? 0) >= 100
          ).length;
          _sharedThisWeek = allCrops.where((c) => 
            c['is_shared'] == true && c['shared_at'] != null
          ).fold(0, (sum, c) => sum + (c['quantity'] ?? 0).toDouble());
          _totalYield = allCrops.fold(0, (sum, c) => sum + (c['quantity'] ?? 0).toDouble());
          _weeklyHarvest = weeklyData.reversed.toList();
        });
      }

      final gardensResult = await _apiService.getUserGardens();
      if (gardensResult['success'] == true) {
        setState(() => _gardens = gardensResult['gardens'] ?? []);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load garden data'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getUserName() {
    if (_userData != null && _userData!['name'] != null) {
      return _userData!['name'].toString().split(' ')[0];
    }
    return 'Gardener';
  }

  String _getGardenPhase() {
    if (_gardens.isEmpty) return 'No Garden';
    if (_activeCropsCount > 10) return 'Thriving 🌟';
    if (_activeCropsCount > 5) return 'Bountiful 🌿';
    if (_activeCropsCount > 0) return 'Growing 🌱';
    if (_archivedCropsCount > 0) return 'Has Archived Crops 📦';
    return 'Ready to Plant 🌻';
  }

  String _getGreetingEmoji() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '🌅';
    if (hour < 17) return '☀️';
    return '🌙';
  }

  String _getMood() {
    if (_activeCropsCount > 15) return 'thriving! 🌟';
    if (_activeCropsCount > 8) return 'growing beautifully! 🌿';
    if (_activeCropsCount > 3) return 'starting to flourish! 🌱';
    if (_activeCropsCount > 0) return 'coming along! 🌻';
    if (_archivedCropsCount > 0) return 'ready for new planting season! 🌾';
    return 'ready for planting! 🌱';
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _panelController.dispose();
    _mapController?.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        if (_showSearchPanel) _closePanel();
      },
      child: Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        body: SafeArea(
          bottom: false,
          child: _isLoading
              ? _buildLoadingScreen(isDarkMode)
              : RefreshIndicator(
                  onRefresh: _refreshGardenData,
                  color: const Color(0xFF39AC86),
                  backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildTopBar(isDarkMode),
                        _buildSearchBar(isDarkMode),
                        if (_showSearchPanel) _buildSearchPanel(isDarkMode),
                        _buildWelcomeMessage(isDarkMode),
                        _buildStatsSection(isDarkMode),
                        _buildCropListHeader(isDarkMode),
                        _buildCropCards(isDarkMode),
                        _buildProductivityHeader(isDarkMode),
                        _buildChartsCard(isDarkMode),
                        _buildHardinessZoneSection(isDarkMode),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
        ),
        floatingActionButton: _buildHarvestFAB(isDarkMode),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  // ADD THIS MISSING METHOD
  Widget _buildLoadingScreen(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF39AC86)),
          const SizedBox(height: 20),
          Text(
            'Loading your garden...',
            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
          ),
        ],
      ),
    );
  }

  // ─────────────── Search Bar ───────────────

  Widget _buildSearchBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _showSearchPanel
                ? const Color(0xFF39AC86)
                : (isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB)),
            width: _showSearchPanel ? 1.5 : 1,
          ),
          boxShadow: _showSearchPanel
              ? [BoxShadow(color: const Color(0xFF39AC86).withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isAITyping
                  ? SizedBox(
                      key: const ValueKey('loader'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: const Color(0xFF39AC86),
                      ),
                    )
                  : Icon(
                      key: const ValueKey('icon'),
                      _showSearchPanel ? Icons.eco : Icons.search,
                      color: _showSearchPanel ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
                      size: 20,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Ask about your crops, soil, pests...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                  fontSize: 14,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _closePanel();
                  setState(() {
                    _aiAnswer = '';
                    _lastQuery = '';
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.close, size: 18, color: isDarkMode ? Colors.white54 : const Color(0xFF9CA3AF)),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF39AC86),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Search AI Panel ───────────────

  Widget _buildSearchPanel(bool isDarkMode) {
    return FadeTransition(
      opacity: _panelAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.05),
          end: Offset.zero,
        ).animate(_panelAnimation),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF253330) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF39AC86).withOpacity(0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF39AC86).withOpacity(0.07),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    bottom: BorderSide(
                      color: const Color(0xFF39AC86).withOpacity(0.12),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.eco, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Garden AI Assistant',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF39AC86),
                          ),
                        ),
                        Text(
                          'Crop & agriculture expert',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_isAITyping)
                      Row(
                        children: [
                          _buildDot(0),
                          _buildDot(150),
                          _buildDot(300),
                        ],
                      )
                    else if (_aiAnswer.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF39AC86).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(fontSize: 10, color: Color(0xFF39AC86), fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _isAITyping
                    ? _buildTypingIndicator(isDarkMode)
                    : _aiAnswer.isEmpty
                        ? _buildSearchSuggestions(isDarkMode)
                        : _buildAIResponse(isDarkMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot(int delayMs) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + delayMs),
      builder: (context, val, _) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Color.fromRGBO(57, 172, 134, val),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF39AC86).withOpacity(0.4),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Searching garden knowledge...',
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.07) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          width: 200,
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.07) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchSuggestions(bool isDarkMode) {
    final suggestions = [
      ('🌱', 'How do I grow tomatoes?'),
      ('🪲', 'What pests affect my crops?'),
      ('💧', 'Best watering schedule?'),
      ('🌿', 'When should I harvest?'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Try asking...',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions.map((s) {
            return GestureDetector(
              onTap: () {
                _searchController.text = s.$2;
                _askAI(s.$2);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF39AC86).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.$1, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      s.$2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF39AC86),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAIResponse(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.06) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 12, color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _lastQuery,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode ? Colors.white54 : const Color(0xFF6B7280),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _aiAnswer,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode ? Colors.white70 : const Color(0xFF1F2937),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _searchController.clear();
            setState(() {
              _aiAnswer = '';
              _lastQuery = '';
            });
            _searchFocusNode.requestFocus();
          },
          child: Row(
            children: [
              Icon(Icons.refresh, size: 14, color: const Color(0xFF39AC86)),
              const SizedBox(width: 6),
              const Text(
                'Ask another question',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF39AC86),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────── Hardiness Zone Section with Map ───────────────

  Widget _buildHardinessZoneSection(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 32, 0, 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.thermostat, color: Color(0xFF39AC86), size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hardiness Zones',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Best crops for your climate',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Interactive Map
          Container(
            height: 200,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: const CameraPosition(
                  target: LatLng(39.8283, -98.5795),
                  zoom: 3.5,
                ),
                markers: _zoneMarkers,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: true,
                zoomGesturesEnabled: true,
                scrollGesturesEnabled: true,
              ),
            ),
          ),

          // Your zone card
          if (!_isLoadingZone && _userZone != null) ...[
            _buildYourZoneCard(isDarkMode),
            const SizedBox(height: 16),
          ] else if (_isLoadingZone) ...[
            _buildZoneLoadingCard(isDarkMode),
            const SizedBox(height: 16),
          ],

          // All zones grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
            ),
            itemCount: _hardinessZones.length,
            itemBuilder: (context, index) {
              final zoneName = _hardinessZones.keys.elementAt(index);
              final zone = _hardinessZones[zoneName]!;
              final isUserZone = zoneName == _userZone;
              return _buildZoneCard(zoneName, zone, isUserZone, isDarkMode);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildYourZoneCard(bool isDarkMode) {
    final zone = _hardinessZones[_userZone]!;
    final Color zoneColor = zone['color'] as Color;
    final List crops = zone['suitableCrops'] as List;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            zoneColor.withOpacity(0.15),
            zoneColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: zoneColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: zoneColor.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: zoneColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: zoneColor.withOpacity(0.4)),
            ),
            child: Center(
              child: Text(
                _userZone!.replaceAll('Zone ', ''),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: zoneColor,
                ),
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
                      _userZone!,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: zoneColor,
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
                        'YOUR ZONE',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  zone['description'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  zone['tempRange'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: zoneColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: crops.take(3).map<Widget>((crop) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: zoneColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        crop.toString(),
                        style: TextStyle(fontSize: 10, color: zoneColor, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneLoadingCard(bool isDarkMode) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF39AC86), strokeWidth: 2),
      ),
    );
  }

  Widget _buildZoneCard(String zoneName, Map<String, dynamic> zone, bool isUserZone, bool isDarkMode) {
    final Color zoneColor = zone['color'] as Color;
    final List crops = zone['suitableCrops'] as List;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUserZone
            ? zoneColor.withOpacity(0.12)
            : (isDarkMode ? const Color(0xFF2D3A35) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUserZone ? zoneColor.withOpacity(0.5) : (isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
          width: isUserZone ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                zoneName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: zoneColor,
                ),
              ),
              if (isUserZone)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('YOU', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            zone['tempRange'] as String,
            style: TextStyle(
              fontSize: 9,
              color: isDarkMode ? Colors.white54 : const Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: crops.take(2).map<Widget>((crop) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: zoneColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  crop.toString(),
                  style: TextStyle(fontSize: 8, color: zoneColor, fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────── Top Bar ───────────────

  Widget _buildTopBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF39AC86).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.eco, color: Color(0xFF39AC86), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('My Garden', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                  'Growth Phase: ${_getGardenPhase()}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF39AC86),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Icon(
                  Icons.notifications_outlined,
                  color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF39AC86),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFF39AC86).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: IconButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const AddNewCropScreen()),
                    );
                    if (result != null) {
                      await _refreshGardenData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Crop added successfully!'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 24),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeMessage(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getGreeting()}, ${_getUserName()}! ${_getGreetingEmoji()}',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _gardens.isEmpty ? 'Start by adding your first garden.' : 'Your plants are ${_getMood()}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('ACTIVE', '$_activeCropsCount', 'Healthy crops', const Color(0xFF39AC86), isDarkMode)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCard('HARVEST', '$_harvestReadyCount', 'Ready now', const Color(0xFFE59866), isDarkMode)),
          const SizedBox(width: 12),
          Expanded(child: _buildStatCardKg('SHARED', _sharedThisWeek, 'This week', const Color(0xFF4299E1), isDarkMode)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String sub, Color color, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatCardKg(String label, double value, String sub, Color color, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: value.toStringAsFixed(1), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const TextSpan(text: 'kg', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ])),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCropListHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Your Current Crops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Row(
            children: [
              if (_archivedCropsCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.archive, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '$_archivedCropsCount archived',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => AllCropsScreen(initialCrops: _crops)),
                  );
                },
                child: const Text('View all', style: TextStyle(color: Color(0xFF39AC86), fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropCards(bool isDarkMode) {
    if (_crops.isEmpty && _archivedCropsCount == 0) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.eco, size: 48, color: const Color(0xFF39AC86).withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text('No crops yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Tap the + button to add your first crop', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
            ],
          ),
        ),
      );
    }
    
    if (_crops.isEmpty && _archivedCropsCount > 0) {
      return Container(
        height: 180,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.archive, size: 48, color: Colors.grey.withOpacity(0.3)),
              const SizedBox(height: 12),
              const Text('All crops archived', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Tap "View all" to restore or add new crops', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _crops.length > 5 ? 5 : _crops.length,
        itemBuilder: (context, index) {
          final crop = _crops[index];
          return Padding(
            padding: EdgeInsets.only(right: index == _crops.length - 1 ? 0 : 16),
            child: _buildCropCard(context, crop, isDarkMode),
          );
        },
      ),
    );
  }

  Widget _buildCropCard(BuildContext context, Map<String, dynamic> crop, bool isDarkMode) {
    final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
    final String status = crop['status']?.toString() ?? 'seedling';
    final String name = crop['name']?.toString() ?? 'Unnamed Crop';
    final String category = crop['category']?.toString() ?? 'vegetable';
    final String? imageUrl = crop['image_url']?.toString();

    Color progressColor;
    Color statusBgColor;
    String statusLabel;

    switch (status) {
      case 'harvest':
        progressColor = const Color(0xFFE59866); statusBgColor = const Color(0xFFE59866); statusLabel = 'READY'; break;
      case 'fruiting':
        progressColor = const Color(0xFF39AC86); statusBgColor = const Color(0xFF39AC86); statusLabel = 'FRUITING'; break;
      case 'flowering':
        progressColor = const Color(0xFFE59866); statusBgColor = const Color(0xFFE59866); statusLabel = 'FLOWERING'; break;
      case 'vegetative':
        progressColor = const Color(0xFF4299E1); statusBgColor = const Color(0xFF4299E1); statusLabel = 'GROWING'; break;
      default:
        progressColor = Colors.grey; statusBgColor = Colors.grey; statusLabel = status.toUpperCase();
    }

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 128,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  color: const Color(0xFF39AC86).withOpacity(0.1),
                  image: (imageUrl != null && imageUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                          onError: (e, s) {},
                        )
                      : null,
                ),
                child: (imageUrl == null || imageUrl.isEmpty)
                    ? Center(child: Icon(Icons.eco, size: 48, color: const Color(0xFF39AC86).withOpacity(0.3)))
                    : null,
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusBgColor.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(statusLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_capitalize(category), style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white70 : const Color(0xFF666666))),
                const SizedBox(height: 16),
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress / 100,
                    child: Container(decoration: BoxDecoration(color: progressColor, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductivityHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Recent Productivity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_isRefreshing)
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39AC86)),
            ),
        ],
      ),
    );
  }

  Widget _buildChartsCard(bool isDarkMode) {
    final maxHarvest = _weeklyHarvest.isEmpty ? 1 : _weeklyHarvest.reduce((a, b) => a > b ? a : b);
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL YIELD (KG)', style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: _totalYield.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                    const TextSpan(text: 'kg', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF999999))),
                  ])),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.trending_up, color: Color(0xFF39AC86), size: 16),
                      const SizedBox(width: 4),
                      Text('+${_calculateGrowth()}% vs last week', style: const TextStyle(color: Color(0xFF39AC86), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF39AC86).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text(_getDateRange(), style: const TextStyle(fontSize: 10, color: Color(0xFF39AC86), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 128,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                final height = maxHarvest > 0 ? (_weeklyHarvest[index] / maxHarvest) : 0;
                // FIXED: Convert height to double explicitly
                return _buildChartBar(height.toDouble(), _weekDays[index], _weeklyHarvest[index]);
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarvestFAB(bool isDarkMode) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFE59866),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFFE59866).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: IconButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Harvest log coming soon!')));
        },
        icon: const Icon(Icons.inventory_2, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildChartBar(double heightFactor, String day, double value) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 32,
          height: heightFactor * 100,
          decoration: BoxDecoration(
            color: const Color(0xFF39AC86).withOpacity(0.2),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
          ),
          child: value > 0
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 32,
                      height: heightFactor * 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFF39AC86), const Color(0xFF39AC86).withOpacity(0.7)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                      ),
                      child: Center(
                        child: Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 8),
        Text(day, style: const TextStyle(fontSize: 10, color: Color(0xFF999999), fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getDateRange() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${months[start.month - 1]} ${start.day} - ${months[now.month - 1]} ${now.day}';
  }

  int _calculateGrowth() {
    if (_weeklyHarvest.isEmpty) return 0;
    final total = _weeklyHarvest.reduce((a, b) => a + b);
    return total > 0 ? 12 : 0;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}





// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:geolocator/geolocator.dart';
// import 'add_new_crop.dart';
// import 'all_crops_screen.dart';
// import '../services/api_service.dart';
// import '../providers/auth_provider.dart';
// import '../services/ai_service.dart';
// import 'dart:async';

// class GardenScreen extends StatefulWidget {
//   const GardenScreen({super.key});

//   @override
//   State<GardenScreen> createState() => _GardenScreenState();
// }

// class _GardenScreenState extends State<GardenScreen> with TickerProviderStateMixin {
//   final ApiService _apiService = ApiService();
//   final AIService _aiService = AIService();
//   final TextEditingController _searchController = TextEditingController();
//   final FocusNode _searchFocusNode = FocusNode();

//   // Data variables
//   List<dynamic> _crops = [];
//   List<dynamic> _gardens = [];
//   Map<String, dynamic>? _userData;

//   // Stats
//   int _activeCropsCount = 0;
//   int _harvestReadyCount = 0;
//   double _sharedThisWeek = 0;
//   double _totalYield = 0;

//   // Loading states
//   bool _isLoading = true;
//   bool _isRefreshing = false;

//   // Cache
//   DateTime? _lastLoadTime;

//   // Image cache buster
//   int _imageVersion = 0;

//   // Weekly harvest data for chart
//   final List<double> _weeklyHarvest = [0.6, 0.3, 0.45, 0.8, 0.55, 0.9, 0.7];
//   final List<String> _weekDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

//   // ── AI Search ──
//   bool _showSearchPanel = false;
//   bool _isAITyping = false;
//   String _aiAnswer = '';
//   String _lastQuery = '';
//   Timer? _debounce;
//   late AnimationController _panelController;
//   late Animation<double> _panelAnimation;

//   // ── Hardiness Zone ──
//   String? _userZone;
//   bool _isLoadingZone = true;
//   Map<String, dynamic> _hardinessZones = {};

//   @override
//   void initState() {
//     super.initState();
//     _panelController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 300),
//     );
//     _panelAnimation = CurvedAnimation(
//       parent: _panelController,
//       curve: Curves.easeOutCubic,
//     );
//     _loadGardenData();
//     _loadHardinessZone();
//     _initAI();

//     _searchFocusNode.addListener(() {
//       if (_searchFocusNode.hasFocus && _searchController.text.trim().isNotEmpty) {
//         _openPanel();
//       }
//     });
//   }

//   Future<void> _initAI() async {
//     await _aiService.initialize();
//   }

//   void _openPanel() {
//     setState(() => _showSearchPanel = true);
//     _panelController.forward();
//   }

//   void _closePanel() {
//     _panelController.reverse().then((_) {
//       if (mounted) setState(() => _showSearchPanel = false);
//     });
//   }

//   void _onSearchChanged(String query) {
//     if (query.trim().isEmpty) {
//       _closePanel();
//       return;
//     }
//     _openPanel();
//     if (_debounce?.isActive ?? false) _debounce!.cancel();
//     _debounce = Timer(const Duration(milliseconds: 700), () {
//       if (query.trim() != _lastQuery) {
//         _askAI(query.trim());
//       }
//     });
//   }

//   Future<void> _askAI(String query) async {
//     // Guard: only garden/crop/agriculture topics
//     final lowerQ = query.toLowerCase();
//     final gardenKeywords = [
//       'crop', 'plant', 'garden', 'grow', 'harvest', 'soil', 'water', 'fertiliz',
//       'pest', 'disease', 'seed', 'fruit', 'vegetable', 'herb', 'flower', 'farm',
//       'compost', 'irrigat', 'prune', 'weed', 'season', 'climate', 'zone',
//       'tomato', 'pepper', 'lettuce', 'carrot', 'bean', 'corn', 'potato',
//     ];
//     final isGardenTopic = gardenKeywords.any((kw) => lowerQ.contains(kw));

//     setState(() {
//       _isAITyping = true;
//       _lastQuery = query;
//       _aiAnswer = '';
//     });

//     if (!isGardenTopic) {
//       await Future.delayed(const Duration(milliseconds: 400));
//       setState(() {
//         _aiAnswer = "🌿 I'm your garden assistant! I can only help with topics related to crops, planting, harvesting, soil, pests, and agriculture. Try asking something like \"How do I grow tomatoes?\" or \"When should I harvest carrots?\"";
//         _isAITyping = false;
//       });
//       return;
//     }

//     try {
//       final response = await _aiService.askQuestion(
//         'You are a friendly, expert garden assistant. Answer only gardening, crop, farming, and agriculture questions. Keep answers concise and practical. Question: $query',
//       );
//       setState(() {
//         _aiAnswer = response;
//         _isAITyping = false;
//       });
//     } catch (e) {
//       setState(() {
//         _aiAnswer = 'Sorry, I couldn\'t fetch an answer right now. Please try again.';
//         _isAITyping = false;
//       });
//     }
//   }

//   // ── Hardiness Zone ──
//   Future<void> _loadHardinessZone() async {
//     _hardinessZones = _generateZoneData();
//     try {
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//       }
//       if (permission == LocationPermission.deniedForever) {
//         setState(() => _isLoadingZone = false);
//         return;
//       }
//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.low,
//         timeLimit: const Duration(seconds: 10),
//       );
//       setState(() {
//         _userZone = _getZoneFromCoordinates(position.latitude);
//         _isLoadingZone = false;
//       });
//     } catch (e) {
//       setState(() => _isLoadingZone = false);
//     }
//   }

//   String _getZoneFromCoordinates(double lat) {
//     if (lat > 60) return 'Zone 1';
//     if (lat > 55) return 'Zone 2';
//     if (lat > 50) return 'Zone 3';
//     if (lat > 45) return 'Zone 4';
//     if (lat > 40) return 'Zone 5';
//     if (lat > 35) return 'Zone 6';
//     if (lat > 30) return 'Zone 7';
//     if (lat > 25) return 'Zone 8';
//     if (lat > 20) return 'Zone 9';
//     return 'Zone 10';
//   }

//   Map<String, dynamic> _generateZoneData() {
//     return {
//       'Zone 1':  {'tempRange': 'Below -50°F', 'color': const Color(0xFF2C3E5C), 'suitableCrops': ['Potatoes', 'Kale', 'Carrots', 'Turnips'], 'description': 'Extreme cold, very short growing season'},
//       'Zone 2':  {'tempRange': '-50°F to -40°F', 'color': const Color(0xFF3E5A8A), 'suitableCrops': ['Potatoes', 'Cabbage', 'Peas', 'Radishes'], 'description': 'Very cold, short growing season'},
//       'Zone 3':  {'tempRange': '-40°F to -30°F', 'color': const Color(0xFF4F7AB3), 'suitableCrops': ['Broccoli', 'Cauliflower', 'Lettuce', 'Spinach'], 'description': 'Cold winters, moderate summers'},
//       'Zone 4':  {'tempRange': '-30°F to -20°F', 'color': const Color(0xFF609CD9), 'suitableCrops': ['Tomatoes', 'Peppers', 'Beans', 'Corn'], 'description': 'Cold climate, good for hardy vegetables'},
//       'Zone 5':  {'tempRange': '-20°F to -10°F', 'color': const Color(0xFF71BDFF), 'suitableCrops': ['Apples', 'Cherries', 'Peaches', 'Grapes'], 'description': 'Temperate, diverse growing options'},
//       'Zone 6':  {'tempRange': '-10°F to 0°F',   'color': const Color(0xFF8ACC66), 'suitableCrops': ['Strawberries', 'Blueberries', 'Raspberries'], 'description': 'Mild winters, long growing season'},
//       'Zone 7':  {'tempRange': '0°F to 10°F',    'color': const Color(0xFFA5D95E), 'suitableCrops': ['Citrus', 'Figs', 'Pomegranates', 'Olives'], 'description': 'Warm, excellent for fruit trees'},
//       'Zone 8':  {'tempRange': '10°F to 20°F',   'color': const Color(0xFFBFF055), 'suitableCrops': ['Avocados', 'Bananas', 'Mangoes', 'Papayas'], 'description': 'Warm, subtropical plants thrive'},
//       'Zone 9':  {'tempRange': '20°F to 30°F',   'color': const Color(0xFFD9FF4C), 'suitableCrops': ['Tomatoes', 'Eggplant', 'Okra', 'Sweet Potatoes'], 'description': 'Hot, year-round growing possible'},
//       'Zone 10': {'tempRange': '30°F to 40°F',   'color': const Color(0xFFF2F242), 'suitableCrops': ['Pineapples', 'Coconuts', 'Tropical Fruits'], 'description': 'Tropical, year-round gardening'},
//     };
//   }

//   // ── Garden Data ──
//   Future<void> _loadGardenData({bool forceRefresh = false}) async {
//     if (!forceRefresh &&
//         _lastLoadTime != null &&
//         DateTime.now().difference(_lastLoadTime!) < const Duration(minutes: 2)) {
//       setState(() => _isLoading = false);
//       return;
//     }
//     setState(() => _isLoading = true);
//     await _fetchGardenData();
//     setState(() {
//       _isLoading = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _refreshGardenData() async {
//     if (_isRefreshing) return;
//     setState(() {
//       _isRefreshing = true;
//       _imageVersion++;
//     });
//     await _fetchGardenData();
//     setState(() {
//       _isRefreshing = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _fetchGardenData() async {
//     try {
//       final authProvider = context.read<AuthProvider>();
//       _userData = authProvider.currentUser;

//       final cropsResult = await _apiService.getUserCrops();
//       if (cropsResult['success'] == true) {
//         final allCrops = cropsResult['crops'] ?? [];
//         setState(() {
//           _crops = allCrops;
//           _activeCropsCount = allCrops.where((c) => c['status'] != 'harvest' && (c['progress'] ?? 0) < 100).length;
//           _harvestReadyCount = allCrops.where((c) => c['status'] == 'harvest' || (c['progress'] ?? 0) >= 100).length;
//           _sharedThisWeek = allCrops.where((c) => c['is_shared'] == true).fold(0, (sum, c) => sum + (c['quantity'] ?? 0).toDouble());
//           _totalYield = allCrops.fold(0, (sum, c) => sum + (c['quantity'] ?? 0).toDouble());
//         });
//       }

//       final gardensResult = await _apiService.getUserGardens();
//       if (gardensResult['success'] == true) {
//         setState(() => _gardens = gardensResult['gardens'] ?? []);
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text('Failed to load garden data'), backgroundColor: Colors.red),
//         );
//       }
//     }
//   }

//   String _getGreeting() {
//     final hour = DateTime.now().hour;
//     if (hour < 12) return 'Good morning';
//     if (hour < 17) return 'Good afternoon';
//     return 'Good evening';
//   }

//   String _getUserName() {
//     if (_userData != null && _userData!['name'] != null) {
//       return _userData!['name'].toString().split(' ')[0];
//     }
//     return 'Gardener';
//   }

//   String _getGardenPhase() {
//     if (_gardens.isEmpty) return 'No Garden';
//     if (_activeCropsCount > 5) return 'Thriving';
//     if (_activeCropsCount > 0) return 'Active';
//     return 'Ready to Plant';
//   }

//   String _getGreetingEmoji() {
//     final hour = DateTime.now().hour;
//     if (hour < 12) return '🌅';
//     if (hour < 17) return '☀️';
//     return '🌙';
//   }

//   String _getMood() {
//     if (_activeCropsCount > 10) return 'thriving! 🌱';
//     if (_activeCropsCount > 5) return 'growing well 🌿';
//     if (_activeCropsCount > 0) return 'starting to grow 🌱';
//     return 'ready for planting 🌻';
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     _searchFocusNode.dispose();
//     _panelController.dispose();
//     _debounce?.cancel();
//     super.dispose();
//   }

//   // ─────────────────────────── BUILD ───────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     return GestureDetector(
//       onTap: () {
//         _searchFocusNode.unfocus();
//         if (_showSearchPanel) _closePanel();
//       },
//       child: Scaffold(
//         backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: SafeArea(
//           bottom: false,
//           child: _isLoading
//               ? _buildLoadingScreen(isDarkMode)
//               : RefreshIndicator(
//                   onRefresh: _refreshGardenData,
//                   color: const Color(0xFF39AC86),
//                   backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//                   child: SingleChildScrollView(
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     child: Column(
//                       children: [
//                         _buildTopBar(isDarkMode),
//                         _buildSearchBar(isDarkMode),
//                         if (_showSearchPanel) _buildSearchPanel(isDarkMode),
//                         _buildWelcomeMessage(isDarkMode),
//                         _buildStatsSection(isDarkMode),
//                         _buildCropListHeader(isDarkMode),
//                         _buildCropCards(isDarkMode),
//                         _buildProductivityHeader(isDarkMode),
//                         _buildChartsCard(isDarkMode),
//                         _buildHardinessZoneSection(isDarkMode),
//                         const SizedBox(height: 100),
//                       ],
//                     ),
//                   ),
//                 ),
//         ),
//         floatingActionButton: _buildHarvestFAB(isDarkMode),
//         floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//       ),
//     );
//   }

//   // ─────────────── Search Bar ───────────────

//   Widget _buildSearchBar(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
//       child: Container(
//         height: 52,
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(16),
//           border: Border.all(
//             color: _showSearchPanel
//                 ? const Color(0xFF39AC86)
//                 : (isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB)),
//             width: _showSearchPanel ? 1.5 : 1,
//           ),
//           boxShadow: _showSearchPanel
//               ? [BoxShadow(color: const Color(0xFF39AC86).withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]
//               : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
//         ),
//         child: Row(
//           children: [
//             const SizedBox(width: 16),
//             AnimatedSwitcher(
//               duration: const Duration(milliseconds: 200),
//               child: _isAITyping
//                   ? SizedBox(
//                       key: const ValueKey('loader'),
//                       width: 18,
//                       height: 18,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         color: const Color(0xFF39AC86),
//                       ),
//                     )
//                   : Icon(
//                       key: const ValueKey('icon'),
//                       _showSearchPanel ? Icons.eco : Icons.search,
//                       color: _showSearchPanel ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
//                       size: 20,
//                     ),
//             ),
//             const SizedBox(width: 10),
//             Expanded(
//               child: TextField(
//                 controller: _searchController,
//                 focusNode: _searchFocusNode,
//                 onChanged: _onSearchChanged,
//                 decoration: InputDecoration(
//                   hintText: 'Ask about your crops, soil, pests...',
//                   hintStyle: TextStyle(
//                     color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
//                     fontSize: 14,
//                   ),
//                   border: InputBorder.none,
//                   contentPadding: EdgeInsets.zero,
//                 ),
//                 style: TextStyle(
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                   fontSize: 14,
//                 ),
//               ),
//             ),
//             if (_searchController.text.isNotEmpty)
//               GestureDetector(
//                 onTap: () {
//                   _searchController.clear();
//                   _closePanel();
//                   setState(() {
//                     _aiAnswer = '';
//                     _lastQuery = '';
//                   });
//                 },
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 12),
//                   child: Icon(Icons.close, size: 18, color: isDarkMode ? Colors.white54 : const Color(0xFF9CA3AF)),
//                 ),
//               )
//             else
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 14),
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: const Text(
//                     'AI',
//                     style: TextStyle(
//                       fontSize: 10,
//                       fontWeight: FontWeight.w800,
//                       color: Color(0xFF39AC86),
//                       letterSpacing: 0.5,
//                     ),
//                   ),
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Search AI Panel ───────────────

//   Widget _buildSearchPanel(bool isDarkMode) {
//     return FadeTransition(
//       opacity: _panelAnimation,
//       child: SlideTransition(
//         position: Tween<Offset>(
//           begin: const Offset(0, -0.05),
//           end: Offset.zero,
//         ).animate(_panelAnimation),
//         child: Container(
//           margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
//           decoration: BoxDecoration(
//             color: isDarkMode ? const Color(0xFF253330) : Colors.white,
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(
//               color: const Color(0xFF39AC86).withOpacity(0.2),
//             ),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.08),
//                 blurRadius: 20,
//                 offset: const Offset(0, 8),
//               ),
//             ],
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Panel Header
//               Container(
//                 padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86).withOpacity(0.07),
//                   borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
//                   border: Border(
//                     bottom: BorderSide(
//                       color: const Color(0xFF39AC86).withOpacity(0.12),
//                     ),
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     Container(
//                       width: 32,
//                       height: 32,
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: const Icon(Icons.eco, color: Colors.white, size: 16),
//                     ),
//                     const SizedBox(width: 10),
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Text(
//                           'Garden AI Assistant',
//                           style: TextStyle(
//                             fontSize: 13,
//                             fontWeight: FontWeight.w700,
//                             color: Color(0xFF39AC86),
//                           ),
//                         ),
//                         Text(
//                           'Crop & agriculture expert',
//                           style: TextStyle(
//                             fontSize: 10,
//                             color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const Spacer(),
//                     if (_isAITyping)
//                       Row(
//                         children: [
//                           _buildDot(0),
//                           _buildDot(150),
//                           _buildDot(300),
//                         ],
//                       )
//                     else if (_aiAnswer.isNotEmpty)
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                         decoration: BoxDecoration(
//                           color: const Color(0xFF39AC86).withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         child: const Text(
//                           'Done',
//                           style: TextStyle(fontSize: 10, color: Color(0xFF39AC86), fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),

//               // Content
//               Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: _isAITyping
//                     ? _buildTypingIndicator(isDarkMode)
//                     : _aiAnswer.isEmpty
//                         ? _buildSearchSuggestions(isDarkMode)
//                         : _buildAIResponse(isDarkMode),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDot(int delayMs) {
//     return TweenAnimationBuilder<double>(
//       tween: Tween(begin: 0.3, end: 1.0),
//       duration: Duration(milliseconds: 600 + delayMs),
//       builder: (context, val, _) => Container(
//         margin: const EdgeInsets.symmetric(horizontal: 2),
//         width: 6,
//         height: 6,
//         decoration: BoxDecoration(
//           color: Color.fromRGBO(57, 172, 134, val),
//           shape: BoxShape.circle,
//         ),
//       ),
//     );
//   }

//   Widget _buildTypingIndicator(bool isDarkMode) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Container(
//               width: 8,
//               height: 8,
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.4),
//                 shape: BoxShape.circle,
//               ),
//             ),
//             const SizedBox(width: 8),
//             Text(
//               'Searching garden knowledge...',
//               style: TextStyle(
//                 fontSize: 13,
//                 color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
//                 fontStyle: FontStyle.italic,
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(height: 12),
//         Container(
//           height: 8,
//           decoration: BoxDecoration(
//             color: isDarkMode ? Colors.white.withOpacity(0.07) : const Color(0xFFF3F4F6),
//             borderRadius: BorderRadius.circular(4),
//           ),
//         ),
//         const SizedBox(height: 8),
//         Container(
//           height: 8,
//           width: 200,
//           decoration: BoxDecoration(
//             color: isDarkMode ? Colors.white.withOpacity(0.07) : const Color(0xFFF3F4F6),
//             borderRadius: BorderRadius.circular(4),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildSearchSuggestions(bool isDarkMode) {
//     final suggestions = [
//       ('🌱', 'How do I grow tomatoes?'),
//       ('🪲', 'What pests affect my crops?'),
//       ('💧', 'Best watering schedule?'),
//       ('🌿', 'When should I harvest?'),
//     ];
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Try asking...',
//           style: TextStyle(
//             fontSize: 11,
//             fontWeight: FontWeight.w600,
//             color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF),
//             letterSpacing: 0.5,
//           ),
//         ),
//         const SizedBox(height: 10),
//         Wrap(
//           spacing: 8,
//           runSpacing: 8,
//           children: suggestions.map((s) {
//             return GestureDetector(
//               onTap: () {
//                 _searchController.text = s.$2;
//                 _askAI(s.$2);
//               },
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86).withOpacity(0.08),
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Text(s.$1, style: const TextStyle(fontSize: 13)),
//                     const SizedBox(width: 6),
//                     Text(
//                       s.$2,
//                       style: const TextStyle(
//                         fontSize: 12,
//                         color: Color(0xFF39AC86),
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           }).toList(),
//         ),
//       ],
//     );
//   }

//   Widget _buildAIResponse(bool isDarkMode) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         // Query echo
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//           decoration: BoxDecoration(
//             color: isDarkMode ? Colors.white.withOpacity(0.06) : const Color(0xFFF9FAFB),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Row(
//             children: [
//               Icon(Icons.search, size: 12, color: isDarkMode ? Colors.white38 : const Color(0xFF9CA3AF)),
//               const SizedBox(width: 6),
//               Expanded(
//                 child: Text(
//                   _lastQuery,
//                   style: TextStyle(
//                     fontSize: 11,
//                     color: isDarkMode ? Colors.white54 : const Color(0xFF6B7280),
//                     fontStyle: FontStyle.italic,
//                   ),
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 12),
//         // Answer
//         Text(
//           _aiAnswer,
//           style: TextStyle(
//             fontSize: 14,
//             color: isDarkMode ? Colors.white70 : const Color(0xFF1F2937),
//             height: 1.6,
//           ),
//         ),
//         const SizedBox(height: 12),
//         // Ask more
//         GestureDetector(
//           onTap: () {
//             _searchController.clear();
//             setState(() {
//               _aiAnswer = '';
//               _lastQuery = '';
//             });
//             _searchFocusNode.requestFocus();
//           },
//           child: Row(
//             children: [
//               Icon(Icons.refresh, size: 14, color: const Color(0xFF39AC86)),
//               const SizedBox(width: 6),
//               const Text(
//                 'Ask another question',
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: Color(0xFF39AC86),
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   // ─────────────── Hardiness Zone Section ───────────────

//   Widget _buildHardinessZoneSection(bool isDarkMode) {
//     return Container(
//       margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Section header
//           Padding(
//             padding: const EdgeInsets.fromLTRB(0, 32, 0, 16),
//             child: Row(
//               children: [
//                 Container(
//                   width: 36,
//                   height: 36,
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(Icons.thermostat, color: Color(0xFF39AC86), size: 20),
//                 ),
//                 const SizedBox(width: 12),
//                 Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Hardiness Zones',
//                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     Text(
//                       'Best crops for your climate',
//                       style: TextStyle(
//                         fontSize: 11,
//                         color: isDarkMode ? Colors.white54 : const Color(0xFF5C8A7A),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),

//           // Your zone card
//           if (!_isLoadingZone && _userZone != null) ...[
//             _buildYourZoneCard(isDarkMode),
//             const SizedBox(height: 16),
//           ] else if (_isLoadingZone) ...[
//             _buildZoneLoadingCard(isDarkMode),
//             const SizedBox(height: 16),
//           ],

//           // All zones grid
//           GridView.builder(
//             shrinkWrap: true,
//             physics: const NeverScrollableScrollPhysics(),
//             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//               crossAxisCount: 2,
//               crossAxisSpacing: 12,
//               mainAxisSpacing: 12,
//               childAspectRatio: 1.45,
//             ),
//             itemCount: _hardinessZones.length,
//             itemBuilder: (context, index) {
//               final zoneName = _hardinessZones.keys.elementAt(index);
//               final zone = _hardinessZones[zoneName]!;
//               final isUserZone = zoneName == _userZone;
//               return _buildZoneCard(zoneName, zone, isUserZone, isDarkMode);
//             },
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildYourZoneCard(bool isDarkMode) {
//     final zone = _hardinessZones[_userZone]!;
//     final Color zoneColor = zone['color'] as Color;
//     final List crops = zone['suitableCrops'] as List;

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: [
//             zoneColor.withOpacity(0.15),
//             zoneColor.withOpacity(0.05),
//           ],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: zoneColor.withOpacity(0.4), width: 1.5),
//         boxShadow: [
//           BoxShadow(
//             color: zoneColor.withOpacity(0.1),
//             blurRadius: 12,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 56,
//             height: 56,
//             decoration: BoxDecoration(
//               color: zoneColor.withOpacity(0.2),
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(color: zoneColor.withOpacity(0.4)),
//             ),
//             child: Center(
//               child: Text(
//                 _userZone!.replaceAll('Zone ', ''),
//                 style: TextStyle(
//                   fontSize: 22,
//                   fontWeight: FontWeight.w900,
//                   color: zoneColor,
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Text(
//                       _userZone!,
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.w800,
//                         color: zoneColor,
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: const Text(
//                         'YOUR ZONE',
//                         style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   zone['description'] as String,
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   zone['tempRange'] as String,
//                   style: TextStyle(
//                     fontSize: 11,
//                     fontWeight: FontWeight.w600,
//                     color: zoneColor,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Wrap(
//                   spacing: 6,
//                   runSpacing: 4,
//                   children: crops.take(3).map<Widget>((crop) {
//                     return Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//                       decoration: BoxDecoration(
//                         color: zoneColor.withOpacity(0.12),
//                         borderRadius: BorderRadius.circular(6),
//                       ),
//                       child: Text(
//                         crop.toString(),
//                         style: TextStyle(fontSize: 10, color: zoneColor, fontWeight: FontWeight.w600),
//                       ),
//                     );
//                   }).toList(),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildZoneLoadingCard(bool isDarkMode) {
//     return Container(
//       height: 100,
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
//       ),
//       child: const Center(
//         child: CircularProgressIndicator(color: Color(0xFF39AC86), strokeWidth: 2),
//       ),
//     );
//   }

//   Widget _buildZoneCard(String zoneName, Map<String, dynamic> zone, bool isUserZone, bool isDarkMode) {
//     final Color zoneColor = zone['color'] as Color;
//     final List crops = zone['suitableCrops'] as List;

//     return Container(
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: isUserZone
//             ? zoneColor.withOpacity(0.12)
//             : (isDarkMode ? const Color(0xFF2D3A35) : Colors.white),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(
//           color: isUserZone ? zoneColor.withOpacity(0.5) : (isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
//           width: isUserZone ? 1.5 : 1,
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.04),
//             blurRadius: 6,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Text(
//                 zoneName,
//                 style: TextStyle(
//                   fontSize: 15,
//                   fontWeight: FontWeight.w800,
//                   color: zoneColor,
//                 ),
//               ),
//               if (isUserZone)
//                 Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86),
//                     borderRadius: BorderRadius.circular(6),
//                   ),
//                   child: const Text('YOU', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
//                 ),
//             ],
//           ),
//           const SizedBox(height: 3),
//           Text(
//             zone['tempRange'] as String,
//             style: TextStyle(
//               fontSize: 9,
//               color: isDarkMode ? Colors.white54 : const Color(0xFF666666),
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//           const Spacer(),
//           Wrap(
//             spacing: 4,
//             runSpacing: 4,
//             children: crops.take(2).map<Widget>((crop) {
//               return Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                 decoration: BoxDecoration(
//                   color: zoneColor.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//                 child: Text(
//                   crop.toString(),
//                   style: TextStyle(fontSize: 8, color: zoneColor, fontWeight: FontWeight.w600),
//                 ),
//               );
//             }).toList(),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─────────────── Existing Widgets (unchanged) ───────────────

//   Widget _buildLoadingScreen(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const CircularProgressIndicator(color: Color(0xFF39AC86)),
//           const SizedBox(height: 20),
//           Text(
//             'Loading your garden...',
//             style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//         border: Border(
//           bottom: BorderSide(
//             color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
//           ),
//         ),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 40,
//             height: 40,
//             decoration: BoxDecoration(
//               color: const Color(0xFF39AC86).withOpacity(0.1),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: const Icon(Icons.eco, color: Color(0xFF39AC86), size: 24),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Text('My Garden', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
//                 Text(
//                   'Growth Phase: ${_getGardenPhase()}',
//                   style: const TextStyle(
//                     fontSize: 10,
//                     color: Color(0xFF39AC86),
//                     fontWeight: FontWeight.w500,
//                     letterSpacing: 1.5,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           Row(
//             children: [
//               Container(
//                 width: 40,
//                 height: 40,
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(
//                     color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1),
//                   ),
//                   boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
//                 ),
//                 child: Icon(
//                   Icons.notifications_outlined,
//                   color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                   size: 20,
//                 ),
//               ),
//               const SizedBox(width: 8),
//               Container(
//                 width: 40,
//                 height: 40,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86),
//                   borderRadius: BorderRadius.circular(20),
//                   boxShadow: [BoxShadow(color: const Color(0xFF39AC86).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
//                 ),
//                 child: IconButton(
//                   onPressed: () async {
//                     final result = await Navigator.of(context).push(
//                       MaterialPageRoute(builder: (context) => const AddNewCropScreen()),
//                     );
//                     if (result != null) {
//                       await _refreshGardenData();
//                       if (mounted) {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(content: Text('Crop added successfully!'), backgroundColor: Colors.green),
//                         );
//                       }
//                     }
//                   },
//                   icon: const Icon(Icons.add, color: Colors.white, size: 24),
//                   padding: EdgeInsets.zero,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildWelcomeMessage(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             '${_getGreeting()}, ${_getUserName()}! ${_getGreetingEmoji()}',
//             style: TextStyle(
//               fontSize: 16,
//               color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             _gardens.isEmpty ? 'Start by adding your first garden.' : 'Your plants are ${_getMood()}',
//             style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildStatsSection(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Row(
//         children: [
//           Expanded(child: _buildStatCard('ACTIVE', '$_activeCropsCount', 'Healthy crops', const Color(0xFF39AC86), isDarkMode)),
//           const SizedBox(width: 12),
//           Expanded(child: _buildStatCard('HARVEST', '$_harvestReadyCount', 'Ready now', const Color(0xFFE59866), isDarkMode)),
//           const SizedBox(width: 12),
//           Expanded(child: _buildStatCardKg('SHARED', _sharedThisWeek, 'This week', const Color(0xFF4299E1), isDarkMode)),
//         ],
//       ),
//     );
//   }

//   Widget _buildStatCard(String label, String value, String sub, Color color, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: color.withOpacity(0.2)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
//           const SizedBox(height: 4),
//           Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
//           const SizedBox(height: 2),
//           Text(sub, style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
//         ],
//       ),
//     );
//   }

//   Widget _buildStatCardKg(String label, double value, String sub, Color color, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: color.withOpacity(0.2)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
//           const SizedBox(height: 4),
//           Text.rich(TextSpan(children: [
//             TextSpan(text: value.toStringAsFixed(1), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
//             const TextSpan(text: 'kg', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//           ])),
//           const SizedBox(height: 2),
//           Text(sub, style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.w500)),
//         ],
//       ),
//     );
//   }

//   Widget _buildCropListHeader(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text('Your Current Crops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//           TextButton(
//             onPressed: () {
//               Navigator.of(context).push(
//                 MaterialPageRoute(builder: (context) => AllCropsScreen(initialCrops: _crops)),
//               );
//             },
//             child: const Text('View all', style: TextStyle(color: Color(0xFF39AC86), fontSize: 14, fontWeight: FontWeight.bold)),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCropCards(bool isDarkMode) {
//     if (_crops.isEmpty) {
//       return Container(
//         height: 200,
//         margin: const EdgeInsets.symmetric(horizontal: 16),
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(20),
//           border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF)),
//         ),
//         child: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(Icons.eco, size: 48, color: const Color(0xFF39AC86).withOpacity(0.3)),
//               const SizedBox(height: 12),
//               const Text('No crops yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//               const SizedBox(height: 4),
//               const Text('Tap the + button to add your first crop', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
//             ],
//           ),
//         ),
//       );
//     }

//     return SizedBox(
//       height: 320,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         itemCount: _crops.length > 5 ? 5 : _crops.length,
//         itemBuilder: (context, index) {
//           final crop = _crops[index];
//           return Padding(
//             padding: EdgeInsets.only(right: index == _crops.length - 1 ? 0 : 16),
//             child: _buildCropCard(context, crop, isDarkMode),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildCropCard(BuildContext context, Map<String, dynamic> crop, bool isDarkMode) {
//     final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
//     final String status = crop['status']?.toString() ?? 'seedling';
//     final String name = crop['name']?.toString() ?? 'Unnamed Crop';
//     final String category = crop['category']?.toString() ?? 'vegetable';
//     final String? imageUrl = crop['image_url']?.toString();

//     Color progressColor;
//     Color statusBgColor;
//     String statusLabel;

//     switch (status) {
//       case 'harvest':
//         progressColor = const Color(0xFFE59866); statusBgColor = const Color(0xFFE59866); statusLabel = 'READY'; break;
//       case 'fruiting':
//         progressColor = const Color(0xFF39AC86); statusBgColor = const Color(0xFF39AC86); statusLabel = 'FRUITING'; break;
//       case 'flowering':
//         progressColor = const Color(0xFFE59866); statusBgColor = const Color(0xFFE59866); statusLabel = 'FLOWERING'; break;
//       case 'vegetative':
//         progressColor = const Color(0xFF4299E1); statusBgColor = const Color(0xFF4299E1); statusLabel = 'GROWING'; break;
//       default:
//         progressColor = Colors.grey; statusBgColor = Colors.grey; statusLabel = status.toUpperCase();
//     }

//     return Container(
//       width: 240,
//       margin: const EdgeInsets.only(right: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
//         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Stack(
//             children: [
//               Container(
//                 height: 128,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
//                   color: const Color(0xFF39AC86).withOpacity(0.1),
//                   image: (imageUrl != null && imageUrl.isNotEmpty)
//                       ? DecorationImage(
//                           image: NetworkImage(imageUrl),
//                           fit: BoxFit.cover,
//                           onError: (e, s) {},
//                         )
//                       : null,
//                 ),
//                 child: (imageUrl == null || imageUrl.isEmpty)
//                     ? Center(child: Icon(Icons.eco, size: 48, color: const Color(0xFF39AC86).withOpacity(0.3)))
//                     : null,
//               ),
//               Positioned(
//                 top: 12,
//                 right: 12,
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                   decoration: BoxDecoration(
//                     color: statusBgColor.withOpacity(0.9),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Text(statusLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
//                 ),
//               ),
//             ],
//           ),
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//                 const SizedBox(height: 4),
//                 Text(_capitalize(category), style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white70 : const Color(0xFF666666))),
//                 const SizedBox(height: 16),
//                 Container(
//                   height: 4,
//                   width: double.infinity,
//                   decoration: BoxDecoration(
//                     color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1),
//                     borderRadius: BorderRadius.circular(2),
//                   ),
//                   child: FractionallySizedBox(
//                     alignment: Alignment.centerLeft,
//                     widthFactor: progress / 100,
//                     child: Container(decoration: BoxDecoration(color: progressColor, borderRadius: BorderRadius.circular(2))),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildProductivityHeader(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text('Recent Productivity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//           if (_isRefreshing)
//             const SizedBox(
//               width: 20, height: 20,
//               child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF39AC86)),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildChartsCard(bool isDarkMode) {
//     return Container(
//       margin: const EdgeInsets.all(16),
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1)),
//         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))],
//       ),
//       child: Column(
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text('TOTAL YIELD (KG)', style: TextStyle(fontSize: 10, color: isDarkMode ? Colors.white70 : const Color(0xFF666666), fontWeight: FontWeight.bold, letterSpacing: 1.5)),
//                   const SizedBox(height: 4),
//                   Text.rich(TextSpan(children: [
//                     TextSpan(text: _totalYield.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
//                     const TextSpan(text: 'kg', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF999999))),
//                   ])),
//                   const SizedBox(height: 4),
//                   Row(
//                     children: [
//                       const Icon(Icons.trending_up, color: Color(0xFF39AC86), size: 16),
//                       const SizedBox(width: 4),
//                       Text('+${_calculateGrowth()}% vs last week', style: const TextStyle(color: Color(0xFF39AC86), fontSize: 12, fontWeight: FontWeight.bold)),
//                     ],
//                   ),
//                 ],
//               ),
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                 decoration: BoxDecoration(color: const Color(0xFF39AC86).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
//                 child: Text(_getDateRange(), style: const TextStyle(fontSize: 10, color: Color(0xFF39AC86), fontWeight: FontWeight.bold)),
//               ),
//             ],
//           ),
//           const SizedBox(height: 32),
//           SizedBox(
//             height: 128,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               crossAxisAlignment: CrossAxisAlignment.end,
//               children: List.generate(7, (index) => _buildChartBar(_weeklyHarvest[index], _weekDays[index])),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildHarvestFAB(bool isDarkMode) {
//     return Container(
//       width: 56,
//       height: 56,
//       decoration: BoxDecoration(
//         color: const Color(0xFFE59866),
//         borderRadius: BorderRadius.circular(28),
//         boxShadow: [BoxShadow(color: const Color(0xFFE59866).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
//       ),
//       child: IconButton(
//         onPressed: () {
//           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Harvest log coming soon!')));
//         },
//         icon: const Icon(Icons.inventory_2, color: Colors.white, size: 24),
//       ),
//     );
//   }

//   Widget _buildChartBar(double height, String day) {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.end,
//       children: [
//         Container(
//           width: 16,
//           height: height * 80,
//           decoration: BoxDecoration(
//             color: const Color(0xFF39AC86).withOpacity(0.2),
//             borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
//           ),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.end,
//             children: [
//               Container(
//                 width: 4, height: 4,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86),
//                   borderRadius: BorderRadius.circular(2),
//                   border: Border.all(color: Colors.white, width: 2),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 8),
//         Text(day, style: const TextStyle(fontSize: 10, color: Color(0xFF999999), fontWeight: FontWeight.bold)),
//       ],
//     );
//   }

//   String _getDateRange() {
//     final now = DateTime.now();
//     final start = now.subtract(const Duration(days: 6));
//     const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
//     return '${months[start.month - 1]} ${start.day} - ${months[now.month - 1]} ${now.day}';
//   }

//   int _calculateGrowth() => 12;

//   String _capitalize(String s) {
//     if (s.isEmpty) return s;
//     return s[0].toUpperCase() + s.substring(1).toLowerCase();
//   }
// }








// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'add_new_crop.dart';
// import 'all_crops_screen.dart'; // ← THIS IMPORT IS MISSING
// import '../services/api_service.dart';
// import '../providers/auth_provider.dart';
// import 'dart:async';

// class GardenScreen extends StatefulWidget {
//   const GardenScreen({super.key});

//   @override
//   State<GardenScreen> createState() => _GardenScreenState();
// }

// class _GardenScreenState extends State<GardenScreen> {
//   final ApiService _apiService = ApiService();
  
//   // Data variables
//   List<dynamic> _crops = [];
//   List<dynamic> _gardens = [];
//   Map<String, dynamic>? _userData;
  
//   // Stats
//   int _activeCropsCount = 0;
//   int _harvestReadyCount = 0;
//   double _sharedThisWeek = 0;
//   double _totalYield = 0;
  
//   // Loading states
//   bool _isLoading = true;
//   bool _isRefreshing = false;
  
//   // Cache
//   DateTime? _lastLoadTime;
  
//   // Image cache buster
//   int _imageVersion = 0;
  
//   // Weekly harvest data for chart
//   final List<double> _weeklyHarvest = [0.6, 0.3, 0.45, 0.8, 0.55, 0.9, 0.7];
//   final List<String> _weekDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

//   @override
//   void initState() {
//     super.initState();
//     _loadGardenData();
//   }

//   Future<void> _loadGardenData({bool forceRefresh = false}) async {
//     if (!forceRefresh && 
//         _lastLoadTime != null && 
//         DateTime.now().difference(_lastLoadTime!) < const Duration(minutes: 2)) {
//       setState(() {
//         _isLoading = false;
//       });
//       return;
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     await _fetchGardenData();

//     setState(() {
//       _isLoading = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _refreshGardenData() async {
//     if (_isRefreshing) return;

//     setState(() {
//       _isRefreshing = true;
//       _imageVersion++;
//     });

//     await _fetchGardenData();

//     setState(() {
//       _isRefreshing = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _fetchGardenData() async {
//     try {
//       final authProvider = context.read<AuthProvider>();
//       _userData = authProvider.currentUser;

//       // Load crops
//       final cropsResult = await _apiService.getUserCrops();
//       if (cropsResult['success'] == true) {
//         final allCrops = cropsResult['crops'] ?? [];
        
//         // Debug print to verify image URLs
//         for (var crop in allCrops) {
//           print('🌱 Crop: ${crop['name']}, Image URL: ${crop['image_url']}');
//         }
        
//         setState(() {
//           _crops = allCrops;
          
//           _activeCropsCount = allCrops.where((crop) => 
//             crop['status'] != 'harvest' && (crop['progress'] ?? 0) < 100
//           ).length;
          
//           _harvestReadyCount = allCrops.where((crop) => 
//             crop['status'] == 'harvest' || (crop['progress'] ?? 0) >= 100
//           ).length;
          
//           _sharedThisWeek = allCrops.where((crop) => 
//             crop['is_shared'] == true
//           ).fold(0, (sum, crop) => sum + (crop['quantity'] ?? 0).toDouble());
          
//           _totalYield = allCrops.fold(0, (sum, crop) => sum + (crop['quantity'] ?? 0).toDouble());
//         });
//       }

//       // Load gardens
//       final gardensResult = await _apiService.getUserGardens();
//       if (gardensResult['success'] == true) {
//         setState(() {
//           _gardens = gardensResult['gardens'] ?? [];
//         });
//       }

//     } catch (e) {
//       print('❌ Error loading garden data: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to load garden data'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   String _getGreeting() {
//     final hour = DateTime.now().hour;
//     if (hour < 12) return 'Good morning';
//     if (hour < 17) return 'Good afternoon';
//     return 'Good evening';
//   }

//   String _getUserName() {
//     if (_userData != null && _userData!['name'] != null) {
//       final name = _userData!['name'].toString();
//       return name.split(' ')[0];
//     }
//     return 'Gardener';
//   }

//   String _getGardenPhase() {
//     if (_gardens.isEmpty) return 'No Garden';
//     if (_activeCropsCount > 5) return 'Thriving';
//     if (_activeCropsCount > 0) return 'Active';
//     return 'Ready to Plant';
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//       body: SafeArea(
//         bottom: false,
//         child: _isLoading
//             ? _buildLoadingScreen(isDarkMode)
//             : RefreshIndicator(
//                 onRefresh: _refreshGardenData,
//                 color: const Color(0xFF39AC86),
//                 backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//                 child: SingleChildScrollView(
//                   physics: const AlwaysScrollableScrollPhysics(),
//                   child: Column(
//                     children: [
//                       _buildTopBar(isDarkMode),
//                       _buildWelcomeMessage(isDarkMode),
//                       _buildStatsSection(isDarkMode),
//                       _buildCropListHeader(isDarkMode),
//                       _buildCropCards(isDarkMode),
//                       _buildProductivityHeader(isDarkMode),
//                       _buildChartsCard(isDarkMode),
//                       const SizedBox(height: 100),
//                     ],
//                   ),
//                 ),
//               ),
//       ),
//       floatingActionButton: _buildHarvestFAB(isDarkMode),
//       floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     );
//   }

//   Widget _buildLoadingScreen(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           CircularProgressIndicator(
//             color: const Color(0xFF39AC86),
//           ),
//           const SizedBox(height: 20),
//           Text(
//             'Loading your garden...',
//             style: TextStyle(
//               color: isDarkMode ? Colors.white : Colors.black,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//         border: Border(
//           bottom: BorderSide(
//             color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
//           ),
//         ),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 40,
//             height: 40,
//             decoration: BoxDecoration(
//               color: const Color(0xFF39AC86).withOpacity(0.1),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: const Icon(
//               Icons.eco,
//               color: Color(0xFF39AC86),
//               size: 24,
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Text(
//                   'My Garden',
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 Text(
//                   'Growth Phase: ${_getGardenPhase()}',
//                   style: TextStyle(
//                     fontSize: 10,
//                     color: const Color(0xFF39AC86),
//                     fontWeight: FontWeight.w500,
//                     letterSpacing: 1.5,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           Row(
//             children: [
//               Container(
//                 width: 40,
//                 height: 40,
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(
//                     color: isDarkMode 
//                         ? const Color(0xFF3A4A44) 
//                         : const Color(0xFFF0F2F1),
//                   ),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.05),
//                       blurRadius: 4,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: Icon(
//                   Icons.notifications_outlined,
//                   color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                   size: 20,
//                 ),
//               ),
//               const SizedBox(width: 8),
              
//               Container(
//                 width: 40,
//                 height: 40,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86),
//                   borderRadius: BorderRadius.circular(20),
//                   boxShadow: [
//                     BoxShadow(
//                       color: const Color(0xFF39AC86).withOpacity(0.3),
//                       blurRadius: 8,
//                       offset: const Offset(0, 4),
//                     ),
//                   ],
//                 ),
//                 child: IconButton(
//                   onPressed: () async {
//                     final result = await Navigator.of(context).push(
//                       MaterialPageRoute(
//                         builder: (context) => const AddNewCropScreen(),
//                       ),
//                     );
                    
//                     if (result != null) {
//                       await _refreshGardenData();
//                       if (mounted) {
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text('Crop added successfully!'),
//                             backgroundColor: Colors.green,
//                           ),
//                         );
//                       }
//                     }
//                   },
//                   icon: const Icon(
//                     Icons.add,
//                     color: Colors.white,
//                     size: 24,
//                   ),
//                   padding: EdgeInsets.zero,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildWelcomeMessage(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             '${_getGreeting()}, ${_getUserName()}! ${_getGreetingEmoji()}',
//             style: TextStyle(
//               fontSize: 16,
//               color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             _gardens.isEmpty
//                 ? 'Start by adding your first garden.'
//                 : 'Your plants are ${_getMood()}',
//             style: const TextStyle(
//               fontSize: 24,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   String _getGreetingEmoji() {
//     final hour = DateTime.now().hour;
//     if (hour < 12) return '🌅';
//     if (hour < 17) return '☀️';
//     return '🌙';
//   }

//   String _getMood() {
//     if (_activeCropsCount > 10) return 'thriving! 🌱';
//     if (_activeCropsCount > 5) return 'growing well 🌿';
//     if (_activeCropsCount > 0) return 'starting to grow 🌱';
//     return 'ready for planting 🌻';
//   }

//   Widget _buildStatsSection(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Row(
//         children: [
//           Expanded(
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: const Color(0xFF39AC86).withOpacity(0.2),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'ACTIVE',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: const Color(0xFF39AC86),
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 1.5,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     '$_activeCropsCount',
//                     style: const TextStyle(
//                       fontSize: 28,
//                       fontWeight: FontWeight.w800,
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     'Healthy crops',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
          
//           Expanded(
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFE59866).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: const Color(0xFFE59866).withOpacity(0.2),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'HARVEST',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: const Color(0xFFE59866),
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 1.5,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     '$_harvestReadyCount',
//                     style: const TextStyle(
//                       fontSize: 28,
//                       fontWeight: FontWeight.w800,
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     'Ready now',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
          
//           Expanded(
//             child: Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF4299E1).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: const Color(0xFF4299E1).withOpacity(0.2),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'SHARED',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: const Color(0xFF4299E1),
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 1.5,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text.rich(
//                     TextSpan(
//                       children: [
//                         TextSpan(
//                           text: _sharedThisWeek.toStringAsFixed(1),
//                           style: const TextStyle(
//                             fontSize: 28,
//                             fontWeight: FontWeight.w800,
//                           ),
//                         ),
//                         const TextSpan(
//                           text: 'kg',
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     'This week',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCropListHeader(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text(
//             'Your Current Crops',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           TextButton(
//             onPressed: () {
//               Navigator.of(context).push(
//                 MaterialPageRoute(
//                   builder: (context) => AllCropsScreen(initialCrops: _crops),
//                 ),
//               );
//             },
//             child: const Text(
//               'View all',
//               style: TextStyle(
//                 color: Color(0xFF39AC86),
//                 fontSize: 14,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCropCards(bool isDarkMode) {
//     if (_crops.isEmpty) {
//       return Container(
//         height: 200,
//         margin: const EdgeInsets.symmetric(horizontal: 16),
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(20),
//           border: Border.all(
//             color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//           ),
//         ),
//         child: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(
//                 Icons.eco,
//                 size: 48,
//                 color: const Color(0xFF39AC86).withOpacity(0.3),
//               ),
//               const SizedBox(height: 12),
//               const Text(
//                 'No crops yet',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 4),
//               Text(
//                 'Tap the + button to add your first crop',
//                 style: TextStyle(
//                   fontSize: 14,
//                   color: const Color(0xFF5C8A7A),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return SizedBox(
//       height: 320,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         itemCount: _crops.length > 5 ? 5 : _crops.length,
//         itemBuilder: (context, index) {
//           final crop = _crops[index];
//           return Padding(
//             padding: EdgeInsets.only(right: index == _crops.length - 1 ? 0 : 16),
//             child: _buildCropCard(context, crop, isDarkMode),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildCropCard(BuildContext context, Map<String, dynamic> crop, bool isDarkMode) {
//     final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
//     final String status = crop['status']?.toString() ?? 'seedling';
//     final String name = crop['name']?.toString() ?? 'Unnamed Crop';
//     final String category = crop['category']?.toString() ?? 'vegetable';
//     final String? imageUrl = crop['image_url']?.toString();
    
//     // Debug print
//     print('🎨 Building card for: $name');
//     print('   - status: $status');
//     print('   - imageUrl exists: ${imageUrl != null}');
    
//     // Safely determine colors and labels
//     Color progressColor;
//     Color statusBgColor;
//     String statusLabel;
    
//     switch (status) {
//       case 'harvest':
//         progressColor = const Color(0xFFE59866);
//         statusBgColor = const Color(0xFFE59866);
//         statusLabel = 'READY';
//         break;
//       case 'fruiting':
//         progressColor = const Color(0xFF39AC86);
//         statusBgColor = const Color(0xFF39AC86);
//         statusLabel = 'FRUITING';
//         break;
//       case 'flowering':
//         progressColor = const Color(0xFFE59866);
//         statusBgColor = const Color(0xFFE59866);
//         statusLabel = 'FLOWERING';
//         break;
//       case 'vegetative':
//         progressColor = const Color(0xFF4299E1);
//         statusBgColor = const Color(0xFF4299E1);
//         statusLabel = 'GROWING';
//         break;
//       default:
//         progressColor = Colors.grey;
//         statusBgColor = Colors.grey;
//         statusLabel = status.toUpperCase();
//     }
    
//     return Container(
//       width: 240,
//       margin: const EdgeInsets.only(right: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(
//           color: isDarkMode 
//               ? const Color(0xFF3A4A44) 
//               : const Color(0xFFF0F2F1),
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 8,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Image Section
//           Stack(
//             children: [
//               Container(
//                 height: 128,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   borderRadius: const BorderRadius.only(
//                     topLeft: Radius.circular(20),
//                     topRight: Radius.circular(20),
//                   ),
//                   color: const Color(0xFF39AC86).withOpacity(0.1),
//                   image: (imageUrl != null && imageUrl.isNotEmpty)
//                       ? DecorationImage(
//                           image: NetworkImage(imageUrl),
//                           fit: BoxFit.cover,
//                           onError: (exception, stackTrace) {
//                             print('❌ Error loading image: $exception');
//                           },
//                         )
//                       : null,
//                 ),
//                 child: (imageUrl == null || imageUrl.isEmpty)
//                     ? Center(
//                         child: Icon(
//                           Icons.eco,
//                           size: 48,
//                           color: const Color(0xFF39AC86).withOpacity(0.3),
//                         ),
//                       )
//                     : null,
//               ),
//               // Status Badge
//               Positioned(
//                 top: 12,
//                 right: 12,
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                   decoration: BoxDecoration(
//                     color: statusBgColor.withOpacity(0.9),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Text(
//                     statusLabel,
//                     style: const TextStyle(
//                       fontSize: 10,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                       letterSpacing: 0.5,
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
          
//           // Content Section
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   name,
//                   style: const TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   _capitalize(category),
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                   ),
//                 ),
//                 const SizedBox(height: 16),
                
//                 // Progress Bar
//                 Container(
//                   height: 4,
//                   width: double.infinity,
//                   decoration: BoxDecoration(
//                     color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFF0F2F1),
//                     borderRadius: BorderRadius.circular(2),
//                   ),
//                   child: FractionallySizedBox(
//                     alignment: Alignment.centerLeft,
//                     widthFactor: progress / 100,
//                     child: Container(
//                       decoration: BoxDecoration(
//                         color: progressColor,
//                         borderRadius: BorderRadius.circular(2),
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildProductivityHeader(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text(
//             'Recent Productivity',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           if (_isRefreshing)
//             SizedBox(
//               width: 20,
//               height: 20,
//               child: CircularProgressIndicator(
//                 strokeWidth: 2,
//                 color: const Color(0xFF39AC86),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildChartsCard(bool isDarkMode) {
//     return Container(
//       margin: const EdgeInsets.all(16),
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(
//           color: isDarkMode 
//               ? const Color(0xFF3A4A44) 
//               : const Color(0xFFF0F2F1),
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 8,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           // Header
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'TOTAL YIELD (KG)',
//                     style: TextStyle(
//                       fontSize: 10,
//                       color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                       fontWeight: FontWeight.bold,
//                       letterSpacing: 1.5,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text.rich(
//                     TextSpan(
//                       children: [
//                         TextSpan(
//                           text: _totalYield.toStringAsFixed(1),
//                           style: const TextStyle(
//                             fontSize: 32,
//                             fontWeight: FontWeight.w800,
//                           ),
//                         ),
//                         const TextSpan(
//                           text: 'kg',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Color(0xFF999999),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Row(
//                     children: [
//                       const Icon(
//                         Icons.trending_up,
//                         color: Color(0xFF39AC86),
//                         size: 16,
//                       ),
//                       const SizedBox(width: 4),
//                       Text(
//                         '+${_calculateGrowth()}% vs last week',
//                         style: const TextStyle(
//                           color: Color(0xFF39AC86),
//                           fontSize: 12,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86).withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   _getDateRange(),
//                   style: const TextStyle(
//                     fontSize: 10,
//                     color: Color(0xFF39AC86),
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 32),
//           // Chart Bars
//           SizedBox(
//             height: 128,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               crossAxisAlignment: CrossAxisAlignment.end,
//               children: List.generate(7, (index) {
//                 return _buildChartBar(_weeklyHarvest[index], _weekDays[index]);
//               }),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildHarvestFAB(bool isDarkMode) {
//     return Container(
//       width: 56,
//       height: 56,
//       decoration: BoxDecoration(
//         color: const Color(0xFFE59866),
//         borderRadius: BorderRadius.circular(28),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFFE59866).withOpacity(0.3),
//             blurRadius: 16,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),
//       child: IconButton(
//         onPressed: () {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(
//               content: Text('Harvest log coming soon!'),
//             ),
//           );
//         },
//         icon: const Icon(
//           Icons.inventory_2,
//           color: Colors.white,
//           size: 24,
//         ),
//       ),
//     );
//   }

//   Widget _buildChartBar(double height, String day) {
//     return Column(
//       mainAxisAlignment: MainAxisAlignment.end,
//       children: [
//         Container(
//           width: 16,
//           height: height * 80,
//           decoration: BoxDecoration(
//             color: const Color(0xFF39AC86).withOpacity(0.2),
//             borderRadius: const BorderRadius.only(
//               topLeft: Radius.circular(4),
//               topRight: Radius.circular(4),
//             ),
//           ),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.end,
//             children: [
//               Container(
//                 width: 4,
//                 height: 4,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86),
//                   borderRadius: BorderRadius.circular(2),
//                   border: Border.all(color: Colors.white, width: 2),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 8),
//         Text(
//           day,
//           style: const TextStyle(
//             fontSize: 10,
//             color: Color(0xFF999999),
//             fontWeight: FontWeight.bold,
//           ),
//         ),
//       ],
//     );
//   }

//   String _getDateRange() {
//     final now = DateTime.now();
//     final start = now.subtract(const Duration(days: 6));
//     const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
//     return '${months[start.month - 1]} ${start.day} - ${months[now.month - 1]} ${now.day}';
//   }

//   int _calculateGrowth() {
//     return 12;
//   }

//   String _capitalize(String s) {
//     if (s.isEmpty) return s;
//     return s[0].toUpperCase() + s.substring(1).toLowerCase();
//   }
// }



