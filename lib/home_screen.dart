import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'product_details_screen.dart';
import 'messages_screen.dart';
import 'add_new_crop.dart';
import 'profile_screen.dart';
import 'main_layout.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onItemShared;
  final VoidCallback? onNavigateToShare;
  final VoidCallback? onNavigateToGarden;
  
  const HomeScreen({
    super.key, 
    this.onItemShared,
    this.onNavigateToShare,
    this.onNavigateToGarden,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final _searchController = TextEditingController();
  final List<String> categories = ['All', 'Vegetables', 'Fruits', 'Herbs', 'Flowers'];
  
  List<dynamic> _sharedItems = [];
  bool _isLoading = false;
  bool _isLoadingShared = false;
  int _selectedCategoryIndex = 0;
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSharedItems();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadSharedItems() async {
    setState(() {
      _isLoadingShared = true;
    });

    try {
      final result = await _apiService.getSharedItems();
      if (result['success'] == true) {
        setState(() {
          _sharedItems = result['items'] ?? [];
        });
      }
    } catch (e) {
      print('❌ Error loading shared items: $e');
    } finally {
      setState(() {
        _isLoadingShared = false;
      });
    }
  }

  List<dynamic> get _filteredItems {
    if (_selectedCategoryIndex == 0) return _sharedItems;
    
    final category = categories[_selectedCategoryIndex].toLowerCase();
    return _sharedItems.where((item) {
      final itemCategory = item['category']?.toString().toLowerCase() ?? '';
      return itemCategory == category.substring(0, category.length - 1);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF39AC86)),
                ),
              );
              
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login', 
                  (route) => false,
                );
              }
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: const Color(0xFF39AC86),
              ),
              const SizedBox(height: 20),
              Text(
                'Loading your garden...',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
      drawer: _buildDrawer(currentUser, isDarkMode),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(currentUser, isDarkMode),
            _buildSearchBar(isDarkMode),
            _buildCategoryChips(isDarkMode),
            _buildWelcomeMessage(currentUser, isDarkMode),
            _buildSectionHeader(isDarkMode),
            Expanded(
              child: _isLoadingShared
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF39AC86)))
                  : _filteredItems.isEmpty
                      ? _buildEmptyState(isDarkMode)
                      : RefreshIndicator(
                          onRefresh: _loadSharedItems,
                          color: const Color(0xFF39AC86),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = _filteredItems[index];
                              return GestureDetector(
                                onTap: () => _navigateToProductDetails(item),
                                child: _buildSharedItemCard(item, isDarkMode),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      // floatingActionButton removed
    );
  }

  Widget _buildDrawer(Map<String, dynamic>? currentUser, bool isDarkMode) {
    return Drawer(
      child: Container(
        color: isDarkMode ? const Color(0xFF1A2A25) : Colors.white,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
              decoration: BoxDecoration(
                color: const Color(0xFF39AC86).withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFE5E7E6),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF39AC86), width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: _buildDrawerProfileImage(currentUser),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?['name'] ?? 'Gardener',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : const Color(0xFF101816),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentUser?['email'] ?? 'email@example.com',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
                        ),
                        if (currentUser?['location'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 12, color: Color(0xFF5C8A7A)),
                              const SizedBox(width: 4),
                              Text(
                                currentUser!['location']!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
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
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(
                    icon: Icons.person_outline,
                    label: 'My Profile',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfileScreen()),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.eco_outlined,
                    label: 'My Garden',
                    onTap: () {
                      Navigator.pop(context);
                      widget.onNavigateToGarden?.call();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.message_outlined,
                    label: 'Messages',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MessagesScreen()),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notifications coming soon!')),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings coming soon!')),
                      );
                    },
                  ),
                  const Divider(thickness: 1, height: 32),
                  _buildDrawerItem(
                    icon: Icons.logout,
                    label: 'Logout',
                    iconColor: Colors.red,
                    textColor: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      _handleLogout(context);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Version 1.0.0',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(Map<String, dynamic>? currentUser, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF39AC86), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildProfileImage(currentUser),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode 
                            ? const Color(0xFF39AC86).withOpacity(0.7)
                            : const Color(0xFF5C8A7A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${currentUser?['name']?.split(' ')[0] ?? 'Gardener'}! 🌿',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : const Color(0xFF101816),
                      ),
                    ),
                  ],
                ),
              ),
              _buildIconButton(
                icon: Icons.message_outlined,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MessagesScreen()),
                ),
              ),
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.notifications_outlined,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications coming soon!')),
                ),
                showBadge: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool showBadge = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: const Color(0xFF39AC86), size: 20),
            padding: EdgeInsets.zero,
          ),
          if (showBadge)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search, color: Color(0xFF5C8A7A), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search for produce, tools, or gardeners...',
                  hintStyle: const TextStyle(color: Color(0xFF5C8A7A), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => _filterItems(value),
              ),
            ),
            IconButton(
              onPressed: () => _showFilterOptions(),
              icon: const Icon(Icons.tune, color: Color(0xFF39AC86), size: 20),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(bool isDarkMode) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          return Container(
            margin: EdgeInsets.only(right: index < categories.length - 1 ? 12 : 0),
            child: ChoiceChip(
              label: Text(
                categories[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: index == _selectedCategoryIndex ? FontWeight.w600 : FontWeight.w500,
                  color: index == _selectedCategoryIndex 
                      ? Colors.white 
                      : (isDarkMode ? Colors.white : const Color(0xFF101816)),
                ),
              ),
              selected: _selectedCategoryIndex == index,
              selectedColor: const Color(0xFF39AC86),
              backgroundColor: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
                side: BorderSide(
                  color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedCategoryIndex = index;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWelcomeMessage(Map<String, dynamic>? currentUser, bool isDarkMode) {
    if (currentUser == null) return const SizedBox();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF39AC86).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.eco, color: Color(0xFF39AC86), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${currentUser['name']?.split(' ')[0] ?? 'Gardener'}!',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF101816),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ready to share your harvest today?',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Nearby Surplus',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          TextButton.icon(
            onPressed: () => _showMapView(),
            icon: const Icon(Icons.map_outlined, color: Color(0xFF39AC86), size: 18),
            label: const Text(
              'See Map',
              style: TextStyle(color: Color(0xFF39AC86), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedItemCard(Map<String, dynamic> item, bool isDarkMode) {
    final user = item['users'] ?? {};
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode 
              ? const Color(0xFF3A4A44).withOpacity(0.5)
              : const Color(0xFFE5E7EB).withOpacity(0.5),
        ),
      ),
      child: Column(
        children: [
          if (item['image_url'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Image.network(
                item['image_url'],
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  height: 180,
                  color: Colors.grey[300],
                  child: const Center(child: Icon(Icons.broken_image, size: 50)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item['name'] ?? 'Unnamed Item',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${item['quantity']} ${item['quantity_unit']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF39AC86),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: user['profile_image_url'] != null
                          ? NetworkImage(user['profile_image_url'])
                          : null,
                      child: user['profile_image_url'] == null
                          ? const Icon(Icons.person, size: 12)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user['name'] ?? 'Anonymous',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          if (user['location'] != null)
                            Text(
                              user['location'],
                              style: const TextStyle(fontSize: 10, color: Color(0xFF5C8A7A)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (item['description'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    item['description'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
                if (item['pickup_instructions'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Color(0xFF5C8A7A)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item['pickup_instructions'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5C8A7A),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Color(0xFF5C8A7A)),
                        const SizedBox(width: 4),
                        Text(
                          item['location_text'] ?? 'Unknown location',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Request',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.eco,
              size: 80,
              color: const Color(0xFF39AC86).withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No shared items yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : const Color(0xFF101816),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share your harvest!',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: widget.onNavigateToShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39AC86),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text(
                'Share Your Harvest',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerProfileImage(Map<String, dynamic>? user) {
    final imageUrl = user?['profile_image_url'];
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _buildProfilePlaceholder(30),
      );
    }
    return _buildProfilePlaceholder(30);
  }

  Widget _buildProfileImage(Map<String, dynamic>? user) {
    final imageUrl = user?['profile_image_url'];
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _buildProfilePlaceholder(20),
      );
    }
    return _buildProfilePlaceholder(20);
  }

  Widget _buildProfilePlaceholder(double iconSize) {
    return Container(
      color: const Color(0xFF39AC86).withOpacity(0.1),
      child: Center(
        child: Icon(Icons.person, size: iconSize, color: Color(0xFF39AC86)),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF5C8A7A),
    Color textColor = const Color(0xFF101816),
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor == const Color(0xFF5C8A7A) 
            ? (isDarkMode ? Colors.white70 : iconColor)
            : iconColor,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: textColor == const Color(0xFF101816)
              ? (isDarkMode ? Colors.white : textColor)
              : textColor,
        ),
      ),
      onTap: onTap,
    );
  }

  void _filterItems(String query) {
    // Implement search filtering
  }

  void _showFilterOptions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filter options coming soon!')),
    );
  }

  void _showMapView() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Map view coming soon!')),
    );
  }

  void _navigateToProductDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(productData: item),
      ),
    );
  }
}








// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'product_details_screen.dart';
// import 'messages_screen.dart';
// import 'add_new_crop.dart';
// import 'profile_screen.dart';
// import 'main_layout.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class HomeScreen extends StatefulWidget {
//   final VoidCallback? onItemShared;
//   final VoidCallback? onNavigateToShare; // Add this callback
//   final VoidCallback? onNavigateToGarden; // Add this callback
  
//   const HomeScreen({
//     super.key, 
//     this.onItemShared,
//     this.onNavigateToShare, // Initialize
//     this.onNavigateToGarden, // Initialize
//   });

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final ApiService _apiService = ApiService();
//   final _searchController = TextEditingController();
//   final List<String> categories = ['All', 'Vegetables', 'Fruits', 'Herbs', 'Flowers'];
  
//   // Shared items
//   List<dynamic> _sharedItems = [];
//   bool _isLoading = false;
//   bool _isLoadingShared = false;
//   int _selectedCategoryIndex = 0;
  
//   // Drawer state
//   final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

//   @override
//   void initState() {
//     super.initState();
//     _loadUserData();
//     _loadSharedItems();
//   }

//   Future<void> _loadUserData() async {
//     setState(() {
//       _isLoading = true;
//     });

//     await Future.delayed(const Duration(milliseconds: 500));

//     setState(() {
//       _isLoading = false;
//     });
//   }

//   Future<void> _loadSharedItems() async {
//     setState(() {
//       _isLoadingShared = true;
//     });

//     try {
//       final result = await _apiService.getSharedItems();
//       if (result['success'] == true) {
//         setState(() {
//           _sharedItems = result['items'] ?? [];
//         });
//       }
//     } catch (e) {
//       print('❌ Error loading shared items: $e');
//     } finally {
//       setState(() {
//         _isLoadingShared = false;
//       });
//     }
//   }

//   List<dynamic> get _filteredItems {
//     if (_selectedCategoryIndex == 0) return _sharedItems;
    
//     final category = categories[_selectedCategoryIndex].toLowerCase();
//     return _sharedItems.where((item) {
//       final itemCategory = item['category']?.toString().toLowerCase() ?? '';
//       return itemCategory == category.substring(0, category.length - 1);
//     }).toList();
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     super.dispose();
//   }

// void _handleLogout(BuildContext context) {
//   showDialog(
//     context: context,
//     builder: (context) => AlertDialog(
//       title: const Text('Logout'),
//       content: const Text('Are you sure you want to logout?'),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.pop(context),
//           child: const Text('Cancel'),
//         ),
//         TextButton(
//           onPressed: () async {
//             Navigator.pop(context); // Close the dialog
            
//             // Show loading indicator
//             showDialog(
//               context: context,
//               barrierDismissible: false,
//               builder: (context) => const Center(
//                 child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//               ),
//             );
            
//             final authProvider = Provider.of<AuthProvider>(context, listen: false);
//             await authProvider.logout();
            
//             // Navigate to login screen and remove all previous routes
//             if (context.mounted) {
//               Navigator.of(context).pushNamedAndRemoveUntil(
//                 '/login', 
//                 (route) => false, // This removes all previous routes
//               );
//             }
//           },
//           child: const Text(
//             'Logout',
//             style: TextStyle(color: Colors.red),
//           ),
//         ),
//       ],
//     ),
//   );
// }

//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUser = authProvider.currentUser;
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     if (_isLoading) {
//       return Scaffold(
//         backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               CircularProgressIndicator(
//                 color: const Color(0xFF39AC86),
//               ),
//               const SizedBox(height: 20),
//               Text(
//                 'Loading your garden...',
//                 style: TextStyle(
//                   color: isDarkMode ? Colors.white : Colors.black,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return Scaffold(
//       key: _scaffoldKey,
//       backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//       drawer: _buildDrawer(currentUser, isDarkMode),
//       body: SafeArea(
//         bottom: false,
//         child: Column(
//           children: [
//             _buildTopBar(currentUser, isDarkMode),
//             _buildSearchBar(isDarkMode),
//             _buildCategoryChips(isDarkMode),
//             _buildWelcomeMessage(currentUser, isDarkMode),
//             _buildSectionHeader(isDarkMode),
//             Expanded(
//               child: _isLoadingShared
//                   ? const Center(child: CircularProgressIndicator(color: Color(0xFF39AC86)))
//                   : _filteredItems.isEmpty
//                       ? _buildEmptyState(isDarkMode)
//                       : RefreshIndicator(
//                           onRefresh: _loadSharedItems,
//                           color: const Color(0xFF39AC86),
//                           child: ListView.builder(
//                             padding: const EdgeInsets.all(16),
//                             itemCount: _filteredItems.length,
//                             itemBuilder: (context, index) {
//                               final item = _filteredItems[index];
//                               return GestureDetector(
//                                 onTap: () => _navigateToProductDetails(item),
//                                 child: _buildSharedItemCard(item, isDarkMode),
//                               );
//                             },
//                           ),
//                         ),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: widget.onNavigateToShare, // Use callback instead of direct access
//         backgroundColor: const Color(0xFF39AC86),
//         child: const Icon(Icons.add, color: Colors.white),
//       ),
//     );
//   }

//   Widget _buildDrawer(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     return Drawer(
//       child: Container(
//         color: isDarkMode ? const Color(0xFF1A2A25) : Colors.white,
//         child: Column(
//           children: [
//             Container(
//               padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                 border: Border(
//                   bottom: BorderSide(
//                     color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFE5E7E6),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Container(
//                     width: 60,
//                     height: 60,
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(30),
//                       border: Border.all(color: const Color(0xFF39AC86), width: 2),
//                     ),
//                     child: ClipRRect(
//                       borderRadius: BorderRadius.circular(30),
//                       child: _buildDrawerProfileImage(currentUser),
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           currentUser?['name'] ?? 'Gardener',
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                           ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           currentUser?['email'] ?? 'email@example.com',
//                           style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                         if (currentUser?['location'] != null) ...[
//                           const SizedBox(height: 4),
//                           Row(
//                             children: [
//                               const Icon(Icons.location_on, size: 12, color: Color(0xFF5C8A7A)),
//                               const SizedBox(width: 4),
//                               Text(
//                                 currentUser!['location']!,
//                                 style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             Expanded(
//               child: ListView(
//                 padding: EdgeInsets.zero,
//                 children: [
//                   _buildDrawerItem(
//                     icon: Icons.person_outline,
//                     label: 'My Profile',
//                     onTap: () {
//                       Navigator.pop(context);
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(builder: (context) => const ProfileScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.eco_outlined,
//                     label: 'My Garden',
//                     onTap: () {
//                       Navigator.pop(context);
//                       widget.onNavigateToGarden?.call(); // Use callback
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.message_outlined,
//                     label: 'Messages',
//                     onTap: () {
//                       Navigator.pop(context);
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(builder: (context) => const MessagesScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.notifications_outlined,
//                     label: 'Notifications',
//                     onTap: () {
//                       Navigator.pop(context);
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(content: Text('Notifications coming soon!')),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.settings_outlined,
//                     label: 'Settings',
//                     onTap: () {
//                       Navigator.pop(context);
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(content: Text('Settings coming soon!')),
//                       );
//                     },
//                   ),
//                   const Divider(thickness: 1, height: 32),
//                   _buildDrawerItem(
//                     icon: Icons.logout,
//                     label: 'Logout',
//                     iconColor: Colors.red,
//                     textColor: Colors.red,
//                     onTap: () {
//                       Navigator.pop(context);
//                       _handleLogout(context);
//                     },
//                   ),
//                 ],
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsets.all(16),
//               child: Text(
//                 'Version 1.0.0',
//                 style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildTopBar(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               GestureDetector(
//                 onTap: () => _scaffoldKey.currentState?.openDrawer(),
//                 child: Container(
//                   width: 40,
//                   height: 40,
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(20),
//                     border: Border.all(color: const Color(0xFF39AC86), width: 2),
//                   ),
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(20),
//                     child: _buildProfileImage(currentUser),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Welcome back,',
//                       style: TextStyle(
//                         fontSize: 12,
//                         color: isDarkMode 
//                             ? const Color(0xFF39AC86).withOpacity(0.7)
//                             : const Color(0xFF5C8A7A),
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       '${currentUser?['name']?.split(' ')[0] ?? 'Gardener'}! 🌿',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                         color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               _buildIconButton(
//                 icon: Icons.message_outlined,
//                 onPressed: () => Navigator.push(
//                   context,
//                   MaterialPageRoute(builder: (context) => const MessagesScreen()),
//                 ),
//               ),
//               const SizedBox(width: 8),
//               _buildIconButton(
//                 icon: Icons.notifications_outlined,
//                 onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
//                   const SnackBar(content: Text('Notifications coming soon!')),
//                 ),
//                 showBadge: true,
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildIconButton({
//     required IconData icon,
//     required VoidCallback onPressed,
//     bool showBadge = false,
//   }) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Container(
//       width: 40,
//       height: 40,
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 4,
//             offset: const Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Stack(
//         children: [
//           IconButton(
//             onPressed: onPressed,
//             icon: Icon(icon, color: const Color(0xFF39AC86), size: 20),
//             padding: EdgeInsets.zero,
//           ),
//           if (showBadge)
//             Positioned(
//               top: 8,
//               right: 8,
//               child: Container(
//                 width: 8,
//                 height: 8,
//                 decoration: BoxDecoration(
//                   color: Colors.red,
//                   borderRadius: BorderRadius.circular(4),
//                   border: Border.all(
//                     color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//                     width: 1.5,
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSearchBar(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Container(
//         height: 48,
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
//           ),
//         ),
//         child: Row(
//           children: [
//             const SizedBox(width: 16),
//             const Icon(Icons.search, color: Color(0xFF5C8A7A), size: 20),
//             const SizedBox(width: 8),
//             Expanded(
//               child: TextField(
//                 controller: _searchController,
//                 decoration: InputDecoration(
//                   hintText: 'Search for produce, tools, or gardeners...',
//                   hintStyle: const TextStyle(color: Color(0xFF5C8A7A), fontSize: 14),
//                   border: InputBorder.none,
//                   contentPadding: EdgeInsets.zero,
//                 ),
//                 onChanged: (value) => _filterItems(value),
//               ),
//             ),
//             IconButton(
//               onPressed: () => _showFilterOptions(),
//               icon: const Icon(Icons.tune, color: Color(0xFF39AC86), size: 20),
//             ),
//             const SizedBox(width: 16),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildCategoryChips(bool isDarkMode) {
//     return SizedBox(
//       height: 50,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         itemCount: categories.length,
//         itemBuilder: (context, index) {
//           return Container(
//             margin: EdgeInsets.only(right: index < categories.length - 1 ? 12 : 0),
//             child: ChoiceChip(
//               label: Text(
//                 categories[index],
//                 style: TextStyle(
//                   fontSize: 14,
//                   fontWeight: index == _selectedCategoryIndex ? FontWeight.w600 : FontWeight.w500,
//                   color: index == _selectedCategoryIndex 
//                       ? Colors.white 
//                       : (isDarkMode ? Colors.white : const Color(0xFF101816)),
//                 ),
//               ),
//               selected: _selectedCategoryIndex == index,
//               selectedColor: const Color(0xFF39AC86),
//               backgroundColor: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(25),
//                 side: BorderSide(
//                   color: isDarkMode ? const Color(0xFF3A4A44) : const Color(0xFFE5E7EB),
//                 ),
//               ),
//               onSelected: (selected) {
//                 setState(() {
//                   _selectedCategoryIndex = index;
//                 });
//               },
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildWelcomeMessage(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     if (currentUser == null) return const SizedBox();
    
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       child: Container(
//         padding: const EdgeInsets.all(12),
//         decoration: BoxDecoration(
//           color: const Color(0xFF39AC86).withOpacity(0.1),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(color: const Color(0xFF39AC86).withOpacity(0.2)),
//         ),
//         child: Row(
//           children: [
//             const Icon(Icons.eco, color: Color(0xFF39AC86), size: 20),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Hello, ${currentUser['name']?.split(' ')[0] ?? 'Gardener'}!',
//                     style: const TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                       color: Color(0xFF101816),
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   const Text(
//                     'Ready to share your harvest today?',
//                     style: TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSectionHeader(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text(
//             'Nearby Surplus',
//             style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//           ),
//           TextButton.icon(
//             onPressed: () => _showMapView(),
//             icon: const Icon(Icons.map_outlined, color: Color(0xFF39AC86), size: 18),
//             label: const Text(
//               'See Map',
//               style: TextStyle(color: Color(0xFF39AC86), fontSize: 14, fontWeight: FontWeight.w600),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSharedItemCard(Map<String, dynamic> item, bool isDarkMode) {
//     final user = item['users'] ?? {};
    
//     return Container(
//       margin: const EdgeInsets.only(bottom: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(
//           color: isDarkMode 
//               ? const Color(0xFF3A4A44).withOpacity(0.5)
//               : const Color(0xFFE5E7EB).withOpacity(0.5),
//         ),
//       ),
//       child: Column(
//         children: [
//           if (item['image_url'] != null)
//             ClipRRect(
//               borderRadius: const BorderRadius.only(
//                 topLeft: Radius.circular(16),
//                 topRight: Radius.circular(16),
//               ),
//               child: Image.network(
//                 item['image_url'],
//                 height: 180,
//                 width: double.infinity,
//                 fit: BoxFit.cover,
//                 errorBuilder: (context, error, stack) => Container(
//                   height: 180,
//                   color: Colors.grey[300],
//                   child: const Center(child: Icon(Icons.broken_image, size: 50)),
//                 ),
//               ),
//             ),
//           Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Expanded(
//                       child: Text(
//                         item['name'] ?? 'Unnamed Item',
//                         style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86).withOpacity(0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         '${item['quantity']} ${item['quantity_unit']}',
//                         style: const TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: Color(0xFF39AC86),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 8),
//                 Row(
//                   children: [
//                     CircleAvatar(
//                       radius: 12,
//                       backgroundImage: user['profile_image_url'] != null
//                           ? NetworkImage(user['profile_image_url'])
//                           : null,
//                       child: user['profile_image_url'] == null
//                           ? const Icon(Icons.person, size: 12)
//                           : null,
//                     ),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             user['name'] ?? 'Anonymous',
//                             style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
//                           ),
//                           if (user['location'] != null)
//                             Text(
//                               user['location'],
//                               style: const TextStyle(fontSize: 10, color: Color(0xFF5C8A7A)),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//                 if (item['description'] != null) ...[
//                   const SizedBox(height: 8),
//                   Text(
//                     item['description'],
//                     maxLines: 2,
//                     overflow: TextOverflow.ellipsis,
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: isDarkMode ? Colors.white70 : Colors.grey[600],
//                     ),
//                   ),
//                 ],
//                 if (item['pickup_instructions'] != null) ...[
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       Icon(Icons.info_outline, size: 16, color: Color(0xFF5C8A7A)),
//                       const SizedBox(width: 4),
//                       Expanded(
//                         child: Text(
//                           item['pickup_instructions'],
//                           style: const TextStyle(
//                             fontSize: 12,
//                             color: Color(0xFF5C8A7A),
//                             fontStyle: FontStyle.italic,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//                 const SizedBox(height: 12),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Row(
//                       children: [
//                         const Icon(Icons.location_on, size: 16, color: Color(0xFF5C8A7A)),
//                         const SizedBox(width: 4),
//                         Text(
//                           item['location_text'] ?? 'Unknown location',
//                           style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                       ],
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(20),
//                       ),
//                       child: const Text(
//                         'Request',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 12,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState(bool isDarkMode) {
//     return Center(
//       child: SingleChildScrollView(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(
//               Icons.eco,
//               size: 80,
//               color: const Color(0xFF39AC86).withOpacity(0.3),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'No shared items yet',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: isDarkMode ? Colors.white : const Color(0xFF101816),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Be the first to share your harvest!',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//               ),
//             ),
//             const SizedBox(height: 24),
//             ElevatedButton(
//               onPressed: widget.onNavigateToShare, // Use callback
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF39AC86),
//                 padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
//               ),
//               child: const Text(
//                 'Share Your Harvest',
//                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildDrawerProfileImage(Map<String, dynamic>? user) {
//     final imageUrl = user?['profile_image_url'];
//     if (imageUrl != null && imageUrl.isNotEmpty) {
//       return Image.network(
//         imageUrl,
//         fit: BoxFit.cover,
//         errorBuilder: (context, error, stack) => _buildProfilePlaceholder(30),
//       );
//     }
//     return _buildProfilePlaceholder(30);
//   }

//   Widget _buildProfileImage(Map<String, dynamic>? user) {
//     final imageUrl = user?['profile_image_url'];
//     if (imageUrl != null && imageUrl.isNotEmpty) {
//       return Image.network(
//         imageUrl,
//         fit: BoxFit.cover,
//         errorBuilder: (context, error, stack) => _buildProfilePlaceholder(20),
//       );
//     }
//     return _buildProfilePlaceholder(20);
//   }

//   Widget _buildProfilePlaceholder(double iconSize) {
//     return Container(
//       color: const Color(0xFF39AC86).withOpacity(0.1),
//       child: Center(
//         child: Icon(Icons.person, size: iconSize, color: Color(0xFF39AC86)),
//       ),
//     );
//   }

//   Widget _buildDrawerItem({
//     required IconData icon,
//     required String label,
//     required VoidCallback onTap,
//     Color iconColor = const Color(0xFF5C8A7A),
//     Color textColor = const Color(0xFF101816),
//   }) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return ListTile(
//       leading: Icon(
//         icon,
//         color: iconColor == const Color(0xFF5C8A7A) 
//             ? (isDarkMode ? Colors.white70 : iconColor)
//             : iconColor,
//       ),
//       title: Text(
//         label,
//         style: TextStyle(
//           color: textColor == const Color(0xFF101816)
//               ? (isDarkMode ? Colors.white : textColor)
//               : textColor,
//         ),
//       ),
//       onTap: onTap,
//     );
//   }

//   void _filterItems(String query) {
//     // Implement search filtering
//   }

//   void _showFilterOptions() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Filter options coming soon!')),
//     );
//   }

//   void _showMapView() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Map view coming soon!')),
//     );
//   }

//   void _navigateToProductDetails(Map<String, dynamic> item) {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => ProductDetailsScreen(productData: item),
//       ),
//     );
//   }
// }
