import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/ai_service.dart';

class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  int _selectedSegment = 0;
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final ApiService _apiService = ApiService();
  final AIService _aiService = AIService();
  
  // Hardiness Zones Data
  Map<String, dynamic> _hardinessZones = {};
  LatLng? _userLocation;
  String? _userZone;
  bool _isLoadingLocation = true;
  bool _isLoadingZones = true;
  GoogleMapController? _mapController;
  Set<Marker> _zoneMarkers = {};
  
  // Community Q&A
  List<QuestionPost> _questions = [];
  bool _isLoadingQuestions = true;
  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Vegetables', 'Fruits', 'Herbs', 'Pests', 'Soil', 'Watering'];
  
  // Image upload for new post
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _isUploadingImage = false;
  String? _uploadedImageUrl;

  // AI Assistant
  bool _showAIAssistant = false;
  String _aiResponse = '';
  bool _isAILoading = false;
  final TextEditingController _aiQuestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadHardinessZones();
    await _getUserLocation();
    await _loadQuestions();
    await _initializeAIAssistant();
  }

  Future<void> _initializeAIAssistant() async {
    await _aiService.initialize();
    await _trainAIWithExistingData();
  }

  Future<void> _trainAIWithExistingData() async {
    try {
      final result = await _apiService.getCropQuestions(limit: 50);
      if (result['success'] == true && result['questions'] != null) {
        final questions = result['questions'] as List;
        for (var q in questions) {
          final answersResult = await _apiService.getQuestionAnswers(q['id']);
          if (answersResult['success'] == true && answersResult['answers'] != null) {
            final answers = answersResult['answers'] as List;
            final qaText = 'Q: ${q['title']}\nA: ${answers.map((a) => a['text']).join('\nA: ')}';
            await _aiService.trainWithData(qaText);
          }
        }
        print('✅ AI trained with ${questions.length} questions');
      }
    } catch (e) {
      print('Error training AI: $e');
    }
  }

  Future<void> _askAIAssistant() async {
    if (_aiQuestionController.text.trim().isEmpty) return;

    setState(() {
      _isAILoading = true;
      _aiResponse = '';
    });

    try {
      final response = await _aiService.askQuestion(_aiQuestionController.text);
      setState(() {
        _aiResponse = response;
      });
    } catch (e) {
      setState(() {
        _aiResponse = 'Sorry, I encountered an error: $e';
      });
    } finally {
      setState(() {
        _isAILoading = false;
      });
    }
  }

  // UPDATED: Get AI suggestion with dialog
  Future<void> _getAISuggestionForQuestion() async {
    if (_questionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a topic first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAILoading = true;
    });

    try {
      final suggestion = await _aiService.suggestPostContent(_questionController.text);
      _showSuggestionDialog(suggestion);
    } catch (e) {
      print('Error getting AI suggestion: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isAILoading = false;
      });
    }
  }

  // NEW: Show suggestion dialog
  void _showSuggestionDialog(String suggestion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF39AC86)),
            SizedBox(width: 8),
            Text('AI Post Suggestion'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF39AC86).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  suggestion,
                  style: const TextStyle(height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '💡 Tip: You can edit the suggestion before posting',
                style: TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Parse and use the suggestion
              String postContent = suggestion;
              
              // Try to extract title if present
              if (suggestion.contains('Title:') || suggestion.contains('TITLE:')) {
                final lines = suggestion.split('\n');
                for (var line in lines) {
                  if (line.toLowerCase().startsWith('title:')) {
                    postContent = line.substring(6).trim();
                    break;
                  }
                }
              }
              
              _questionController.text = postContent;
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Suggestion added! You can now edit and post.'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF39AC86),
            ),
            child: const Text('Use Suggestion'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHardinessZones() async {
    setState(() {
      _isLoadingZones = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.open-meteo.com/v1/elevation?latitude=39.8283&longitude=-98.5795'),
      );
      
      if (response.statusCode == 200) {
        _hardinessZones = _generateZoneData();
      } else {
        _hardinessZones = _generateZoneData();
      }
    } catch (e) {
      print('Error loading zones: $e');
      _hardinessZones = _generateZoneData();
    } finally {
      setState(() {
        _isLoadingZones = false;
      });
    }
  }

  Map<String, dynamic> _generateZoneData() {
    return {
      'Zone 1': {
        'name': 'Zone 1',
        'tempRange': 'Below -50°F',
        'color': '#2C3E5C',
        'description': 'Extreme cold, very short growing season',
        'suitableCrops': ['Potatoes', 'Kale', 'Carrots', 'Turnips'],
      },
      'Zone 2': {
        'name': 'Zone 2',
        'tempRange': '-50°F to -40°F',
        'color': '#3E5A8A',
        'description': 'Very cold, short growing season',
        'suitableCrops': ['Potatoes', 'Cabbage', 'Peas', 'Radishes'],
      },
      'Zone 3': {
        'name': 'Zone 3',
        'tempRange': '-40°F to -30°F',
        'color': '#4F7AB3',
        'description': 'Cold winters, moderate summers',
        'suitableCrops': ['Broccoli', 'Cauliflower', 'Lettuce', 'Spinach'],
      },
      'Zone 4': {
        'name': 'Zone 4',
        'tempRange': '-30°F to -20°F',
        'color': '#609CD9',
        'description': 'Cold climate, good for hardy vegetables',
        'suitableCrops': ['Tomatoes', 'Peppers', 'Beans', 'Corn'],
      },
      'Zone 5': {
        'name': 'Zone 5',
        'tempRange': '-20°F to -10°F',
        'color': '#71BDFF',
        'description': 'Temperate, diverse growing options',
        'suitableCrops': ['Apples', 'Cherries', 'Peaches', 'Grapes'],
      },
      'Zone 6': {
        'name': 'Zone 6',
        'tempRange': '-10°F to 0°F',
        'color': '#8ACC66',
        'description': 'Mild winters, long growing season',
        'suitableCrops': ['Strawberries', 'Blueberries', 'Raspberries'],
      },
      'Zone 7': {
        'name': 'Zone 7',
        'tempRange': '0°F to 10°F',
        'color': '#A5D95E',
        'description': 'Warm, excellent for fruit trees',
        'suitableCrops': ['Citrus', 'Figs', 'Pomegranates', 'Olives'],
      },
      'Zone 8': {
        'name': 'Zone 8',
        'tempRange': '10°F to 20°F',
        'color': '#BFF055',
        'description': 'Warm, subtropical plants thrive',
        'suitableCrops': ['Avocados', 'Bananas', 'Mangoes', 'Papayas'],
      },
      'Zone 9': {
        'name': 'Zone 9',
        'tempRange': '20°F to 30°F',
        'color': '#D9FF4C',
        'description': 'Hot, year-round growing possible',
        'suitableCrops': ['Tomatoes', 'Eggplant', 'Okra', 'Sweet Potatoes'],
      },
      'Zone 10': {
        'name': 'Zone 10',
        'tempRange': '30°F to 40°F',
        'color': '#F2F242',
        'description': 'Tropical, year-round gardening',
        'suitableCrops': ['Pineapples', 'Coconuts', 'Tropical Fruits'],
      },
    };
  }

  String _getZoneFromCoordinates(double lat, double lng) {
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

  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() {
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
        _userZone = _getZoneFromCoordinates(position.latitude, position.longitude);
        _isLoadingLocation = false;
        _addZoneMarkers();
      });
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _isLoadingLocation = false;
      });
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
    if (_userLocation != null) {
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(_userLocation!, 4),
      );
    }
  }

  // ============ COMMUNITY Q&A METHODS ============

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoadingQuestions = true;
    });

    try {
      final result = await _apiService.getCropQuestions(
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        search: _searchController.text.isEmpty ? null : _searchController.text,
        limit: 20,
        offset: 0,
      );
      
      if (result['success'] == true) {
        setState(() {
          _questions = List<QuestionPost>.from(
            result['questions'].map((q) => QuestionPost.fromJson(q))
          );
        });
      } else {
        if (_questions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to load questions'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading questions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading questions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingQuestions = false;
      });
    }
  }

  Future<void> _likeQuestion(QuestionPost question) async {
    try {
      final result = await _apiService.toggleQuestionLike(question.id);
      
      if (result['success'] == true && mounted) {
        setState(() {
          final index = _questions.indexWhere((q) => q.id == question.id);
          if (index != -1) {
            _questions[index].likes = result['likes'] ?? question.likes;
            _questions[index].userLiked = result['liked'] ?? !question.userLiked;
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['liked'] == true ? 'Liked!' : 'Unliked'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error liking question: $e');
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    
    if (image != null && mounted) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });
    }
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null || _selectedImageBytes == null) return null;
    
    setState(() {
      _isUploadingImage = true;
    });
    
    try {
      final base64Image = base64Encode(_selectedImageBytes!);
      final fileName = _selectedImage!.name;

      final result = await _apiService.uploadImageWeb(base64Image, fileName);
      
      if (result['success'] == true) {
        return result['imageUrl'];
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to upload image'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    } catch (e) {
      print('❌ Upload image error: $e');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _postQuestion() async {
    if (_questionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a question'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoadingQuestions = true;
    });

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _uploadImage();
      }

      final result = await _apiService.postCropQuestion(
        title: _questionController.text.trim(),
        description: '',
        category: _selectedCategory == 'All' ? 'Vegetables' : _selectedCategory,
        imageUrl: imageUrl,
      );
      
      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Question posted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        _questionController.clear();
        _removeSelectedImage();
        
        await _loadQuestions();
        await _trainAIWithExistingData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to post question'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error posting question: $e');
    } finally {
      setState(() {
        _isLoadingQuestions = false;
      });
    }
  }

  Future<void> _postAnswer(String questionId, String answerText) async {
    try {
      final result = await _apiService.postAnswer(
        questionId: questionId,
        text: answerText,
      );
      
      if (result['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Answer posted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        await _loadQuestions();
        await _trainAIWithExistingData();
      }
    } catch (e) {
      print('Error posting answer: $e');
    }
  }

  void _showAskQuestionDialog() {
    _removeSelectedImage();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Create a Post'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCategory == 'All' ? 'Vegetables' : _selectedCategory,
                    items: _categories.where((c) => c != 'All').map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        _selectedCategory = value ?? 'Vegetables';
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _questionController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'What\'s on your mind?',
                      hintText: 'Share your question or experience with the community...',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  ElevatedButton.icon(
                    onPressed: _isAILoading ? null : _getAISuggestionForQuestion,
                    icon: _isAILoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Get AI Suggestion'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39AC86),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (_selectedImageBytes != null)
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                child: Image.memory(
                                  _selectedImageBytes!,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      _selectedImage = null;
                                      _selectedImageBytes = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        
                        if (_selectedImageBytes == null)
                          InkWell(
                            onTap: () async {
                              await _pickImage();
                              setDialogState(() {});
                            },
                            child: Container(
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      size: 32,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Add a photo (optional)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        
                        if (_selectedImageBytes != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: TextButton.icon(
                              onPressed: () async {
                                await _pickImage();
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Change photo'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF39AC86),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _questionController.clear();
                  _removeSelectedImage();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _postQuestion();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF39AC86),
                ),
                child: const Text('Post'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQuestionDetail(QuestionPost question) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuestionDetailSheet(
        question: question,
        onAnswerAdded: (answerText) async {
          await _postAnswer(question.id, answerText);
        },
      ),
    );
  }

  List<QuestionPost> get _filteredQuestions {
    if (_selectedCategory == 'All') {
      return _questions;
    }
    return _questions.where((q) => q.category == _selectedCategory).toList();
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()} years ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()} months ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} days ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hours ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(isDarkMode),
            _buildSegmentedControl(isDarkMode),
            if (_selectedSegment == 1) _buildSearchBar(isDarkMode),
            Expanded(
              child: _selectedSegment == 0
                  ? _buildZoneMapSection(isDarkMode)
                  : _buildCommunitySection(isDarkMode),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedSegment == 1
          ? FloatingActionButton(
              onPressed: _showAskQuestionDialog,
              backgroundColor: const Color(0xFF39AC86),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : _selectedSegment == 0
              ? FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      _showAIAssistant = !_showAIAssistant;
                    });
                  },
                  backgroundColor: const Color(0xFF39AC86),
                  child: const Icon(Icons.assistant, color: Colors.white),
                )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildTopBar(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: isDarkMode 
            ? const Color(0xFF212C28).withOpacity(0.8)
            : const Color(0xFFF9F8F6).withOpacity(0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDarkMode 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.menu,
              color: Color(0xFF39AC86),
              size: 20,
            ),
          ),
          const Text(
            'Garden Community',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDarkMode 
                  ? Colors.white.withOpacity(0.1) 
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.notifications,
              color: isDarkMode ? Colors.white : const Color(0xFF101816),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF39AC86).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedSegment = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedSegment == 0
                      ? (isDarkMode ? const Color(0xFF39AC86) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Hardiness Zones',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _selectedSegment == 0
                          ? (isDarkMode ? Colors.white : const Color(0xFF39AC86))
                          : const Color(0xFF39AC86).withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedSegment = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedSegment == 1
                      ? (isDarkMode ? const Color(0xFF39AC86) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'Community Feed',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _selectedSegment == 1
                          ? (isDarkMode ? Colors.white : const Color(0xFF39AC86))
                          : const Color(0xFF39AC86).withOpacity(0.6),
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

  Widget _buildSearchBar(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.search, color: Color(0xFF39AC86), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search posts...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                  ),
                  border: InputBorder.none,
                ),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                ),
                onChanged: (value) {
                  _loadQuestions();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneMapSection(bool isDarkMode) {
    if (_isLoadingZones || _isLoadingLocation) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF39AC86).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Color(0xFF39AC86),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your Hardiness Zone',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C8A7A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _userZone ?? 'Not detected',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_userZone != null && _hardinessZones[_userZone] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Color(int.parse(_hardinessZones[_userZone]!['color'].replaceFirst('#', '0xFF'))).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _userZone!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(int.parse(_hardinessZones[_userZone]!['color'].replaceFirst('#', '0xFF'))),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_userZone != null)
                      Text(
                        _hardinessZones[_userZone]?['description'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
                        ),
                      ),
                  ],
                ),
              ),

              Container(
                height: 350,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: CameraPosition(
                      target: _userLocation ?? const LatLng(39.8283, -98.5795),
                      zoom: 4,
                    ),
                    markers: {
                      if (_userLocation != null)
                        Marker(
                          markerId: const MarkerId('user-location'),
                          position: _userLocation!,
                          infoWindow: const InfoWindow(
                            title: 'Your Location',
                            snippet: 'Your hardiness zone',
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                        ),
                      ..._zoneMarkers,
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: true,
                    zoomGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                    tiltGesturesEnabled: true,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hardiness Zones',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.5,
                      ),
                      itemCount: _hardinessZones.keys.length,
                      itemBuilder: (context, index) {
                        final zoneName = _hardinessZones.keys.elementAt(index);
                        final zone = _hardinessZones[zoneName]!;
                        final isUserZone = zoneName == _userZone;
                        final zoneColor = Color(int.parse(zone['color'].replaceFirst('#', '0xFF')));
                        
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUserZone ? zoneColor.withOpacity(0.2) : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isUserZone ? zoneColor : Colors.black.withOpacity(0.05),
                              width: isUserZone ? 2 : 1,
                            ),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: zoneColor,
                                    ),
                                  ),
                                  if (isUserZone)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF39AC86),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'YOUR ZONE',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                zone['tempRange'],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Best crops:',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: zoneColor,
                                ),
                              ),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: (zone['suitableCrops'] as List).take(3).map((crop) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: zoneColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      crop,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: zoneColor,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_showAIAssistant)
          Positioned(
            bottom: 80,
            right: 16,
            left: 16,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF2C3E35) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF39AC86),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.assistant, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text(
                            'AI Garden Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _showAIAssistant = false;
                              });
                            },
                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                          IconButton(
                            onPressed: _isAILoading ? null : () async {
                              if (_aiQuestionController.text.isNotEmpty) {
                                await _askAIAssistant();
                              }
                            },
                            icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  _aiResponse.isEmpty 
                                      ? 'Ask me anything about gardening, crops, pests, or farming techniques!'
                                      : _aiResponse,
                                  style: TextStyle(
                                    color: isDarkMode ? Colors.white : const Color(0xFF101816),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _aiQuestionController,
                                    decoration: InputDecoration(
                                      hintText: 'Ask a question...',
                                      hintStyle: TextStyle(
                                        color: isDarkMode ? Colors.white70 : Colors.grey[600],
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    style: TextStyle(
                                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                                    ),
                                    onSubmitted: (_) => _askAIAssistant(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF39AC86),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed: _isAILoading ? null : _askAIAssistant,
                                    icon: _isAILoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.send, color: Colors.white, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCommunitySection(bool isDarkMode) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];
              final isSelected = _selectedCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  selectedColor: const Color(0xFF39AC86),
                  backgroundColor: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : (isDarkMode ? Colors.white : const Color(0xFF101816)),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category;
                      _loadQuestions();
                    });
                  },
                ),
              );
            },
          ),
        ),
        
        Expanded(
          child: _isLoadingQuestions
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF39AC86)))
              : _filteredQuestions.isEmpty
                  ? _buildEmptyState(isDarkMode)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredQuestions.length,
                      itemBuilder: (context, index) {
                        final question = _filteredQuestions[index];
                        return _buildPostCard(question, isDarkMode);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPostCard(QuestionPost question, bool isDarkMode) {
    final timeAgo = _getTimeAgo(question.createdAt);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: question.solved ? const Color(0xFF39AC86) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (question.authorImage.isNotEmpty)
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: NetworkImage(question.authorImage),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF39AC86).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        question.author[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF39AC86),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.author,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : const Color(0xFF101816),
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFF5C8A7A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF39AC86).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              question.category,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF39AC86),
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
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: () => _showQuestionDetail(question),
              child: Text(
                question.title,
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                  height: 1.4,
                ),
              ),
            ),
          ),
          
          if (question.imageUrl != null && question.imageUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showQuestionDetail(question),
              child: ClipRRect(
                child: Image.network(
                  question.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 50),
                  ),
                ),
              ),
            ),
          ],
          
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _likeQuestion(question),
                  child: Row(
                    children: [
                      Icon(
                        question.userLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 18,
                        color: question.userLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${question.likes}',
                        style: TextStyle(
                          fontSize: 13,
                          color: question.userLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                
                GestureDetector(
                  onTap: () => _showQuestionDetail(question),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 18, color: const Color(0xFF5C8A7A)),
                      const SizedBox(width: 6),
                      Text(
                        '${question.answers} comments',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5C8A7A),
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (question.solved) ...[
                  const Spacer(),
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF39AC86)),
                  const SizedBox(width: 4),
                  const Text('Solved', style: TextStyle(fontSize: 12, color: Color(0xFF39AC86))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.question_answer, size: 80, color: const Color(0xFF39AC86).withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No posts yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : const Color(0xFF101816))),
          const SizedBox(height: 8),
          const Text('Be the first to share something with the community!', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showAskQuestionDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF39AC86),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Create a Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _searchController.dispose();
    _replyController.dispose();
    _aiQuestionController.dispose();
    super.dispose();
  }
}

// Question Post Model
class QuestionPost {
  final String id;
  final String title;
  final String description;
  final String category;
  final String author;
  final String authorImage;
  int answers;
  int likes;
  final DateTime createdAt;
  bool solved;
  final String? imageUrl;
  bool userLiked;

  QuestionPost({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.author,
    required this.authorImage,
    required this.answers,
    required this.likes,
    required this.createdAt,
    required this.solved,
    this.imageUrl,
    this.userLiked = false,
  });

  factory QuestionPost.fromJson(Map<String, dynamic> json) {
    return QuestionPost(
      id: json['id'],
      title: json['title'],
      description: json['description'] ?? '',
      category: json['category'],
      author: json['author'],
      authorImage: json['authorImage'] ?? '',
      answers: json['answers'] ?? 0,
      likes: json['likes'] ?? 0,
      createdAt: DateTime.parse(json['createdAt']),
      solved: json['solved'] ?? false,
      imageUrl: json['image_url'],
      userLiked: json['userLiked'] ?? false,
    );
  }
}

// Question Detail Sheet
class _QuestionDetailSheet extends StatefulWidget {
  final QuestionPost question;
  final Function(String) onAnswerAdded;

  const _QuestionDetailSheet({
    required this.question,
    required this.onAnswerAdded,
  });

  @override
  State<_QuestionDetailSheet> createState() => _QuestionDetailSheetState();
}

class _QuestionDetailSheetState extends State<_QuestionDetailSheet> {
  final TextEditingController _replyController = TextEditingController();
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _answers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _apiService.getQuestionAnswers(widget.question.id);
      if (result['success'] == true) {
        setState(() {
          _answers = List<Map<String, dynamic>>.from(result['answers'] ?? []);
        });
      }
    } catch (e) {
      print('Error loading answers: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _likeAnswer(Map<String, dynamic> answer) async {
    try {
      final result = await _apiService.toggleAnswerLike(answer['id']);
      
      if (result['success'] == true && mounted) {
        setState(() {
          final index = _answers.indexWhere((a) => a['id'] == answer['id']);
          if (index != -1) {
            _answers[index]['likes'] = result['likes'] ?? answer['likes'];
            _answers[index]['userLiked'] = result['liked'] ?? !(answer['userLiked'] ?? false);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['liked'] == true ? 'Liked!' : 'Unliked'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error liking answer: $e');
    }
  }

  void _addAnswer() {
    if (_replyController.text.trim().isEmpty) return;

    final answerText = _replyController.text.trim();
    _replyController.clear();
    widget.onAnswerAdded(answerText);
    _loadAnswers();
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      widget.question.authorImage.isNotEmpty
                          ? CircleAvatar(radius: 24, backgroundImage: NetworkImage(widget.question.authorImage))
                          : Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF39AC86).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  widget.question.author[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF39AC86),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.question.author,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDarkMode ? Colors.white : const Color(0xFF101816),
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  _getTimeAgo(widget.question.createdAt),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF39AC86).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.question.category,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF39AC86),
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
                  const SizedBox(height: 16),
                  
                  Text(
                    widget.question.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                      height: 1.4,
                    ),
                  ),
                  
                  if (widget.question.imageUrl != null && widget.question.imageUrl!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        widget.question.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 300,
                            color: Colors.grey[300],
                            child: const Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF5C8A7A)),
                      const SizedBox(width: 8),
                      Text(
                        '${_answers.length} Comments',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF5C8A7A),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _answers.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  'No comments yet. Be the first to comment!',
                                  style: TextStyle(color: Color(0xFF5C8A7A)),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _answers.length,
                              itemBuilder: (context, index) {
                                final answer = _answers[index];
                                final timeAgo = answer['createdAt'] is DateTime 
                                    ? _getTimeAgo(answer['createdAt']) 
                                    : 'Just now';
                                final isLiked = answer['userLiked'] ?? false;
                                
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      answer['authorImage'] != null && answer['authorImage'].isNotEmpty
                                          ? CircleAvatar(radius: 20, backgroundImage: NetworkImage(answer['authorImage']))
                                          : Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF39AC86).withOpacity(0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  answer['author'][0].toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Color(0xFF39AC86),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              answer['author'],
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isDarkMode ? Colors.white : const Color(0xFF101816),
                                              ),
                                            ),
                                            Text(
                                              timeAgo,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF5C8A7A),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              answer['text'],
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: isDarkMode ? Colors.white70 : const Color(0xFF101816),
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            GestureDetector(
                                              onTap: () => _likeAnswer(answer),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                                                    size: 14,
                                                    color: isLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${answer['likes']}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ],
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1A2A25) : Colors.white,
              border: Border(
                top: BorderSide(color: Colors.black.withOpacity(0.05)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white.withOpacity(0.1) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _replyController,
                      decoration: const InputDecoration(
                        hintText: 'Write a comment...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF39AC86),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _addAnswer,
                    icon: const Icon(Icons.send, size: 20, color: Colors.white),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}












// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:http/http.dart' as http;
// import 'package:provider/provider.dart';
// import '../providers/auth_provider.dart';
// import '../services/api_service.dart';
// import '../services/ai_service.dart';

// class GuidesScreen extends StatefulWidget {
//   const GuidesScreen({super.key});

//   @override
//   State<GuidesScreen> createState() => _GuidesScreenState();
// }

// class _GuidesScreenState extends State<GuidesScreen> {
//   int _selectedSegment = 0;
//   final TextEditingController _questionController = TextEditingController();
//   final TextEditingController _searchController = TextEditingController();
//   final TextEditingController _replyController = TextEditingController();
//   final ApiService _apiService = ApiService();
//   final AIService _aiService = AIService();
  
//   // Hardiness Zones Data
//   Map<String, dynamic> _hardinessZones = {};
//   LatLng? _userLocation;
//   String? _userZone;
//   bool _isLoadingLocation = true;
//   bool _isLoadingZones = true;
//   GoogleMapController? _mapController;
//   Set<Marker> _zoneMarkers = {};
  
//   // Community Q&A
//   List<QuestionPost> _questions = [];
//   bool _isLoadingQuestions = true;
//   String _selectedCategory = 'All';
//   final List<String> _categories = ['All', 'Vegetables', 'Fruits', 'Herbs', 'Pests', 'Soil', 'Watering'];
  
//   // Image upload for new post
//   XFile? _selectedImage;
//   Uint8List? _selectedImageBytes;
//   bool _isUploadingImage = false;
//   String? _uploadedImageUrl;

//   // AI Assistant
//   bool _showAIAssistant = false;
//   String _aiResponse = '';
//   bool _isAILoading = false;
//   final TextEditingController _aiQuestionController = TextEditingController();

//   @override
//   void initState() {
//     super.initState();
//     _initialize();
//   }

//   Future<void> _initialize() async {
//     await _loadHardinessZones();
//     await _getUserLocation();
//     await _loadQuestions();
//     await _initializeAIAssistant();
//   }

//   Future<void> _initializeAIAssistant() async {
//     await _aiService.initialize();
//     await _trainAIWithExistingData();
//   }

//   Future<void> _trainAIWithExistingData() async {
//     try {
//       final result = await _apiService.getCropQuestions(limit: 50);
//       if (result['success'] == true && result['questions'] != null) {
//         final questions = result['questions'] as List;
//         for (var q in questions) {
//           final answersResult = await _apiService.getQuestionAnswers(q['id']);
//           if (answersResult['success'] == true && answersResult['answers'] != null) {
//             final answers = answersResult['answers'] as List;
//             final qaText = 'Q: ${q['title']}\nA: ${answers.map((a) => a['text']).join('\nA: ')}';
//             await _aiService.trainWithData(qaText);
//           }
//         }
//         print('✅ AI trained with ${questions.length} questions');
//       }
//     } catch (e) {
//       print('Error training AI: $e');
//     }
//   }

//   Future<void> _askAIAssistant() async {
//     if (_aiQuestionController.text.trim().isEmpty) return;

//     setState(() {
//       _isAILoading = true;
//       _aiResponse = '';
//     });

//     try {
//       final response = await _aiService.askQuestion(_aiQuestionController.text);
//       setState(() {
//         _aiResponse = response;
//       });
//     } catch (e) {
//       setState(() {
//         _aiResponse = 'Sorry, I encountered an error: $e';
//       });
//     } finally {
//       setState(() {
//         _isAILoading = false;
//       });
//     }
//   }

//   Future<void> _getAISuggestionForQuestion() async {
//     if (_questionController.text.trim().isEmpty) return;

//     setState(() {
//       _isAILoading = true;
//     });

//     try {
//       final suggestion = await _aiService.suggestAnswer(_questionController.text);
//       setState(() {
//         _aiResponse = suggestion;
//         _showAIAssistant = true;
//       });
      
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('AI suggestion ready! Check the AI Assistant.'),
//           backgroundColor: const Color(0xFF39AC86),
//           duration: const Duration(seconds: 3),
//         ),
//       );
//     } catch (e) {
//       print('Error getting AI suggestion: $e');
//     } finally {
//       setState(() {
//         _isAILoading = false;
//       });
//     }
//   }

//   Future<void> _loadHardinessZones() async {
//     setState(() {
//       _isLoadingZones = true;
//     });

//     try {
//       final response = await http.get(
//         Uri.parse('https://api.open-meteo.com/v1/elevation?latitude=39.8283&longitude=-98.5795'),
//       );
      
//       if (response.statusCode == 200) {
//         _hardinessZones = _generateZoneData();
//       } else {
//         _hardinessZones = _generateZoneData();
//       }
//     } catch (e) {
//       print('Error loading zones: $e');
//       _hardinessZones = _generateZoneData();
//     } finally {
//       setState(() {
//         _isLoadingZones = false;
//       });
//     }
//   }

//   Map<String, dynamic> _generateZoneData() {
//     return {
//       'Zone 1': {
//         'name': 'Zone 1',
//         'tempRange': 'Below -50°F',
//         'color': '#2C3E5C',
//         'description': 'Extreme cold, very short growing season',
//         'suitableCrops': ['Potatoes', 'Kale', 'Carrots', 'Turnips'],
//       },
//       'Zone 2': {
//         'name': 'Zone 2',
//         'tempRange': '-50°F to -40°F',
//         'color': '#3E5A8A',
//         'description': 'Very cold, short growing season',
//         'suitableCrops': ['Potatoes', 'Cabbage', 'Peas', 'Radishes'],
//       },
//       'Zone 3': {
//         'name': 'Zone 3',
//         'tempRange': '-40°F to -30°F',
//         'color': '#4F7AB3',
//         'description': 'Cold winters, moderate summers',
//         'suitableCrops': ['Broccoli', 'Cauliflower', 'Lettuce', 'Spinach'],
//       },
//       'Zone 4': {
//         'name': 'Zone 4',
//         'tempRange': '-30°F to -20°F',
//         'color': '#609CD9',
//         'description': 'Cold climate, good for hardy vegetables',
//         'suitableCrops': ['Tomatoes', 'Peppers', 'Beans', 'Corn'],
//       },
//       'Zone 5': {
//         'name': 'Zone 5',
//         'tempRange': '-20°F to -10°F',
//         'color': '#71BDFF',
//         'description': 'Temperate, diverse growing options',
//         'suitableCrops': ['Apples', 'Cherries', 'Peaches', 'Grapes'],
//       },
//       'Zone 6': {
//         'name': 'Zone 6',
//         'tempRange': '-10°F to 0°F',
//         'color': '#8ACC66',
//         'description': 'Mild winters, long growing season',
//         'suitableCrops': ['Strawberries', 'Blueberries', 'Raspberries'],
//       },
//       'Zone 7': {
//         'name': 'Zone 7',
//         'tempRange': '0°F to 10°F',
//         'color': '#A5D95E',
//         'description': 'Warm, excellent for fruit trees',
//         'suitableCrops': ['Citrus', 'Figs', 'Pomegranates', 'Olives'],
//       },
//       'Zone 8': {
//         'name': 'Zone 8',
//         'tempRange': '10°F to 20°F',
//         'color': '#BFF055',
//         'description': 'Warm, subtropical plants thrive',
//         'suitableCrops': ['Avocados', 'Bananas', 'Mangoes', 'Papayas'],
//       },
//       'Zone 9': {
//         'name': 'Zone 9',
//         'tempRange': '20°F to 30°F',
//         'color': '#D9FF4C',
//         'description': 'Hot, year-round growing possible',
//         'suitableCrops': ['Tomatoes', 'Eggplant', 'Okra', 'Sweet Potatoes'],
//       },
//       'Zone 10': {
//         'name': 'Zone 10',
//         'tempRange': '30°F to 40°F',
//         'color': '#F2F242',
//         'description': 'Tropical, year-round gardening',
//         'suitableCrops': ['Pineapples', 'Coconuts', 'Tropical Fruits'],
//       },
//     };
//   }

//   String _getZoneFromCoordinates(double lat, double lng) {
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

//   Future<void> _getUserLocation() async {
//     setState(() {
//       _isLoadingLocation = true;
//     });

//     try {
//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//       }
      
//       if (permission == LocationPermission.deniedForever) {
//         setState(() {
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
//         _userZone = _getZoneFromCoordinates(position.latitude, position.longitude);
//         _isLoadingLocation = false;
//         _addZoneMarkers();
//       });
//     } catch (e) {
//       print('Error getting location: $e');
//       setState(() {
//         _isLoadingLocation = false;
//       });
//     }
//   }

//   void _addZoneMarkers() {
//     Set<Marker> markers = {};

//     _hardinessZones.forEach((zoneName, zoneData) {
//       markers.add(
//         Marker(
//           markerId: MarkerId(zoneName),
//           position: _getZoneCenter(zoneName),
//           infoWindow: InfoWindow(
//             title: zoneName,
//             snippet: zoneData['description'],
//           ),
//           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//         ),
//       );
//     });

//     setState(() {
//       _zoneMarkers = markers;
//     });
//   }

//   LatLng _getZoneCenter(String zoneName) {
//     switch(zoneName) {
//       case 'Zone 1': return const LatLng(65, -100);
//       case 'Zone 2': return const LatLng(57.5, -100);
//       case 'Zone 3': return const LatLng(52.5, -100);
//       case 'Zone 4': return const LatLng(47.5, -100);
//       case 'Zone 5': return const LatLng(42.5, -100);
//       case 'Zone 6': return const LatLng(37.5, -100);
//       case 'Zone 7': return const LatLng(32.5, -100);
//       case 'Zone 8': return const LatLng(27.5, -100);
//       case 'Zone 9': return const LatLng(22.5, -100);
//       case 'Zone 10': return const LatLng(10, -100);
//       default: return const LatLng(39.8283, -98.5795);
//     }
//   }

//   void _onMapCreated(GoogleMapController controller) {
//     _mapController = controller;
//     if (_userLocation != null) {
//       controller.animateCamera(
//         CameraUpdate.newLatLngZoom(_userLocation!, 4),
//       );
//     }
//   }

//   // ============ COMMUNITY Q&A METHODS ============

//   Future<void> _loadQuestions() async {
//     setState(() {
//       _isLoadingQuestions = true;
//     });

//     try {
//       final result = await _apiService.getCropQuestions(
//         category: _selectedCategory == 'All' ? null : _selectedCategory,
//         search: _searchController.text.isEmpty ? null : _searchController.text,
//         limit: 20,
//         offset: 0,
//       );
      
//       if (result['success'] == true) {
//         setState(() {
//           _questions = List<QuestionPost>.from(
//             result['questions'].map((q) => QuestionPost.fromJson(q))
//           );
//         });
//       } else {
//         if (_questions.isEmpty) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(result['error'] ?? 'Failed to load questions'),
//               backgroundColor: Colors.red,
//             ),
//           );
//         }
//       }
//     } catch (e) {
//       print('Error loading questions: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Error loading questions: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } finally {
//       setState(() {
//         _isLoadingQuestions = false;
//       });
//     }
//   }

//   Future<void> _likeQuestion(QuestionPost question) async {
//     try {
//       final result = await _apiService.toggleQuestionLike(question.id);
      
//       if (result['success'] == true && mounted) {
//         setState(() {
//           final index = _questions.indexWhere((q) => q.id == question.id);
//           if (index != -1) {
//             _questions[index].likes = result['likes'] ?? question.likes;
//             _questions[index].userLiked = result['liked'] ?? !question.userLiked;
//           }
//         });
        
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(result['liked'] == true ? 'Liked!' : 'Unliked'),
//             backgroundColor: Colors.green,
//             duration: const Duration(seconds: 1),
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error liking question: $e');
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
//       });
//     }
//   }

//   void _removeSelectedImage() {
//     setState(() {
//       _selectedImage = null;
//       _selectedImageBytes = null;
//     });
//   }

//   Future<String?> _uploadImage() async {
//     if (_selectedImage == null || _selectedImageBytes == null) return null;
    
//     setState(() {
//       _isUploadingImage = true;
//     });
    
//     try {
//       final base64Image = base64Encode(_selectedImageBytes!);
//       final fileName = _selectedImage!.name;

//       final result = await _apiService.uploadImageWeb(base64Image, fileName);
      
//       if (result['success'] == true) {
//         return result['imageUrl'];
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
//       return null;
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isUploadingImage = false;
//         });
//       }
//     }
//   }

//   Future<void> _postQuestion() async {
//     if (_questionController.text.trim().isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Please enter a question'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//       return;
//     }

//     setState(() {
//       _isLoadingQuestions = true;
//     });

//     try {
//       String? imageUrl;
//       if (_selectedImage != null) {
//         imageUrl = await _uploadImage();
//       }

//       final result = await _apiService.postCropQuestion(
//         title: _questionController.text.trim(),
//         description: '',
//         category: _selectedCategory == 'All' ? 'Vegetables' : _selectedCategory,
//         imageUrl: imageUrl,
//       );
      
//       if (result['success'] == true && mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Question posted successfully!'),
//             backgroundColor: Colors.green,
//           ),
//         );
        
//         _questionController.clear();
//         _removeSelectedImage();
        
//         await _loadQuestions();
//         await _trainAIWithExistingData();
//       } else if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(result['error'] ?? 'Failed to post question'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error posting question: $e');
//     } finally {
//       setState(() {
//         _isLoadingQuestions = false;
//       });
//     }
//   }

//   Future<void> _postAnswer(String questionId, String answerText) async {
//     try {
//       final result = await _apiService.postAnswer(
//         questionId: questionId,
//         text: answerText,
//       );
      
//       if (result['success'] == true && mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Answer posted successfully!'),
//             backgroundColor: Colors.green,
//           ),
//         );
        
//         await _loadQuestions();
//         await _trainAIWithExistingData();
//       }
//     } catch (e) {
//       print('Error posting answer: $e');
//     }
//   }

//   void _showAskQuestionDialog() {
//     // Reset image selection when opening dialog
//     _removeSelectedImage();
    
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setDialogState) {
//           return AlertDialog(
//             title: const Text('Create a Post'),
//             content: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   // Category Dropdown
//                   DropdownButtonFormField<String>(
//                     value: _selectedCategory == 'All' ? 'Vegetables' : _selectedCategory,
//                     items: _categories.where((c) => c != 'All').map((category) {
//                       return DropdownMenuItem(
//                         value: category,
//                         child: Text(category),
//                       );
//                     }).toList(),
//                     onChanged: (value) {
//                       setDialogState(() {
//                         _selectedCategory = value ?? 'Vegetables';
//                       });
//                     },
//                     decoration: const InputDecoration(
//                       labelText: 'Category',
//                       border: OutlineInputBorder(),
//                     ),
//                   ),
//                   const SizedBox(height: 16),
                  
//                   // Question Text Field
//                   TextField(
//                     controller: _questionController,
//                     maxLines: 4,
//                     decoration: const InputDecoration(
//                       labelText: 'What\'s on your mind?',
//                       hintText: 'Share your question or experience with the community...',
//                       border: OutlineInputBorder(),
//                       alignLabelWithHint: true,
//                     ),
//                   ),
//                   const SizedBox(height: 16),
                  
//                   // AI Suggestion Button
//                   ElevatedButton.icon(
//                     onPressed: _getAISuggestionForQuestion,
//                     icon: const Icon(Icons.auto_awesome, size: 18),
//                     label: const Text('Get AI Suggestion'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xFF39AC86),
//                       foregroundColor: Colors.white,
//                     ),
//                   ),
//                   const SizedBox(height: 16),
                  
//                   // Image Picker Section (Like Facebook)
//                   Container(
//                     decoration: BoxDecoration(
//                       border: Border.all(color: Colors.grey[300]!),
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: Column(
//                       children: [
//                         // Image preview if selected
//                         if (_selectedImageBytes != null)
//                           Stack(
//                             children: [
//                               ClipRRect(
//                                 borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
//                                 child: Image.memory(
//                                   _selectedImageBytes!,
//                                   height: 200,
//                                   width: double.infinity,
//                                   fit: BoxFit.cover,
//                                 ),
//                               ),
//                               Positioned(
//                                 top: 8,
//                                 right: 8,
//                                 child: GestureDetector(
//                                   onTap: () {
//                                     setDialogState(() {
//                                       _selectedImage = null;
//                                       _selectedImageBytes = null;
//                                     });
//                                   },
//                                   child: Container(
//                                     padding: const EdgeInsets.all(6),
//                                     decoration: const BoxDecoration(
//                                       color: Colors.black54,
//                                       shape: BoxShape.circle,
//                                     ),
//                                     child: const Icon(
//                                       Icons.close,
//                                       color: Colors.white,
//                                       size: 16,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
                        
//                         // Add Photo Button
//                         if (_selectedImageBytes == null)
//                           InkWell(
//                             onTap: () async {
//                               await _pickImage();
//                               setDialogState(() {});
//                             },
//                             child: Container(
//                               height: 100,
//                               decoration: BoxDecoration(
//                                 color: Colors.grey[100],
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                               child: Center(
//                                 child: Column(
//                                   mainAxisAlignment: MainAxisAlignment.center,
//                                   children: [
//                                     Icon(
//                                       Icons.add_photo_alternate,
//                                       size: 32,
//                                       color: Colors.grey[600],
//                                     ),
//                                     const SizedBox(height: 8),
//                                     Text(
//                                       'Add a photo (optional)',
//                                       style: TextStyle(
//                                         fontSize: 12,
//                                         color: Colors.grey[600],
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ),
//                           ),
                        
//                         // Change Photo Button
//                         if (_selectedImageBytes != null)
//                           Padding(
//                             padding: const EdgeInsets.all(8),
//                             child: TextButton.icon(
//                               onPressed: () async {
//                                 await _pickImage();
//                                 setDialogState(() {});
//                               },
//                               icon: const Icon(Icons.edit, size: 16),
//                               label: const Text('Change photo'),
//                               style: TextButton.styleFrom(
//                                 foregroundColor: const Color(0xFF39AC86),
//                               ),
//                             ),
//                           ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   _questionController.clear();
//                   _removeSelectedImage();
//                   Navigator.pop(context);
//                 },
//                 child: const Text('Cancel'),
//               ),
//               ElevatedButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _postQuestion();
//                 },
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF39AC86),
//                 ),
//                 child: const Text('Post'),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//   }

//   void _showQuestionDetail(QuestionPost question) {
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (context) => _QuestionDetailSheet(
//         question: question,
//         onAnswerAdded: (answerText) async {
//           await _postAnswer(question.id, answerText);
//         },
//       ),
//     );
//   }

//   List<QuestionPost> get _filteredQuestions {
//     if (_selectedCategory == 'All') {
//       return _questions;
//     }
//     return _questions.where((q) => q.category == _selectedCategory).toList();
//   }

//   String _getTimeAgo(DateTime date) {
//     final now = DateTime.now();
//     final diff = now.difference(date);
    
//     if (diff.inDays > 365) {
//       return '${(diff.inDays / 365).floor()} years ago';
//     } else if (diff.inDays > 30) {
//       return '${(diff.inDays / 30).floor()} months ago';
//     } else if (diff.inDays > 0) {
//       return '${diff.inDays} days ago';
//     } else if (diff.inHours > 0) {
//       return '${diff.inHours} hours ago';
//     } else if (diff.inMinutes > 0) {
//       return '${diff.inMinutes} minutes ago';
//     } else {
//       return 'Just now';
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//       body: SafeArea(
//         bottom: false,
//         child: Column(
//           children: [
//             _buildTopBar(isDarkMode),
//             _buildSegmentedControl(isDarkMode),
//             if (_selectedSegment == 1) _buildSearchBar(isDarkMode),
//             Expanded(
//               child: _selectedSegment == 0
//                   ? _buildZoneMapSection(isDarkMode)
//                   : _buildCommunitySection(isDarkMode),
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: _selectedSegment == 1
//           ? FloatingActionButton(
//               onPressed: _showAskQuestionDialog,
//               backgroundColor: const Color(0xFF39AC86),
//               child: const Icon(Icons.add, color: Colors.white),
//             )
//           : _selectedSegment == 0
//               ? FloatingActionButton(
//                   onPressed: () {
//                     setState(() {
//                       _showAIAssistant = !_showAIAssistant;
//                     });
//                   },
//                   backgroundColor: const Color(0xFF39AC86),
//                   child: const Icon(Icons.assistant, color: Colors.white),
//                 )
//               : null,
//       floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     );
//   }

//   Widget _buildTopBar(bool isDarkMode) {
//     return Container(
//       padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
//       decoration: BoxDecoration(
//         color: isDarkMode 
//             ? const Color(0xFF212C28).withOpacity(0.8)
//             : const Color(0xFFF9F8F6).withOpacity(0.8),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Container(
//             width: 40,
//             height: 40,
//             decoration: BoxDecoration(
//               color: isDarkMode 
//                   ? Colors.white.withOpacity(0.1) 
//                   : Colors.white,
//               borderRadius: BorderRadius.circular(20),
//             ),
//             child: const Icon(
//               Icons.menu,
//               color: Color(0xFF39AC86),
//               size: 20,
//             ),
//           ),
//           const Text(
//             'Garden Community',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           Container(
//             width: 40,
//             height: 40,
//             decoration: BoxDecoration(
//               color: isDarkMode 
//                   ? Colors.white.withOpacity(0.1) 
//                   : Colors.white,
//               borderRadius: BorderRadius.circular(20),
//             ),
//             child: Icon(
//               Icons.notifications,
//               color: isDarkMode ? Colors.white : const Color(0xFF101816),
//               size: 20,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSegmentedControl(bool isDarkMode) {
//     return Container(
//       margin: const EdgeInsets.all(16),
//       padding: const EdgeInsets.all(4),
//       decoration: BoxDecoration(
//         color: const Color(0xFF39AC86).withOpacity(0.1),
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: Row(
//         children: [
//           Expanded(
//             child: GestureDetector(
//               onTap: () => setState(() => _selectedSegment = 0),
//               child: Container(
//                 padding: const EdgeInsets.symmetric(vertical: 12),
//                 decoration: BoxDecoration(
//                   color: _selectedSegment == 0
//                       ? (isDarkMode ? const Color(0xFF39AC86) : Colors.white)
//                       : Colors.transparent,
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Center(
//                   child: Text(
//                     'Hardiness Zones',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                       color: _selectedSegment == 0
//                           ? (isDarkMode ? Colors.white : const Color(0xFF39AC86))
//                           : const Color(0xFF39AC86).withOpacity(0.6),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           Expanded(
//             child: GestureDetector(
//               onTap: () => setState(() => _selectedSegment = 1),
//               child: Container(
//                 padding: const EdgeInsets.symmetric(vertical: 12),
//                 decoration: BoxDecoration(
//                   color: _selectedSegment == 1
//                       ? (isDarkMode ? const Color(0xFF39AC86) : Colors.white)
//                       : Colors.transparent,
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Center(
//                   child: Text(
//                     'Community Feed',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                       color: _selectedSegment == 1
//                           ? (isDarkMode ? Colors.white : const Color(0xFF39AC86))
//                           : const Color(0xFF39AC86).withOpacity(0.6),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildSearchBar(bool isDarkMode) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       child: Container(
//         height: 48,
//         decoration: BoxDecoration(
//           color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Row(
//           children: [
//             const SizedBox(width: 16),
//             const Icon(Icons.search, color: Color(0xFF39AC86), size: 20),
//             const SizedBox(width: 8),
//             Expanded(
//               child: TextField(
//                 controller: _searchController,
//                 decoration: InputDecoration(
//                   hintText: 'Search posts...',
//                   hintStyle: TextStyle(
//                     color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                   ),
//                   border: InputBorder.none,
//                 ),
//                 style: TextStyle(
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                 ),
//                 onChanged: (value) {
//                   _loadQuestions();
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildZoneMapSection(bool isDarkMode) {
//     if (_isLoadingZones || _isLoadingLocation) {
//       return const Center(child: CircularProgressIndicator());
//     }

//     return Stack(
//       children: [
//         SingleChildScrollView(
//           child: Column(
//             children: [
//               // User Location Card
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
//                   borderRadius: BorderRadius.circular(16),
//                 ),
//                 child: Column(
//                   children: [
//                     Row(
//                       children: [
//                         Container(
//                           width: 48,
//                           height: 48,
//                           decoration: BoxDecoration(
//                             color: const Color(0xFF39AC86).withOpacity(0.1),
//                             borderRadius: BorderRadius.circular(24),
//                           ),
//                           child: const Icon(
//                             Icons.my_location,
//                             color: Color(0xFF39AC86),
//                             size: 24,
//                           ),
//                         ),
//                         const SizedBox(width: 12),
//                         Expanded(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               const Text(
//                                 'Your Hardiness Zone',
//                                 style: TextStyle(
//                                   fontSize: 12,
//                                   color: Color(0xFF5C8A7A),
//                                 ),
//                               ),
//                               const SizedBox(height: 4),
//                               Text(
//                                 _userZone ?? 'Not detected',
//                                 style: const TextStyle(
//                                   fontSize: 20,
//                                   fontWeight: FontWeight.bold,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                         if (_userZone != null && _hardinessZones[_userZone] != null)
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                             decoration: BoxDecoration(
//                               color: Color(int.parse(_hardinessZones[_userZone]!['color'].replaceFirst('#', '0xFF'))).withOpacity(0.2),
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             child: Text(
//                               _userZone!,
//                               style: TextStyle(
//                                 fontSize: 12,
//                                 fontWeight: FontWeight.bold,
//                                 color: Color(int.parse(_hardinessZones[_userZone]!['color'].replaceFirst('#', '0xFF'))),
//                               ),
//                             ),
//                           ),
//                       ],
//                     ),
//                     const SizedBox(height: 16),
//                     if (_userZone != null)
//                       Text(
//                         _hardinessZones[_userZone]?['description'] ?? '',
//                         style: TextStyle(
//                           fontSize: 14,
//                           color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),

//               // Interactive Map (Works on both Web and Mobile)
//               Container(
//                 height: 350,
//                 margin: const EdgeInsets.symmetric(horizontal: 16),
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(16),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.1),
//                       blurRadius: 10,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(16),
//                   child: GoogleMap(
//                     onMapCreated: _onMapCreated,
//                     initialCameraPosition: CameraPosition(
//                       target: _userLocation ?? const LatLng(39.8283, -98.5795),
//                       zoom: 4,
//                     ),
//                     markers: {
//                       if (_userLocation != null)
//                         Marker(
//                           markerId: const MarkerId('user-location'),
//                           position: _userLocation!,
//                           infoWindow: const InfoWindow(
//                             title: 'Your Location',
//                             snippet: 'Your hardiness zone',
//                           ),
//                           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//                         ),
//                       ..._zoneMarkers,
//                     },
//                     myLocationEnabled: true,
//                     myLocationButtonEnabled: true,
//                     zoomControlsEnabled: true,
//                     zoomGesturesEnabled: true,
//                     scrollGesturesEnabled: true,
//                     tiltGesturesEnabled: true,
//                   ),
//                 ),
//               ),

//               // Zone Cards
//               Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       'Hardiness Zones',
//                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     const SizedBox(height: 16),
//                     GridView.builder(
//                       shrinkWrap: true,
//                       physics: const NeverScrollableScrollPhysics(),
//                       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                         crossAxisCount: 2,
//                         crossAxisSpacing: 12,
//                         mainAxisSpacing: 12,
//                         childAspectRatio: 1.5,
//                       ),
//                       itemCount: _hardinessZones.keys.length,
//                       itemBuilder: (context, index) {
//                         final zoneName = _hardinessZones.keys.elementAt(index);
//                         final zone = _hardinessZones[zoneName]!;
//                         final isUserZone = zoneName == _userZone;
//                         final zoneColor = Color(int.parse(zone['color'].replaceFirst('#', '0xFF')));
                        
//                         return Container(
//                           padding: const EdgeInsets.all(12),
//                           decoration: BoxDecoration(
//                             color: isUserZone ? zoneColor.withOpacity(0.2) : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white),
//                             borderRadius: BorderRadius.circular(12),
//                             border: Border.all(
//                               color: isUserZone ? zoneColor : Colors.black.withOpacity(0.05),
//                               width: isUserZone ? 2 : 1,
//                             ),
//                           ),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Row(
//                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                                 children: [
//                                   Text(
//                                     zoneName,
//                                     style: TextStyle(
//                                       fontSize: 16,
//                                       fontWeight: FontWeight.bold,
//                                       color: zoneColor,
//                                     ),
//                                   ),
//                                   if (isUserZone)
//                                     Container(
//                                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                                       decoration: BoxDecoration(
//                                         color: const Color(0xFF39AC86),
//                                         borderRadius: BorderRadius.circular(8),
//                                       ),
//                                       child: const Text(
//                                         'YOUR ZONE',
//                                         style: TextStyle(
//                                           fontSize: 8,
//                                           fontWeight: FontWeight.bold,
//                                           color: Colors.white,
//                                         ),
//                                       ),
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 4),
//                               Text(
//                                 zone['tempRange'],
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   color: isDarkMode ? Colors.white70 : const Color(0xFF666666),
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                               Text(
//                                 'Best crops:',
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   fontWeight: FontWeight.bold,
//                                   color: zoneColor,
//                                 ),
//                               ),
//                               Wrap(
//                                 spacing: 4,
//                                 runSpacing: 4,
//                                 children: (zone['suitableCrops'] as List).take(3).map((crop) {
//                                   return Container(
//                                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                                     decoration: BoxDecoration(
//                                       color: zoneColor.withOpacity(0.1),
//                                       borderRadius: BorderRadius.circular(4),
//                                     ),
//                                     child: Text(
//                                       crop,
//                                       style: TextStyle(
//                                         fontSize: 8,
//                                         color: zoneColor,
//                                       ),
//                                     ),
//                                   );
//                                 }).toList(),
//                               ),
//                             ],
//                           ),
//                         );
//                       },
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//         if (_showAIAssistant)
//           Positioned(
//             bottom: 80,
//             right: 16,
//             left: 16,
//             child: Material(
//               elevation: 8,
//               borderRadius: BorderRadius.circular(16),
//               child: Container(
//                 height: 300,
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? const Color(0xFF2C3E35) : Colors.white,
//                   borderRadius: BorderRadius.circular(16),
//                 ),
//                 child: Column(
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.all(12),
//                       decoration: BoxDecoration(
//                         color: const Color(0xFF39AC86),
//                         borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
//                       ),
//                       child: Row(
//                         children: [
//                           const Icon(Icons.assistant, color: Colors.white),
//                           const SizedBox(width: 8),
//                           const Text(
//                             'AI Garden Assistant',
//                             style: TextStyle(
//                               color: Colors.white,
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           const Spacer(),
//                           IconButton(
//                             onPressed: () {
//                               setState(() {
//                                 _showAIAssistant = false;
//                               });
//                             },
//                             icon: const Icon(Icons.close, color: Colors.white, size: 20),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.all(12),
//                         child: Column(
//                           children: [
//                             Expanded(
//                               child: SingleChildScrollView(
//                                 child: Text(
//                                   _aiResponse.isEmpty 
//                                       ? 'Ask me anything about gardening, crops, pests, or farming techniques!'
//                                       : _aiResponse,
//                                   style: TextStyle(
//                                     color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                                   ),
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             Row(
//                               children: [
//                                 Expanded(
//                                   child: TextField(
//                                     controller: _aiQuestionController,
//                                     decoration: InputDecoration(
//                                       hintText: 'Ask a question...',
//                                       hintStyle: TextStyle(
//                                         color: isDarkMode ? Colors.white70 : Colors.grey[600],
//                                       ),
//                                       border: OutlineInputBorder(
//                                         borderRadius: BorderRadius.circular(24),
//                                       ),
//                                       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//                                     ),
//                                     style: TextStyle(
//                                       color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                                     ),
//                                     onSubmitted: (_) => _askAIAssistant(),
//                                   ),
//                                 ),
//                                 const SizedBox(width: 8),
//                                 Container(
//                                   decoration: BoxDecoration(
//                                     color: const Color(0xFF39AC86),
//                                     shape: BoxShape.circle,
//                                   ),
//                                   child: IconButton(
//                                     onPressed: _isAILoading ? null : _askAIAssistant,
//                                     icon: _isAILoading
//                                         ? const SizedBox(
//                                             width: 20,
//                                             height: 20,
//                                             child: CircularProgressIndicator(
//                                               strokeWidth: 2,
//                                               color: Colors.white,
//                                             ),
//                                           )
//                                         : const Icon(Icons.send, color: Colors.white, size: 20),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//       ],
//     );
//   }

//   Widget _buildCommunitySection(bool isDarkMode) {
//     return Column(
//       children: [
//         // Category Filter Chips
//         SizedBox(
//           height: 44,
//           child: ListView.builder(
//             scrollDirection: Axis.horizontal,
//             padding: const EdgeInsets.symmetric(horizontal: 16),
//             itemCount: _categories.length,
//             itemBuilder: (context, index) {
//               final category = _categories[index];
//               final isSelected = _selectedCategory == category;
//               return Padding(
//                 padding: const EdgeInsets.only(right: 8),
//                 child: ChoiceChip(
//                   label: Text(category),
//                   selected: isSelected,
//                   selectedColor: const Color(0xFF39AC86),
//                   backgroundColor: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
//                   labelStyle: TextStyle(
//                     color: isSelected ? Colors.white : (isDarkMode ? Colors.white : const Color(0xFF101816)),
//                   ),
//                   onSelected: (selected) {
//                     setState(() {
//                       _selectedCategory = category;
//                       _loadQuestions();
//                     });
//                   },
//                 ),
//               );
//             },
//           ),
//         ),
        
//         // Posts Feed
//         Expanded(
//           child: _isLoadingQuestions
//               ? const Center(child: CircularProgressIndicator(color: Color(0xFF39AC86)))
//               : _filteredQuestions.isEmpty
//                   ? _buildEmptyState(isDarkMode)
//                   : ListView.builder(
//                       padding: const EdgeInsets.all(16),
//                       itemCount: _filteredQuestions.length,
//                       itemBuilder: (context, index) {
//                         final question = _filteredQuestions[index];
//                         return _buildPostCard(question, isDarkMode);
//                       },
//                     ),
//         ),
//       ],
//     );
//   }

//   Widget _buildPostCard(QuestionPost question, bool isDarkMode) {
//     final timeAgo = _getTimeAgo(question.createdAt);
    
//     return Container(
//       margin: const EdgeInsets.only(bottom: 16),
//       decoration: BoxDecoration(
//         color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: question.solved ? const Color(0xFF39AC86) : Colors.black.withOpacity(0.05),
//         ),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Post Header (Author info)
//           Padding(
//             padding: const EdgeInsets.all(12),
//             child: Row(
//               children: [
//                 if (question.authorImage.isNotEmpty)
//                   CircleAvatar(
//                     radius: 20,
//                     backgroundImage: NetworkImage(question.authorImage),
//                   )
//                 else
//                   Container(
//                     width: 40,
//                     height: 40,
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF39AC86).withOpacity(0.1),
//                       shape: BoxShape.circle,
//                     ),
//                     child: Center(
//                       child: Text(
//                         question.author[0].toUpperCase(),
//                         style: const TextStyle(
//                           color: Color(0xFF39AC86),
//                           fontWeight: FontWeight.bold,
//                           fontSize: 16,
//                         ),
//                       ),
//                     ),
//                   ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         question.author,
//                         style: TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                         ),
//                       ),
//                       Row(
//                         children: [
//                           Text(
//                             timeAgo,
//                             style: TextStyle(
//                               fontSize: 11,
//                               color: const Color(0xFF5C8A7A),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                             decoration: BoxDecoration(
//                               color: const Color(0xFF39AC86).withOpacity(0.1),
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: Text(
//                               question.category,
//                               style: const TextStyle(
//                                 fontSize: 10,
//                                 fontWeight: FontWeight.bold,
//                                 color: Color(0xFF39AC86),
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
          
//           // Post Content (Text)
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 12),
//             child: GestureDetector(
//               onTap: () => _showQuestionDetail(question),
//               child: Text(
//                 question.title,
//                 style: TextStyle(
//                   fontSize: 16,
//                   color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                   height: 1.4,
//                 ),
//               ),
//             ),
//           ),
          
//           // Post Image (if exists) - Like Facebook style
//           if (question.imageUrl != null && question.imageUrl!.isNotEmpty) ...[
//             const SizedBox(height: 12),
//             GestureDetector(
//               onTap: () => _showQuestionDetail(question),
//               child: ClipRRect(
//                 child: Image.network(
//                   question.imageUrl!,
//                   width: double.infinity,
//                   fit: BoxFit.cover,
//                   loadingBuilder: (context, child, loadingProgress) {
//                     if (loadingProgress == null) return child;
//                     return Container(
//                       height: 200,
//                       color: Colors.grey[300],
//                       child: const Center(
//                         child: CircularProgressIndicator(),
//                       ),
//                     );
//                   },
//                   errorBuilder: (context, error, stack) => Container(
//                     height: 200,
//                     color: Colors.grey[300],
//                     child: const Icon(Icons.broken_image, size: 50),
//                   ),
//                 ),
//               ),
//             ),
//           ],
          
//           // Post Actions (Like, Comment, etc.)
//           Padding(
//             padding: const EdgeInsets.all(12),
//             child: Row(
//               children: [
//                 // Like button
//                 GestureDetector(
//                   onTap: () => _likeQuestion(question),
//                   child: Row(
//                     children: [
//                       Icon(
//                         question.userLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
//                         size: 18,
//                         color: question.userLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
//                       ),
//                       const SizedBox(width: 6),
//                       Text(
//                         '${question.likes}',
//                         style: TextStyle(
//                           fontSize: 13,
//                           color: question.userLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(width: 24),
                
//                 // Comment button
//                 GestureDetector(
//                   onTap: () => _showQuestionDetail(question),
//                   child: Row(
//                     children: [
//                       Icon(Icons.chat_bubble_outline, size: 18, color: const Color(0xFF5C8A7A)),
//                       const SizedBox(width: 6),
//                       Text(
//                         '${question.answers} comments',
//                         style: const TextStyle(
//                           fontSize: 13,
//                           color: Color(0xFF5C8A7A),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
                
//                 if (question.solved) ...[
//                   const Spacer(),
//                   const Icon(Icons.check_circle, size: 16, color: Color(0xFF39AC86)),
//                   const SizedBox(width: 4),
//                   const Text('Solved', style: TextStyle(fontSize: 12, color: Color(0xFF39AC86))),
//                 ],
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState(bool isDarkMode) {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(Icons.question_answer, size: 80, color: const Color(0xFF39AC86).withOpacity(0.3)),
//           const SizedBox(height: 16),
//           Text('No posts yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : const Color(0xFF101816))),
//           const SizedBox(height: 8),
//           const Text('Be the first to share something with the community!', style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A))),
//           const SizedBox(height: 24),
//           ElevatedButton(
//             onPressed: _showAskQuestionDialog,
//             style: ElevatedButton.styleFrom(
//               backgroundColor: const Color(0xFF39AC86),
//               padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
//             ),
//             child: const Text('Create a Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _questionController.dispose();
//     _searchController.dispose();
//     _replyController.dispose();
//     _aiQuestionController.dispose();
//     super.dispose();
//   }
// }

// // Question Post Model
// class QuestionPost {
//   final String id;
//   final String title;
//   final String description;
//   final String category;
//   final String author;
//   final String authorImage;
//   int answers;
//   int likes;
//   final DateTime createdAt;
//   bool solved;
//   final String? imageUrl;
//   bool userLiked;

//   QuestionPost({
//     required this.id,
//     required this.title,
//     required this.description,
//     required this.category,
//     required this.author,
//     required this.authorImage,
//     required this.answers,
//     required this.likes,
//     required this.createdAt,
//     required this.solved,
//     this.imageUrl,
//     this.userLiked = false,
//   });

//   factory QuestionPost.fromJson(Map<String, dynamic> json) {
//     return QuestionPost(
//       id: json['id'],
//       title: json['title'],
//       description: json['description'] ?? '',
//       category: json['category'],
//       author: json['author'],
//       authorImage: json['authorImage'] ?? '',
//       answers: json['answers'] ?? 0,
//       likes: json['likes'] ?? 0,
//       createdAt: DateTime.parse(json['createdAt']),
//       solved: json['solved'] ?? false,
//       imageUrl: json['image_url'],
//       userLiked: json['userLiked'] ?? false,
//     );
//   }
// }

// // Question Detail Sheet
// class _QuestionDetailSheet extends StatefulWidget {
//   final QuestionPost question;
//   final Function(String) onAnswerAdded;

//   const _QuestionDetailSheet({
//     required this.question,
//     required this.onAnswerAdded,
//   });

//   @override
//   State<_QuestionDetailSheet> createState() => _QuestionDetailSheetState();
// }

// class _QuestionDetailSheetState extends State<_QuestionDetailSheet> {
//   final TextEditingController _replyController = TextEditingController();
//   final ApiService _apiService = ApiService();
//   List<Map<String, dynamic>> _answers = [];
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadAnswers();
//   }

//   Future<void> _loadAnswers() async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final result = await _apiService.getQuestionAnswers(widget.question.id);
//       if (result['success'] == true) {
//         setState(() {
//           _answers = List<Map<String, dynamic>>.from(result['answers'] ?? []);
//         });
//       }
//     } catch (e) {
//       print('Error loading answers: $e');
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _likeAnswer(Map<String, dynamic> answer) async {
//     try {
//       final result = await _apiService.toggleAnswerLike(answer['id']);
      
//       if (result['success'] == true && mounted) {
//         setState(() {
//           final index = _answers.indexWhere((a) => a['id'] == answer['id']);
//           if (index != -1) {
//             _answers[index]['likes'] = result['likes'] ?? answer['likes'];
//             _answers[index]['userLiked'] = result['liked'] ?? !(answer['userLiked'] ?? false);
//           }
//         });
        
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(result['liked'] == true ? 'Liked!' : 'Unliked'),
//             backgroundColor: Colors.green,
//             duration: const Duration(seconds: 1),
//           ),
//         );
//       }
//     } catch (e) {
//       print('Error liking answer: $e');
//     }
//   }

//   void _addAnswer() {
//     if (_replyController.text.trim().isEmpty) return;

//     final answerText = _replyController.text.trim();
//     _replyController.clear();
//     widget.onAnswerAdded(answerText);
//     _loadAnswers();
//   }

//   String _getTimeAgo(DateTime date) {
//     final now = DateTime.now();
//     final diff = now.difference(date);
    
//     if (diff.inDays > 0) return '${diff.inDays}d ago';
//     if (diff.inHours > 0) return '${diff.inHours}h ago';
//     if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
//     return 'Just now';
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
//     return Container(
//       height: MediaQuery.of(context).size.height * 0.85,
//       decoration: BoxDecoration(
//         color: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       child: Column(
//         children: [
//           // Drag handle
//           Container(
//             margin: const EdgeInsets.only(top: 12),
//             width: 40,
//             height: 4,
//             decoration: BoxDecoration(
//               color: Colors.grey[300],
//               borderRadius: BorderRadius.circular(2),
//             ),
//           ),
          
//           // Post content
//           Expanded(
//             child: SingleChildScrollView(
//               padding: const EdgeInsets.all(16),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   // Author info
//                   Row(
//                     children: [
//                       widget.question.authorImage.isNotEmpty
//                           ? CircleAvatar(radius: 24, backgroundImage: NetworkImage(widget.question.authorImage))
//                           : Container(
//                               width: 48,
//                               height: 48,
//                               decoration: BoxDecoration(
//                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                 shape: BoxShape.circle,
//                               ),
//                               child: Center(
//                                 child: Text(
//                                   widget.question.author[0].toUpperCase(),
//                                   style: const TextStyle(
//                                     color: Color(0xFF39AC86),
//                                     fontWeight: FontWeight.bold,
//                                     fontSize: 18,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               widget.question.author,
//                               style: TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 16,
//                                 color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                               ),
//                             ),
//                             Row(
//                               children: [
//                                 Text(
//                                   _getTimeAgo(widget.question.createdAt),
//                                   style: const TextStyle(fontSize: 12, color: Color(0xFF5C8A7A)),
//                                 ),
//                                 const SizedBox(width: 8),
//                                 Container(
//                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
//                                   decoration: BoxDecoration(
//                                     color: const Color(0xFF39AC86).withOpacity(0.1),
//                                     borderRadius: BorderRadius.circular(8),
//                                   ),
//                                   child: Text(
//                                     widget.question.category,
//                                     style: const TextStyle(
//                                       fontSize: 11,
//                                       fontWeight: FontWeight.bold,
//                                       color: Color(0xFF39AC86),
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 16),
                  
//                   // Post text
//                   Text(
//                     widget.question.title,
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.w500,
//                       color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                       height: 1.4,
//                     ),
//                   ),
                  
//                   // Post image
//                   if (widget.question.imageUrl != null && widget.question.imageUrl!.isNotEmpty) ...[
//                     const SizedBox(height: 16),
//                     ClipRRect(
//                       borderRadius: BorderRadius.circular(12),
//                       child: Image.network(
//                         widget.question.imageUrl!,
//                         width: double.infinity,
//                         fit: BoxFit.cover,
//                         loadingBuilder: (context, child, loadingProgress) {
//                           if (loadingProgress == null) return child;
//                           return Container(
//                             height: 300,
//                             color: Colors.grey[300],
//                             child: const Center(child: CircularProgressIndicator()),
//                           );
//                         },
//                       ),
//                     ),
//                   ],
                  
//                   const SizedBox(height: 24),
                  
//                   // Answers section
//                   Row(
//                     children: [
//                       const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF5C8A7A)),
//                       const SizedBox(width: 8),
//                       Text(
//                         '${_answers.length} Comments',
//                         style: const TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: Color(0xFF5C8A7A),
//                         ),
//                       ),
//                     ],
//                   ),
//                   const Divider(height: 24),
                  
//                   // Comments list
//                   _isLoading
//                       ? const Center(child: CircularProgressIndicator())
//                       : _answers.isEmpty
//                           ? const Center(
//                               child: Padding(
//                                 padding: EdgeInsets.all(32),
//                                 child: Text(
//                                   'No comments yet. Be the first to comment!',
//                                   style: TextStyle(color: Color(0xFF5C8A7A)),
//                                 ),
//                               ),
//                             )
//                           : ListView.builder(
//                               shrinkWrap: true,
//                               physics: const NeverScrollableScrollPhysics(),
//                               itemCount: _answers.length,
//                               itemBuilder: (context, index) {
//                                 final answer = _answers[index];
//                                 final timeAgo = answer['createdAt'] is DateTime 
//                                     ? _getTimeAgo(answer['createdAt']) 
//                                     : 'Just now';
//                                 final isLiked = answer['userLiked'] ?? false;
                                
//                                 return Container(
//                                   margin: const EdgeInsets.only(bottom: 16),
//                                   child: Row(
//                                     crossAxisAlignment: CrossAxisAlignment.start,
//                                     children: [
//                                       answer['authorImage'] != null && answer['authorImage'].isNotEmpty
//                                           ? CircleAvatar(radius: 20, backgroundImage: NetworkImage(answer['authorImage']))
//                                           : Container(
//                                               width: 40,
//                                               height: 40,
//                                               decoration: BoxDecoration(
//                                                 color: const Color(0xFF39AC86).withOpacity(0.1),
//                                                 shape: BoxShape.circle,
//                                               ),
//                                               child: Center(
//                                                 child: Text(
//                                                   answer['author'][0].toUpperCase(),
//                                                   style: const TextStyle(
//                                                     color: Color(0xFF39AC86),
//                                                     fontWeight: FontWeight.bold,
//                                                   ),
//                                                 ),
//                                               ),
//                                             ),
//                                       const SizedBox(width: 12),
//                                       Expanded(
//                                         child: Column(
//                                           crossAxisAlignment: CrossAxisAlignment.start,
//                                           children: [
//                                             Text(
//                                               answer['author'],
//                                               style: TextStyle(
//                                                 fontWeight: FontWeight.bold,
//                                                 fontSize: 14,
//                                                 color: isDarkMode ? Colors.white : const Color(0xFF101816),
//                                               ),
//                                             ),
//                                             Text(
//                                               timeAgo,
//                                               style: const TextStyle(
//                                                 fontSize: 11,
//                                                 color: Color(0xFF5C8A7A),
//                                               ),
//                                             ),
//                                             const SizedBox(height: 8),
//                                             Text(
//                                               answer['text'],
//                                               style: TextStyle(
//                                                 fontSize: 14,
//                                                 color: isDarkMode ? Colors.white70 : const Color(0xFF101816),
//                                                 height: 1.3,
//                                               ),
//                                             ),
//                                             const SizedBox(height: 8),
//                                             GestureDetector(
//                                               onTap: () => _likeAnswer(answer),
//                                               child: Row(
//                                                 children: [
//                                                   Icon(
//                                                     isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
//                                                     size: 14,
//                                                     color: isLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
//                                                   ),
//                                                   const SizedBox(width: 4),
//                                                   Text(
//                                                     '${answer['likes']}',
//                                                     style: TextStyle(
//                                                       fontSize: 12,
//                                                       color: isLiked ? const Color(0xFF39AC86) : const Color(0xFF5C8A7A),
//                                                     ),
//                                                   ),
//                                                 ],
//                                               ),
//                                             ),
//                                           ],
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 );
//                               },
//                             ),
//                 ],
//               ),
//             ),
//           ),
          
//           // Comment input
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: isDarkMode ? const Color(0xFF1A2A25) : Colors.white,
//               border: Border(
//                 top: BorderSide(color: Colors.black.withOpacity(0.05)),
//               ),
//             ),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 16),
//                     decoration: BoxDecoration(
//                       color: isDarkMode ? Colors.white.withOpacity(0.1) : const Color(0xFFF5F5F5),
//                       borderRadius: BorderRadius.circular(24),
//                     ),
//                     child: TextField(
//                       controller: _replyController,
//                       decoration: const InputDecoration(
//                         hintText: 'Write a comment...',
//                         border: InputBorder.none,
//                       ),
//                       maxLines: null,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Container(
//                   width: 40,
//                   height: 40,
//                   decoration: const BoxDecoration(
//                     color: Color(0xFF39AC86),
//                     shape: BoxShape.circle,
//                   ),
//                   child: IconButton(
//                     onPressed: _addAnswer,
//                     icon: const Icon(Icons.send, size: 20, color: Colors.white),
//                     padding: EdgeInsets.zero,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }



