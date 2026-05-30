import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'update_crop_status_screen.dart';
import 'add_new_crop.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';

class AllCropsScreen extends StatefulWidget {
  final List<dynamic>? initialCrops;
  
  const AllCropsScreen({Key? key, this.initialCrops}) : super(key: key);

  @override
  State<AllCropsScreen> createState() => _AllCropsScreenState();
}

class _AllCropsScreenState extends State<AllCropsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  
  int _selectedFilterIndex = 0;
  int _selectedTabIndex = 0; // 0 = Active, 1 = Archived
  final TextEditingController _searchController = TextEditingController();
  
  List<dynamic> _allCrops = [];
  List<dynamic> _archivedCrops = [];
  List<dynamic> _filteredCrops = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  
  final List<Map<String, dynamic>> _filters = [
    {'label': 'All', 'value': 'all'},
    {'label': 'Vegetables', 'value': 'vegetable'},
    {'label': 'Fruits', 'value': 'fruit'},
    {'label': 'Herbs', 'value': 'herb'},
    {'label': 'Flowers', 'value': 'flower'},
    {'label': 'Other', 'value': 'other'},
  ];

  final List<String> _archiveReasons = [
    'Pest Infestation',
    'Disease',
    'Weather Damage',
    'Poor Growth',
    'Harvested',
    'Season Ended',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _initializeCrops();
    _searchController.addListener(_filterCrops);
  }

  void _initializeCrops() {
    if (widget.initialCrops != null && widget.initialCrops!.isNotEmpty) {
      setState(() {
        _allCrops = widget.initialCrops!
            .where((crop) => crop['is_archived'] != true)
            .toList();
        _archivedCrops = widget.initialCrops!
            .where((crop) => crop['is_archived'] == true)
            .toList();
        _filteredCrops = _allCrops;
        _isLoading = false;
      });
    } else {
      _loadCrops();
    }
  }

  Future<void> _loadCrops({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final cropsResult = await _apiService.getUserCrops();
      
      if (cropsResult['success'] == true) {
        final allCrops = cropsResult['crops'] ?? [];
        setState(() {
          _allCrops = allCrops.where((crop) => crop['is_archived'] != true).toList();
          _archivedCrops = allCrops.where((crop) => crop['is_archived'] == true).toList();
          _filteredCrops = _allCrops;
        });
      }
    } catch (e) {
      print('❌ Error loading crops: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load crops'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _refreshCrops() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    await _loadCrops(forceRefresh: true);
  }

  void _filterCrops() {
    final query = _searchController.text.toLowerCase();
    final filterValue = _filters[_selectedFilterIndex]['value'];
    final cropsToFilter = _selectedTabIndex == 0 ? _allCrops : _archivedCrops;

    setState(() {
      _filteredCrops = cropsToFilter.where((crop) {
        final matchesSearch = query.isEmpty || 
            (crop['name']?.toString().toLowerCase().contains(query) ?? false) ||
            (crop['variety']?.toString().toLowerCase().contains(query) ?? false);

        final matchesCategory = filterValue == 'all' || 
            crop['category'] == filterValue;

        return matchesSearch && matchesCategory;
      }).toList();
    });
  }

  void _updateFilter(int index) {
    setState(() {
      _selectedFilterIndex = index;
    });
    _filterCrops();
  }

  void _switchTab(int index) {
    setState(() {
      _selectedTabIndex = index;
      _selectedFilterIndex = 0; // Reset filter when switching tabs
    });
    _filterCrops();
  }

  String _getStatusColor(String status) {
    switch (status) {
      case 'harvest':
        return '#E59866';
      case 'fruiting':
        return '#39AC86';
      case 'flowering':
        return '#E59866';
      case 'vegetative':
        return '#4299E1';
      case 'seedling':
        return '#9B59B6';
      default:
        return '#808080';
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'seedling':
        return '🌱 Seedling';
      case 'vegetative':
        return '🌿 Vegetative';
      case 'flowering':
        return '🌸 Flowering';
      case 'fruiting':
        return '🍎 Fruiting';
      case 'harvest':
        return '🎉 Ready to Harvest';
      case 'dormant':
        return '💤 Dormant';
      default:
        return _capitalize(status);
    }
  }

  Future<void> _archiveCrop(Map<String, dynamic> crop) async {
    String? selectedReason = _archiveReasons.first;
    String? customReason;
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.archive, color: Colors.orange),
                SizedBox(width: 8),
                Text('Archive Crop'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Are you sure you want to archive "${crop['name']}"?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reason for archiving:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  items: _archiveReasons.map((reason) {
                    return DropdownMenuItem(
                      value: reason,
                      child: Text(reason),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value;
                    });
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) {
                      customReason = value;
                    },
                    decoration: const InputDecoration(
                      hintText: 'Please specify...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  
                  final reason = selectedReason == 'Other' 
                      ? customReason ?? 'Other' 
                      : selectedReason;
                  
                  // Show loading
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                  
                  try {
                    final result = await _apiService.archiveCrop(
                      crop['id'],
                      reason ?? 'Unknown',
                    );
                    
                    if (mounted) Navigator.pop(context);
                    
                    if (result['success'] == true) {
                      await _refreshCrops();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('"${crop['name']}" has been archived.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else {
                      throw Exception(result['error']);
                    }
                  } catch (e) {
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to archive: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: const Text('Archive'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _restoreCrop(Map<String, dynamic> crop) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.restore, color: Colors.green),
            SizedBox(width: 8),
            Text('Restore Crop'),
          ],
        ),
        content: Text(
          'Are you sure you want to restore "${crop['name']}" to your active crops?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );
              
              try {
                final result = await _apiService.restoreCrop(crop['id']);
                
                if (mounted) Navigator.pop(context);
                
                if (result['success'] == true) {
                  await _refreshCrops();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${crop['name']}" has been restored!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  throw Exception(result['error']);
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to restore: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePermanently(Map<String, dynamic> crop) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Permanently'),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${crop['name']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );
              
              try {
                final result = await _apiService.deleteCropPermanent(crop['id']);
                
                if (mounted) Navigator.pop(context);
                
                if (result['success'] == true) {
                  await _refreshCrops();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${crop['name']}" has been deleted.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  throw Exception(result['error']);
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualProgressDialog(Map<String, dynamic> crop) async {
    final TextEditingController progressController = TextEditingController();
    final currentProgress = (crop['progress'] as num?)?.toInt() ?? 0;
    progressController.text = currentProgress.toString();
    
    final autoUpdateEnabled = crop['auto_update_enabled'] ?? true;
    
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
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'Manual Growth Adjustment',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Adjust if there are growth delays',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.autorenew, color: Color(0xFF19E6A2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Auto-Update Progress',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Automatically calculate based on planting date',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: autoUpdateEnabled,
                        onChanged: (value) async {
                          try {
                            final result = await _apiService.toggleCropAutoUpdate(crop['id'], value);
                            if (result['success'] == true) {
                              await _refreshCrops();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(value 
                                    ? 'Auto-update enabled' 
                                    : 'Auto-update disabled. You can now manually adjust progress.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            print('Error toggling auto-update: $e');
                          }
                          Navigator.pop(context);
                        },
                        activeColor: const Color(0xFF19E6A2),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                if (!autoUpdateEnabled) ...[
                  const Text(
                    'Current Progress',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: (currentProgress / 100).clamp(0.0, 1.0),
                          onChanged: (value) {
                            progressController.text = (value * 100).toInt().toString();
                            setSheetState(() {});
                          },
                          activeColor: const Color(0xFF19E6A2),
                          divisions: 100,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 60,
                        child: TextField(
                          controller: progressController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            suffixText: '%',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          onChanged: (value) {
                            final intVal = int.tryParse(value) ?? 0;
                            setSheetState(() {
                              progressController.text = intVal.clamp(0, 100).toString();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF19E6A2).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Expected Growth Stages:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _buildStageIndicator('🌱 Seedling', currentProgress >= 0),
                            _buildStageIndicator('🌿 Vegetative', currentProgress >= 20),
                            _buildStageIndicator('🌸 Flowering', currentProgress >= 40),
                            _buildStageIndicator('🍎 Fruiting', currentProgress >= 60),
                            _buildStageIndicator('🎉 Harvest', currentProgress >= 80),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final newProgress = int.tryParse(progressController.text) ?? 0;
                            final clampedProgress = newProgress.clamp(0, 100);
                            
                            Navigator.pop(context);
                            
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            
                            try {
                              final result = await _apiService.updateCropProgress(
                                crop['id'],
                                clampedProgress,
                              );
                              
                              if (mounted) Navigator.pop(context);
                              
                              if (result['success'] == true) {
                                await _refreshCrops();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Growth progress updated!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else {
                                throw Exception('Failed to update');
                              }
                            } catch (e) {
                              if (mounted) Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to update progress'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF19E6A2),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Save Progress',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 40,
                          color: Color(0xFF19E6A2),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Auto-update is enabled',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your crop progress is automatically calculated based on the planting date (${_formatDate(crop['planting_date'])}).',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Current progress: ${(crop['progress'] as num?)?.toInt() ?? 0}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF19E6A2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (crop['days_to_harvest'] != null)
                          Text(
                            'Expected harvest in ~${crop['days_to_harvest'] - (crop['days_planted'] ?? 0)} days',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStageIndicator(String label, bool isReached) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isReached ? const Color(0xFF19E6A2).withOpacity(0.2) : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: isReached ? const Color(0xFF19E6A2) : Colors.grey,
          fontWeight: isReached ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Not set';
    try {
      final date = DateTime.parse(dateStr);
      return '${_getMonthAbbr(date.month)} ${date.day}, ${date.year}';
    } catch (e) {
      return 'Not set';
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCrops);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF11211C) : const Color(0xFFF6F8F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDarkMode),
            _buildTabSwitcher(isDarkMode),
            _buildSearchBar(isDarkMode),
            if (_selectedTabIndex == 0) _buildFilterChips(isDarkMode),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState(isDarkMode)
                  : _filteredCrops.isEmpty
                      ? _buildEmptyState(isDarkMode)
                      : RefreshIndicator(
                          onRefresh: _refreshCrops,
                          color: const Color(0xFF19E6A2),
                          backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredCrops.length,
                            itemBuilder: (context, index) {
                              final crop = _filteredCrops[index];
                              return _buildCropListItem(context, crop, isDarkMode);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedTabIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddNewCropScreen(),
                  ),
                );
                
                if (result != null) {
                  await _refreshCrops();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Crop added successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              backgroundColor: const Color(0xFF19E6A2),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildTabSwitcher(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A2B26) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 0
                      ? const Color(0xFF19E6A2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.eco,
                      size: 18,
                      color: _selectedTabIndex == 0
                          ? Colors.white
                          : (isDarkMode ? Colors.white70 : Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active Crops',
                      style: TextStyle(
                        color: _selectedTabIndex == 0
                            ? Colors.white
                            : (isDarkMode ? Colors.white70 : Colors.grey[600]),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 0
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFF19E6A2).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_allCrops.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 0
                              ? Colors.white
                              : const Color(0xFF19E6A2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _switchTab(1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 1
                      ? const Color(0xFF19E6A2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.archive,
                      size: 18,
                      color: _selectedTabIndex == 1
                          ? Colors.white
                          : (isDarkMode ? Colors.white70 : Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Archived',
                      style: TextStyle(
                        color: _selectedTabIndex == 1
                            ? Colors.white
                            : (isDarkMode ? Colors.white70 : Colors.grey[600]),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _selectedTabIndex == 1
                            ? Colors.white.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_archivedCrops.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _selectedTabIndex == 1
                              ? Colors.white
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
            ? const Color(0xFF11211C).withOpacity(0.8)
            : const Color(0xFFF6F8F7).withOpacity(0.8),
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? const Color(0xFF1A2B26) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
              size: 20,
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'My Crops',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
                    ),
                  ),
                  if (_isRefreshing) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: const Color(0xFF19E6A2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF19E6A2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_selectedTabIndex == 0 ? _filteredCrops.length : _archivedCrops.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF19E6A2),
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
          color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Icon(Icons.search, color: Color(0xFF4E977F), size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search your crops',
                  hintStyle: TextStyle(color: Color(0xFF4E977F)),
                  border: InputBorder.none,
                ),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
                  fontSize: 16,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  _searchController.clear();
                  _filterCrops();
                },
                icon: const Icon(Icons.clear, color: Color(0xFF4E977F), size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(bool isDarkMode) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedFilterIndex == index;
          
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Material(
              color: isSelected
                  ? const Color(0xFF19E6A2)
                  : (isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: () => _updateFilter(index),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(
                            color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFE5E7EB),
                          ),
                  ),
                  child: Text(
                    filter['label'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF19E6A2)),
          const SizedBox(height: 16),
          Text(
            'Loading your crops...',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
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
              _selectedTabIndex == 0 ? Icons.eco : Icons.archive,
              size: 80,
              color: const Color(0xFF19E6A2).withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedTabIndex == 0 ? 'No crops found' : 'No archived crops',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedTabIndex == 0
                  ? (_searchController.text.isNotEmpty || _selectedFilterIndex != 0
                      ? 'Try adjusting your search or filters'
                      : 'Add your first crop to get started!')
                  : 'Archived crops will appear here',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
              ),
            ),
            if (_selectedTabIndex == 0) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AddNewCropScreen(),
                    ),
                  );
                  
                  if (result != null) {
                    await _refreshCrops();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF19E6A2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Add Your First Crop',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCropListItem(
    BuildContext context,
    Map<String, dynamic> crop,
    bool isDarkMode,
  ) {
    final String name = crop['name']?.toString() ?? 'Unnamed Crop';
    final String status = crop['stage'] ?? crop['status'] ?? 'seedling';
    final String variety = crop['variety']?.toString() ?? 'Unknown';
    final String category = crop['category']?.toString() ?? 'vegetable';
    final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
    final String? imageUrl = crop['image_url']?.toString();
    final int quantity = (crop['quantity'] as num?)?.toInt() ?? 1;
    final String quantityUnit = crop['quantity_unit']?.toString() ?? 'plants';
    final bool autoUpdateEnabled = crop['auto_update_enabled'] ?? true;
    final int daysPlanted = crop['days_planted'] ?? 0;
    final int daysToHarvest = crop['days_to_harvest'] ?? 90;
    final bool isArchived = crop['is_archived'] == true;
    final String? archiveReason = crop['archive_reason'];
    
    final String statusColor = _getStatusColor(status);
    final String statusLabel = _getStatusLabel(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? (isArchived ? Colors.grey[800]!.withOpacity(0.5) : Colors.black.withOpacity(0.3))
            : (isArchived ? Colors.grey[200] : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isArchived 
              ? Colors.grey.withOpacity(0.5)
              : (isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF19E6A2).withOpacity(0.1),
            ),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: 72,
                    height: 72,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFF19E6A2).withOpacity(0.1),
                        child: const Center(
                          child: Icon(
                            Icons.eco,
                            color: Color(0xFF19E6A2),
                            size: 32,
                          ),
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Icon(
                      Icons.eco,
                      color: Color(0xFF19E6A2),
                      size: 32,
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isArchived
                                    ? Colors.grey
                                    : (isDarkMode ? Colors.white : const Color(0xFF0E1B17)),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isArchived)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Archived',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          if (!autoUpdateEnabled && !isArchived)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Manual',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isArchived
                            ? Colors.grey.withOpacity(0.2)
                            : Color(int.parse(statusColor.replaceFirst('#', '0xFF'))).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$quantity $quantityUnit',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isArchived
                              ? Colors.grey
                              : Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!isArchived) ...[
                  Row(
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
                        ),
                      ),
                      if (autoUpdateEnabled && daysPlanted > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Day $daysPlanted/$daysToHarvest',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_capitalize(category)} • $variety',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4E977F),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress / 100,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF19E6A2), Color(0xFF39AC86)],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${progress.toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17),
                        ),
                      ),
                    ],
                  ),
                ] else if (archiveReason != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Reason: $archiveReason',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isArchived)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
                size: 20,
              ),
              onSelected: (value) {
                if (value == 'archive') {
                  _archiveCrop(crop);
                } else if (value == 'edit') {
                  _showManualProgressDialog(crop);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Edit Progress'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Archive Crop'),
                    ],
                  ),
                ),
              ],
            ),
          if (isArchived)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _restoreCrop(crop),
                  icon: const Icon(Icons.restore, color: Colors.green, size: 20),
                  tooltip: 'Restore',
                ),
                IconButton(
                  onPressed: () => _deletePermanently(crop),
                  icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                  tooltip: 'Delete Permanently',
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _getMonthAbbr(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}







// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'update_crop_status_screen.dart';
// import 'add_new_crop.dart';
// import '../services/api_service.dart';
// import '../providers/auth_provider.dart';

// class AllCropsScreen extends StatefulWidget {
//   final List<dynamic>? initialCrops;
  
//   const AllCropsScreen({Key? key, this.initialCrops}) : super(key: key);

//   @override
//   State<AllCropsScreen> createState() => _AllCropsScreenState();
// }

// class _AllCropsScreenState extends State<AllCropsScreen> {
//   final ApiService _apiService = ApiService();
  
//   int _selectedFilterIndex = 0;
//   final TextEditingController _searchController = TextEditingController();
  
//   List<dynamic> _allCrops = [];
//   List<dynamic> _filteredCrops = [];
//   bool _isLoading = true;
//   bool _isRefreshing = false;
  
//   final List<Map<String, dynamic>> _filters = [
//     {'label': 'All', 'value': 'all'},
//     {'label': 'Vegetables', 'value': 'vegetable'},
//     {'label': 'Fruits', 'value': 'fruit'},
//     {'label': 'Herbs', 'value': 'herb'},
//     {'label': 'Flowers', 'value': 'flower'},
//     {'label': 'Other', 'value': 'other'},
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _initializeCrops();
//     _searchController.addListener(_filterCrops);
//   }

//   void _initializeCrops() {
//     if (widget.initialCrops != null && widget.initialCrops!.isNotEmpty) {
//       setState(() {
//         _allCrops = widget.initialCrops!;
//         _filteredCrops = _allCrops;
//         _isLoading = false;
//       });
//     } else {
//       _loadCrops();
//     }
//   }

//   Future<void> _loadCrops({bool forceRefresh = false}) async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final cropsResult = await _apiService.getUserCrops();
      
//       if (cropsResult['success'] == true) {
//         setState(() {
//           _allCrops = cropsResult['crops'] ?? [];
//           _filteredCrops = _allCrops;
//         });
//       }
//     } catch (e) {
//       print('❌ Error loading crops: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Failed to load crops'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } finally {
//       setState(() {
//         _isLoading = false;
//         _isRefreshing = false;
//       });
//     }
//   }

//   Future<void> _refreshCrops() async {
//     if (_isRefreshing) return;

//     setState(() {
//       _isRefreshing = true;
//     });

//     await _loadCrops(forceRefresh: true);
//   }

//   void _filterCrops() {
//     final query = _searchController.text.toLowerCase();
//     final filterValue = _filters[_selectedFilterIndex]['value'];

//     setState(() {
//       _filteredCrops = _allCrops.where((crop) {
//         final matchesSearch = query.isEmpty || 
//             (crop['name']?.toString().toLowerCase().contains(query) ?? false) ||
//             (crop['variety']?.toString().toLowerCase().contains(query) ?? false);

//         final matchesCategory = filterValue == 'all' || 
//             crop['category'] == filterValue;

//         return matchesSearch && matchesCategory;
//       }).toList();
//     });
//   }

//   void _updateFilter(int index) {
//     setState(() {
//       _selectedFilterIndex = index;
//     });
//     _filterCrops();
//   }

//   String _getStatusColor(String status) {
//     switch (status) {
//       case 'harvest':
//         return '#E59866';
//       case 'fruiting':
//         return '#39AC86';
//       case 'flowering':
//         return '#E59866';
//       case 'vegetative':
//         return '#4299E1';
//       case 'seedling':
//         return '#9B59B6';
//       default:
//         return '#808080';
//     }
//   }

//   String _getStatusLabel(String status) {
//     switch (status) {
//       case 'seedling':
//         return '🌱 Seedling';
//       case 'vegetative':
//         return '🌿 Vegetative';
//       case 'flowering':
//         return '🌸 Flowering';
//       case 'fruiting':
//         return '🍎 Fruiting';
//       case 'harvest':
//         return '🎉 Ready to Harvest';
//       case 'dormant':
//         return '💤 Dormant';
//       default:
//         return _capitalize(status);
//     }
//   }

//   Future<void> _showManualProgressDialog(Map<String, dynamic> crop) async {
//     final TextEditingController progressController = TextEditingController();
//     final currentProgress = (crop['progress'] as num?)?.toInt() ?? 0;
//     progressController.text = currentProgress.toString();
    
//     final autoUpdateEnabled = crop['auto_update_enabled'] ?? true;
    
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
//               left: 16,
//               right: 16,
//               top: 16,
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const Center(
//                   child: Text(
//                     'Manual Growth Adjustment',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 const Center(
//                   child: Text(
//                     'Adjust if there are growth delays',
//                     style: TextStyle(
//                       fontSize: 12,
//                       color: Colors.grey,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 20),
                
//                 // Auto-update toggle
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: Colors.grey[100],
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(Icons.autorenew, color: Color(0xFF19E6A2)),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             const Text(
//                               'Auto-Update Progress',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                             Text(
//                               'Automatically calculate based on planting date',
//                               style: TextStyle(
//                                 fontSize: 11,
//                                 color: Colors.grey[600],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       Switch(
//                         value: autoUpdateEnabled,
//                         onChanged: (value) async {
//                           setSheetState(() {
//                             // Update UI immediately
//                           });
                          
//                           // Call API to toggle
//                           try {
//                             final result = await _apiService.toggleCropAutoUpdate(crop['id'], value);
//                             if (result['success'] == true) {
//                               setSheetState(() {
//                                 // Refresh the UI
//                                 _refreshCrops();
//                               });
                              
//                               if (!value) {
//                                 ScaffoldMessenger.of(context).showSnackBar(
//                                   const SnackBar(
//                                     content: Text('Auto-update disabled. You can now manually adjust progress.'),
//                                     backgroundColor: Colors.orange,
//                                   ),
//                                 );
//                               } else {
//                                 ScaffoldMessenger.of(context).showSnackBar(
//                                   const SnackBar(
//                                     content: Text('Auto-update enabled. Progress will auto-calculate.'),
//                                     backgroundColor: Colors.green,
//                                   ),
//                                 );
//                               }
//                             }
//                           } catch (e) {
//                             print('Error toggling auto-update: $e');
//                           }
                          
//                           Navigator.pop(context);
//                           _showManualProgressDialog(crop);
//                         },
//                         activeColor: const Color(0xFF19E6A2),
//                       ),
//                     ],
//                   ),
//                 ),
                
//                 const SizedBox(height: 20),
                
//                 if (!autoUpdateEnabled) ...[
//                   const Text(
//                     'Current Progress',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Slider(
//                           value: (currentProgress / 100).clamp(0.0, 1.0),
//                           onChanged: (value) {
//                             progressController.text = (value * 100).toInt().toString();
//                             setSheetState(() {});
//                           },
//                           activeColor: const Color(0xFF19E6A2),
//                           divisions: 100,
//                         ),
//                       ),
//                       const SizedBox(width: 16),
//                       SizedBox(
//                         width: 60,
//                         child: TextField(
//                           controller: progressController,
//                           keyboardType: TextInputType.number,
//                           textAlign: TextAlign.center,
//                           decoration: InputDecoration(
//                             suffixText: '%',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
//                           ),
//                           onChanged: (value) {
//                             final intVal = int.tryParse(value) ?? 0;
//                             setSheetState(() {
//                               progressController.text = intVal.clamp(0, 100).toString();
//                             });
//                           },
//                         ),
//                       ),
//                     ],
//                   ),
                  
//                   const SizedBox(height: 24),
                  
//                   // Growth stage info
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF19E6A2).withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Text(
//                           'Expected Growth Stages:',
//                           style: TextStyle(
//                             fontWeight: FontWeight.bold,
//                             fontSize: 12,
//                           ),
//                         ),
//                         const SizedBox(height: 8),
//                         Wrap(
//                           spacing: 8,
//                           children: [
//                             _buildStageIndicator('🌱 Seedling', currentProgress >= 0),
//                             _buildStageIndicator('🌿 Vegetative', currentProgress >= 20),
//                             _buildStageIndicator('🌸 Flowering', currentProgress >= 40),
//                             _buildStageIndicator('🍎 Fruiting', currentProgress >= 60),
//                             _buildStageIndicator('🎉 Harvest', currentProgress >= 80),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
                  
//                   const SizedBox(height: 24),
                  
//                   Row(
//                     children: [
//                       Expanded(
//                         child: OutlinedButton(
//                           onPressed: () => Navigator.pop(context),
//                           style: OutlinedButton.styleFrom(
//                             padding: const EdgeInsets.symmetric(vertical: 12),
//                           ),
//                           child: const Text('Cancel'),
//                         ),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: ElevatedButton(
//                           onPressed: () async {
//                             final newProgress = int.tryParse(progressController.text) ?? 0;
//                             final clampedProgress = newProgress.clamp(0, 100);
                            
//                             Navigator.pop(context);
                            
//                             // Show loading
//                             showDialog(
//                               context: context,
//                               barrierDismissible: false,
//                               builder: (context) => const Center(
//                                 child: CircularProgressIndicator(),
//                               ),
//                             );
                            
//                             try {
//                               final result = await _apiService.updateCropProgress(
//                                 crop['id'],
//                                 clampedProgress,
//                               );
                              
//                               if (mounted) Navigator.pop(context);
                              
//                               if (result['success'] == true) {
//                                 await _refreshCrops();
//                                 if (mounted) {
//                                   ScaffoldMessenger.of(context).showSnackBar(
//                                     const SnackBar(
//                                       content: Text('Growth progress updated!'),
//                                       backgroundColor: Colors.green,
//                                     ),
//                                   );
//                                 }
//                               } else {
//                                 throw Exception('Failed to update');
//                               }
//                             } catch (e) {
//                               if (mounted) Navigator.pop(context);
//                               ScaffoldMessenger.of(context).showSnackBar(
//                                 const SnackBar(
//                                   content: Text('Failed to update progress'),
//                                   backgroundColor: Colors.red,
//                                 ),
//                               );
//                             }
//                           },
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: const Color(0xFF19E6A2),
//                             padding: const EdgeInsets.symmetric(vertical: 12),
//                           ),
//                           child: const Text(
//                             'Save Progress',
//                             style: TextStyle(fontWeight: FontWeight.bold),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 16),
//                 ] else ...[
//                   Container(
//                     padding: const EdgeInsets.all(16),
//                     decoration: BoxDecoration(
//                       color: Colors.grey[100],
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: Column(
//                       children: [
//                         const Icon(
//                           Icons.auto_awesome,
//                           size: 40,
//                           color: Color(0xFF19E6A2),
//                         ),
//                         const SizedBox(height: 12),
//                         const Text(
//                           'Auto-update is enabled',
//                           style: TextStyle(
//                             fontWeight: FontWeight.bold,
//                             fontSize: 16,
//                           ),
//                         ),
//                         const SizedBox(height: 8),
//                         Text(
//                           'Your crop progress is automatically calculated based on the planting date (${_formatDate(crop['planting_date'])}).',
//                           textAlign: TextAlign.center,
//                           style: const TextStyle(fontSize: 12),
//                         ),
//                         const SizedBox(height: 16),
//                         Text(
//                           'Current progress: ${(crop['progress'] as num?)?.toInt() ?? 0}%',
//                           style: const TextStyle(
//                             fontWeight: FontWeight.bold,
//                             fontSize: 14,
//                             color: Color(0xFF19E6A2),
//                           ),
//                         ),
//                         const SizedBox(height: 8),
//                         if (crop['days_to_harvest'] != null)
//                           Text(
//                             'Expected harvest in ~${crop['days_to_harvest'] - (crop['days_planted'] ?? 0)} days',
//                             style: const TextStyle(fontSize: 11),
//                           ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 24),
//                   SizedBox(
//                     width: double.infinity,
//                     child: OutlinedButton(
//                       onPressed: () => Navigator.pop(context),
//                       style: OutlinedButton.styleFrom(
//                         padding: const EdgeInsets.symmetric(vertical: 12),
//                       ),
//                       child: const Text('Close'),
//                     ),
//                   ),
//                   const SizedBox(height: 16),
//                 ],
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildStageIndicator(String label, bool isReached) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: BoxDecoration(
//         color: isReached ? const Color(0xFF19E6A2).withOpacity(0.2) : Colors.grey[200],
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Text(
//         label,
//         style: TextStyle(
//           fontSize: 10,
//           color: isReached ? const Color(0xFF19E6A2) : Colors.grey,
//           fontWeight: isReached ? FontWeight.bold : FontWeight.normal,
//         ),
//       ),
//     );
//   }

//   String _formatDate(String? dateStr) {
//     if (dateStr == null) return 'Not set';
//     try {
//       final date = DateTime.parse(dateStr);
//       return '${_getMonthAbbr(date.month)} ${date.day}, ${date.year}';
//     } catch (e) {
//       return 'Not set';
//     }
//   }

//   @override
//   void dispose() {
//     _searchController.removeListener(_filterCrops);
//     _searchController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF11211C) : const Color(0xFFF6F8F7),
//       body: SafeArea(
//         child: Column(
//           children: [
//             _buildTopBar(isDarkMode),
//             _buildSearchBar(isDarkMode),
//             _buildFilterChips(isDarkMode),
//             Expanded(
//               child: _isLoading
//                   ? _buildLoadingState(isDarkMode)
//                   : _filteredCrops.isEmpty
//                       ? _buildEmptyState(isDarkMode)
//                       : RefreshIndicator(
//                           onRefresh: _refreshCrops,
//                           color: const Color(0xFF19E6A2),
//                           backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//                           child: ListView.builder(
//                             padding: const EdgeInsets.all(16),
//                             itemCount: _filteredCrops.length,
//                             itemBuilder: (context, index) {
//                               final crop = _filteredCrops[index];
//                               return _buildCropListItem(context, crop, isDarkMode);
//                             },
//                           ),
//                         ),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () async {
//           final result = await Navigator.of(context).push(
//             MaterialPageRoute(
//               builder: (context) => const AddNewCropScreen(),
//             ),
//           );
          
//           if (result != null) {
//             await _refreshCrops();
//             if (mounted) {
//               ScaffoldMessenger.of(context).showSnackBar(
//                 const SnackBar(
//                   content: Text('Crop added successfully!'),
//                   backgroundColor: Colors.green,
//                 ),
//               );
//             }
//           }
//         },
//         backgroundColor: const Color(0xFF19E6A2),
//         child: const Icon(Icons.add, color: Colors.white, size: 28),
//       ),
//       floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF11211C).withOpacity(0.8)
//             : const Color(0xFFF6F8F7).withOpacity(0.8),
//         border: Border(
//           bottom: BorderSide(
//             color: isDarkMode ? const Color(0xFF1A2B26) : const Color(0xFFE5E7EB),
//           ),
//         ),
//       ),
//       child: Row(
//         children: [
//           IconButton(
//             onPressed: () => Navigator.pop(context),
//             icon: Icon(
//               Icons.arrow_back_ios,
//               color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//               size: 20,
//             ),
//           ),
//           Expanded(
//             child: Center(
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Text(
//                     'My Crops',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                     ),
//                   ),
//                   if (_isRefreshing) ...[
//                     const SizedBox(width: 8),
//                     SizedBox(
//                       width: 16,
//                       height: 16,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         color: const Color(0xFF19E6A2),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//             decoration: BoxDecoration(
//               color: const Color(0xFF19E6A2).withOpacity(0.1),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: Text(
//               '${_filteredCrops.length}',
//               style: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.bold,
//                 color: Color(0xFF19E6A2),
//               ),
//             ),
//           ),
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
//           color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.05),
//               blurRadius: 4,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Row(
//           children: [
//             const Padding(
//               padding: EdgeInsets.only(left: 16),
//               child: Icon(Icons.search, color: Color(0xFF4E977F), size: 20),
//             ),
//             const SizedBox(width: 8),
//             Expanded(
//               child: TextField(
//                 controller: _searchController,
//                 decoration: const InputDecoration(
//                   hintText: 'Search your crops',
//                   hintStyle: TextStyle(color: Color(0xFF4E977F)),
//                   border: InputBorder.none,
//                 ),
//                 style: TextStyle(
//                   color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                   fontSize: 16,
//                 ),
//               ),
//             ),
//             if (_searchController.text.isNotEmpty)
//               IconButton(
//                 onPressed: () {
//                   _searchController.clear();
//                   _filterCrops();
//                 },
//                 icon: const Icon(Icons.clear, color: Color(0xFF4E977F), size: 18),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildFilterChips(bool isDarkMode) {
//     return SizedBox(
//       height: 40,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         itemCount: _filters.length,
//         itemBuilder: (context, index) {
//           final filter = _filters[index];
//           final isSelected = _selectedFilterIndex == index;
          
//           return Padding(
//             padding: const EdgeInsets.only(right: 12),
//             child: Material(
//               color: isSelected
//                   ? const Color(0xFF19E6A2)
//                   : (isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white),
//               borderRadius: BorderRadius.circular(20),
//               child: InkWell(
//                 onTap: () => _updateFilter(index),
//                 borderRadius: BorderRadius.circular(20),
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(20),
//                     border: isSelected
//                         ? null
//                         : Border.all(
//                             color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFE5E7EB),
//                           ),
//                   ),
//                   child: Text(
//                     filter['label'],
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.w500,
//                       color: isSelected
//                           ? Colors.white
//                           : (isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17)),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildLoadingState(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const CircularProgressIndicator(color: Color(0xFF19E6A2)),
//           const SizedBox(height: 16),
//           Text(
//             'Loading your crops...',
//             style: TextStyle(
//               color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
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
//               color: const Color(0xFF19E6A2).withOpacity(0.3),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'No crops found',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               _searchController.text.isNotEmpty || _selectedFilterIndex != 0
//                   ? 'Try adjusting your search or filters'
//                   : 'Add your first crop to get started!',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
//               ),
//             ),
//             const SizedBox(height: 24),
//             ElevatedButton(
//               onPressed: () async {
//                 final result = await Navigator.of(context).push(
//                   MaterialPageRoute(
//                     builder: (context) => const AddNewCropScreen(),
//                   ),
//                 );
                
//                 if (result != null) {
//                   await _refreshCrops();
//                 }
//               },
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF19E6A2),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
//               ),
//               child: const Text(
//                 'Add Your First Crop',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.white,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

// Widget _buildCropListItem(
//   BuildContext context,
//   Map<String, dynamic> crop,
//   bool isDarkMode,
// ) {
//   final String name = crop['name']?.toString() ?? 'Unnamed Crop';
//   final String status = crop['stage'] ?? crop['status'] ?? 'seedling';
//   final String variety = crop['variety']?.toString() ?? 'Unknown';
//   final String category = crop['category']?.toString() ?? 'vegetable';
//   final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
//   final String? imageUrl = crop['image_url']?.toString();
//   final int quantity = (crop['quantity'] as num?)?.toInt() ?? 1;
//   final String quantityUnit = crop['quantity_unit']?.toString() ?? 'plants';
//   final bool autoUpdateEnabled = crop['auto_update_enabled'] ?? true;
//   final int daysPlanted = crop['days_planted'] ?? 0;
//   final int daysToHarvest = crop['days_to_harvest'] ?? 90;
  
//   final String statusColor = _getStatusColor(status);
//   final String statusLabel = _getStatusLabel(status);

//   return GestureDetector(
//     onTap: () => _showManualProgressDialog(crop),
//     child: Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             width: 72,
//             height: 72,
//             margin: const EdgeInsets.only(right: 16),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(8),
//               color: const Color(0xFF19E6A2).withOpacity(0.1),
//             ),
//             child: imageUrl != null && imageUrl.isNotEmpty
//                 ? Image.network(
//                     imageUrl,
//                     fit: BoxFit.cover,
//                     width: 72,
//                     height: 72,
//                     errorBuilder: (context, error, stackTrace) {
//                       return Container(
//                         color: const Color(0xFF19E6A2).withOpacity(0.1),
//                         child: const Center(
//                           child: Icon(
//                             Icons.eco,
//                             color: Color(0xFF19E6A2),
//                             size: 32,
//                           ),
//                         ),
//                       );
//                     },
//                   )
//                 : const Center(
//                     child: Icon(
//                       Icons.eco,
//                       color: Color(0xFF19E6A2),
//                       size: 32,
//                     ),
//                   ),
//           ),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Row(
//                         children: [
//                           Flexible(
//                             child: Text(
//                               name,
//                               style: TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                                 color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                               ),
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
//                           if (!autoUpdateEnabled)
//                             Container(
//                               margin: const EdgeInsets.only(left: 8),
//                               padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                               decoration: BoxDecoration(
//                                 color: Colors.orange.withOpacity(0.2),
//                                 borderRadius: BorderRadius.circular(8),
//                               ),
//                               child: const Text(
//                                 'Manual',
//                                 style: TextStyle(
//                                   fontSize: 9,
//                                   fontWeight: FontWeight.bold,
//                                   color: Colors.orange,
//                                 ),
//                               ),
//                             ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))).withOpacity(0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         '$quantity $quantityUnit',
//                         style: TextStyle(
//                           fontSize: 10,
//                           fontWeight: FontWeight.bold,
//                           color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 Row(
//                   children: [
//                     Text(
//                       statusLabel,
//                       style: TextStyle(
//                         fontSize: 13,
//                         fontWeight: FontWeight.w600,
//                         color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
//                       ),
//                     ),
//                     if (autoUpdateEnabled && daysPlanted > 0) ...[
//                       const SizedBox(width: 8),
//                       Container(
//                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         child: Text(
//                           'Day $daysPlanted/$daysToHarvest',
//                           style: const TextStyle(
//                             fontSize: 9,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.blue,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   '${_capitalize(category)} • $variety',
//                   style: const TextStyle(
//                     fontSize: 12,
//                     color: Color(0xFF4E977F),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Container(
//                         height: 8,
//                         decoration: BoxDecoration(
//                           color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1),
//                           borderRadius: BorderRadius.circular(4),
//                         ),
//                         child: FractionallySizedBox(
//                           alignment: Alignment.centerLeft,
//                           widthFactor: progress / 100,
//                           child: Container(
//                             decoration: BoxDecoration(
//                               gradient: const LinearGradient(
//                                 colors: [Color(0xFF19E6A2), Color(0xFF39AC86)],
//                               ),
//                               borderRadius: BorderRadius.circular(4),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Text(
//                       '${progress.toInt()}%',
//                       style: TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                         color: isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//           // FIXED: Changed Icons.sliders to Icons.tune
//           Icon(
//             autoUpdateEnabled ? Icons.edit : Icons.tune,
//             color: const Color(0xFF4E977F),
//             size: 20,
//           ),
//         ],
//       ),
//     ),
//   );
// }

//   String _getMonthAbbr(int month) {
//     const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
//     return months[month - 1];
//   }

//   String _capitalize(String s) {
//     if (s.isEmpty) return s;
//     return s[0].toUpperCase() + s.substring(1).toLowerCase();
//   }
// }







// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import 'update_crop_status_screen.dart';
// import 'add_new_crop.dart';
// import '../services/api_service.dart';
// import '../providers/auth_provider.dart';

// class AllCropsScreen extends StatefulWidget {
//   final List<dynamic>? initialCrops;
  
//   const AllCropsScreen({Key? key, this.initialCrops}) : super(key: key);

//   @override
//   State<AllCropsScreen> createState() => _AllCropsScreenState();
// }

// class _AllCropsScreenState extends State<AllCropsScreen> {
//   final ApiService _apiService = ApiService();
  
//   int _selectedFilterIndex = 0;
//   final TextEditingController _searchController = TextEditingController();
  
//   List<dynamic> _allCrops = [];
//   List<dynamic> _filteredCrops = [];
//   bool _isLoading = true;
//   bool _isRefreshing = false;
  
//   final List<Map<String, dynamic>> _filters = [
//     {'label': 'All', 'value': 'all'},
//     {'label': 'Vegetables', 'value': 'vegetable'},
//     {'label': 'Fruits', 'value': 'fruit'},
//     {'label': 'Herbs', 'value': 'herb'},
//     {'label': 'Flowers', 'value': 'flower'},
//     {'label': 'Other', 'value': 'other'},
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _initializeCrops();
//     _searchController.addListener(_filterCrops);
//   }

//   void _initializeCrops() {
//     if (widget.initialCrops != null && widget.initialCrops!.isNotEmpty) {
//       setState(() {
//         _allCrops = widget.initialCrops!;
//         _filteredCrops = _allCrops;
//         _isLoading = false;
//       });
//     } else {
//       _loadCrops();
//     }
//   }

//   Future<void> _loadCrops({bool forceRefresh = false}) async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final cropsResult = await _apiService.getUserCrops();
      
//       if (cropsResult['success'] == true) {
//         setState(() {
//           _allCrops = cropsResult['crops'] ?? [];
//           _filteredCrops = _allCrops;
//         });
//       }
//     } catch (e) {
//       print('❌ Error loading crops: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to load crops'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _refreshCrops() async {
//     if (_isRefreshing) return;

//     setState(() {
//       _isRefreshing = true;
//     });

//     await _loadCrops(forceRefresh: true);

//     setState(() {
//       _isRefreshing = false;
//     });
//   }

//   void _filterCrops() {
//     final query = _searchController.text.toLowerCase();
//     final filterValue = _filters[_selectedFilterIndex]['value'];

//     setState(() {
//       _filteredCrops = _allCrops.where((crop) {
//         final matchesSearch = query.isEmpty || 
//             (crop['name']?.toString().toLowerCase().contains(query) ?? false) ||
//             (crop['variety']?.toString().toLowerCase().contains(query) ?? false);

//         final matchesCategory = filterValue == 'all' || 
//             crop['category'] == filterValue;

//         return matchesSearch && matchesCategory;
//       }).toList();
//     });
//   }

//   void _updateFilter(int index) {
//     setState(() {
//       _selectedFilterIndex = index;
//     });
//     _filterCrops();
//   }

//   String _getStatusColor(String status) {
//     switch (status) {
//       case 'harvest':
//         return '#E59866';
//       case 'fruiting':
//         return '#39AC86';
//       case 'flowering':
//         return '#E59866';
//       case 'vegetative':
//         return '#4299E1';
//       default:
//         return '#808080';
//     }
//   }

//   String _getStatusLabel(String status) {
//     switch (status) {
//       case 'seedling':
//         return 'Seedling';
//       case 'vegetative':
//         return 'Vegetative';
//       case 'flowering':
//         return 'Flowering';
//       case 'fruiting':
//         return 'Fruiting';
//       case 'harvest':
//         return 'Ready to Harvest';
//       case 'dormant':
//         return 'Dormant';
//       default:
//         return _capitalize(status);
//     }
//   }

//   @override
//   void dispose() {
//     _searchController.removeListener(_filterCrops);
//     _searchController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF11211C) : const Color(0xFFF6F8F7),
//       body: SafeArea(
//         child: Column(
//           children: [
//             _buildTopBar(isDarkMode),
//             _buildSearchBar(isDarkMode),
//             _buildFilterChips(isDarkMode),
//             Expanded(
//               child: _isLoading
//                   ? _buildLoadingState(isDarkMode)
//                   : _filteredCrops.isEmpty
//                       ? _buildEmptyState(isDarkMode)
//                       : RefreshIndicator(
//                           onRefresh: _refreshCrops,
//                           color: const Color(0xFF19E6A2),
//                           backgroundColor: isDarkMode ? const Color(0xFF2C3A35) : Colors.white,
//                           child: ListView.builder(
//                             padding: const EdgeInsets.all(16),
//                             itemCount: _filteredCrops.length,
//                             itemBuilder: (context, index) {
//                               final crop = _filteredCrops[index];
//                               return _buildCropListItem(context, crop, isDarkMode);
//                             },
//                           ),
//                         ),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () async {
//           final result = await Navigator.of(context).push(
//             MaterialPageRoute(
//               builder: (context) => const AddNewCropScreen(),
//             ),
//           );
          
//           if (result != null) {
//             await _refreshCrops();
//             if (mounted) {
//               ScaffoldMessenger.of(context).showSnackBar(
//                 const SnackBar(
//                   content: Text('Crop added successfully!'),
//                   backgroundColor: Colors.green,
//                 ),
//               );
//             }
//           }
//         },
//         backgroundColor: const Color(0xFF19E6A2),
//         child: const Icon(Icons.add, color: Colors.white, size: 28),
//       ),
//       floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF11211C).withOpacity(0.8)
//             : const Color(0xFFF6F8F7).withOpacity(0.8),
//         border: Border(
//           bottom: BorderSide(
//             color: isDarkMode ? const Color(0xFF1A2B26) : const Color(0xFFE5E7EB),
//           ),
//         ),
//       ),
//       child: Row(
//         children: [
//           IconButton(
//             onPressed: () => Navigator.pop(context),
//             icon: Icon(
//               Icons.arrow_back_ios,
//               color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//               size: 20,
//             ),
//           ),
//           Expanded(
//             child: Center(
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Text(
//                     'My Crops List',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                     ),
//                   ),
//                   if (_isRefreshing) ...[
//                     const SizedBox(width: 8),
//                     SizedBox(
//                       width: 16,
//                       height: 16,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         color: const Color(0xFF19E6A2),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//             decoration: BoxDecoration(
//               color: const Color(0xFF19E6A2).withOpacity(0.1),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: Text(
//               '${_filteredCrops.length}',
//               style: const TextStyle(
//                 fontSize: 14,
//                 fontWeight: FontWeight.bold,
//                 color: Color(0xFF19E6A2),
//               ),
//             ),
//           ),
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
//           color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.05),
//               blurRadius: 4,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: Row(
//           children: [
//             const Padding(
//               padding: EdgeInsets.only(left: 16),
//               child: Icon(Icons.search, color: Color(0xFF4E977F), size: 20),
//             ),
//             const SizedBox(width: 8),
//             Expanded(
//               child: TextField(
//                 controller: _searchController,
//                 decoration: InputDecoration(
//                   hintText: 'Search your crops',
//                   hintStyle: const TextStyle(color: Color(0xFF4E977F)),
//                   border: InputBorder.none,
//                 ),
//                 style: TextStyle(
//                   color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                   fontSize: 16,
//                 ),
//               ),
//             ),
//             if (_searchController.text.isNotEmpty)
//               IconButton(
//                 onPressed: () {
//                   _searchController.clear();
//                   _filterCrops();
//                 },
//                 icon: const Icon(Icons.clear, color: Color(0xFF4E977F), size: 18),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildFilterChips(bool isDarkMode) {
//     return SizedBox(
//       height: 40,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         itemCount: _filters.length,
//         itemBuilder: (context, index) {
//           final filter = _filters[index];
//           final isSelected = _selectedFilterIndex == index;
          
//           return Padding(
//             padding: const EdgeInsets.only(right: 12),
//             child: Material(
//               color: isSelected
//                   ? const Color(0xFF19E6A2)
//                   : (isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white),
//               borderRadius: BorderRadius.circular(20),
//               child: InkWell(
//                 onTap: () => _updateFilter(index),
//                 borderRadius: BorderRadius.circular(20),
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
//                   decoration: BoxDecoration(
//                     borderRadius: BorderRadius.circular(20),
//                     border: isSelected
//                         ? null
//                         : Border.all(
//                             color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFE5E7EB),
//                           ),
//                   ),
//                   child: Text(
//                     filter['label'],
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.w500,
//                       color: isSelected
//                           ? Colors.white
//                           : (isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17)),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildLoadingState(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           CircularProgressIndicator(color: const Color(0xFF19E6A2)),
//           const SizedBox(height: 16),
//           Text(
//             'Loading your crops...',
//             style: TextStyle(
//               color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
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
//               color: const Color(0xFF19E6A2).withOpacity(0.3),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'No crops found',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               _searchController.text.isNotEmpty || _selectedFilterIndex != 0
//                   ? 'Try adjusting your search or filters'
//                   : 'Add your first crop to get started!',
//               style: TextStyle(
//                 fontSize: 14,
//                 color: isDarkMode ? Colors.white70 : const Color(0xFF4E977F),
//               ),
//             ),
//             const SizedBox(height: 24),
//             ElevatedButton(
//               onPressed: () async {
//                 final result = await Navigator.of(context).push(
//                   MaterialPageRoute(
//                     builder: (context) => const AddNewCropScreen(),
//                   ),
//                 );
                
//                 if (result != null) {
//                   await _refreshCrops();
//                 }
//               },
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF19E6A2),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
//               ),
//               child: const Text(
//                 'Add Your First Crop',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.white,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildCropListItem(
//     BuildContext context,
//     Map<String, dynamic> crop,
//     bool isDarkMode,
//   ) {
//     final String name = crop['name']?.toString() ?? 'Unnamed Crop';
//     final String status = crop['status']?.toString() ?? 'seedling';
//     final String variety = crop['variety']?.toString() ?? 'Unknown';
//     final String category = crop['category']?.toString() ?? 'vegetable';
//     final double progress = (crop['progress'] as num?)?.toDouble() ?? 0.0;
//     final String? imageUrl = crop['image_url']?.toString();
//     final int quantity = (crop['quantity'] as num?)?.toInt() ?? 1;
//     final String quantityUnit = crop['quantity_unit']?.toString() ?? 'plants';
    
//     DateTime? plantingDate;
//     try {
//       plantingDate = crop['planting_date'] != null 
//           ? DateTime.parse(crop['planting_date']) 
//           : null;
//     } catch (e) {
//       plantingDate = null;
//     }
    
//     final String dateStr = plantingDate != null
//         ? '${_getMonthAbbr(plantingDate.month)} ${plantingDate.day}'
//         : 'Not set';
    
//     final String statusColor = _getStatusColor(status);
//     final String statusLabel = _getStatusLabel(status);

//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1),
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             width: 72,
//             height: 72,
//             margin: const EdgeInsets.only(right: 16),
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(8),
//               color: const Color(0xFF19E6A2).withOpacity(0.1),
//             ),
//             child: imageUrl != null && imageUrl.isNotEmpty
//                 ? Image.network(
//                     imageUrl,
//                     fit: BoxFit.cover,
//                     width: 72,
//                     height: 72,
//                     errorBuilder: (context, error, stackTrace) {
//                       print('❌ Image error: $error');
//                       return Container(
//                         color: const Color(0xFF19E6A2).withOpacity(0.1),
//                         child: const Center(
//                           child: Icon(
//                             Icons.broken_image,
//                             color: Color(0xFF19E6A2),
//                             size: 32,
//                           ),
//                         ),
//                       );
//                     },
//                   )
//                 : const Center(
//                     child: Icon(
//                       Icons.eco,
//                       color: Color(0xFF19E6A2),
//                       size: 32,
//                     ),
//                   ),
//         ),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         name,
//                         style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           color: isDarkMode ? Colors.white : const Color(0xFF0E1B17),
//                         ),
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))).withOpacity(0.1),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Text(
//                         '$quantity $quantityUnit',
//                         style: TextStyle(
//                           fontSize: 10,
//                           fontWeight: FontWeight.bold,
//                           color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   statusLabel,
//                   style: TextStyle(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w600,
//                     color: Color(int.parse(statusColor.replaceFirst('#', '0xFF'))),
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   '${_capitalize(category)} • $variety',
//                   style: TextStyle(
//                     fontSize: 12,
//                     color: const Color(0xFF4E977F),
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   'Planted: $dateStr',
//                   style: TextStyle(
//                     fontSize: 10,
//                     color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Container(
//                         height: 6,
//                         decoration: BoxDecoration(
//                           color: isDarkMode ? const Color(0xFF2A3A35) : const Color(0xFFF0F2F1),
//                           borderRadius: BorderRadius.circular(3),
//                         ),
//                         child: FractionallySizedBox(
//                           alignment: Alignment.centerLeft,
//                           widthFactor: progress / 100,
//                           child: Container(
//                             decoration: BoxDecoration(
//                               color: const Color(0xFF19E6A2),
//                               borderRadius: BorderRadius.circular(3),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Text(
//                       '${progress.toInt()}%',
//                       style: TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                         color: isDarkMode ? const Color(0xFFA0B8AF) : const Color(0xFF0E1B17),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.only(left: 8),
//             child: Icon(
//               Icons.chevron_right,
//               color: const Color(0xFF4E977F),
//               size: 20,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   String _getMonthAbbr(int month) {
//     const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
//     return months[month - 1];
//   }

//   String _capitalize(String s) {
//     if (s.isEmpty) return s;
//     return s[0].toUpperCase() + s.substring(1).toLowerCase();
//   }
// }
