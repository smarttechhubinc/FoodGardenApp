import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'product_details_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final _searchController = TextEditingController();
  final List<String> categories = [
    'All',
    'Vegetables',
    'Fruits',
    'Herbs',
    'Flowers'
  ];

  List<dynamic> _sharedItems = [];
  bool _isLoading = false;
  bool _isLoadingShared = false;
  int _selectedCategoryIndex = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Notification panel ──
  bool _showNotificationPanel = false;
  late AnimationController _notifController;
  late Animation<Offset> _notifSlide;
  late Animation<double> _notifFade;
  
  // Real notifications data
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _notifController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _notifSlide = Tween<Offset>(
      begin: const Offset(0, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _notifController, curve: Curves.easeOut));
    _notifFade = CurvedAnimation(parent: _notifController, curve: Curves.easeOut);

    _loadUserData();
    _loadSharedItems();
    _loadNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notifController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
  }

  Future<void> _loadSharedItems() async {
    setState(() => _isLoadingShared = true);
    try {
      final result = await _apiService.getSharedItems();
      if (result['success'] == true) {
        setState(() => _sharedItems = result['items'] ?? []);
      }
    } catch (e) {
      print('❌ Error loading shared items: $e');
    } finally {
      setState(() => _isLoadingShared = false);
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.userId;
      
      if (currentUserId == null) return;
      
      // Get user's requests
      final requestsResult = await _apiService.getMyRequests();
      List<Map<String, dynamic>> notificationsList = [];
      
      if (requestsResult['success'] == true) {
        final requests = requestsResult['requests'] ?? [];
        
        for (var request in requests) {
          final status = request['status'];
          final product = request['product'] ?? {};
          final quantity = request['quantity'];
          
          if (status == 'pending') {
            notificationsList.add({
              'icon': Icons.hourglass_empty,
              'color': const Color(0xFFE59866),
              'title': 'Request Pending',
              'body': 'Your request for ${quantity} ${product['name'] ?? 'produce'} is waiting for approval.',
              'time': _formatTimeAgo(request['created_at']),
              'read': false,
              'type': 'request',
              'data': request,
            });
          } else if (status == 'accepted') {
            notificationsList.add({
              'icon': Icons.check_circle,
              'color': const Color(0xFF39AC86),
              'title': 'Request Accepted! 🎉',
              'body': 'Great news! Your request for ${quantity} ${product['name'] ?? 'produce'} has been accepted.',
              'time': _formatTimeAgo(request['updated_at']),
              'read': false,
              'type': 'request',
              'data': request,
            });
          } else if (status == 'declined') {
            notificationsList.add({
              'icon': Icons.cancel,
              'color': const Color(0xFFE74C3C),
              'title': 'Request Declined',
              'body': 'Your request for ${quantity} ${product['name'] ?? 'produce'} was declined.',
              'time': _formatTimeAgo(request['updated_at']),
              'read': false,
              'type': 'request',
              'data': request,
            });
          }
        }
      }
      
      // Get incoming requests (as owner)
      final incomingResult = await _apiService.getIncomingRequests();
      if (incomingResult['success'] == true) {
        final requests = incomingResult['requests'] ?? [];
        
        for (var request in requests) {
          final requester = request['requester'] ?? {};
          final product = request['product'] ?? {};
          final quantity = request['quantity'];
          
          notificationsList.add({
            'icon': Icons.eco,
            'color': const Color(0xFF39AC86),
            'title': 'New Request!',
            'body': '${requester['name'] ?? 'Someone'} requested ${quantity} ${product['name'] ?? 'produce'} from you.',
            'time': _formatTimeAgo(request['created_at']),
            'read': false,
            'type': 'incoming_request',
            'data': request,
          });
        }
      }
      
      // Sort by time (newest first)
      notificationsList.sort((a, b) => b['rawTime']?.compareTo(a['rawTime'] ?? '') ?? 0);
      
      setState(() {
        _notifications = notificationsList;
      });
      
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }
  
  String _formatTimeAgo(String? timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final time = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(time);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${(diff.inDays / 7).floor()}w ago';
    } catch (e) {
      return 'Recently';
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

  int get _unreadCount => _notifications.where((n) => n['read'] == false).length;

  void _toggleNotifications() {
    if (_showNotificationPanel) {
      _notifController.reverse().then((_) {
        if (mounted) setState(() => _showNotificationPanel = false);
      });
    } else {
      setState(() => _showNotificationPanel = true);
      _notifController.forward(from: 0);
    }
  }

  void _markAllRead() {
    setState(() {
      for (int i = 0; i < _notifications.length; i++) {
        _notifications[i]['read'] = true;
      }
    });
  }

  // ── Map popup with address from coordinates ──
  Future<void> _showMapView() async {
    // Build markers from shared items that have lat/lng
    final Set<Marker> markers = {};
    
    for (int i = 0; i < _sharedItems.length; i++) {
      final item = _sharedItems[i];
      final lat = item['latitude'];
      final lng = item['longitude'];
      if (lat == null || lng == null) continue;
      
      // Get address from coordinates
      String address = item['location_text'] ?? 'Pickup location';
      try {
        final placemarks = await placemarkFromCoordinates(
          (lat as num).toDouble(), 
          (lng as num).toDouble()
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[];
          if (place.street?.isNotEmpty == true) parts.add(place.street!);
          if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
          if (place.administrativeArea?.isNotEmpty == true) parts.add(place.administrativeArea!);
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (e) {
        print('Error getting address: $e');
      }
      
      markers.add(
        Marker(
          markerId: MarkerId('item_$i'),
          position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
          infoWindow: InfoWindow(
            title: item['name'] ?? 'Produce',
            snippet: '${item['quantity']} ${item['quantity_unit']} • $address',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    // Default centre: Lagos (fallback if no items have coords)
    LatLng centre = const LatLng(6.5244, 3.3792);
    if (markers.isNotEmpty) {
      final first = markers.first.position;
      centre = first;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MapPopup(
        markers: markers,
        centre: centre,
        itemCount: markers.length,
      ),
    );
    
    // Refresh notifications when coming back
    await _loadNotifications();
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
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              await authProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              }
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── BUILD ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor:
            isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF39AC86)),
              const SizedBox(height: 20),
              Text(
                'Loading your garden...',
                style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_showNotificationPanel) _toggleNotifications();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor:
            isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        drawer: _buildDrawer(currentUser, isDarkMode),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // ── Main scrollable content ──
              Column(
                children: [
                  _buildTopBar(isDarkMode),
                  _buildSearchBar(isDarkMode),
                  _buildCategoryChips(isDarkMode),
                  // REMOVED: _buildWelcomeMessage
                  _buildSectionHeader(isDarkMode),
                  Expanded(
                    child: _isLoadingShared
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF39AC86)))
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
                                      onTap: () =>
                                          _navigateToProductDetails(item),
                                      child: _buildSharedItemCard(
                                          item, isDarkMode),
                                    );
                                  },
                                ),
                              ),
                  ),
                ],
              ),

              // ── Notification drop-down panel ──
              if (_showNotificationPanel)
                Positioned(
                  top: 0,
                  right: 0,
                  left: 0,
                  child: FadeTransition(
                    opacity: _notifFade,
                    child: SlideTransition(
                      position: _notifSlide,
                      child: _buildNotificationPanel(isDarkMode),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── Notification Panel ───────────────

  Widget _buildNotificationPanel(bool isDarkMode) {
    return GestureDetector(
      onTap: () {}, // prevent tap-through to close
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 72, 12, 0),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF253330) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF3A4A44)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  if (_unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadCount new',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  const Spacer(),
                  if (_unreadCount > 0)
                    TextButton(
                      onPressed: _markAllRead,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text(
                        'Mark all read',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF39AC86)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleNotifications,
                    child: Icon(Icons.close,
                        size: 20,
                        color: isDarkMode
                            ? Colors.white54
                            : const Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),

            Divider(
              height: 1,
              color: isDarkMode
                  ? const Color(0xFF3A4A44)
                  : const Color(0xFFF3F4F6),
            ),

            // Notification list or empty state
            _notifications.isEmpty
                ? _buildNoNotifications(isDarkMode)
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDarkMode
                          ? const Color(0xFF3A4A44)
                          : const Color(0xFFF3F4F6),
                    ),
                    itemBuilder: (context, index) {
                      final n = _notifications[index];
                      return _buildNotificationTile(n, isDarkMode, index);
                    },
                  ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
      Map<String, dynamic> n, bool isDarkMode, int index) {
    final bool isUnread = n['read'] == false;
    return GestureDetector(
      onTap: () {
        setState(() => _notifications[index]['read'] = true);
        // Navigate based on notification type
        if (n['type'] == 'incoming_request') {
          // Navigate to chat or product details
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MessagesScreen(),
            ),
          );
        }
      },
      child: Container(
        color: isUnread
            ? const Color(0xFF39AC86).withOpacity(0.05)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (n['color'] as Color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(n['icon'] as IconData,
                  color: n['color'] as Color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n['title'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isDarkMode
                                ? Colors.white
                                : const Color(0xFF101816),
                          ),
                        ),
                      ),
                      Text(
                        n['time'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode
                              ? Colors.white38
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    n['body'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? Colors.white60
                          : const Color(0xFF5C8A7A),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (isUnread) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFF39AC86),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoNotifications(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.notifications_none,
            size: 48,
            color: const Color(0xFF39AC86).withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No new notifications',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white70 : const Color(0xFF101816),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "You're all caught up! 🌿",
            style: TextStyle(fontSize: 13, color: Color(0xFF5C8A7A)),
          ),
        ],
      ),
    );
  }

  // ─────────────── Top Bar (REMOVED welcome text) ───────────────

  Widget _buildTopBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
      ),
      child: Row(
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
                child: _buildProfileImage(null),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // REMOVED: Welcome back text and user name
          const Expanded(
            child: SizedBox(),
          ),
          _buildIconButton(
            icon: Icons.message_outlined,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const MessagesScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _buildNotificationButton(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildNotificationButton(bool isDarkMode) {
    return GestureDetector(
      onTap: _toggleNotifications,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _showNotificationPanel
              ? const Color(0xFF39AC86)
              : (isDarkMode ? const Color(0xFF2D3A35) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _showNotificationPanel
                  ? const Color(0xFF39AC86).withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                _showNotificationPanel
                    ? Icons.notifications
                    : Icons.notifications_outlined,
                color: _showNotificationPanel
                    ? Colors.white
                    : const Color(0xFF39AC86),
                size: 20,
              ),
            ),
            if (_unreadCount > 0)
              Positioned(
                top: 6,
                right: 6,
                child: _AnimatedBadge(count: _unreadCount),
              ),
          ],
        ),
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
                    color: isDarkMode
                        ? const Color(0xFF2D3A35)
                        : Colors.white,
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────── Search Bar ───────────────

  Widget _buildSearchBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? const Color(0xFF3A4A44)
                : const Color(0xFFE5E7EB),
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
                decoration: const InputDecoration(
                  hintText: 'Search for produce, tools, or gardeners...',
                  hintStyle:
                      TextStyle(color: Color(0xFF5C8A7A), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => _filterItems(value),
              ),
            ),
            IconButton(
              onPressed: () => _showFilterOptions(),
              icon: const Icon(Icons.tune,
                  color: Color(0xFF39AC86), size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Category Chips ───────────────

  Widget _buildCategoryChips(bool isDarkMode) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          return Container(
            margin: EdgeInsets.only(
                right: index < categories.length - 1 ? 12 : 0),
            child: ChoiceChip(
              label: Text(
                categories[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: index == _selectedCategoryIndex
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: index == _selectedCategoryIndex
                      ? Colors.white
                      : (isDarkMode
                          ? Colors.white
                          : const Color(0xFF101816)),
                ),
              ),
              selected: _selectedCategoryIndex == index,
              selectedColor: const Color(0xFF39AC86),
              backgroundColor:
                  isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
                side: BorderSide(
                  color: isDarkMode
                      ? const Color(0xFF3A4A44)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              onSelected: (selected) {
                setState(() => _selectedCategoryIndex = index);
              },
            ),
          );
        },
      ),
    );
  }

  // ─────────────── Section Header ───────────────

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
          GestureDetector(
            onTap: _showMapView,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF39AC86).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color:
                        const Color(0xFF39AC86).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.map_outlined,
                      color: Color(0xFF39AC86), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'See Map',
                    style: TextStyle(
                      color: Color(0xFF39AC86),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Item Card ───────────────

  Widget _buildSharedItemCard(
      Map<String, dynamic> item, bool isDarkMode) {
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
                  child: const Center(
                      child: Icon(Icons.broken_image, size: 50)),
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
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                      backgroundImage:
                          user['profile_image_url'] != null
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
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          if (user['location'] != null)
                            Text(
                              user['location'],
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF5C8A7A)),
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
                      color: isDarkMode
                          ? Colors.white70
                          : Colors.grey[600],
                    ),
                  ),
                ],
                if (item['pickup_instructions'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: Color(0xFF5C8A7A)),
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
                        const Icon(Icons.location_on,
                            size: 16, color: Color(0xFF5C8A7A)),
                        const SizedBox(width: 4),
                        Text(
                          item['location_text'] ?? 'Unknown location',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF5C8A7A)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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

  // ─────────────── Empty State ───────────────

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco,
                size: 80,
                color: const Color(0xFF39AC86).withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'No shared items yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF101816),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share your harvest!',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode
                    ? Colors.white70
                    : const Color(0xFF5C8A7A),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: widget.onNavigateToShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF39AC86),
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
              ),
              child: const Text(
                'Share Your Harvest',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Drawer ───────────────

  Widget _buildDrawer(
      Map<String, dynamic>? currentUser, bool isDarkMode) {
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
                    color: isDarkMode
                        ? const Color(0xFF2A3A35)
                        : const Color(0xFFE5E7E6),
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
                      border: Border.all(
                          color: const Color(0xFF39AC86), width: 2),
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
                            color: isDarkMode
                                ? Colors.white
                                : const Color(0xFF101816),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentUser?['email'] ?? 'email@example.com',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF5C8A7A)),
                        ),
                        if (currentUser?['location'] != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 12, color: Color(0xFF5C8A7A)),
                              const SizedBox(width: 4),
                              Text(
                                currentUser!['location']!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5C8A7A)),
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
                        MaterialPageRoute(
                            builder: (context) =>
                                const ProfileScreen()),
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
                        MaterialPageRoute(
                            builder: (context) =>
                                const MessagesScreen()),
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () {
                      Navigator.pop(context);
                      _toggleNotifications();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Settings coming soon!')),
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Version 1.0.0',
                style:
                    TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Profile Images ───────────────

  Widget _buildDrawerProfileImage(Map<String, dynamic>? user) {
    final imageUrl = user?['profile_image_url'];
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) =>
            _buildProfilePlaceholder(30),
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
        errorBuilder: (context, error, stack) =>
            _buildProfilePlaceholder(20),
      );
    }
    return _buildProfilePlaceholder(20);
  }

  Widget _buildProfilePlaceholder(double iconSize) {
    return Container(
      color: const Color(0xFF39AC86).withOpacity(0.1),
      child: Center(
        child: Icon(Icons.person,
            size: iconSize, color: const Color(0xFF39AC86)),
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

  void _filterItems(String query) {}

  void _showFilterOptions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Filter options coming soon!')),
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

// ─────────────────────────── Animated Badge ───────────────────────────

class _AnimatedBadge extends StatefulWidget {
  final int count;
  const _AnimatedBadge({required this.count});

  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Center(
          child: Text(
            widget.count > 9 ? '9+' : '${widget.count}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Map Popup (FIXED) ───────────────────────────

class _MapPopup extends StatefulWidget {
  final Set<Marker> markers;
  final LatLng centre;
  final int itemCount;

  const _MapPopup({
    required this.markers,
    required this.centre,
    required this.itemCount,
  });

  @override
  State<_MapPopup> createState() => _MapPopupState();
}

class _MapPopupState extends State<_MapPopup> {
  GoogleMapController? _mapController;
  bool _isMapLoaded = false;

  @override
  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF39AC86).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map_outlined,
                      color: Color(0xFF39AC86), size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nearby Pickup Spots',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      widget.itemCount == 0
                          ? 'No produce available right now'
                          : '${widget.itemCount} produce ${widget.itemCount == 1 ? 'spot' : 'spots'} near you',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5C8A7A)),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF2D3A35)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.close,
                        size: 18,
                        color: isDarkMode
                            ? Colors.white70
                            : const Color(0xFF666666)),
                  ),
                ),
              ],
            ),
          ),

          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _buildLegendItem(
                    BitmapDescriptor.hueGreen, 'Pickup available'),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: (controller) {
                        _mapController = controller;
                        setState(() => _isMapLoaded = true);
                      },
                      initialCameraPosition: CameraPosition(
                        target: widget.centre,
                        zoom: widget.markers.length > 1 ? 11 : 14,
                      ),
                      markers: widget.markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      onTap: (latLng) {
                        // Do nothing, just prevent errors
                      },
                    ),
                    // Zoom controls
                    if (_isMapLoaded)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Column(
                          children: [
                            _mapButton(
                              icon: Icons.add,
                              onTap: () => _mapController
                                  ?.animateCamera(CameraUpdate.zoomIn()),
                            ),
                            const SizedBox(height: 6),
                            _mapButton(
                              icon: Icons.remove,
                              onTap: () => _mapController
                                  ?.animateCamera(CameraUpdate.zoomOut()),
                            ),
                            const SizedBox(height: 6),
                            _mapButton(
                              icon: Icons.my_location,
                              onTap: () {
                                if (_mapController != null) {
                                  _mapController!.animateCamera(
                                    CameraUpdate.newLatLngZoom(
                                        widget.centre, 13),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    // Empty overlay
                    if (widget.markers.isEmpty)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.35),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(16),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.eco,
                                      size: 40,
                                      color: const Color(0xFF39AC86)
                                          .withOpacity(0.4)),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No produce on the map yet',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Share some to be first!',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF5C8A7A)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _mapButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, color: const Color(0xFF39AC86), size: 18),
      ),
    );
  }

  Widget _buildLegendItem(double hue, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Color(0xFF39AC86),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF5C8A7A))),
      ],
    );
  }
}






// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geocoding/geocoding.dart';
// import 'product_details_screen.dart';
// import 'messages_screen.dart';
// import 'profile_screen.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class HomeScreen extends StatefulWidget {
//   final VoidCallback? onItemShared;
//   final VoidCallback? onNavigateToShare;
//   final VoidCallback? onNavigateToGarden;

//   const HomeScreen({
//     super.key,
//     this.onItemShared,
//     this.onNavigateToShare,
//     this.onNavigateToGarden,
//   });

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen>
//     with SingleTickerProviderStateMixin {
//   final ApiService _apiService = ApiService();
//   final _searchController = TextEditingController();
//   final List<String> categories = [
//     'All',
//     'Vegetables',
//     'Fruits',
//     'Herbs',
//     'Flowers'
//   ];

//   List<dynamic> _sharedItems = [];
//   bool _isLoading = false;
//   bool _isLoadingShared = false;
//   int _selectedCategoryIndex = 0;

//   final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

//   // ── Notification panel ──
//   bool _showNotificationPanel = false;
//   late AnimationController _notifController;
//   late Animation<Offset> _notifSlide;
//   late Animation<double> _notifFade;
  
//   // Real notifications data
//   List<Map<String, dynamic>> _notifications = [];

//   @override
//   void initState() {
//     super.initState();
//     _notifController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 320),
//     );
//     _notifSlide = Tween<Offset>(
//       begin: const Offset(0, -0.08),
//       end: Offset.zero,
//     ).animate(CurvedAnimation(parent: _notifController, curve: Curves.easeOut));
//     _notifFade = CurvedAnimation(parent: _notifController, curve: Curves.easeOut);

//     _loadUserData();
//     _loadSharedItems();
//     _loadNotifications();
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     _notifController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadUserData() async {
//     setState(() => _isLoading = true);
//     await Future.delayed(const Duration(milliseconds: 500));
//     setState(() => _isLoading = false);
//   }

//   Future<void> _loadSharedItems() async {
//     setState(() => _isLoadingShared = true);
//     try {
//       final result = await _apiService.getSharedItems();
//       if (result['success'] == true) {
//         setState(() => _sharedItems = result['items'] ?? []);
//       }
//     } catch (e) {
//       print('❌ Error loading shared items: $e');
//     } finally {
//       setState(() => _isLoadingShared = false);
//     }
//   }

//   Future<void> _loadNotifications() async {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUserId = authProvider.userId;
      
//       if (currentUserId == null) return;
      
//       // Get user's requests
//       final requestsResult = await _apiService.getMyRequests();
//       List<Map<String, dynamic>> notificationsList = [];
      
//       if (requestsResult['success'] == true) {
//         final requests = requestsResult['requests'] ?? [];
        
//         for (var request in requests) {
//           final status = request['status'];
//           final product = request['product'] ?? {};
//           final quantity = request['quantity'];
          
//           if (status == 'pending') {
//             notificationsList.add({
//               'icon': Icons.hourglass_empty,
//               'color': const Color(0xFFE59866),
//               'title': 'Request Pending',
//               'body': 'Your request for ${quantity} ${product['name'] ?? 'produce'} is waiting for approval.',
//               'time': _formatTimeAgo(request['created_at']),
//               'read': false,
//               'type': 'request',
//               'data': request,
//             });
//           } else if (status == 'accepted') {
//             notificationsList.add({
//               'icon': Icons.check_circle,
//               'color': const Color(0xFF39AC86),
//               'title': 'Request Accepted! 🎉',
//               'body': 'Great news! Your request for ${quantity} ${product['name'] ?? 'produce'} has been accepted.',
//               'time': _formatTimeAgo(request['updated_at']),
//               'read': false,
//               'type': 'request',
//               'data': request,
//             });
//           } else if (status == 'declined') {
//             notificationsList.add({
//               'icon': Icons.cancel,
//               'color': const Color(0xFFE74C3C),
//               'title': 'Request Declined',
//               'body': 'Your request for ${quantity} ${product['name'] ?? 'produce'} was declined.',
//               'time': _formatTimeAgo(request['updated_at']),
//               'read': false,
//               'type': 'request',
//               'data': request,
//             });
//           }
//         }
//       }
      
//       // Get incoming requests (as owner)
//       final incomingResult = await _apiService.getIncomingRequests();
//       if (incomingResult['success'] == true) {
//         final requests = incomingResult['requests'] ?? [];
        
//         for (var request in requests) {
//           final requester = request['requester'] ?? {};
//           final product = request['product'] ?? {};
//           final quantity = request['quantity'];
          
//           notificationsList.add({
//             'icon': Icons.eco,
//             'color': const Color(0xFF39AC86),
//             'title': 'New Request!',
//             'body': '${requester['name'] ?? 'Someone'} requested ${quantity} ${product['name'] ?? 'produce'} from you.',
//             'time': _formatTimeAgo(request['created_at']),
//             'read': false,
//             'type': 'incoming_request',
//             'data': request,
//           });
//         }
//       }
      
//       // Sort by time (newest first)
//       notificationsList.sort((a, b) => b['rawTime']?.compareTo(a['rawTime'] ?? '') ?? 0);
      
//       setState(() {
//         _notifications = notificationsList;
//       });
      
//     } catch (e) {
//       print('Error loading notifications: $e');
//     }
//   }
  
//   String _formatTimeAgo(String? timestamp) {
//     if (timestamp == null) return 'Just now';
//     try {
//       final time = DateTime.parse(timestamp);
//       final now = DateTime.now();
//       final diff = now.difference(time);
      
//       if (diff.inMinutes < 1) return 'Just now';
//       if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
//       if (diff.inHours < 24) return '${diff.inHours}h ago';
//       if (diff.inDays < 7) return '${diff.inDays}d ago';
//       return '${(diff.inDays / 7).floor()}w ago';
//     } catch (e) {
//       return 'Recently';
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

//   int get _unreadCount => _notifications.where((n) => n['read'] == false).length;

//   void _toggleNotifications() {
//     if (_showNotificationPanel) {
//       _notifController.reverse().then((_) {
//         if (mounted) setState(() => _showNotificationPanel = false);
//       });
//     } else {
//       setState(() => _showNotificationPanel = true);
//       _notifController.forward(from: 0);
//     }
//   }

//   void _markAllRead() {
//     setState(() {
//       for (int i = 0; i < _notifications.length; i++) {
//         _notifications[i]['read'] = true;
//       }
//     });
//   }

//   // ── Map popup with address from coordinates ──
//   Future<void> _showMapView() async {
//     // Build markers from shared items that have lat/lng
//     final Set<Marker> markers = {};
    
//     for (int i = 0; i < _sharedItems.length; i++) {
//       final item = _sharedItems[i];
//       final lat = item['latitude'];
//       final lng = item['longitude'];
//       if (lat == null || lng == null) continue;
      
//       // Get address from coordinates
//       String address = item['location_text'] ?? 'Pickup location';
//       try {
//         final placemarks = await placemarkFromCoordinates(
//           (lat as num).toDouble(), 
//           (lng as num).toDouble()
//         );
//         if (placemarks.isNotEmpty) {
//           final place = placemarks.first;
//           final parts = <String>[];
//           if (place.street?.isNotEmpty == true) parts.add(place.street!);
//           if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
//           if (place.administrativeArea?.isNotEmpty == true) parts.add(place.administrativeArea!);
//           if (parts.isNotEmpty) address = parts.join(', ');
//         }
//       } catch (e) {
//         print('Error getting address: $e');
//       }
      
//       markers.add(
//         Marker(
//           markerId: MarkerId('item_$i'),
//           position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
//           infoWindow: InfoWindow(
//             title: item['name'] ?? 'Produce',
//             snippet: '${item['quantity']} ${item['quantity_unit']} • $address',
//           ),
//           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//         ),
//       );
//     }

//     // Default centre: Lagos (fallback if no items have coords)
//     LatLng centre = const LatLng(6.5244, 3.3792);
//     if (markers.isNotEmpty) {
//       final first = markers.first.position;
//       centre = first;
//     }

//     await showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (context) => _MapPopup(
//         markers: markers,
//         centre: centre,
//         itemCount: markers.length,
//       ),
//     );
    
//     // Refresh notifications when coming back
//     await _loadNotifications();
//   }

//   void _handleLogout(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Logout'),
//         content: const Text('Are you sure you want to logout?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(context);
//               showDialog(
//                 context: context,
//                 barrierDismissible: false,
//                 builder: (context) => const Center(
//                   child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//                 ),
//               );
//               final authProvider =
//                   Provider.of<AuthProvider>(context, listen: false);
//               await authProvider.logout();
//               if (context.mounted) {
//                 Navigator.of(context).pushNamedAndRemoveUntil(
//                   '/login',
//                   (route) => false,
//                 );
//               }
//             },
//             child: const Text('Logout', style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─────────────────────────── BUILD ───────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUser = authProvider.currentUser;
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     if (_isLoading) {
//       return Scaffold(
//         backgroundColor:
//             isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const CircularProgressIndicator(color: Color(0xFF39AC86)),
//               const SizedBox(height: 20),
//               Text(
//                 'Loading your garden...',
//                 style: TextStyle(
//                     color: isDarkMode ? Colors.white : Colors.black),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return GestureDetector(
//       onTap: () {
//         if (_showNotificationPanel) _toggleNotifications();
//       },
//       child: Scaffold(
//         key: _scaffoldKey,
//         backgroundColor:
//             isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         drawer: _buildDrawer(currentUser, isDarkMode),
//         body: SafeArea(
//           bottom: false,
//           child: Stack(
//             children: [
//               // ── Main scrollable content ──
//               Column(
//                 children: [
//                   _buildTopBar(currentUser, isDarkMode),
//                   _buildSearchBar(isDarkMode),
//                   _buildCategoryChips(isDarkMode),
//                   _buildWelcomeMessage(currentUser, isDarkMode),
//                   _buildSectionHeader(isDarkMode),
//                   Expanded(
//                     child: _isLoadingShared
//                         ? const Center(
//                             child: CircularProgressIndicator(
//                                 color: Color(0xFF39AC86)))
//                         : _filteredItems.isEmpty
//                             ? _buildEmptyState(isDarkMode)
//                             : RefreshIndicator(
//                                 onRefresh: _loadSharedItems,
//                                 color: const Color(0xFF39AC86),
//                                 child: ListView.builder(
//                                   padding: const EdgeInsets.all(16),
//                                   itemCount: _filteredItems.length,
//                                   itemBuilder: (context, index) {
//                                     final item = _filteredItems[index];
//                                     return GestureDetector(
//                                       onTap: () =>
//                                           _navigateToProductDetails(item),
//                                       child: _buildSharedItemCard(
//                                           item, isDarkMode),
//                                     );
//                                   },
//                                 ),
//                               ),
//                   ),
//                 ],
//               ),

//               // ── Notification drop-down panel ──
//               if (_showNotificationPanel)
//                 Positioned(
//                   top: 0,
//                   right: 0,
//                   left: 0,
//                   child: FadeTransition(
//                     opacity: _notifFade,
//                     child: SlideTransition(
//                       position: _notifSlide,
//                       child: _buildNotificationPanel(isDarkMode),
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ─────────────── Notification Panel ───────────────

//   Widget _buildNotificationPanel(bool isDarkMode) {
//     return GestureDetector(
//       onTap: () {}, // prevent tap-through to close
//       child: Container(
//         margin: const EdgeInsets.fromLTRB(12, 72, 12, 0),
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF253330) : Colors.white,
//           borderRadius: BorderRadius.circular(20),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.15),
//               blurRadius: 24,
//               offset: const Offset(0, 8),
//             ),
//           ],
//           border: Border.all(
//             color: isDarkMode
//                 ? const Color(0xFF3A4A44)
//                 : const Color(0xFFE5E7EB),
//           ),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Header
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
//               child: Row(
//                 children: [
//                   const Text(
//                     'Notifications',
//                     style: TextStyle(
//                         fontSize: 16, fontWeight: FontWeight.w800),
//                   ),
//                   const SizedBox(width: 8),
//                   if (_unreadCount > 0)
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: Text(
//                         '$_unreadCount new',
//                         style: const TextStyle(
//                             fontSize: 11,
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                   const Spacer(),
//                   if (_unreadCount > 0)
//                     TextButton(
//                       onPressed: _markAllRead,
//                       style: TextButton.styleFrom(
//                           padding: EdgeInsets.zero,
//                           minimumSize: Size.zero,
//                           tapTargetSize: MaterialTapTargetSize.shrinkWrap),
//                       child: const Text(
//                         'Mark all read',
//                         style: TextStyle(
//                             fontSize: 12, color: Color(0xFF39AC86)),
//                       ),
//                     ),
//                   const SizedBox(width: 8),
//                   GestureDetector(
//                     onTap: _toggleNotifications,
//                     child: Icon(Icons.close,
//                         size: 20,
//                         color: isDarkMode
//                             ? Colors.white54
//                             : const Color(0xFF9CA3AF)),
//                   ),
//                 ],
//               ),
//             ),

//             Divider(
//               height: 1,
//               color: isDarkMode
//                   ? const Color(0xFF3A4A44)
//                   : const Color(0xFFF3F4F6),
//             ),

//             // Notification list or empty state
//             _notifications.isEmpty
//                 ? _buildNoNotifications(isDarkMode)
//                 : ListView.separated(
//                     shrinkWrap: true,
//                     physics: const NeverScrollableScrollPhysics(),
//                     itemCount: _notifications.length,
//                     separatorBuilder: (_, __) => Divider(
//                       height: 1,
//                       color: isDarkMode
//                           ? const Color(0xFF3A4A44)
//                           : const Color(0xFFF3F4F6),
//                     ),
//                     itemBuilder: (context, index) {
//                       final n = _notifications[index];
//                       return _buildNotificationTile(n, isDarkMode, index);
//                     },
//                   ),

//             const SizedBox(height: 8),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildNotificationTile(
//       Map<String, dynamic> n, bool isDarkMode, int index) {
//     final bool isUnread = n['read'] == false;
//     return GestureDetector(
//       onTap: () {
//         setState(() => _notifications[index]['read'] = true);
//         // Navigate based on notification type
//         if (n['type'] == 'incoming_request') {
//           // Navigate to chat or product details
//           Navigator.pop(context);
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => MessagesScreen(),
//             ),
//           );
//         }
//       },
//       child: Container(
//         color: isUnread
//             ? const Color(0xFF39AC86).withOpacity(0.05)
//             : Colors.transparent,
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 color: (n['color'] as Color).withOpacity(0.12),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Icon(n['icon'] as IconData,
//                   color: n['color'] as Color, size: 20),
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Text(
//                           n['title'] as String,
//                           style: TextStyle(
//                             fontSize: 13,
//                             fontWeight: isUnread
//                                 ? FontWeight.w700
//                                 : FontWeight.w500,
//                             color: isDarkMode
//                                 ? Colors.white
//                                 : const Color(0xFF101816),
//                           ),
//                         ),
//                       ),
//                       Text(
//                         n['time'] as String,
//                         style: TextStyle(
//                           fontSize: 10,
//                           color: isDarkMode
//                               ? Colors.white38
//                               : const Color(0xFF9CA3AF),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 3),
//                   Text(
//                     n['body'] as String,
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: isDarkMode
//                           ? Colors.white60
//                           : const Color(0xFF5C8A7A),
//                       height: 1.4,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             if (isUnread) ...[
//               const SizedBox(width: 8),
//               Container(
//                 width: 8,
//                 height: 8,
//                 margin: const EdgeInsets.only(top: 4),
//                 decoration: const BoxDecoration(
//                   color: Color(0xFF39AC86),
//                   shape: BoxShape.circle,
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildNoNotifications(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 32),
//       child: Column(
//         children: [
//           Icon(
//             Icons.notifications_none,
//             size: 48,
//             color: const Color(0xFF39AC86).withOpacity(0.3),
//           ),
//           const SizedBox(height: 12),
//           Text(
//             'No new notifications',
//             style: TextStyle(
//               fontSize: 15,
//               fontWeight: FontWeight.w600,
//               color: isDarkMode ? Colors.white70 : const Color(0xFF101816),
//             ),
//           ),
//           const SizedBox(height: 4),
//           const Text(
//             "You're all caught up! 🌿",
//             style: TextStyle(fontSize: 13, color: Color(0xFF5C8A7A)),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─────────────── Top Bar ───────────────

//   Widget _buildTopBar(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
//       decoration: BoxDecoration(
//         color: isDarkMode
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Row(
//         children: [
//           GestureDetector(
//             onTap: () => _scaffoldKey.currentState?.openDrawer(),
//             child: Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(color: const Color(0xFF39AC86), width: 2),
//               ),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(20),
//                 child: _buildProfileImage(currentUser),
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Welcome back,',
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode
//                         ? const Color(0xFF39AC86).withOpacity(0.7)
//                         : const Color(0xFF5C8A7A),
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   '${currentUser?['name']?.split(' ')[0] ?? 'Gardener'}! 🌿',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           _buildIconButton(
//             icon: Icons.message_outlined,
//             onPressed: () => Navigator.push(
//               context,
//               MaterialPageRoute(
//                   builder: (context) => const MessagesScreen()),
//             ),
//           ),
//           const SizedBox(width: 8),
//           _buildNotificationButton(isDarkMode),
//         ],
//       ),
//     );
//   }

//   Widget _buildNotificationButton(bool isDarkMode) {
//     return GestureDetector(
//       onTap: _toggleNotifications,
//       child: Container(
//         width: 40,
//         height: 40,
//         decoration: BoxDecoration(
//           color: _showNotificationPanel
//               ? const Color(0xFF39AC86)
//               : (isDarkMode ? const Color(0xFF2D3A35) : Colors.white),
//           borderRadius: BorderRadius.circular(20),
//           boxShadow: [
//             BoxShadow(
//               color: _showNotificationPanel
//                   ? const Color(0xFF39AC86).withOpacity(0.3)
//                   : Colors.black.withOpacity(0.05),
//               blurRadius: 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Stack(
//           children: [
//             Center(
//               child: Icon(
//                 _showNotificationPanel
//                     ? Icons.notifications
//                     : Icons.notifications_outlined,
//                 color: _showNotificationPanel
//                     ? Colors.white
//                     : const Color(0xFF39AC86),
//                 size: 20,
//               ),
//             ),
//             if (_unreadCount > 0)
//               Positioned(
//                 top: 6,
//                 right: 6,
//                 child: _AnimatedBadge(count: _unreadCount),
//               ),
//           ],
//         ),
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
//                     color: isDarkMode
//                         ? const Color(0xFF2D3A35)
//                         : Colors.white,
//                     width: 1.5,
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   // ─────────────── Search Bar ───────────────

//   Widget _buildSearchBar(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Container(
//         height: 48,
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: isDarkMode
//                 ? const Color(0xFF3A4A44)
//                 : const Color(0xFFE5E7EB),
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
//                 decoration: const InputDecoration(
//                   hintText: 'Search for produce, tools, or gardeners...',
//                   hintStyle:
//                       TextStyle(color: Color(0xFF5C8A7A), fontSize: 14),
//                   border: InputBorder.none,
//                   contentPadding: EdgeInsets.zero,
//                 ),
//                 onChanged: (value) => _filterItems(value),
//               ),
//             ),
//             IconButton(
//               onPressed: () => _showFilterOptions(),
//               icon: const Icon(Icons.tune,
//                   color: Color(0xFF39AC86), size: 20),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Category Chips ───────────────

//   Widget _buildCategoryChips(bool isDarkMode) {
//     return SizedBox(
//       height: 50,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding:
//             const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         itemCount: categories.length,
//         itemBuilder: (context, index) {
//           return Container(
//             margin: EdgeInsets.only(
//                 right: index < categories.length - 1 ? 12 : 0),
//             child: ChoiceChip(
//               label: Text(
//                 categories[index],
//                 style: TextStyle(
//                   fontSize: 14,
//                   fontWeight: index == _selectedCategoryIndex
//                       ? FontWeight.w600
//                       : FontWeight.w500,
//                   color: index == _selectedCategoryIndex
//                       ? Colors.white
//                       : (isDarkMode
//                           ? Colors.white
//                           : const Color(0xFF101816)),
//                 ),
//               ),
//               selected: _selectedCategoryIndex == index,
//               selectedColor: const Color(0xFF39AC86),
//               backgroundColor:
//                   isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(25),
//                 side: BorderSide(
//                   color: isDarkMode
//                       ? const Color(0xFF3A4A44)
//                       : const Color(0xFFE5E7EB),
//                 ),
//               ),
//               onSelected: (selected) {
//                 setState(() => _selectedCategoryIndex = index);
//               },
//             ),
//           );
//         },
//       ),
//     );
//   }

//   // ─────────────── Welcome Message ───────────────

//   Widget _buildWelcomeMessage(
//       Map<String, dynamic>? currentUser, bool isDarkMode) {
//     if (currentUser == null) return const SizedBox();
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       child: Container(
//         padding: const EdgeInsets.all(12),
//         decoration: BoxDecoration(
//           color: const Color(0xFF39AC86).withOpacity(0.1),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//               color: const Color(0xFF39AC86).withOpacity(0.2)),
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
//                     style: TextStyle(
//                         fontSize: 12, color: Color(0xFF5C8A7A)),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Section Header ───────────────

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
//           GestureDetector(
//             onTap: _showMapView,
//             child: Container(
//               padding: const EdgeInsets.symmetric(
//                   horizontal: 14, vertical: 8),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(
//                     color:
//                         const Color(0xFF39AC86).withOpacity(0.3)),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.map_outlined,
//                       color: Color(0xFF39AC86), size: 16),
//                   SizedBox(width: 6),
//                   Text(
//                     'See Map',
//                     style: TextStyle(
//                       color: Color(0xFF39AC86),
//                       fontSize: 13,
//                       fontWeight: FontWeight.w700,
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

//   // ─────────────── Item Card ───────────────

//   Widget _buildSharedItemCard(
//       Map<String, dynamic> item, bool isDarkMode) {
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
//                   child: const Center(
//                       child: Icon(Icons.broken_image, size: 50)),
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
//                         style: const TextStyle(
//                             fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 8, vertical: 4),
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
//                       backgroundImage:
//                           user['profile_image_url'] != null
//                               ? NetworkImage(user['profile_image_url'])
//                               : null,
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
//                             style: const TextStyle(
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold),
//                           ),
//                           if (user['location'] != null)
//                             Text(
//                               user['location'],
//                               style: const TextStyle(
//                                   fontSize: 10,
//                                   color: Color(0xFF5C8A7A)),
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
//                       color: isDarkMode
//                           ? Colors.white70
//                           : Colors.grey[600],
//                     ),
//                   ),
//                 ],
//                 if (item['pickup_instructions'] != null) ...[
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       const Icon(Icons.info_outline,
//                           size: 16, color: Color(0xFF5C8A7A)),
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
//                         const Icon(Icons.location_on,
//                             size: 16, color: Color(0xFF5C8A7A)),
//                         const SizedBox(width: 4),
//                         Text(
//                           item['location_text'] ?? 'Unknown location',
//                           style: const TextStyle(
//                               fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                       ],
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 16, vertical: 8),
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

//   // ─────────────── Empty State ───────────────

//   Widget _buildEmptyState(bool isDarkMode) {
//     return Center(
//       child: SingleChildScrollView(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(Icons.eco,
//                 size: 80,
//                 color: const Color(0xFF39AC86).withOpacity(0.3)),
//             const SizedBox(height: 16),
//             Text(
//               'No shared items yet',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: isDarkMode
//                     ? Colors.white
//                     : const Color(0xFF101816),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Be the first to share your harvest!',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: isDarkMode
//                     ? Colors.white70
//                     : const Color(0xFF5C8A7A),
//               ),
//             ),
//             const SizedBox(height: 24),
//             ElevatedButton(
//               onPressed: widget.onNavigateToShare,
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF39AC86),
//                 padding: const EdgeInsets.symmetric(
//                     horizontal: 32, vertical: 12),
//               ),
//               child: const Text(
//                 'Share Your Harvest',
//                 style: TextStyle(
//                     fontSize: 16, fontWeight: FontWeight.bold),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Drawer ───────────────

//   Widget _buildDrawer(
//       Map<String, dynamic>? currentUser, bool isDarkMode) {
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
//                     color: isDarkMode
//                         ? const Color(0xFF2A3A35)
//                         : const Color(0xFFE5E7E6),
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
//                       border: Border.all(
//                           color: const Color(0xFF39AC86), width: 2),
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
//                             color: isDarkMode
//                                 ? Colors.white
//                                 : const Color(0xFF101816),
//                           ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           currentUser?['email'] ?? 'email@example.com',
//                           style: const TextStyle(
//                               fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                         if (currentUser?['location'] != null) ...[
//                           const SizedBox(height: 4),
//                           Row(
//                             children: [
//                               const Icon(Icons.location_on,
//                                   size: 12, color: Color(0xFF5C8A7A)),
//                               const SizedBox(width: 4),
//                               Text(
//                                 currentUser!['location']!,
//                                 style: const TextStyle(
//                                     fontSize: 12,
//                                     color: Color(0xFF5C8A7A)),
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
//                         MaterialPageRoute(
//                             builder: (context) =>
//                                 const ProfileScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.eco_outlined,
//                     label: 'My Garden',
//                     onTap: () {
//                       Navigator.pop(context);
//                       widget.onNavigateToGarden?.call();
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.message_outlined,
//                     label: 'Messages',
//                     onTap: () {
//                       Navigator.pop(context);
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                             builder: (context) =>
//                                 const MessagesScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.notifications_outlined,
//                     label: 'Notifications',
//                     onTap: () {
//                       Navigator.pop(context);
//                       _toggleNotifications();
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.settings_outlined,
//                     label: 'Settings',
//                     onTap: () {
//                       Navigator.pop(context);
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(
//                             content: Text('Settings coming soon!')),
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
//             const Padding(
//               padding: EdgeInsets.all(16),
//               child: Text(
//                 'Version 1.0.0',
//                 style:
//                     TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Profile Images ───────────────

//   Widget _buildDrawerProfileImage(Map<String, dynamic>? user) {
//     final imageUrl = user?['profile_image_url'];
//     if (imageUrl != null && imageUrl.isNotEmpty) {
//       return Image.network(
//         imageUrl,
//         fit: BoxFit.cover,
//         errorBuilder: (context, error, stack) =>
//             _buildProfilePlaceholder(30),
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
//         errorBuilder: (context, error, stack) =>
//             _buildProfilePlaceholder(20),
//       );
//     }
//     return _buildProfilePlaceholder(20);
//   }

//   Widget _buildProfilePlaceholder(double iconSize) {
//     return Container(
//       color: const Color(0xFF39AC86).withOpacity(0.1),
//       child: Center(
//         child: Icon(Icons.person,
//             size: iconSize, color: const Color(0xFF39AC86)),
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

//   void _filterItems(String query) {}

//   void _showFilterOptions() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Filter options coming soon!')),
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

// // ─────────────────────────── Animated Badge ───────────────────────────

// class _AnimatedBadge extends StatefulWidget {
//   final int count;
//   const _AnimatedBadge({required this.count});

//   @override
//   State<_AnimatedBadge> createState() => _AnimatedBadgeState();
// }

// class _AnimatedBadgeState extends State<_AnimatedBadge>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _ctrl;
//   late Animation<double> _scale;

//   @override
//   void initState() {
//     super.initState();
//     _ctrl = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 900),
//     )..repeat(reverse: true);
//     _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
//       CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
//     );
//   }

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return ScaleTransition(
//       scale: _scale,
//       child: Container(
//         width: 18,
//         height: 18,
//         decoration: BoxDecoration(
//           color: Colors.red,
//           shape: BoxShape.circle,
//           border: Border.all(color: Colors.white, width: 1.5),
//         ),
//         child: Center(
//           child: Text(
//             widget.count > 9 ? '9+' : '${widget.count}',
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 9,
//               fontWeight: FontWeight.w900,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ─────────────────────────── Map Popup (FIXED) ───────────────────────────

// class _MapPopup extends StatefulWidget {
//   final Set<Marker> markers;
//   final LatLng centre;
//   final int itemCount;

//   const _MapPopup({
//     required this.markers,
//     required this.centre,
//     required this.itemCount,
//   });

//   @override
//   State<_MapPopup> createState() => _MapPopupState();
// }

// class _MapPopupState extends State<_MapPopup> {
//   GoogleMapController? _mapController;
//   bool _isMapLoaded = false;

//   @override
//   void dispose() {
//     _mapController?.dispose();
//     _mapController = null;
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     return Container(
//       height: MediaQuery.of(context).size.height * 0.82,
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
//       ),
//       child: Column(
//         children: [
//           // Handle
//           Container(
//             margin: const EdgeInsets.only(top: 12),
//             width: 40,
//             height: 4,
//             decoration: BoxDecoration(
//               color: Colors.grey[300],
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),

//           // Header
//           Padding(
//             padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
//             child: Row(
//               children: [
//                 Container(
//                   width: 36,
//                   height: 36,
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.12),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(Icons.map_outlined,
//                       color: Color(0xFF39AC86), size: 20),
//                 ),
//                 const SizedBox(width: 12),
//                 Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Nearby Pickup Spots',
//                       style: TextStyle(
//                           fontSize: 16, fontWeight: FontWeight.w800),
//                     ),
//                     Text(
//                       widget.itemCount == 0
//                           ? 'No produce available right now'
//                           : '${widget.itemCount} produce ${widget.itemCount == 1 ? 'spot' : 'spots'} near you',
//                       style: const TextStyle(
//                           fontSize: 12, color: Color(0xFF5C8A7A)),
//                     ),
//                   ],
//                 ),
//                 const Spacer(),
//                 GestureDetector(
//                   onTap: () => Navigator.pop(context),
//                   child: Container(
//                     width: 32,
//                     height: 32,
//                     decoration: BoxDecoration(
//                       color: isDarkMode
//                           ? const Color(0xFF2D3A35)
//                           : Colors.white,
//                       borderRadius: BorderRadius.circular(16),
//                     ),
//                     child: Icon(Icons.close,
//                         size: 18,
//                         color: isDarkMode
//                             ? Colors.white70
//                             : const Color(0xFF666666)),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // Legend
//           Padding(
//             padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
//             child: Row(
//               children: [
//                 _buildLegendItem(
//                     BitmapDescriptor.hueGreen, 'Pickup available'),
//               ],
//             ),
//           ),

//           // Map
//           Expanded(
//             child: Padding(
//               padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(20),
//                 child: Stack(
//                   children: [
//                     GoogleMap(
//                       onMapCreated: (controller) {
//                         _mapController = controller;
//                         setState(() => _isMapLoaded = true);
//                       },
//                       initialCameraPosition: CameraPosition(
//                         target: widget.centre,
//                         zoom: widget.markers.length > 1 ? 11 : 14,
//                       ),
//                       markers: widget.markers,
//                       myLocationEnabled: true,
//                       myLocationButtonEnabled: false,
//                       zoomControlsEnabled: false,
//                       mapToolbarEnabled: false,
//                       onTap: (latLng) {
//                         // Do nothing, just prevent errors
//                       },
//                     ),
//                     // Zoom controls
//                     if (_isMapLoaded)
//                       Positioned(
//                         top: 12,
//                         right: 12,
//                         child: Column(
//                           children: [
//                             _mapButton(
//                               icon: Icons.add,
//                               onTap: () => _mapController
//                                   ?.animateCamera(CameraUpdate.zoomIn()),
//                             ),
//                             const SizedBox(height: 6),
//                             _mapButton(
//                               icon: Icons.remove,
//                               onTap: () => _mapController
//                                   ?.animateCamera(CameraUpdate.zoomOut()),
//                             ),
//                             const SizedBox(height: 6),
//                             _mapButton(
//                               icon: Icons.my_location,
//                               onTap: () {
//                                 if (_mapController != null) {
//                                   _mapController!.animateCamera(
//                                     CameraUpdate.newLatLngZoom(
//                                         widget.centre, 13),
//                                   );
//                                 }
//                               },
//                             ),
//                           ],
//                         ),
//                       ),
//                     // Empty overlay
//                     if (widget.markers.isEmpty)
//                       Positioned.fill(
//                         child: Container(
//                           color: Colors.black.withOpacity(0.35),
//                           child: Center(
//                             child: Container(
//                               padding: const EdgeInsets.symmetric(
//                                   horizontal: 24, vertical: 16),
//                               decoration: BoxDecoration(
//                                 color: Colors.white,
//                                 borderRadius:
//                                     BorderRadius.circular(16),
//                               ),
//                               child: Column(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   Icon(Icons.eco,
//                                       size: 40,
//                                       color: const Color(0xFF39AC86)
//                                           .withOpacity(0.4)),
//                                   const SizedBox(height: 8),
//                                   const Text(
//                                     'No produce on the map yet',
//                                     style: TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                         fontSize: 14),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   const Text(
//                                     'Share some to be first!',
//                                     style: TextStyle(
//                                         fontSize: 12,
//                                         color: Color(0xFF5C8A7A)),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(height: 20),
//         ],
//       ),
//     );
//   }

//   Widget _mapButton(
//       {required IconData icon, required VoidCallback onTap}) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: 36,
//         height: 36,
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(10),
//           boxShadow: [
//             BoxShadow(
//                 color: Colors.black.withOpacity(0.12),
//                 blurRadius: 6,
//                 offset: const Offset(0, 2))
//           ],
//         ),
//         child: Icon(icon, color: const Color(0xFF39AC86), size: 18),
//       ),
//     );
//   }

//   Widget _buildLegendItem(double hue, String label) {
//     return Row(
//       children: [
//         Container(
//           width: 12,
//           height: 12,
//           decoration: const BoxDecoration(
//             color: Color(0xFF39AC86),
//             shape: BoxShape.circle,
//           ),
//         ),
//         const SizedBox(width: 6),
//         Text(label,
//             style: const TextStyle(
//                 fontSize: 11, color: Color(0xFF5C8A7A))),
//       ],
//     );
//   }
// }










// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'product_details_screen.dart';
// import 'messages_screen.dart';
// import 'profile_screen.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class HomeScreen extends StatefulWidget {
//   final VoidCallback? onItemShared;
//   final VoidCallback? onNavigateToShare;
//   final VoidCallback? onNavigateToGarden;

//   const HomeScreen({
//     super.key,
//     this.onItemShared,
//     this.onNavigateToShare,
//     this.onNavigateToGarden,
//   });

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen>
//     with SingleTickerProviderStateMixin {
//   final ApiService _apiService = ApiService();
//   final _searchController = TextEditingController();
//   final List<String> categories = [
//     'All',
//     'Vegetables',
//     'Fruits',
//     'Herbs',
//     'Flowers'
//   ];

//   List<dynamic> _sharedItems = [];
//   bool _isLoading = false;
//   bool _isLoadingShared = false;
//   int _selectedCategoryIndex = 0;

//   final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

//   // ── Notification panel ──
//   bool _showNotificationPanel = false;
//   late AnimationController _notifController;
//   late Animation<Offset> _notifSlide;
//   late Animation<double> _notifFade;

//   // Mock notifications — replace with real data from your API
//   final List<Map<String, dynamic>> _notifications = [
//     {
//       'icon': Icons.eco,
//       'color': Color(0xFF39AC86),
//       'title': 'New produce nearby',
//       'body': 'Fresh tomatoes just shared 0.3 km away.',
//       'time': '2m ago',
//       'read': false,
//     },
//     {
//       'icon': Icons.check_circle,
//       'color': Color(0xFF4299E1),
//       'title': 'Request accepted',
//       'body': 'Your request for carrots has been accepted!',
//       'time': '1h ago',
//       'read': false,
//     },
//     {
//       'icon': Icons.message,
//       'color': Color(0xFFE59866),
//       'title': 'New message',
//       'body': 'Amaka sent you a message about the herbs.',
//       'time': '3h ago',
//       'read': true,
//     },
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _notifController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 320),
//     );
//     _notifSlide = Tween<Offset>(
//       begin: const Offset(0, -0.08),
//       end: Offset.zero,
//     ).animate(CurvedAnimation(parent: _notifController, curve: Curves.easeOut));
//     _notifFade = CurvedAnimation(parent: _notifController, curve: Curves.easeOut);

//     _loadUserData();
//     _loadSharedItems();
//   }

//   @override
//   void dispose() {
//     _searchController.dispose();
//     _notifController.dispose();
//     super.dispose();
//   }

//   Future<void> _loadUserData() async {
//     setState(() => _isLoading = true);
//     await Future.delayed(const Duration(milliseconds: 500));
//     setState(() => _isLoading = false);
//   }

//   Future<void> _loadSharedItems() async {
//     setState(() => _isLoadingShared = true);
//     try {
//       final result = await _apiService.getSharedItems();
//       if (result['success'] == true) {
//         setState(() => _sharedItems = result['items'] ?? []);
//       }
//     } catch (e) {
//       print('❌ Error loading shared items: $e');
//     } finally {
//       setState(() => _isLoadingShared = false);
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

//   int get _unreadCount => _notifications.where((n) => n['read'] == false).length;

//   // ── Notification panel toggle ──
//   void _toggleNotifications() {
//     if (_showNotificationPanel) {
//       _notifController.reverse().then((_) {
//         if (mounted) setState(() => _showNotificationPanel = false);
//       });
//     } else {
//       setState(() => _showNotificationPanel = true);
//       _notifController.forward(from: 0);
//     }
//   }

//   void _markAllRead() {
//     setState(() {
//       for (final n in _notifications) {
//         n['read'] = true;
//       }
//     });
//   }

//   // ── Map popup ──
//   void _showMapView() {
//     // Build markers from shared items that have lat/lng
//     final Set<Marker> markers = {};
//     for (int i = 0; i < _sharedItems.length; i++) {
//       final item = _sharedItems[i];
//       final lat = item['latitude'];
//       final lng = item['longitude'];
//       if (lat == null || lng == null) continue;
//       markers.add(
//         Marker(
//           markerId: MarkerId('item_$i'),
//           position: LatLng((lat as num).toDouble(), (lng as num).toDouble()),
//           infoWindow: InfoWindow(
//             title: item['name'] ?? 'Produce',
//             snippet:
//                 '${item['quantity']} ${item['quantity_unit']} • ${item['location_text'] ?? ''}',
//           ),
//           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//         ),
//       );
//     }

//     // Default centre: Lagos (fallback if no items have coords)
//     LatLng centre = const LatLng(6.5244, 3.3792);
//     if (markers.isNotEmpty) {
//       final first = markers.first.position;
//       centre = first;
//     }

//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (context) => _MapPopup(
//         markers: markers,
//         centre: centre,
//         itemCount: markers.length,
//       ),
//     );
//   }

//   void _handleLogout(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Logout'),
//         content: const Text('Are you sure you want to logout?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(context);
//               showDialog(
//                 context: context,
//                 barrierDismissible: false,
//                 builder: (context) => const Center(
//                   child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//                 ),
//               );
//               final authProvider =
//                   Provider.of<AuthProvider>(context, listen: false);
//               await authProvider.logout();
//               if (context.mounted) {
//                 Navigator.of(context).pushNamedAndRemoveUntil(
//                   '/login',
//                   (route) => false,
//                 );
//               }
//             },
//             child: const Text('Logout', style: TextStyle(color: Colors.red)),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─────────────────────────── BUILD ───────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUser = authProvider.currentUser;
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     if (_isLoading) {
//       return Scaffold(
//         backgroundColor:
//             isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         body: Center(
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const CircularProgressIndicator(color: Color(0xFF39AC86)),
//               const SizedBox(height: 20),
//               Text(
//                 'Loading your garden...',
//                 style: TextStyle(
//                     color: isDarkMode ? Colors.white : Colors.black),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return GestureDetector(
//       onTap: () {
//         if (_showNotificationPanel) _toggleNotifications();
//       },
//       child: Scaffold(
//         key: _scaffoldKey,
//         backgroundColor:
//             isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         drawer: _buildDrawer(currentUser, isDarkMode),
//         body: SafeArea(
//           bottom: false,
//           child: Stack(
//             children: [
//               // ── Main scrollable content ──
//               Column(
//                 children: [
//                   _buildTopBar(currentUser, isDarkMode),
//                   _buildSearchBar(isDarkMode),
//                   _buildCategoryChips(isDarkMode),
//                   _buildWelcomeMessage(currentUser, isDarkMode),
//                   _buildSectionHeader(isDarkMode),
//                   Expanded(
//                     child: _isLoadingShared
//                         ? const Center(
//                             child: CircularProgressIndicator(
//                                 color: Color(0xFF39AC86)))
//                         : _filteredItems.isEmpty
//                             ? _buildEmptyState(isDarkMode)
//                             : RefreshIndicator(
//                                 onRefresh: _loadSharedItems,
//                                 color: const Color(0xFF39AC86),
//                                 child: ListView.builder(
//                                   padding: const EdgeInsets.all(16),
//                                   itemCount: _filteredItems.length,
//                                   itemBuilder: (context, index) {
//                                     final item = _filteredItems[index];
//                                     return GestureDetector(
//                                       onTap: () =>
//                                           _navigateToProductDetails(item),
//                                       child: _buildSharedItemCard(
//                                           item, isDarkMode),
//                                     );
//                                   },
//                                 ),
//                               ),
//                   ),
//                 ],
//               ),

//               // ── Notification drop-down panel ──
//               if (_showNotificationPanel)
//                 Positioned(
//                   top: 0,
//                   right: 0,
//                   left: 0,
//                   child: FadeTransition(
//                     opacity: _notifFade,
//                     child: SlideTransition(
//                       position: _notifSlide,
//                       child: _buildNotificationPanel(isDarkMode),
//                     ),
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ─────────────── Notification Panel ───────────────

//   Widget _buildNotificationPanel(bool isDarkMode) {
//     return GestureDetector(
//       onTap: () {}, // prevent tap-through to close
//       child: Container(
//         margin: const EdgeInsets.fromLTRB(12, 72, 12, 0),
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF253330) : Colors.white,
//           borderRadius: BorderRadius.circular(20),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.15),
//               blurRadius: 24,
//               offset: const Offset(0, 8),
//             ),
//           ],
//           border: Border.all(
//             color: isDarkMode
//                 ? const Color(0xFF3A4A44)
//                 : const Color(0xFFE5E7EB),
//           ),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Header
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
//               child: Row(
//                 children: [
//                   const Text(
//                     'Notifications',
//                     style: TextStyle(
//                         fontSize: 16, fontWeight: FontWeight.w800),
//                   ),
//                   const SizedBox(width: 8),
//                   if (_unreadCount > 0)
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 8, vertical: 2),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: Text(
//                         '$_unreadCount new',
//                         style: const TextStyle(
//                             fontSize: 11,
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                   const Spacer(),
//                   if (_unreadCount > 0)
//                     TextButton(
//                       onPressed: _markAllRead,
//                       style: TextButton.styleFrom(
//                           padding: EdgeInsets.zero,
//                           minimumSize: Size.zero,
//                           tapTargetSize: MaterialTapTargetSize.shrinkWrap),
//                       child: const Text(
//                         'Mark all read',
//                         style: TextStyle(
//                             fontSize: 12, color: Color(0xFF39AC86)),
//                       ),
//                     ),
//                   const SizedBox(width: 8),
//                   GestureDetector(
//                     onTap: _toggleNotifications,
//                     child: Icon(Icons.close,
//                         size: 20,
//                         color: isDarkMode
//                             ? Colors.white54
//                             : const Color(0xFF9CA3AF)),
//                   ),
//                 ],
//               ),
//             ),

//             Divider(
//               height: 1,
//               color: isDarkMode
//                   ? const Color(0xFF3A4A44)
//                   : const Color(0xFFF3F4F6),
//             ),

//             // Notification list or empty state
//             _notifications.isEmpty
//                 ? _buildNoNotifications(isDarkMode)
//                 : ListView.separated(
//                     shrinkWrap: true,
//                     physics: const NeverScrollableScrollPhysics(),
//                     itemCount: _notifications.length,
//                     separatorBuilder: (_, __) => Divider(
//                       height: 1,
//                       color: isDarkMode
//                           ? const Color(0xFF3A4A44)
//                           : const Color(0xFFF3F4F6),
//                     ),
//                     itemBuilder: (context, index) {
//                       final n = _notifications[index];
//                       return _buildNotificationTile(n, isDarkMode, index);
//                     },
//                   ),

//             const SizedBox(height: 8),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildNotificationTile(
//       Map<String, dynamic> n, bool isDarkMode, int index) {
//     final bool isUnread = n['read'] == false;
//     return GestureDetector(
//       onTap: () {
//         setState(() => _notifications[index]['read'] = true);
//       },
//       child: Container(
//         color: isUnread
//             ? const Color(0xFF39AC86).withOpacity(0.05)
//             : Colors.transparent,
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 color: (n['color'] as Color).withOpacity(0.12),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Icon(n['icon'] as IconData,
//                   color: n['color'] as Color, size: 20),
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Text(
//                           n['title'] as String,
//                           style: TextStyle(
//                             fontSize: 13,
//                             fontWeight: isUnread
//                                 ? FontWeight.w700
//                                 : FontWeight.w500,
//                             color: isDarkMode
//                                 ? Colors.white
//                                 : const Color(0xFF101816),
//                           ),
//                         ),
//                       ),
//                       Text(
//                         n['time'] as String,
//                         style: TextStyle(
//                           fontSize: 10,
//                           color: isDarkMode
//                               ? Colors.white38
//                               : const Color(0xFF9CA3AF),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 3),
//                   Text(
//                     n['body'] as String,
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: isDarkMode
//                           ? Colors.white60
//                           : const Color(0xFF5C8A7A),
//                       height: 1.4,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             if (isUnread) ...[
//               const SizedBox(width: 8),
//               Container(
//                 width: 8,
//                 height: 8,
//                 margin: const EdgeInsets.only(top: 4),
//                 decoration: const BoxDecoration(
//                   color: Color(0xFF39AC86),
//                   shape: BoxShape.circle,
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildNoNotifications(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 32),
//       child: Column(
//         children: [
//           Icon(
//             Icons.notifications_none,
//             size: 48,
//             color: const Color(0xFF39AC86).withOpacity(0.3),
//           ),
//           const SizedBox(height: 12),
//           Text(
//             'No new notifications',
//             style: TextStyle(
//               fontSize: 15,
//               fontWeight: FontWeight.w600,
//               color: isDarkMode ? Colors.white70 : const Color(0xFF101816),
//             ),
//           ),
//           const SizedBox(height: 4),
//           const Text(
//             "You're all caught up! 🌿",
//             style: TextStyle(fontSize: 13, color: Color(0xFF5C8A7A)),
//           ),
//         ],
//       ),
//     );
//   }

//   // ─────────────── Top Bar ───────────────

//   Widget _buildTopBar(Map<String, dynamic>? currentUser, bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
//       decoration: BoxDecoration(
//         color: isDarkMode
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Row(
//         children: [
//           GestureDetector(
//             onTap: () => _scaffoldKey.currentState?.openDrawer(),
//             child: Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(color: const Color(0xFF39AC86), width: 2),
//               ),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(20),
//                 child: _buildProfileImage(currentUser),
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Welcome back,',
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: isDarkMode
//                         ? const Color(0xFF39AC86).withOpacity(0.7)
//                         : const Color(0xFF5C8A7A),
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   '${currentUser?['name']?.split(' ')[0] ?? 'Gardener'}! 🌿',
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           _buildIconButton(
//             icon: Icons.message_outlined,
//             onPressed: () => Navigator.push(
//               context,
//               MaterialPageRoute(
//                   builder: (context) => const MessagesScreen()),
//             ),
//           ),
//           const SizedBox(width: 8),
//           // Notification button with animated badge
//           _buildNotificationButton(isDarkMode),
//         ],
//       ),
//     );
//   }

//   Widget _buildNotificationButton(bool isDarkMode) {
//     return GestureDetector(
//       onTap: _toggleNotifications,
//       child: Container(
//         width: 40,
//         height: 40,
//         decoration: BoxDecoration(
//           color: _showNotificationPanel
//               ? const Color(0xFF39AC86)
//               : (isDarkMode ? const Color(0xFF2D3A35) : Colors.white),
//           borderRadius: BorderRadius.circular(20),
//           boxShadow: [
//             BoxShadow(
//               color: _showNotificationPanel
//                   ? const Color(0xFF39AC86).withOpacity(0.3)
//                   : Colors.black.withOpacity(0.05),
//               blurRadius: 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Stack(
//           children: [
//             Center(
//               child: Icon(
//                 _showNotificationPanel
//                     ? Icons.notifications
//                     : Icons.notifications_outlined,
//                 color: _showNotificationPanel
//                     ? Colors.white
//                     : const Color(0xFF39AC86),
//                 size: 20,
//               ),
//             ),
//             // Animated badge
//             if (_unreadCount > 0)
//               Positioned(
//                 top: 6,
//                 right: 6,
//                 child: _AnimatedBadge(count: _unreadCount),
//               ),
//           ],
//         ),
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
//                     color: isDarkMode
//                         ? const Color(0xFF2D3A35)
//                         : Colors.white,
//                     width: 1.5,
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   // ─────────────── Search Bar ───────────────

//   Widget _buildSearchBar(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Container(
//         height: 48,
//         decoration: BoxDecoration(
//           color: isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: isDarkMode
//                 ? const Color(0xFF3A4A44)
//                 : const Color(0xFFE5E7EB),
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
//                 decoration: const InputDecoration(
//                   hintText: 'Search for produce, tools, or gardeners...',
//                   hintStyle:
//                       TextStyle(color: Color(0xFF5C8A7A), fontSize: 14),
//                   border: InputBorder.none,
//                   contentPadding: EdgeInsets.zero,
//                 ),
//                 onChanged: (value) => _filterItems(value),
//               ),
//             ),
//             IconButton(
//               onPressed: () => _showFilterOptions(),
//               icon: const Icon(Icons.tune,
//                   color: Color(0xFF39AC86), size: 20),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Category Chips ───────────────

//   Widget _buildCategoryChips(bool isDarkMode) {
//     return SizedBox(
//       height: 50,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding:
//             const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//         itemCount: categories.length,
//         itemBuilder: (context, index) {
//           return Container(
//             margin: EdgeInsets.only(
//                 right: index < categories.length - 1 ? 12 : 0),
//             child: ChoiceChip(
//               label: Text(
//                 categories[index],
//                 style: TextStyle(
//                   fontSize: 14,
//                   fontWeight: index == _selectedCategoryIndex
//                       ? FontWeight.w600
//                       : FontWeight.w500,
//                   color: index == _selectedCategoryIndex
//                       ? Colors.white
//                       : (isDarkMode
//                           ? Colors.white
//                           : const Color(0xFF101816)),
//                 ),
//               ),
//               selected: _selectedCategoryIndex == index,
//               selectedColor: const Color(0xFF39AC86),
//               backgroundColor:
//                   isDarkMode ? const Color(0xFF2D3A35) : Colors.white,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(25),
//                 side: BorderSide(
//                   color: isDarkMode
//                       ? const Color(0xFF3A4A44)
//                       : const Color(0xFFE5E7EB),
//                 ),
//               ),
//               onSelected: (selected) {
//                 setState(() => _selectedCategoryIndex = index);
//               },
//             ),
//           );
//         },
//       ),
//     );
//   }

//   // ─────────────── Welcome Message ───────────────

//   Widget _buildWelcomeMessage(
//       Map<String, dynamic>? currentUser, bool isDarkMode) {
//     if (currentUser == null) return const SizedBox();
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       child: Container(
//         padding: const EdgeInsets.all(12),
//         decoration: BoxDecoration(
//           color: const Color(0xFF39AC86).withOpacity(0.1),
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//               color: const Color(0xFF39AC86).withOpacity(0.2)),
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
//                     style: TextStyle(
//                         fontSize: 12, color: Color(0xFF5C8A7A)),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Section Header ───────────────

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
//           GestureDetector(
//             onTap: _showMapView,
//             child: Container(
//               padding: const EdgeInsets.symmetric(
//                   horizontal: 14, vertical: 8),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(
//                     color:
//                         const Color(0xFF39AC86).withOpacity(0.3)),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.map_outlined,
//                       color: Color(0xFF39AC86), size: 16),
//                   SizedBox(width: 6),
//                   Text(
//                     'See Map',
//                     style: TextStyle(
//                       color: Color(0xFF39AC86),
//                       fontSize: 13,
//                       fontWeight: FontWeight.w700,
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

//   // ─────────────── Item Card ───────────────

//   Widget _buildSharedItemCard(
//       Map<String, dynamic> item, bool isDarkMode) {
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
//                   child: const Center(
//                       child: Icon(Icons.broken_image, size: 50)),
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
//                         style: const TextStyle(
//                             fontSize: 18, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 8, vertical: 4),
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
//                       backgroundImage:
//                           user['profile_image_url'] != null
//                               ? NetworkImage(user['profile_image_url'])
//                               : null,
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
//                             style: const TextStyle(
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold),
//                           ),
//                           if (user['location'] != null)
//                             Text(
//                               user['location'],
//                               style: const TextStyle(
//                                   fontSize: 10,
//                                   color: Color(0xFF5C8A7A)),
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
//                       color: isDarkMode
//                           ? Colors.white70
//                           : Colors.grey[600],
//                     ),
//                   ),
//                 ],
//                 if (item['pickup_instructions'] != null) ...[
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       const Icon(Icons.info_outline,
//                           size: 16, color: Color(0xFF5C8A7A)),
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
//                         const Icon(Icons.location_on,
//                             size: 16, color: Color(0xFF5C8A7A)),
//                         const SizedBox(width: 4),
//                         Text(
//                           item['location_text'] ?? 'Unknown location',
//                           style: const TextStyle(
//                               fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                       ],
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 16, vertical: 8),
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

//   // ─────────────── Empty State ───────────────

//   Widget _buildEmptyState(bool isDarkMode) {
//     return Center(
//       child: SingleChildScrollView(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(Icons.eco,
//                 size: 80,
//                 color: const Color(0xFF39AC86).withOpacity(0.3)),
//             const SizedBox(height: 16),
//             Text(
//               'No shared items yet',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: isDarkMode
//                     ? Colors.white
//                     : const Color(0xFF101816),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Be the first to share your harvest!',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: isDarkMode
//                     ? Colors.white70
//                     : const Color(0xFF5C8A7A),
//               ),
//             ),
//             const SizedBox(height: 24),
//             ElevatedButton(
//               onPressed: widget.onNavigateToShare,
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF39AC86),
//                 padding: const EdgeInsets.symmetric(
//                     horizontal: 32, vertical: 12),
//               ),
//               child: const Text(
//                 'Share Your Harvest',
//                 style: TextStyle(
//                     fontSize: 16, fontWeight: FontWeight.bold),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Drawer ───────────────

//   Widget _buildDrawer(
//       Map<String, dynamic>? currentUser, bool isDarkMode) {
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
//                     color: isDarkMode
//                         ? const Color(0xFF2A3A35)
//                         : const Color(0xFFE5E7E6),
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
//                       border: Border.all(
//                           color: const Color(0xFF39AC86), width: 2),
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
//                             color: isDarkMode
//                                 ? Colors.white
//                                 : const Color(0xFF101816),
//                           ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           currentUser?['email'] ?? 'email@example.com',
//                           style: const TextStyle(
//                               fontSize: 12, color: Color(0xFF5C8A7A)),
//                         ),
//                         if (currentUser?['location'] != null) ...[
//                           const SizedBox(height: 4),
//                           Row(
//                             children: [
//                               const Icon(Icons.location_on,
//                                   size: 12, color: Color(0xFF5C8A7A)),
//                               const SizedBox(width: 4),
//                               Text(
//                                 currentUser!['location']!,
//                                 style: const TextStyle(
//                                     fontSize: 12,
//                                     color: Color(0xFF5C8A7A)),
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
//                         MaterialPageRoute(
//                             builder: (context) =>
//                                 const ProfileScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.eco_outlined,
//                     label: 'My Garden',
//                     onTap: () {
//                       Navigator.pop(context);
//                       widget.onNavigateToGarden?.call();
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.message_outlined,
//                     label: 'Messages',
//                     onTap: () {
//                       Navigator.pop(context);
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                             builder: (context) =>
//                                 const MessagesScreen()),
//                       );
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.notifications_outlined,
//                     label: 'Notifications',
//                     onTap: () {
//                       Navigator.pop(context);
//                       _toggleNotifications();
//                     },
//                   ),
//                   _buildDrawerItem(
//                     icon: Icons.settings_outlined,
//                     label: 'Settings',
//                     onTap: () {
//                       Navigator.pop(context);
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         const SnackBar(
//                             content: Text('Settings coming soon!')),
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
//             const Padding(
//               padding: EdgeInsets.all(16),
//               child: Text(
//                 'Version 1.0.0',
//                 style:
//                     TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ─────────────── Profile Images ───────────────

//   Widget _buildDrawerProfileImage(Map<String, dynamic>? user) {
//     final imageUrl = user?['profile_image_url'];
//     if (imageUrl != null && imageUrl.isNotEmpty) {
//       return Image.network(
//         imageUrl,
//         fit: BoxFit.cover,
//         errorBuilder: (context, error, stack) =>
//             _buildProfilePlaceholder(30),
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
//         errorBuilder: (context, error, stack) =>
//             _buildProfilePlaceholder(20),
//       );
//     }
//     return _buildProfilePlaceholder(20);
//   }

//   Widget _buildProfilePlaceholder(double iconSize) {
//     return Container(
//       color: const Color(0xFF39AC86).withOpacity(0.1),
//       child: Center(
//         child: Icon(Icons.person,
//             size: iconSize, color: const Color(0xFF39AC86)),
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

//   void _filterItems(String query) {}

//   void _showFilterOptions() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(content: Text('Filter options coming soon!')),
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

// // ─────────────────────────── Animated Badge ───────────────────────────

// class _AnimatedBadge extends StatefulWidget {
//   final int count;
//   const _AnimatedBadge({required this.count});

//   @override
//   State<_AnimatedBadge> createState() => _AnimatedBadgeState();
// }

// class _AnimatedBadgeState extends State<_AnimatedBadge>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _ctrl;
//   late Animation<double> _scale;

//   @override
//   void initState() {
//     super.initState();
//     _ctrl = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 900),
//     )..repeat(reverse: true);
//     _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
//       CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
//     );
//   }

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return ScaleTransition(
//       scale: _scale,
//       child: Container(
//         width: 16,
//         height: 16,
//         decoration: BoxDecoration(
//           color: Colors.red,
//           shape: BoxShape.circle,
//           border: Border.all(color: Colors.white, width: 1.5),
//         ),
//         child: Center(
//           child: Text(
//             widget.count > 9 ? '9+' : '${widget.count}',
//             style: const TextStyle(
//               color: Colors.white,
//               fontSize: 8,
//               fontWeight: FontWeight.w900,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ─────────────────────────── Map Popup ───────────────────────────

// class _MapPopup extends StatefulWidget {
//   final Set<Marker> markers;
//   final LatLng centre;
//   final int itemCount;

//   const _MapPopup({
//     required this.markers,
//     required this.centre,
//     required this.itemCount,
//   });

//   @override
//   State<_MapPopup> createState() => _MapPopupState();
// }

// class _MapPopupState extends State<_MapPopup> {
//   GoogleMapController? _mapController;

//   @override
//   void dispose() {
//     _mapController?.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;

//     return Container(
//       height: MediaQuery.of(context).size.height * 0.82,
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
//       ),
//       child: Column(
//         children: [
//           // Handle
//           Container(
//             margin: const EdgeInsets.only(top: 12),
//             width: 40,
//             height: 4,
//             decoration: BoxDecoration(
//               color: Colors.grey[300],
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),

//           // Header
//           Padding(
//             padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
//             child: Row(
//               children: [
//                 Container(
//                   width: 36,
//                   height: 36,
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF39AC86).withOpacity(0.12),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(Icons.map_outlined,
//                       color: Color(0xFF39AC86), size: 20),
//                 ),
//                 const SizedBox(width: 12),
//                 Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Nearby Pickup Spots',
//                       style: TextStyle(
//                           fontSize: 16, fontWeight: FontWeight.w800),
//                     ),
//                     Text(
//                       widget.itemCount == 0
//                           ? 'No produce available right now'
//                           : '${widget.itemCount} produce ${widget.itemCount == 1 ? 'spot' : 'spots'} near you',
//                       style: const TextStyle(
//                           fontSize: 12, color: Color(0xFF5C8A7A)),
//                     ),
//                   ],
//                 ),
//                 const Spacer(),
//                 GestureDetector(
//                   onTap: () => Navigator.pop(context),
//                   child: Container(
//                     width: 32,
//                     height: 32,
//                     decoration: BoxDecoration(
//                       color: isDarkMode
//                           ? const Color(0xFF2D3A35)
//                           : Colors.white,
//                       borderRadius: BorderRadius.circular(16),
//                     ),
//                     child: Icon(Icons.close,
//                         size: 18,
//                         color: isDarkMode
//                             ? Colors.white70
//                             : const Color(0xFF666666)),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // Legend
//           Padding(
//             padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
//             child: Row(
//               children: [
//                 _buildLegendItem(
//                     BitmapDescriptor.hueGreen, 'Pickup available'),
//               ],
//             ),
//           ),

//           // Map
//           Expanded(
//             child: Padding(
//               padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(20),
//                 child: Stack(
//                   children: [
//                     GoogleMap(
//                       onMapCreated: (c) {
//                         _mapController = c;
//                       },
//                       initialCameraPosition: CameraPosition(
//                         target: widget.centre,
//                         zoom: widget.markers.length > 1 ? 11 : 14,
//                       ),
//                       markers: widget.markers,
//                       myLocationEnabled: true,
//                       myLocationButtonEnabled: false,
//                       zoomControlsEnabled: false,
//                       mapToolbarEnabled: false,
//                     ),
//                     // Zoom controls
//                     Positioned(
//                       top: 12,
//                       right: 12,
//                       child: Column(
//                         children: [
//                           _mapButton(
//                             icon: Icons.add,
//                             onTap: () => _mapController
//                                 ?.animateCamera(CameraUpdate.zoomIn()),
//                           ),
//                           const SizedBox(height: 6),
//                           _mapButton(
//                             icon: Icons.remove,
//                             onTap: () => _mapController
//                                 ?.animateCamera(CameraUpdate.zoomOut()),
//                           ),
//                           const SizedBox(height: 6),
//                           _mapButton(
//                             icon: Icons.my_location,
//                             onTap: () =>
//                                 _mapController?.animateCamera(
//                               CameraUpdate.newLatLngZoom(
//                                   widget.centre, 13),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     // Empty overlay
//                     if (widget.markers.isEmpty)
//                       Positioned.fill(
//                         child: Container(
//                           color: Colors.black.withOpacity(0.35),
//                           child: Center(
//                             child: Container(
//                               padding: const EdgeInsets.symmetric(
//                                   horizontal: 24, vertical: 16),
//                               decoration: BoxDecoration(
//                                 color: Colors.white,
//                                 borderRadius:
//                                     BorderRadius.circular(16),
//                               ),
//                               child: Column(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   Icon(Icons.eco,
//                                       size: 40,
//                                       color: const Color(0xFF39AC86)
//                                           .withOpacity(0.4)),
//                                   const SizedBox(height: 8),
//                                   const Text(
//                                     'No produce on the map yet',
//                                     style: TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                         fontSize: 14),
//                                   ),
//                                   const SizedBox(height: 4),
//                                   const Text(
//                                     'Share some to be first!',
//                                     style: TextStyle(
//                                         fontSize: 12,
//                                         color: Color(0xFF5C8A7A)),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(height: 20),
//         ],
//       ),
//     );
//   }

//   Widget _mapButton(
//       {required IconData icon, required VoidCallback onTap}) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         width: 36,
//         height: 36,
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(10),
//           boxShadow: [
//             BoxShadow(
//                 color: Colors.black.withOpacity(0.12),
//                 blurRadius: 6,
//                 offset: const Offset(0, 2))
//           ],
//         ),
//         child: Icon(icon, color: const Color(0xFF39AC86), size: 18),
//       ),
//     );
//   }

//   Widget _buildLegendItem(double hue, String label) {
//     return Row(
//       children: [
//         Container(
//           width: 12,
//           height: 12,
//           decoration: const BoxDecoration(
//             color: Color(0xFF39AC86),
//             shape: BoxShape.circle,
//           ),
//         ),
//         const SizedBox(width: 6),
//         Text(label,
//             style: const TextStyle(
//                 fontSize: 11, color: Color(0xFF5C8A7A))),
//       ],
//     );
//   }
// }







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
//   final VoidCallback? onNavigateToShare;
//   final VoidCallback? onNavigateToGarden;
  
//   const HomeScreen({
//     super.key, 
//     this.onItemShared,
//     this.onNavigateToShare,
//     this.onNavigateToGarden,
//   });

//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   final ApiService _apiService = ApiService();
//   final _searchController = TextEditingController();
//   final List<String> categories = ['All', 'Vegetables', 'Fruits', 'Herbs', 'Flowers'];
  
//   List<dynamic> _sharedItems = [];
//   bool _isLoading = false;
//   bool _isLoadingShared = false;
//   int _selectedCategoryIndex = 0;
  
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

//   void _handleLogout(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Logout'),
//         content: const Text('Are you sure you want to logout?'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           TextButton(
//             onPressed: () async {
//               Navigator.pop(context);
              
//               showDialog(
//                 context: context,
//                 barrierDismissible: false,
//                 builder: (context) => const Center(
//                   child: CircularProgressIndicator(color: Color(0xFF39AC86)),
//                 ),
//               );
              
//               final authProvider = Provider.of<AuthProvider>(context, listen: false);
//               await authProvider.logout();
              
//               if (context.mounted) {
//                 Navigator.of(context).pushNamedAndRemoveUntil(
//                   '/login', 
//                   (route) => false,
//                 );
//               }
//             },
//             child: const Text(
//               'Logout',
//               style: TextStyle(color: Colors.red),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

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
//       // floatingActionButton removed
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
//                       widget.onNavigateToGarden?.call();
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
//               onPressed: widget.onNavigateToShare,
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
