import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'edit_profile_screen.dart';
import 'add_garden_screen.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  
  // Cache variables
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isFirstLoad = true;
  DateTime? _lastLoadTime;
  
  // Data variables
  Map<String, dynamic>? _profileData;
  List<dynamic> _activeCrops = [];
  List<dynamic> _sharingHistory = [];
  Map<String, dynamic> _impactStats = {
    'sharedKg': 0,
    'helpedCount': 0,
    'savedCO2': 0,
  };
  List<dynamic> _gardens = [];

  // Cache buster for images
  int _imageVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isFirstLoad && 
        !_isLoading && 
        !_isRefreshing &&
        _lastLoadTime != null && 
        DateTime.now().difference(_lastLoadTime!) > const Duration(seconds: 30)) {
      _refreshProfileData(showLoading: false);
    }
  }

  Future<void> _loadProfileData({bool forceRefresh = false}) async {
    if (!forceRefresh && 
        !_isFirstLoad && 
        _profileData != null && 
        _gardens.isNotEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    await _fetchProfileData();

    setState(() {
      _isLoading = false;
      _isFirstLoad = false;
      _lastLoadTime = DateTime.now();
    });
  }

  Future<void> _refreshProfileData({bool showLoading = true}) async {
    if (_isRefreshing) return;

    print('🔄 REFRESHING PROFILE DATA');
    setState(() {
      _isRefreshing = showLoading;
      _imageVersion++;
    });

    await _fetchProfileData();

    setState(() {
      _isRefreshing = false;
      _lastLoadTime = DateTime.now();
    });
  }

  Future<void> _fetchProfileData() async {
    try {
      final profileResult = await _apiService.getUserProfile();
      if (profileResult['success'] == true) {
        final newProfileData = profileResult['profile'];
        setState(() {
          _profileData = newProfileData;
        });
        
        // CRITICAL: Update AuthProvider with fresh user data
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await authProvider.updateUserData(newProfileData);
      }

      final cropsResult = await _apiService.getUserCrops();
      if (cropsResult['success'] == true) {
        final allCrops = cropsResult['crops'] ?? [];
        setState(() {
          _activeCrops = allCrops.where((crop) => 
            crop['status'] != 'harvest' && (crop['progress'] ?? 0) < 100
          ).take(5).toList();
          
          _sharingHistory = allCrops.where((crop) => 
            crop['is_shared'] == true
          ).take(5).toList();
        });
      }

      final gardensResult = await _apiService.getUserGardens();
      if (gardensResult['success'] == true) {
        setState(() {
          _gardens = gardensResult['gardens'] ?? [];
        });
      }

      final impactResult = await _apiService.getImpactStats();
      if (impactResult['success'] == true) {
        setState(() {
          _impactStats = impactResult['impact'] ?? _impactStats;
        });
      }

    } catch (e) {
      print('❌ Error loading profile data: $e');
      
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        setState(() {
          _profileData = currentUser;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load profile data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    // USE FRESHLY FETCHED PROFILE DATA FIRST, THEN FALLBACK TO AUTH PROVIDER
    final currentUser = _profileData ?? authProvider.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (_isRefreshing && currentUser == null) {
      return Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF39AC86)),
        ),
      );
    }
    
    return WillPopScope(
      onWillPop: () async {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushReplacementNamed(context, '/');
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        body: SafeArea(
          child: _isLoading && _isFirstLoad
              ? _buildLoadingScreen(isDarkMode)
              : RefreshIndicator(
                  onRefresh: () => _refreshProfileData(showLoading: true),
                  color: const Color(0xFF39AC86),
                  backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildTopBar(isDarkMode),
                        _buildProfileHeader(currentUser, isDarkMode),
                        _buildImpactDashboard(context, isDarkMode),
                        const SizedBox(height: 24),
                        if (_gardens.isNotEmpty) _buildGardensSection(isDarkMode),
                        const SizedBox(height: 24),
                        _buildActiveCropsSection(isDarkMode),
                        const SizedBox(height: 32),
                        if (_sharingHistory.isNotEmpty) _buildSharingHistorySection(isDarkMode),
                        const SizedBox(height: 24),
                        _buildCommunityImpactCard(isDarkMode),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: const Color(0xFF39AC86),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading your garden profile...',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center, // Changed to center
        children: [
          // REMOVED THE BACK ARROW BUTTON
          Row(
            children: [
              const Text(
                'My Garden Profile',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isRefreshing) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFF39AC86),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(Map<String, dynamic>? currentUser, bool isDarkMode) {
    if (currentUser == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF39AC86)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(64),
                  border: Border.all(
                    color: const Color(0xFF39AC86).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(64),
                  child: _buildProfileImage(currentUser),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFD49D45),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
                    width: 4,
                  ),
                ),
                child: const Icon(
                  Icons.eco,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Text(
            currentUser['name'] ?? 'Gardener',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF39AC86).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF39AC86).withOpacity(0.2),
                  ),
                ),
                child: Text(
                  _gardens.isNotEmpty ? '${_gardens.length} Gardens' : 'Gardener',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF39AC86),
                  ),
                ),
              ),
              if (currentUser['location'] != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: Color(0xFF5C8A7A),
                ),
                const SizedBox(width: 4),
                Text(
                  currentUser['location']!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5C8A7A),
                  ),
                ),
              ],
            ],
          ),
          
          const SizedBox(height: 16),
          
          Text(
            currentUser['bio'] ?? 'Welcome to your garden profile! Start by adding your first garden.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5C8A7A),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditProfileScreen(
                          userData: currentUser,
                        ),
                      ),
                    );
                    
                    if (result != null) {
                      print('🔄 Returning from EditProfileScreen, refreshing...');
                      setState(() {
                        _lastLoadTime = null;
                        _imageVersion++;
                      });
                      await _refreshProfileData(showLoading: true);
                    }
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF39AC86),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF39AC86).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddGardenScreen(),
                    ),
                  );
                  
                  if (result != null) {
                    await _refreshProfileData(showLoading: true);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Garden created successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF39AC86).withOpacity(0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Color(0xFF39AC86),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImpactDashboard(BuildContext context, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildImpactCard(
              context,
              icon: Icons.eco,
              iconColor: const Color(0xFFD49D45),
              value: '${_impactStats['sharedKg']}',
              unit: 'kg',
              label: 'SHARED',
              change: _impactStats['sharedChange'] != null 
                  ? '+${_impactStats['sharedChange']}kg'
                  : '+0kg',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildImpactCard(
              context,
              icon: Icons.group,
              iconColor: const Color(0xFF39AC86),
              value: '${_impactStats['helpedCount']}',
              unit: '',
              label: 'HELPED',
              change: _impactStats['helpedChange'] != null 
                  ? '+${_impactStats['helpedChange']}'
                  : '+0',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildImpactCard(
              context,
              icon: Icons.co2,
              iconColor: const Color(0xFF3B82F6),
              value: '${_impactStats['savedCO2']}',
              unit: 'kg',
              label: 'CO2 SAVED',
              change: _impactStats['savedChange'] != null 
                  ? '+${_impactStats['savedChange']}kg'
                  : '+0kg',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardensSection(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Gardens',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gardens list coming soon!')),
                  );
                },
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF39AC86),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._gardens.take(2).map((garden) => _buildGardenCard(context, garden)),
        ],
      ),
    );
  }

  Widget _buildActiveCropsSection(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Growing Now',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Crops list coming soon!')),
                  );
                },
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF39AC86),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_activeCrops.isEmpty)
            _buildEmptyState(isDarkMode)
          else
            ..._activeCrops.map((crop) => _buildCropCard(context, crop)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.eco,
            color: const Color(0xFF39AC86).withOpacity(0.3),
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'No active crops yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first crop to start tracking!',
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF5C8A7A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharingHistorySection(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recently Shared',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'See All',
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF5C8A7A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._sharingHistory.take(2).map((crop) => _buildHistoryItem(context, crop)),
        ],
      ),
    );
  }

  Widget _buildCommunityImpactCard(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF39AC86).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF39AC86).withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF39AC86),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.eco,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community Impact',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _impactStats['sharedKg'] > 0
                        ? 'You\'ve shared ${_impactStats['sharedKg']}kg of food!'
                        : 'Start sharing your harvest to help others!',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF5C8A7A),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF39AC86),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage(Map<String, dynamic> user) {
    final imageUrl = user['profile_image_url'];
    
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final cacheBuster = '?v=$_imageVersion';
      final imageUrlWithCache = imageUrl + cacheBuster;
      
      print('🖼️ Loading profile image: $imageUrlWithCache');
      
      return Image.network(
        imageUrlWithCache,
        fit: BoxFit.cover,
        width: 128,
        height: 128,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Profile image load error: $error');
          return _buildDefaultProfileIcon();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: const Color(0xFF39AC86).withOpacity(0.1),
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
                color: const Color(0xFF39AC86),
              ),
            ),
          );
        },
      );
    } else {
      print('🖼️ No profile image URL for user: ${user['name']}');
      return _buildDefaultProfileIcon();
    }
  }

  Widget _buildDefaultProfileIcon() {
    return Container(
      width: 128,
      height: 128,
      color: const Color(0xFF39AC86).withOpacity(0.1),
      child: const Center(
        child: Icon(
          Icons.person,
          size: 64,
          color: Color(0xFF39AC86),
        ),
      ),
    );
  }

  Widget _buildImpactCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String value,
    required String unit,
    required String label,
    required String change,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                if (unit.isNotEmpty) TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5C8A7A),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF39AC86),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGardenCard(BuildContext context, Map<String, dynamic> garden) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final type = garden['type']?.toString().toUpperCase() ?? 'OUTDOOR';
    final size = garden['size']?.toString().capitalize() ?? 'Medium';
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF39AC86).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.eco,
              color: Color(0xFF39AC86),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  garden['name'] ?? 'My Garden',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$size ${type.toLowerCase()} garden',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5C8A7A),
                  ),
                ),
                if (garden['location'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    garden['location']!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5C8A7A),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropCard(BuildContext context, Map<String, dynamic> crop) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
    final progressPercent = progress.toInt();
    final status = crop['status']?.toString().capitalize() ?? 'Growing';
    final category = crop['category']?.toString().capitalize() ?? 'Vegetable';
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF39AC86).withOpacity(0.1),
              image: crop['image_url'] != null
                  ? DecorationImage(
                      image: NetworkImage(crop['image_url']!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: crop['image_url'] == null
                ? const Center(
                    child: Icon(
                      Icons.eco,
                      color: Color(0xFF39AC86),
                      size: 32,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      crop['name'] ?? 'Crop',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$progressPercent%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF39AC86),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$status • $category',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5C8A7A),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: progress / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, Map<String, dynamic> crop) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final date = crop['created_at'] != null
        ? DateTime.parse(crop['created_at']).toLocal()
        : DateTime.now();
    final formattedDate = '${date.month}/${date.day}/${date.year}';
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFF39AC86).withOpacity(0.1),
                  image: crop['image_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(crop['image_url']!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: crop['image_url'] == null
                    ? const Center(
                        child: Icon(
                          Icons.eco,
                          color: Color(0xFF39AC86),
                          size: 24,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop['name'] ?? 'Shared Item',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Shared on $formattedDate',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF5C8A7A),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Icon(
            Icons.check_circle,
            color: Color(0xFF39AC86),
            size: 24,
          ),
        ],
      ),
    );
  }
}

// Helper extension for string capitalization
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}








// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'edit_profile_screen.dart';
// import 'add_garden_screen.dart';
// import '../providers/auth_provider.dart';
// import '../services/api_service.dart';

// class ProfileScreen extends StatefulWidget {
//   const ProfileScreen({super.key});

//   @override
//   State<ProfileScreen> createState() => _ProfileScreenState();
// }

// class _ProfileScreenState extends State<ProfileScreen> {
//   final ApiService _apiService = ApiService();
  
//   // Cache variables
//   bool _isLoading = true;
//   bool _isRefreshing = false;
//   bool _isFirstLoad = true;
//   DateTime? _lastLoadTime;
  
//   // Data variables
//   Map<String, dynamic>? _profileData;
//   List<dynamic> _activeCrops = [];
//   List<dynamic> _sharingHistory = [];
//   Map<String, dynamic> _impactStats = {
//     'sharedKg': 0,
//     'helpedCount': 0,
//     'savedCO2': 0,
//   };
//   List<dynamic> _gardens = [];

//   // Cache buster for images
//   int _imageVersion = 0;

//   @override
//   void initState() {
//     super.initState();
//     _loadProfileData();
//   }

//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     if (!_isFirstLoad && 
//         !_isLoading && 
//         !_isRefreshing &&
//         _lastLoadTime != null && 
//         DateTime.now().difference(_lastLoadTime!) > const Duration(seconds: 30)) {
//       _refreshProfileData(showLoading: false);
//     }
//   }

//   Future<void> _loadProfileData({bool forceRefresh = false}) async {
//     if (!forceRefresh && 
//         !_isFirstLoad && 
//         _profileData != null && 
//         _gardens.isNotEmpty) {
//       setState(() {
//         _isLoading = false;
//       });
//       return;
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     await _fetchProfileData();

//     setState(() {
//       _isLoading = false;
//       _isFirstLoad = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _refreshProfileData({bool showLoading = true}) async {
//     if (_isRefreshing) return;

//     print('🔄 REFRESHING PROFILE DATA');
//     setState(() {
//       _isRefreshing = showLoading;
//       _imageVersion++;
//     });

//     await _fetchProfileData();

//     setState(() {
//       _isRefreshing = false;
//       _lastLoadTime = DateTime.now();
//     });
//   }

//   Future<void> _fetchProfileData() async {
//     try {
//       final profileResult = await _apiService.getUserProfile();
//       if (profileResult['success'] == true) {
//         final newProfileData = profileResult['profile'];
//         setState(() {
//           _profileData = newProfileData;
//         });
        
//         // CRITICAL: Update AuthProvider with fresh user data
//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         await authProvider.updateUserData(newProfileData);
//       }

//       final cropsResult = await _apiService.getUserCrops();
//       if (cropsResult['success'] == true) {
//         final allCrops = cropsResult['crops'] ?? [];
//         setState(() {
//           _activeCrops = allCrops.where((crop) => 
//             crop['status'] != 'harvest' && (crop['progress'] ?? 0) < 100
//           ).take(5).toList();
          
//           _sharingHistory = allCrops.where((crop) => 
//             crop['is_shared'] == true
//           ).take(5).toList();
//         });
//       }

//       final gardensResult = await _apiService.getUserGardens();
//       if (gardensResult['success'] == true) {
//         setState(() {
//           _gardens = gardensResult['gardens'] ?? [];
//         });
//       }

//       final impactResult = await _apiService.getImpactStats();
//       if (impactResult['success'] == true) {
//         setState(() {
//           _impactStats = impactResult['impact'] ?? _impactStats;
//         });
//       }

//     } catch (e) {
//       print('❌ Error loading profile data: $e');
      
//       final authProvider = context.read<AuthProvider>();
//       final currentUser = authProvider.currentUser;
//       if (currentUser != null) {
//         setState(() {
//           _profileData = currentUser;
//         });
//       }

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Failed to load profile data'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
    
//     // USE FRESHLY FETCHED PROFILE DATA FIRST, THEN FALLBACK TO AUTH PROVIDER
//     final currentUser = _profileData ?? authProvider.currentUser;
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     if (_isRefreshing && currentUser == null) {
//       return Scaffold(
//         backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: const Center(
//           child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//         ),
//       );
//     }
    
//     return WillPopScope(
//       onWillPop: () async {
//         if (Navigator.canPop(context)) {
//           Navigator.pop(context, true);
//         } else {
//           Navigator.pushReplacementNamed(context, '/');
//         }
//         return false;
//       },
//       child: Scaffold(
//         backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: SafeArea(
//           child: _isLoading && _isFirstLoad
//               ? _buildLoadingScreen(isDarkMode)
//               : RefreshIndicator(
//                   onRefresh: () => _refreshProfileData(showLoading: true),
//                   color: const Color(0xFF39AC86),
//                   backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//                   child: SingleChildScrollView(
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     child: Column(
//                       children: [
//                         _buildTopBar(isDarkMode),
//                         _buildProfileHeader(currentUser, isDarkMode),
//                         _buildImpactDashboard(context, isDarkMode),
//                         const SizedBox(height: 24),
//                         if (_gardens.isNotEmpty) _buildGardensSection(isDarkMode),
//                         const SizedBox(height: 24),
//                         _buildActiveCropsSection(isDarkMode),
//                         const SizedBox(height: 32),
//                         if (_sharingHistory.isNotEmpty) _buildSharingHistorySection(isDarkMode),
//                         const SizedBox(height: 24),
//                         _buildCommunityImpactCard(isDarkMode),
//                         const SizedBox(height: 100),
//                       ],
//                     ),
//                   ),
//                 ),
//         ),
//       ),
//     );
//   }

//   Widget _buildLoadingScreen(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const CircularProgressIndicator(
//             color: const Color(0xFF39AC86),
//           ),
//           const SizedBox(height: 20),
//           Text(
//             'Loading your garden profile...',
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
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           GestureDetector(
//             onTap: () {
//               if (Navigator.canPop(context)) {
//                 Navigator.pop(context, true);
//               } else {
//                 Navigator.pushReplacementNamed(context, '/');
//               }
//             },
//             child: Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(20),
//                 color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//               ),
//               child: const Icon(
//                 Icons.arrow_back_ios,
//                 size: 16,
//                 color: Color(0xFF39AC86),
//               ),
//             ),
//           ),
//           Row(
//             children: [
//               const Text(
//                 'My Garden Profile',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               if (_isRefreshing) ...[
//                 const SizedBox(width: 8),
//                 SizedBox(
//                   width: 16,
//                   height: 16,
//                   child: CircularProgressIndicator(
//                     strokeWidth: 2,
//                     color: const Color(0xFF39AC86),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//           Container(width: 40, height: 40),
//         ],
//       ),
//     );
//   }

//   Widget _buildProfileHeader(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     if (currentUser == null) {
//       return Container(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
//         child: const Center(
//           child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//         ),
//       );
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
//       child: Column(
//         children: [
//           Stack(
//             alignment: Alignment.bottomRight,
//             children: [
//               Container(
//                 width: 128,
//                 height: 128,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(64),
//                   border: Border.all(
//                     color: const Color(0xFF39AC86).withOpacity(0.3),
//                     width: 2,
//                   ),
//                 ),
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(64),
//                   child: _buildProfileImage(currentUser),
//                 ),
//               ),
//               Container(
//                 width: 36,
//                 height: 36,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFFD49D45),
//                   borderRadius: BorderRadius.circular(18),
//                   border: Border.all(
//                     color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//                     width: 4,
//                   ),
//                 ),
//                 child: const Icon(
//                   Icons.eco,
//                   color: Colors.white,
//                   size: 18,
//                 ),
//               ),
//             ],
//           ),
          
//           const SizedBox(height: 16),
          
//           Text(
//             currentUser['name'] ?? 'Gardener',
//             style: const TextStyle(
//               fontSize: 28,
//               fontWeight: FontWeight.w800,
//             ),
//           ),
          
//           const SizedBox(height: 8),
          
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF39AC86).withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(
//                     color: const Color(0xFF39AC86).withOpacity(0.2),
//                   ),
//                 ),
//                 child: Text(
//                   _gardens.isNotEmpty ? '${_gardens.length} Gardens' : 'Gardener',
//                   style: const TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: Color(0xFF39AC86),
//                   ),
//                 ),
//               ),
//               if (currentUser['location'] != null) ...[
//                 const SizedBox(width: 8),
//                 const Icon(
//                   Icons.location_on,
//                   size: 16,
//                   color: Color(0xFF5C8A7A),
//                 ),
//                 const SizedBox(width: 4),
//                 Text(
//                   currentUser['location']!,
//                   style: const TextStyle(
//                     fontSize: 14,
//                     color: Color(0xFF5C8A7A),
//                   ),
//                 ),
//               ],
//             ],
//           ),
          
//           const SizedBox(height: 16),
          
//           Text(
//             currentUser['bio'] ?? 'Welcome to your garden profile! Start by adding your first garden.',
//             textAlign: TextAlign.center,
//             style: const TextStyle(
//               fontSize: 14,
//               color: Color(0xFF5C8A7A),
//             ),
//           ),
          
//           const SizedBox(height: 16),
          
//           Row(
//             children: [
//               Expanded(
//                 child: GestureDetector(
//                   onTap: () async {
//                     final result = await Navigator.push(
//                       context,
//                       MaterialPageRoute(
//                         builder: (context) => EditProfileScreen(
//                           userData: currentUser,
//                         ),
//                       ),
//                     );
                    
//                     if (result != null) {
//                       print('🔄 Returning from EditProfileScreen, refreshing...');
//                       setState(() {
//                         _lastLoadTime = null;
//                         _imageVersion++;
//                       });
//                       await _refreshProfileData(showLoading: true);
//                     }
//                   },
//                   child: Container(
//                     height: 48,
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF39AC86),
//                       borderRadius: BorderRadius.circular(12),
//                       boxShadow: [
//                         BoxShadow(
//                           color: const Color(0xFF39AC86).withOpacity(0.3),
//                           blurRadius: 10,
//                           offset: const Offset(0, 4),
//                         ),
//                       ],
//                     ),
//                     child: const Center(
//                       child: Text(
//                         'Edit Profile',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
              
//               const SizedBox(width: 12),
              
//               GestureDetector(
//                 onTap: () async {
//                   final result = await Navigator.push(
//                     context,
//                     MaterialPageRoute(
//                       builder: (context) => const AddGardenScreen(),
//                     ),
//                   );
                  
//                   if (result != null) {
//                     await _refreshProfileData(showLoading: true);
//                     if (mounted) {
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(
//                           content: Text('Garden created successfully!'),
//                           backgroundColor: Colors.green,
//                         ),
//                       );
//                     }
//                   }
//                 },
//                 child: Container(
//                   width: 48,
//                   height: 48,
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(12),
//                     border: Border.all(
//                       color: const Color(0xFF39AC86).withOpacity(0.2),
//                     ),
//                   ),
//                   child: const Icon(
//                     Icons.add,
//                     color: Color(0xFF39AC86),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildImpactDashboard(BuildContext context, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Row(
//         children: [
//           Expanded(
//             child: _buildImpactCard(
//               context,
//               icon: Icons.eco,
//               iconColor: const Color(0xFFD49D45),
//               value: '${_impactStats['sharedKg']}',
//               unit: 'kg',
//               label: 'SHARED',
//               change: _impactStats['sharedChange'] != null 
//                   ? '+${_impactStats['sharedChange']}kg'
//                   : '+0kg',
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: _buildImpactCard(
//               context,
//               icon: Icons.group,
//               iconColor: const Color(0xFF39AC86),
//               value: '${_impactStats['helpedCount']}',
//               unit: '',
//               label: 'HELPED',
//               change: _impactStats['helpedChange'] != null 
//                   ? '+${_impactStats['helpedChange']}'
//                   : '+0',
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: _buildImpactCard(
//               context,
//               icon: Icons.co2,
//               iconColor: const Color(0xFF3B82F6),
//               value: '${_impactStats['savedCO2']}',
//               unit: 'kg',
//               label: 'CO2 SAVED',
//               change: _impactStats['savedChange'] != null 
//                   ? '+${_impactStats['savedChange']}kg'
//                   : '+0kg',
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildGardensSection(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Text(
//                 'My Gardens',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               GestureDetector(
//                 onTap: () {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     const SnackBar(content: Text('Gardens list coming soon!')),
//                   );
//                 },
//                 child: Text(
//                   'View All',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: const Color(0xFF39AC86),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           ..._gardens.take(2).map((garden) => _buildGardenCard(context, garden)),
//         ],
//       ),
//     );
//   }

//   Widget _buildActiveCropsSection(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Text(
//                 'Growing Now',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               GestureDetector(
//                 onTap: () {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     const SnackBar(content: Text('Crops list coming soon!')),
//                   );
//                 },
//                 child: Text(
//                   'View All',
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.bold,
//                     color: const Color(0xFF39AC86),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           if (_activeCrops.isEmpty)
//             _buildEmptyState(isDarkMode)
//           else
//             ..._activeCrops.map((crop) => _buildCropCard(context, crop)),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//         ),
//       ),
//       child: Column(
//         children: [
//           Icon(
//             Icons.eco,
//             color: const Color(0xFF39AC86).withOpacity(0.3),
//             size: 48,
//           ),
//           const SizedBox(height: 12),
//           const Text(
//             'No active crops yet',
//             style: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 8),
//           Text(
//             'Add your first crop to start tracking!',
//             style: TextStyle(
//               fontSize: 14,
//               color: const Color(0xFF5C8A7A),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSharingHistorySection(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Text(
//                 'Recently Shared',
//                 style: TextStyle(
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               Text(
//                 'See All',
//                 style: TextStyle(
//                   fontSize: 14,
//                   color: const Color(0xFF5C8A7A),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           ..._sharingHistory.take(2).map((crop) => _buildHistoryItem(context, crop)),
//         ],
//       ),
//     );
//   }

//   Widget _buildCommunityImpactCard(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           color: const Color(0xFF39AC86).withOpacity(0.05),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: const Color(0xFF39AC86).withOpacity(0.1),
//           ),
//         ),
//         child: Row(
//           children: [
//             Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86),
//                 borderRadius: BorderRadius.circular(20),
//               ),
//               child: const Icon(
//                 Icons.eco,
//                 color: Colors.white,
//               ),
//             ),
//             const SizedBox(width: 16),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text(
//                     'Community Impact',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     _impactStats['sharedKg'] > 0
//                         ? 'You\'ve shared ${_impactStats['sharedKg']}kg of food!'
//                         : 'Start sharing your harvest to help others!',
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: const Color(0xFF5C8A7A),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const Icon(
//               Icons.arrow_forward_ios,
//               color: Color(0xFF39AC86),
//               size: 16,
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildProfileImage(Map<String, dynamic> user) {
//     final imageUrl = user['profile_image_url'];
    
//     if (imageUrl != null && imageUrl.isNotEmpty) {
//       final cacheBuster = '?v=$_imageVersion';
//       final imageUrlWithCache = imageUrl + cacheBuster;
      
//       print('🖼️ Loading profile image: $imageUrlWithCache');
      
//       return Image.network(
//         imageUrlWithCache,
//         fit: BoxFit.cover,
//         width: 128,
//         height: 128,
//         errorBuilder: (context, error, stackTrace) {
//           print('❌ Profile image load error: $error');
//           return _buildDefaultProfileIcon();
//         },
//         loadingBuilder: (context, child, loadingProgress) {
//           if (loadingProgress == null) return child;
//           return Container(
//             color: const Color(0xFF39AC86).withOpacity(0.1),
//             child: Center(
//               child: CircularProgressIndicator(
//                 value: loadingProgress.expectedTotalBytes != null
//                     ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
//                     : null,
//                 color: const Color(0xFF39AC86),
//               ),
//             ),
//           );
//         },
//       );
//     } else {
//       print('🖼️ No profile image URL for user: ${user['name']}');
//       return _buildDefaultProfileIcon();
//     }
//   }

//   Widget _buildDefaultProfileIcon() {
//     return Container(
//       width: 128,
//       height: 128,
//       color: const Color(0xFF39AC86).withOpacity(0.1),
//       child: const Center(
//         child: Icon(
//           Icons.person,
//           size: 64,
//           color: Color(0xFF39AC86),
//         ),
//       ),
//     );
//   }

//   Widget _buildImpactCard(
//     BuildContext context, {
//     required IconData icon,
//     required Color iconColor,
//     required String value,
//     required String unit,
//     required String label,
//     required String change,
//   }) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//         ),
//       ),
//       child: Column(
//         children: [
//           Icon(
//             icon,
//             color: iconColor,
//             size: 24,
//           ),
//           const SizedBox(height: 8),
//           RichText(
//             text: TextSpan(
//               children: [
//                 TextSpan(
//                   text: value,
//                   style: TextStyle(
//                     fontSize: 24,
//                     fontWeight: FontWeight.w800,
//                     color: isDarkMode ? Colors.white : Colors.black,
//                   ),
//                 ),
//                 if (unit.isNotEmpty) TextSpan(
//                   text: ' $unit',
//                   style: TextStyle(
//                     fontSize: 12,
//                     fontWeight: FontWeight.w400,
//                     color: isDarkMode ? Colors.white : Colors.black,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             label,
//             style: const TextStyle(
//               fontSize: 10,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF5C8A7A),
//               letterSpacing: 1,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             change,
//             style: const TextStyle(
//               fontSize: 10,
//               fontWeight: FontWeight.bold,
//               color: Color(0xFF39AC86),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildGardenCard(BuildContext context, Map<String, dynamic> garden) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final type = garden['type']?.toString().toUpperCase() ?? 'OUTDOOR';
//     final size = garden['size']?.toString().capitalize() ?? 'Medium';
    
//     return Container(
//       padding: const EdgeInsets.all(16),
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//         ),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 48,
//             height: 48,
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
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   garden['name'] ?? 'My Garden',
//                   style: const TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   '$size ${type.toLowerCase()} garden',
//                   style: const TextStyle(
//                     fontSize: 14,
//                     color: Color(0xFF5C8A7A),
//                   ),
//                 ),
//                 if (garden['location'] != null) ...[
//                   const SizedBox(height: 4),
//                   Text(
//                     garden['location']!,
//                     style: const TextStyle(
//                       fontSize: 12,
//                       color: Color(0xFF5C8A7A),
//                     ),
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCropCard(BuildContext context, Map<String, dynamic> crop) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
//     final progressPercent = progress.toInt();
//     final status = crop['status']?.toString().capitalize() ?? 'Growing';
//     final category = crop['category']?.toString().capitalize() ?? 'Vegetable';
    
//     return Container(
//       padding: const EdgeInsets.all(12),
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//         ),
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 64,
//             height: 64,
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(8),
//               color: const Color(0xFF39AC86).withOpacity(0.1),
//               image: crop['image_url'] != null
//                   ? DecorationImage(
//                       image: NetworkImage(crop['image_url']!),
//                       fit: BoxFit.cover,
//                     )
//                   : null,
//             ),
//             child: crop['image_url'] == null
//                 ? const Center(
//                     child: Icon(
//                       Icons.eco,
//                       color: Color(0xFF39AC86),
//                       size: 32,
//                     ),
//                   )
//                 : null,
//           ),
//           const SizedBox(width: 16),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Text(
//                       crop['name'] ?? 'Crop',
//                       style: const TextStyle(
//                         fontSize: 16,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86).withOpacity(0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         '$progressPercent%',
//                         style: const TextStyle(
//                           fontSize: 12,
//                           fontWeight: FontWeight.bold,
//                           color: Color(0xFF39AC86),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   '$status • $category',
//                   style: const TextStyle(
//                     fontSize: 14,
//                     color: Color(0xFF5C8A7A),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Container(
//                   height: 6,
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                     borderRadius: BorderRadius.circular(3),
//                   ),
//                   child: FractionallySizedBox(
//                     widthFactor: progress / 100,
//                     child: Container(
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(3),
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

//   Widget _buildHistoryItem(BuildContext context, Map<String, dynamic> crop) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final date = crop['created_at'] != null
//         ? DateTime.parse(crop['created_at']).toLocal()
//         : DateTime.now();
//     final formattedDate = '${date.month}/${date.day}/${date.year}';
    
//     return Container(
//       padding: const EdgeInsets.symmetric(vertical: 16),
//       decoration: BoxDecoration(
//         border: Border(
//           bottom: BorderSide(
//             color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFE5E3DF),
//           ),
//         ),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Row(
//             children: [
//               Container(
//                 width: 48,
//                 height: 48,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(8),
//                   color: const Color(0xFF39AC86).withOpacity(0.1),
//                   image: crop['image_url'] != null
//                       ? DecorationImage(
//                           image: NetworkImage(crop['image_url']!),
//                           fit: BoxFit.cover,
//                         )
//                       : null,
//                 ),
//                 child: crop['image_url'] == null
//                     ? const Center(
//                         child: Icon(
//                           Icons.eco,
//                           color: Color(0xFF39AC86),
//                           size: 24,
//                         ),
//                       )
//                     : null,
//               ),
//               const SizedBox(width: 16),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     crop['name'] ?? 'Shared Item',
//                     style: const TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     'Shared on $formattedDate',
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: const Color(0xFF5C8A7A),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//           const Icon(
//             Icons.check_circle,
//             color: Color(0xFF39AC86),
//             size: 24,
//           ),
//         ],
//       ),
//     );
//   }
// }

// // Helper extension for string capitalization
// extension StringExtension on String {
//   String capitalize() {
//     return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
//   }
// }
