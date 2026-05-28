import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // IMPORTANT: Uncomment the one you're using
  static const String baseUrl = 'https://foodsharingbackend-n5py.onrender.com'; // Production
  // static const String baseUrl = 'http://localhost:5000'; // Local development
  // static const String baseUrl = 'http://10.0.2.2:5000'; // Android emulator sys
  // https://foodsharingbackend-n5py.onrender.com
  
  String? _token;
  bool _isInitialized = false;

  // PUBLIC GETTERS
  String get apiBaseUrl => ApiService.baseUrl;
  
  Map<String, String> get headers {
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    
    return headers;
  }

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  
  String? get token => _token;

  // Initialize - must be called at app startup
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('🔄 Initializing ApiService...');
    await _loadToken();
    _isInitialized = true;
    
    print('✅ ApiService initialized');
    print('🔑 Token loaded: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
  }

  // Load token from shared preferences
  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      
      if (_token != null) {
        print('📁 Loaded token from storage: ${_token!.substring(0, 30)}...');
      } else {
        print('📁 No token found in storage');
      }
    } catch (e) {
      print('❌ Error loading token: $e');
      _token = null;
    }
  }

  // Save token to shared preferences
  Future<void> _saveToken(String token) async {
    try {
      _token = token;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      print('💾 Token saved to storage: ${token.substring(0, 30)}...');
    } catch (e) {
      print('❌ Error saving token: $e');
    }
  }

  // Clear token (logout)
  Future<void> clearToken() async {
    try {
      print('🗑️ Clearing token...');
      _token = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      await prefs.remove('user_data');
      print('✅ Token cleared');
    } catch (e) {
      print('❌ Error clearing token: $e');
    }
  }

  // ============ AUTH METHODS ============

  // Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      print('=' * 50);
      print('🔄 LOGIN STARTED');
      print('📤 Email: $email');
      print('🌐 URL: $baseUrl/api/auth/login');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      print('📥 HTTP Status: ${response.statusCode}');
      print('📥 Response length: ${response.body.length} characters');
      
      if (response.body.length > 200) {
        print('📥 Response preview: ${response.body.substring(0, 200)}...');
      } else {
        print('📥 Response: ${response.body}');
      }

      if (response.body.isEmpty) {
        print('❌ ERROR: Empty response from server');
        return {
          'success': false,
          'error': 'Server returned empty response',
          'statusCode': response.statusCode,
        };
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
        print('✅ JSON parsed successfully');
        print('📊 Response keys: ${data.keys.toList()}');
      } catch (e) {
        print('❌ JSON Parse Error: $e');
        print('❌ Raw response: ${response.body}');
        return {
          'success': false,
          'error': 'Invalid JSON response from server: $e',
          'statusCode': response.statusCode,
        };
      }

      if (response.statusCode == 200) {
        final token = data['token'];
        
        if (token != null && token is String && token.isNotEmpty) {
          print('✅ Token found: ${token.substring(0, 50)}...');
          
          await _saveToken(token);
          
          if (data['user'] != null) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_data', jsonEncode(data['user']));
              print('✅ User data saved');
            } catch (e) {
              print('⚠️ Warning: Could not save user data: $e');
            }
          }
          
          print('✅ LOGIN SUCCESS');
          print('=' * 50);
          
          return {
            'success': true,
            'token': token,
            'user': data['user'],
            'message': data['message'] ?? 'Login successful',
          };
        } else {
          print('❌ ERROR: Token missing or invalid in response');
          return {
            'success': false,
            'error': 'Authentication token missing from server response',
            'responseData': data,
            'statusCode': response.statusCode,
          };
        }
      } else {
        print('❌ ERROR: Server returned status ${response.statusCode}');
        final errorMessage = data['error'] ?? 
                           data['message'] ?? 
                           'Login failed with status ${response.statusCode}';
        
        return {
          'success': false,
          'error': errorMessage,
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('💥 EXCEPTION: $e');
      print('=' * 50);
      return {
        'success': false,
        'error': 'Network error: $e',
      };
    }
  }

  // Register user
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      print('=' * 50);
      print('🔄 REGISTRATION STARTED');
      print('📤 Email: $email, Name: $name');
      print('🌐 URL: $baseUrl/api/auth/register');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'name': name.trim(),
          'phone': phone.trim(),
        }),
      );

      print('📥 HTTP Status: ${response.statusCode}');
      print('📥 Response length: ${response.body.length} characters');
      
      Map<String, dynamic> data = jsonDecode(response.body);
      print('📊 Response keys: ${data.keys.toList()}');

      if (response.statusCode == 201) {
        final token = data['token'];
        
        if (token != null && token is String && token.isNotEmpty) {
          print('✅ Token found: ${token.substring(0, 50)}...');
          
          await _saveToken(token);
          
          if (data['user'] != null) {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_data', jsonEncode(data['user']));
              print('✅ User data saved');
            } catch (e) {
              print('⚠️ Warning: Could not save user data: $e');
            }
          }
          
          print('✅ REGISTRATION SUCCESS');
          print('=' * 50);
          
          return {
            'success': true,
            'token': token,
            'user': data['user'],
            'message': data['message'] ?? 'Registration successful',
          };
        } else {
          print('❌ ERROR: Token missing in registration response');
          return {
            'success': false,
            'error': 'Authentication token missing from server response',
            'responseData': data,
          };
        }
      } else {
        print('❌ ERROR: Registration failed');
        return {
          'success': false,
          'error': data['error'] ?? 'Registration failed',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('💥 EXCEPTION: $e');
      print('=' * 50);
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ IMAGE UPLOAD METHODS ============

  Future<Map<String, dynamic>> uploadImageWeb(String base64Image, String fileName) async {
    try {
      print('🔄 Uploading image via web (base64)...');
      print('📤 Base64 length: ${base64Image.length}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/crops/upload-image-web'),
        headers: headers,
        body: jsonEncode({
          'image': base64Image,
          'fileName': fileName,
        }),
      );

      print('📥 Upload response status: ${response.statusCode}');
      print('📥 Upload response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'imageUrl': data['imageUrl'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload image',
        };
      }
    } catch (e) {
      print('❌ Upload image error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> uploadProfileImageWeb(String base64Image, String fileName) async {
    try {
      print('🔄 Uploading profile image via web...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/profile/upload-image-web'),
        headers: headers,
        body: jsonEncode({
          'image': base64Image,
          'fileName': fileName,
        }),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final currentUserData = await getSavedUserData();
        
        if (currentUserData != null) {
          final updatedUser = {
            ...currentUserData,
            'profile_image_url': data['imageUrl'],
          };
          await prefs.setString('user_data', jsonEncode(updatedUser));
          print('✅ User profile image updated locally');
        }
        
        return {
          'success': true,
          'imageUrl': data['imageUrl'],
          'user': data['user'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload image',
        };
      }
    } catch (e) {
      print('❌ Upload error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> uploadCropImage(String imagePath) async {
    try {
      print('🔄 Uploading crop image...');
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/crops/upload-image'),
      );
      
      request.headers.addAll(headers);
      
      final file = await http.MultipartFile.fromPath('image', imagePath);
      request.files.add(file);
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'imageUrl': data['imageUrl'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to upload image',
        };
      }
    } catch (e) {
      print('❌ Upload crop image error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ USER METHODS ============

  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      print('=' * 50);
      print('🔄 GETTING CURRENT USER');
      print('🌐 URL: $baseUrl/api/auth/me');
      print('🔑 Using token: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
      
      if (_token == null || _token!.isEmpty) {
        print('❌ ERROR: No authentication token available');
        return {
          'success': false,
          'error': 'Not authenticated',
        };
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: headers,
      );

      print('📥 HTTP Status: ${response.statusCode}');
      print('📥 Response length: ${response.body.length} characters');
      
      Map<String, dynamic> data = jsonDecode(response.body);
      print('📊 Response keys: ${data.keys.toList()}');

      if (response.statusCode == 200 && data['success'] == true) {
        print('✅ USER FETCH SUCCESS');
        print('=' * 50);
        return {
          'success': true,
          'user': data['user'],
        };
      } else {
        print('❌ ERROR: Failed to fetch user');
        print('❌ Server message: ${data['error']}');
        
        if (response.statusCode == 401) {
          print('⚠️ Token invalid, clearing...');
          await clearToken();
        }
        
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch user',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('💥 EXCEPTION: $e');
      print('=' * 50);
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      print('🔄 Getting user profile');
      print('🌐 URL: $baseUrl/api/profile');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/profile'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'profile': data['profile'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch profile',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get profile error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    String? name,
    String? bio,
    String? location,
    String? gardenName,
    String? gardenSize,
  }) async {
    try {
      print('🔄 Updating user profile');
      print('🌐 URL: $baseUrl/api/profile');
      
      final Map<String, dynamic> updateData = {};
      
      if (name != null) updateData['name'] = name;
      if (bio != null) updateData['bio'] = bio;
      if (location != null) updateData['location'] = location;
      if (gardenName != null) updateData['garden_name'] = gardenName;
      if (gardenSize != null) updateData['garden_size'] = gardenSize;
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/profile'),
        headers: headers,
        body: jsonEncode(updateData),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        final currentUserData = await getSavedUserData();
        
        if (currentUserData != null) {
          final updatedUser = {...currentUserData, ...updateData};
          
          if (data['user'] != null && data['user']['profile_image_url'] != null) {
            updatedUser['profile_image_url'] = data['user']['profile_image_url'];
          }
          
          await prefs.setString('user_data', jsonEncode(updatedUser));
          print('✅ User data updated locally');
          
          return {
            'success': true,
            'user': updatedUser,
            'message': data['message'] ?? 'Profile updated successfully',
          };
        } else {
          return {
            'success': true,
            'user': data['user'] ?? updateData,
            'message': data['message'] ?? 'Profile updated successfully',
          };
        }
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update profile',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Update profile error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getImpactStats() async {
    try {
      print('🔄 Getting impact stats');
      print('🌐 URL: $baseUrl/api/profile/stats/impact');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/profile/stats/impact'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'impact': data['impact'] ?? {},
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch impact stats',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get impact stats error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ GARDEN & CROPS METHODS ============

  Future<Map<String, dynamic>> getUserCrops() async {
    try {
      print('🔄 Getting user crops');
      print('🌐 URL: $baseUrl/api/crops');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/crops'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'crops': data['crops'] ?? [],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch crops',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get crops error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ NEW CROP GROWTH TRACKING METHODS ============

  // Update crop progress manually
  Future<Map<String, dynamic>> updateCropProgress(String cropId, int progress) async {
    try {
      print('🔄 Updating crop progress: $cropId to $progress%');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/crops/$cropId/progress'),
        headers: headers,
        body: jsonEncode({
          'manual_progress': progress,
        }),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Failed to update crop progress',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      print('❌ Update crop progress error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Toggle auto-update for a crop
  Future<Map<String, dynamic>> toggleCropAutoUpdate(String cropId, bool enabled) async {
    try {
      print('🔄 Toggling crop auto-update: $cropId to $enabled');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/crops/$cropId/auto-update'),
        headers: headers,
        body: jsonEncode({
          'enabled': enabled,
        }),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Failed to toggle auto-update',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      print('❌ Toggle auto-update error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Get crop growth analytics (for charts/stats)
  Future<Map<String, dynamic>> getCropGrowthAnalytics(String cropId) async {
    try {
      print('🔄 Getting crop growth analytics for: $cropId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/crops/$cropId/analytics'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Failed to fetch analytics',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      print('❌ Get crop analytics error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Get all crops with growth predictions
  Future<Map<String, dynamic>> getCropsWithPredictions() async {
    try {
      print('🔄 Getting crops with growth predictions');
      print('🌐 URL: $baseUrl/api/crops/predictions');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/crops/predictions'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'crops': data['crops'] ?? [],
          'predictions': data['predictions'] ?? {},
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch crops with predictions',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get crops with predictions error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getUserGardens() async {
    try {
      print('🔄 Getting user gardens');
      print('🌐 URL: $baseUrl/api/gardens');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/gardens'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'gardens': data['gardens'] ?? [],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch gardens',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get gardens error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ SHARED ITEMS METHODS ============

  Future<Map<String, dynamic>> getSharedItems() async {
    try {
      print('🔄 Getting shared items');
      print('🌐 URL: $baseUrl/api/shared-items');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/shared-items'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'items': data['items'] ?? [],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch shared items',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get shared items error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getMySharedItems() async {
    try {
      print('🔄 Getting my shared items');
      print('🌐 URL: $baseUrl/api/shared-items/my-items');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/shared-items/my-items'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'items': data['items'] ?? [],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to fetch your shared items',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Get my shared items error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> createSharedItem(Map<String, dynamic> itemData) async {
    try {
      print('🔄 Creating shared item');
      print('📤 Data: $itemData');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/shared-items'),
        headers: headers,
        body: jsonEncode(itemData),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Item shared successfully',
          'item': data['item'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to share item',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Create shared item error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateSharedItemStatus(String itemId, String status) async {
    try {
      print('🔄 Updating shared item $itemId status to $status');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/shared-items/$itemId/status'),
        headers: headers,
        body: jsonEncode({'status': status}),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Status updated successfully',
          'item': data['item'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update status',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Update shared item error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateSharedItemQuantity(String itemId, int newQuantity) async {
    try {
      print('🔄 Updating shared item $itemId quantity to $newQuantity');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/shared-items/$itemId'),
        headers: headers,
        body: jsonEncode({'quantity': newQuantity}),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Quantity updated successfully',
          'item': data['item'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update quantity',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Update quantity error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> updateSharedItem(String itemId, {int? quantity, String? status}) async {
    try {
      print('🔄 Updating shared item $itemId');
      final Map<String, dynamic> updateData = {};
      if (quantity != null) updateData['quantity'] = quantity;
      if (status != null) updateData['status'] = status;
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/shared-items/$itemId'),
        headers: headers,
        body: jsonEncode(updateData),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Item updated successfully',
          'item': data['item'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to update item',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Update item error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> deleteSharedItem(String itemId) async {
    try {
      print('🔄 Deleting shared item $itemId');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/api/shared-items/$itemId'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Item deleted successfully',
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to delete item',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      print('❌ Delete shared item error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ CHAT METHODS ============

  Future<Map<String, dynamic>> getUserChats() async {
    try {
      print('🔄 Getting user chats');
      final response = await http.get(
        Uri.parse('$baseUrl/api/chats'),
        headers: headers,
      );
      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Error getting chats: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getChatMessages(String chatId) async {
    try {
      print('🔄 Getting chat messages for $chatId');
      final response = await http.get(
        Uri.parse('$baseUrl/api/chats/$chatId/messages'),
        headers: headers,
      );
      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Error getting messages: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String recipientId,
    required String text,
    String? productId,
  }) async {
    try {
      print('🔄 Sending message to $recipientId');
      final response = await http.post(
        Uri.parse('$baseUrl/api/messages'),
        headers: headers,
        body: jsonEncode({
          'chatId': chatId,
          'recipientId': recipientId,
          'text': text,
          'productId': productId,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Error sending message: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> markMessagesAsRead(String chatId, List<String> messageIds) async {
    try {
      print('🔄 Marking messages as read in $chatId');
      final response = await http.post(
        Uri.parse('$baseUrl/api/chats/$chatId/read'),
        headers: headers,
        body: jsonEncode({'messageIds': messageIds}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Error marking messages as read: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> createOrGetChat({
    required String recipientId,
    String? productId,
  }) async {
    try {
      print('🔄 Creating or getting chat with recipient: $recipientId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/chats'),
        headers: headers,
        body: jsonEncode({
          'recipientId': recipientId,
          'productId': productId,
        }),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': data['chat'],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to create chat',
        };
      }
    } catch (e) {
      print('❌ Create chat error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ QUESTIONS & ANSWERS METHODS ============

  // Get all questions with optional filters
  Future<Map<String, dynamic>> getCropQuestions({
    String? category,
    String? search,
    bool? solved,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print('🔄 Getting crop questions');
      
      // Build query parameters
      final Map<String, String> queryParams = {};
      if (category != null && category != 'All') queryParams['category'] = category;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (solved != null) queryParams['solved'] = solved.toString();
      queryParams['limit'] = limit.toString();
      queryParams['offset'] = offset.toString();
      
      final uri = Uri.parse('$baseUrl/api/questions').replace(queryParameters: queryParams);
      print('🌐 URL: $uri');
      
      final response = await http.get(
        uri,
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Get crop questions error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
        'questions': [],
      };
    }
  }

  // Get a single question with its answers
  Future<Map<String, dynamic>> getQuestionWithAnswers(String questionId) async {
    try {
      print('🔄 Getting question details for: $questionId');
      final response = await http.get(
        Uri.parse('$baseUrl/api/questions/$questionId'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Get question details error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Post a new question
  Future<Map<String, dynamic>> postCropQuestion({
    required String title,
    String? description,
    required String category,
    String? imageUrl,
  }) async {
    try {
      print('🔄 Posting new question');
      print('📤 Title: $title');
      print('📤 Category: $category');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/questions'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description ?? '',
          'category': category,
          'image_url': imageUrl,
        }),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Post crop question error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Post an answer to a question
  Future<Map<String, dynamic>> postAnswer({
    required String questionId,
    required String text,
  }) async {
    try {
      print('🔄 Posting answer to question: $questionId');
      print('📤 Answer: $text');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/questions/$questionId/answers'),
        headers: headers,
        body: jsonEncode({'text': text}),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Post answer error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Get answers for a specific question
  Future<Map<String, dynamic>> getQuestionAnswers(String questionId) async {
    try {
      print('🔄 Getting answers for question: $questionId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/questions/$questionId'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      final data = jsonDecode(response.body);
      
      if (data['success'] == true && data['question'] != null) {
        return {
          'success': true,
          'answers': data['question']['answers'] ?? [],
        };
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to get answers',
        };
      }
    } catch (e) {
      print('❌ Get answers error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Toggle like for question
  Future<Map<String, dynamic>> toggleQuestionLike(String questionId) async {
    try {
      print('🔄 Toggling like for question: $questionId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/questions/$questionId/like'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Failed to toggle like',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      print('❌ Toggle like error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Toggle like for answer
  Future<Map<String, dynamic>> toggleAnswerLike(String answerId) async {
    try {
      print('🔄 Toggling like for answer: $answerId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/answers/$answerId/like'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'error': 'Failed to toggle like',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      print('❌ Toggle like error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Mark a question as solved
  Future<Map<String, dynamic>> markQuestionSolved(String questionId) async {
    try {
      print('🔄 Marking question as solved: $questionId');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/questions/$questionId'),
        headers: headers,
        body: jsonEncode({'solved': true}),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Mark question solved error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // Accept an answer as solution
  Future<Map<String, dynamic>> acceptAnswer(String answerId) async {
    try {
      print('🔄 Accepting answer as solution: $answerId');
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/answers/$answerId/accept'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ Accept answer error: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  // ============ OTHER METHODS ============

  Future<Map<String, dynamic>> logout() async {
    try {
      print('=' * 50);
      print('🔄 LOGOUT STARTED');
      
      if (_token != null && _token!.isNotEmpty) {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/logout'),
          headers: headers,
        );
        print('📥 Logout HTTP Status: ${response.statusCode}');
      }
      
      await clearToken();
      
      print('✅ LOGOUT COMPLETE');
      print('=' * 50);
      
      return {
        'success': true,
        'message': 'Logged out successfully',
      };
    } catch (e) {
      await clearToken();
      print('⚠️ Logout server call failed, but local data cleared: $e');
      
      return {
        'success': true,
        'message': 'Logged out locally',
      };
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      print('=' * 50);
      print('🔄 FORGOT PASSWORD');
      print('📤 Email: $email');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      );

      print('📥 HTTP Status: ${response.statusCode}');
      
      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ PASSWORD RESET EMAIL SENT');
        return {
          'success': true,
          'message': data['message'] ?? 'Password reset email sent',
        };
      } else {
        print('❌ ERROR: Failed to send reset email');
        return {
          'success': false,
          'error': data['error'] ?? 'Failed to send reset email',
        };
      }
    } catch (e) {
      print('💥 EXCEPTION: $e');
      return {
        'success': false,
        'error': 'Connection error: $e',
      };
    }
  }

  Future<Map<String, dynamic>?> getSavedUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      
      if (userDataString != null && userDataString.isNotEmpty) {
        return jsonDecode(userDataString);
      }
    } catch (e) {
      print('❌ Error loading saved user data: $e');
    }
    return null;
  }

  bool isTokenValid(String? token) {
    if (token == null || token.isEmpty) return false;
    
    final parts = token.split('.');
    if (parts.length != 3) return false;
    
    if (!token.startsWith('eyJ')) return false;
    
    return true;
  }

  Future<bool> checkTokenValidity() async {
    if (_token == null || _token!.isEmpty) return false;
    
    if (!isTokenValid(_token)) {
      print('⚠️ Token format is invalid');
      await clearToken();
      return false;
    }
    
    return true;
  }




  // Create a product request
Future<Map<String, dynamic>> createProductRequest({
  required String productId,
  required int quantity,
  String? message,
}) async {
  try {
    print('🔄 Creating product request for product: $productId');
    print('📤 Quantity: $quantity');
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/products/$productId/request'),
      headers: headers,
      body: jsonEncode({
        'quantity': quantity,
        'message': message ?? '',
      }),
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      return {
        'success': false,
        'error': 'Failed to create request',
        'statusCode': response.statusCode,
      };
    }
  } catch (e) {
    print('❌ Create product request error: $e');
    return {
      'success': false,
      'error': 'Connection error: $e',
    };
  }
}

// Check if user has an existing request for a product
// Future<Map<String, dynamic>> getUserProductRequest(String productId) async {
//   try {
//     print('🔄 Checking existing request for product: $productId');
    
//     final response = await http.get(
//       Uri.parse('$baseUrl/api/products/$productId/my-request'),
//       headers: headers,
//     );

//     print('📥 Response status: ${response.statusCode}');
//     print('📥 Response body: ${response.body}');

//     return jsonDecode(response.body);
//   } catch (e) {
//     print('❌ Check request error: $e');
//     return {
//       'success': false,
//       'error': 'Connection error: $e',
//     };
//   }
// }

  // Get user's existing request for a product (works for requester AND owner)
Future<Map<String, dynamic>> getUserProductRequest(String productId) async {
  try {
    print('🔄 Getting user request for product: $productId');
    
    final response = await http.get(
      Uri.parse('$baseUrl/api/products/$productId/my-request'),
      headers: headers,
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return {
        'success': false,
        'error': 'Failed to fetch request',
        'request': null
      };
    }
  } catch (e) {
    print('❌ Get user request error: $e');
    return {
      'success': false,
      'error': 'Connection error: $e',
      'request': null
    };
  }
}

// Accept a product request (for owner)
Future<Map<String, dynamic>> acceptProductRequest(String requestId) async {
  try {
    print('🔄 Accepting product request: $requestId');
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/requests/$requestId/accept'),
      headers: headers,
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    return jsonDecode(response.body);
  } catch (e) {
    print('❌ Accept request error: $e');
    return {
      'success': false,
      'error': 'Connection error: $e',
    };
  }
}

// Decline a product request (for owner)
Future<Map<String, dynamic>> declineProductRequest(String requestId) async {
  try {
    print('🔄 Declining product request: $requestId');
    
    final response = await http.post(
      Uri.parse('$baseUrl/api/requests/$requestId/decline'),
      headers: headers,
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    return jsonDecode(response.body);
  } catch (e) {
    print('❌ Decline request error: $e');
    return {
      'success': false,
      'error': 'Connection error: $e',
    };
  }
}



// Get request details
Future<Map<String, dynamic>> getRequestDetails(String requestId) async {
  try {
    print('🔄 Getting request details: $requestId');
    
    final response = await http.get(
      Uri.parse('$baseUrl/api/request/$requestId'),
      headers: headers,
    );

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');

    return jsonDecode(response.body);
  } catch (e) {
    print('❌ Get request details error: $e');
    return {
      'success': false,
      'error': 'Connection error: $e',
    };
  }
}



  

  // ============ HTTP METHODS ============

  Future<Map<String, dynamic>> httpGet(String endpoint) async {
    try {
      print('🔄 GET $endpoint');
      final response = await http.get(
        Uri.parse('$baseUrl/$endpoint'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ HTTP GET error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> httpPost(String endpoint, Map<String, dynamic> data) async {
    try {
      print('🔄 POST $endpoint');
      print('📤 Data: $data');
      
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: headers,
        body: jsonEncode(data),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ HTTP POST error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> httpPut(String endpoint, Map<String, dynamic> data) async {
    try {
      print('🔄 PUT $endpoint');
      print('📤 Data: $data');
      
      final response = await http.put(
        Uri.parse('$baseUrl/$endpoint'),
        headers: headers,
        body: jsonEncode(data),
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ HTTP PUT error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> httpDelete(String endpoint) async {
    try {
      print('🔄 DELETE $endpoint');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$endpoint'),
        headers: headers,
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      return jsonDecode(response.body);
    } catch (e) {
      print('❌ HTTP DELETE error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }
}











// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// class ApiService {
//   static final ApiService _instance = ApiService._internal();
//   factory ApiService() => _instance;
//   ApiService._internal();

//   // IMPORTANT: Uncomment the one you're using
//   static const String baseUrl = 'https://foodsharingbackend.onrender.com'; // Production
//   // static const String baseUrl = 'http://localhost:5000'; // Local development
//   // static const String baseUrl = 'http://10.0.2.2:5000'; // Android emulator sys
  
//   String? _token;
//   bool _isInitialized = false;

//   // PUBLIC GETTERS
//   String get apiBaseUrl => ApiService.baseUrl;
  
//   Map<String, String> get headers {
//     Map<String, String> headers = {
//       'Content-Type': 'application/json',
//     };
    
//     if (_token != null && _token!.isNotEmpty) {
//       headers['Authorization'] = 'Bearer $_token';
//     }
    
//     return headers;
//   }

//   bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  
//   String? get token => _token;

//   // Initialize - must be called at app startup
//   Future<void> initialize() async {
//     if (_isInitialized) return;
    
//     print('🔄 Initializing ApiService...');
//     await _loadToken();
//     _isInitialized = true;
    
//     print('✅ ApiService initialized');
//     print('🔑 Token loaded: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
//   }

//   // Load token from shared preferences
//   Future<void> _loadToken() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       _token = prefs.getString('auth_token');
      
//       if (_token != null) {
//         print('📁 Loaded token from storage: ${_token!.substring(0, 30)}...');
//       } else {
//         print('📁 No token found in storage');
//       }
//     } catch (e) {
//       print('❌ Error loading token: $e');
//       _token = null;
//     }
//   }

//   // Save token to shared preferences
//   Future<void> _saveToken(String token) async {
//     try {
//       _token = token;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('auth_token', token);
//       print('💾 Token saved to storage: ${token.substring(0, 30)}...');
//     } catch (e) {
//       print('❌ Error saving token: $e');
//     }
//   }

//   // Clear token (logout)
//   Future<void> clearToken() async {
//     try {
//       print('🗑️ Clearing token...');
//       _token = null;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.remove('auth_token');
//       await prefs.remove('user_data');
//       print('✅ Token cleared');
//     } catch (e) {
//       print('❌ Error clearing token: $e');
//     }
//   }

//   // ============ AUTH METHODS ============

//   // Login user
//   Future<Map<String, dynamic>> login({
//     required String email,
//     required String password,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGIN STARTED');
//       print('📤 Email: $email');
//       print('🌐 URL: $baseUrl/api/auth/login');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/login'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       if (response.body.length > 200) {
//         print('📥 Response preview: ${response.body.substring(0, 200)}...');
//       } else {
//         print('📥 Response: ${response.body}');
//       }

//       if (response.body.isEmpty) {
//         print('❌ ERROR: Empty response from server');
//         return {
//           'success': false,
//           'error': 'Server returned empty response',
//           'statusCode': response.statusCode,
//         };
//       }

//       Map<String, dynamic> data;
//       try {
//         data = jsonDecode(response.body);
//         print('✅ JSON parsed successfully');
//         print('📊 Response keys: ${data.keys.toList()}');
//       } catch (e) {
//         print('❌ JSON Parse Error: $e');
//         print('❌ Raw response: ${response.body}');
//         return {
//           'success': false,
//           'error': 'Invalid JSON response from server: $e',
//           'statusCode': response.statusCode,
//         };
//       }

//       if (response.statusCode == 200) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ LOGIN SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Login successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing or invalid in response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//             'statusCode': response.statusCode,
//           };
//         }
//       } else {
//         print('❌ ERROR: Server returned status ${response.statusCode}');
//         final errorMessage = data['error'] ?? 
//                            data['message'] ?? 
//                            'Login failed with status ${response.statusCode}';
        
//         return {
//           'success': false,
//           'error': errorMessage,
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Network error: $e',
//       };
//     }
//   }

//   // Register user
//   Future<Map<String, dynamic>> register({
//     required String email,
//     required String password,
//     required String name,
//     required String phone,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 REGISTRATION STARTED');
//       print('📤 Email: $email, Name: $name');
//       print('🌐 URL: $baseUrl/api/auth/register');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/register'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//           'name': name.trim(),
//           'phone': phone.trim(),
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 201) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ REGISTRATION SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Registration successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing in registration response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//           };
//         }
//       } else {
//         print('❌ ERROR: Registration failed');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Registration failed',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ IMAGE UPLOAD METHODS ============

//   Future<Map<String, dynamic>> uploadImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading image via web (base64)...');
//       print('📤 Base64 length: ${base64Image.length}');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/crops/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Upload response status: ${response.statusCode}');
//       print('📥 Upload response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadProfileImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading profile image via web...');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/profile/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {
//             ...currentUserData,
//             'profile_image_url': data['imageUrl'],
//           };
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User profile image updated locally');
//         }
        
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//           'user': data['user'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadCropImage(String imagePath) async {
//     try {
//       print('🔄 Uploading crop image...');
      
//       var request = http.MultipartRequest(
//         'POST',
//         Uri.parse('$baseUrl/api/crops/upload-image'),
//       );
      
//       request.headers.addAll(headers);
      
//       final file = await http.MultipartFile.fromPath('image', imagePath);
//       request.files.add(file);
      
//       final streamedResponse = await request.send();
//       final response = await http.Response.fromStream(streamedResponse);
      
//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload crop image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ USER METHODS ============

//   Future<Map<String, dynamic>> getCurrentUser() async {
//     try {
//       print('=' * 50);
//       print('🔄 GETTING CURRENT USER');
//       print('🌐 URL: $baseUrl/api/auth/me');
//       print('🔑 Using token: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
      
//       if (_token == null || _token!.isEmpty) {
//         print('❌ ERROR: No authentication token available');
//         return {
//           'success': false,
//           'error': 'Not authenticated',
//         };
//       }

//       final response = await http.get(
//         Uri.parse('$baseUrl/api/auth/me'),
//         headers: headers,
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 200 && data['success'] == true) {
//         print('✅ USER FETCH SUCCESS');
//         print('=' * 50);
//         return {
//           'success': true,
//           'user': data['user'],
//         };
//       } else {
//         print('❌ ERROR: Failed to fetch user');
//         print('❌ Server message: ${data['error']}');
        
//         if (response.statusCode == 401) {
//           print('⚠️ Token invalid, clearing...');
//           await clearToken();
//         }
        
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch user',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserProfile() async {
//     try {
//       print('🔄 Getting user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'profile': data['profile'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateUserProfile({
//     String? name,
//     String? bio,
//     String? location,
//     String? gardenName,
//     String? gardenSize,
//   }) async {
//     try {
//       print('🔄 Updating user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final Map<String, dynamic> updateData = {};
      
//       if (name != null) updateData['name'] = name;
//       if (bio != null) updateData['bio'] = bio;
//       if (location != null) updateData['location'] = location;
//       if (gardenName != null) updateData['garden_name'] = gardenName;
//       if (gardenSize != null) updateData['garden_size'] = gardenSize;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {...currentUserData, ...updateData};
          
//           if (data['user'] != null && data['user']['profile_image_url'] != null) {
//             updatedUser['profile_image_url'] = data['user']['profile_image_url'];
//           }
          
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User data updated locally');
          
//           return {
//             'success': true,
//             'user': updatedUser,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         } else {
//           return {
//             'success': true,
//             'user': data['user'] ?? updateData,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         }
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getImpactStats() async {
//     try {
//       print('🔄 Getting impact stats');
//       print('🌐 URL: $baseUrl/api/profile/stats/impact');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile/stats/impact'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'impact': data['impact'] ?? {},
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch impact stats',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get impact stats error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ GARDEN & CROPS METHODS ============

//   Future<Map<String, dynamic>> getUserCrops() async {
//     try {
//       print('🔄 Getting user crops');
//       print('🌐 URL: $baseUrl/api/crops');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/crops'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'crops': data['crops'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch crops',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get crops error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserGardens() async {
//     try {
//       print('🔄 Getting user gardens');
//       print('🌐 URL: $baseUrl/api/gardens');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/gardens'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'gardens': data['gardens'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch gardens',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get gardens error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ SHARED ITEMS METHODS ============

//   Future<Map<String, dynamic>> getSharedItems() async {
//     try {
//       print('🔄 Getting shared items');
//       print('🌐 URL: $baseUrl/api/shared-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getMySharedItems() async {
//     try {
//       print('🔄 Getting my shared items');
//       print('🌐 URL: $baseUrl/api/shared-items/my-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items/my-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch your shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get my shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> createSharedItem(Map<String, dynamic> itemData) async {
//     try {
//       print('🔄 Creating shared item');
//       print('📤 Data: $itemData');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//         body: jsonEncode(itemData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 201 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item shared successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to share item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Create shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemStatus(String itemId, String status) async {
//     try {
//       print('🔄 Updating shared item $itemId status to $status');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId/status'),
//         headers: headers,
//         body: jsonEncode({'status': status}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Status updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update status',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemQuantity(String itemId, int newQuantity) async {
//     try {
//       print('🔄 Updating shared item $itemId quantity to $newQuantity');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode({'quantity': newQuantity}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Quantity updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update quantity',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update quantity error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItem(String itemId, {int? quantity, String? status}) async {
//     try {
//       print('🔄 Updating shared item $itemId');
//       final Map<String, dynamic> updateData = {};
//       if (quantity != null) updateData['quantity'] = quantity;
//       if (status != null) updateData['status'] = status;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> deleteSharedItem(String itemId) async {
//     try {
//       print('🔄 Deleting shared item $itemId');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item deleted successfully',
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to delete item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Delete shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ CHAT METHODS ============

//   Future<Map<String, dynamic>> getUserChats() async {
//     try {
//       print('🔄 Getting user chats');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting chats: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> getChatMessages(String chatId) async {
//     try {
//       print('🔄 Getting chat messages for $chatId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats/$chatId/messages'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting messages: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> sendMessage({
//     required String chatId,
//     required String recipientId,
//     required String text,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Sending message to $recipientId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/messages'),
//         headers: headers,
//         body: jsonEncode({
//           'chatId': chatId,
//           'recipientId': recipientId,
//           'text': text,
//           'productId': productId,
//         }),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error sending message: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> markMessagesAsRead(String chatId, List<String> messageIds) async {
//     try {
//       print('🔄 Marking messages as read in $chatId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats/$chatId/read'),
//         headers: headers,
//         body: jsonEncode({'messageIds': messageIds}),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error marking messages as read: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> createOrGetChat({
//     required String recipientId,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Creating or getting chat with recipient: $recipientId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//         body: jsonEncode({
//           'recipientId': recipientId,
//           'productId': productId,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'chat': data['chat'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to create chat',
//         };
//       }
//     } catch (e) {
//       print('❌ Create chat error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ QUESTIONS & ANSWERS METHODS ============

//   // Get all questions with optional filters
//   Future<Map<String, dynamic>> getCropQuestions({
//     String? category,
//     String? search,
//     bool? solved,
//     int limit = 20,
//     int offset = 0,
//   }) async {
//     try {
//       print('🔄 Getting crop questions');
      
//       // Build query parameters
//       final Map<String, String> queryParams = {};
//       if (category != null && category != 'All') queryParams['category'] = category;
//       if (search != null && search.isNotEmpty) queryParams['search'] = search;
//       if (solved != null) queryParams['solved'] = solved.toString();
//       queryParams['limit'] = limit.toString();
//       queryParams['offset'] = offset.toString();
      
//       final uri = Uri.parse('$baseUrl/api/questions').replace(queryParameters: queryParams);
//       print('🌐 URL: $uri');
      
//       final response = await http.get(
//         uri,
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get crop questions error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//         'questions': [],
//       };
//     }
//   }

//   // Get a single question with its answers
//   Future<Map<String, dynamic>> getQuestionWithAnswers(String questionId) async {
//     try {
//       print('🔄 Getting question details for: $questionId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get question details error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post a new question
//   Future<Map<String, dynamic>> postCropQuestion({
//     required String title,
//     String? description,
//     required String category,
//     String? imageUrl,
//   }) async {
//     try {
//       print('🔄 Posting new question');
//       print('📤 Title: $title');
//       print('📤 Category: $category');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions'),
//         headers: headers,
//         body: jsonEncode({
//           'title': title,
//           'description': description ?? '',
//           'category': category,
//           'image_url': imageUrl,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post crop question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post an answer to a question
//   Future<Map<String, dynamic>> postAnswer({
//     required String questionId,
//     required String text,
//   }) async {
//     try {
//       print('🔄 Posting answer to question: $questionId');
//       print('📤 Answer: $text');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/answers'),
//         headers: headers,
//         body: jsonEncode({'text': text}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Get answers for a specific question
//   Future<Map<String, dynamic>> getQuestionAnswers(String questionId) async {
//     try {
//       print('🔄 Getting answers for question: $questionId');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final data = jsonDecode(response.body);
      
//       if (data['success'] == true && data['question'] != null) {
//         return {
//           'success': true,
//           'answers': data['question']['answers'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to get answers',
//         };
//       }
//     } catch (e) {
//       print('❌ Get answers error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Toggle like for question - UPDATED (removed /toggle-like)
//   Future<Map<String, dynamic>> toggleQuestionLike(String questionId) async {
//     try {
//       print('🔄 Toggling like for question: $questionId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       if (response.statusCode == 200) {
//         return jsonDecode(response.body);
//       } else {
//         return {
//           'success': false,
//           'error': 'Failed to toggle like',
//           'statusCode': response.statusCode
//         };
//       }
//     } catch (e) {
//       print('❌ Toggle like error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Toggle like for answer - UPDATED (removed /toggle-like)
//   Future<Map<String, dynamic>> toggleAnswerLike(String answerId) async {
//     try {
//       print('🔄 Toggling like for answer: $answerId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/answers/$answerId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       if (response.statusCode == 200) {
//         return jsonDecode(response.body);
//       } else {
//         return {
//           'success': false,
//           'error': 'Failed to toggle like',
//           'statusCode': response.statusCode
//         };
//       }
//     } catch (e) {
//       print('❌ Toggle like error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Mark a question as solved
//   Future<Map<String, dynamic>> markQuestionSolved(String questionId) async {
//     try {
//       print('🔄 Marking question as solved: $questionId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//         body: jsonEncode({'solved': true}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Mark question solved error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Accept an answer as solution
//   Future<Map<String, dynamic>> acceptAnswer(String answerId) async {
//     try {
//       print('🔄 Accepting answer as solution: $answerId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/answers/$answerId/accept'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Accept answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ OTHER METHODS ============

//   Future<Map<String, dynamic>> logout() async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGOUT STARTED');
      
//       if (_token != null && _token!.isNotEmpty) {
//         final response = await http.post(
//           Uri.parse('$baseUrl/api/auth/logout'),
//           headers: headers,
//         );
//         print('📥 Logout HTTP Status: ${response.statusCode}');
//       }
      
//       await clearToken();
      
//       print('✅ LOGOUT COMPLETE');
//       print('=' * 50);
      
//       return {
//         'success': true,
//         'message': 'Logged out successfully',
//       };
//     } catch (e) {
//       await clearToken();
//       print('⚠️ Logout server call failed, but local data cleared: $e');
      
//       return {
//         'success': true,
//         'message': 'Logged out locally',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> forgotPassword(String email) async {
//     try {
//       print('=' * 50);
//       print('🔄 FORGOT PASSWORD');
//       print('📤 Email: $email');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/forgot-password'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': email.trim()}),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200) {
//         print('✅ PASSWORD RESET EMAIL SENT');
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Password reset email sent',
//         };
//       } else {
//         print('❌ ERROR: Failed to send reset email');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to send reset email',
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>?> getSavedUserData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final userDataString = prefs.getString('user_data');
      
//       if (userDataString != null && userDataString.isNotEmpty) {
//         return jsonDecode(userDataString);
//       }
//     } catch (e) {
//       print('❌ Error loading saved user data: $e');
//     }
//     return null;
//   }

//   bool isTokenValid(String? token) {
//     if (token == null || token.isEmpty) return false;
    
//     final parts = token.split('.');
//     if (parts.length != 3) return false;
    
//     if (!token.startsWith('eyJ')) return false;
    
//     return true;
//   }

//   Future<bool> checkTokenValidity() async {
//     if (_token == null || _token!.isEmpty) return false;
    
//     if (!isTokenValid(_token)) {
//       print('⚠️ Token format is invalid');
//       await clearToken();
//       return false;
//     }
    
//     return true;
//   }

//   // ============ HTTP METHODS ============

//   Future<Map<String, dynamic>> httpGet(String endpoint) async {
//     try {
//       print('🔄 GET $endpoint');
//       final response = await http.get(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP GET error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPost(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 POST $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP POST error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPut(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 PUT $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP PUT error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpDelete(String endpoint) async {
//     try {
//       print('🔄 DELETE $endpoint');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP DELETE error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }
// }







// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// class ApiService {
//   static final ApiService _instance = ApiService._internal();
//   factory ApiService() => _instance;
//   ApiService._internal();

//   // IMPORTANT: Uncomment the one you're using
//   static const String baseUrl = 'https://foodsharingbackend.onrender.com'; // Production
//   // static const String baseUrl = 'http://localhost:5000'; // Local development
//   // static const String baseUrl = 'http://10.0.2.2:5000'; // Android emulator sys
  
//   String? _token;
//   bool _isInitialized = false;

//   // PUBLIC GETTERS
//   String get apiBaseUrl => ApiService.baseUrl;
  
//   Map<String, String> get headers {
//     Map<String, String> headers = {
//       'Content-Type': 'application/json',
//     };
    
//     if (_token != null && _token!.isNotEmpty) {
//       headers['Authorization'] = 'Bearer $_token';
//     }
    
//     return headers;
//   }

//   bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  
//   String? get token => _token;

//   // Initialize - must be called at app startup
//   Future<void> initialize() async {
//     if (_isInitialized) return;
    
//     print('🔄 Initializing ApiService...');
//     await _loadToken();
//     _isInitialized = true;
    
//     print('✅ ApiService initialized');
//     print('🔑 Token loaded: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
//   }

//   // Load token from shared preferences
//   Future<void> _loadToken() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       _token = prefs.getString('auth_token');
      
//       if (_token != null) {
//         print('📁 Loaded token from storage: ${_token!.substring(0, 30)}...');
//       } else {
//         print('📁 No token found in storage');
//       }
//     } catch (e) {
//       print('❌ Error loading token: $e');
//       _token = null;
//     }
//   }

//   // Save token to shared preferences
//   Future<void> _saveToken(String token) async {
//     try {
//       _token = token;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('auth_token', token);
//       print('💾 Token saved to storage: ${token.substring(0, 30)}...');
//     } catch (e) {
//       print('❌ Error saving token: $e');
//     }
//   }

//   // Clear token (logout)
//   Future<void> clearToken() async {
//     try {
//       print('🗑️ Clearing token...');
//       _token = null;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.remove('auth_token');
//       await prefs.remove('user_data');
//       print('✅ Token cleared');
//     } catch (e) {
//       print('❌ Error clearing token: $e');
//     }
//   }

//   // ============ AUTH METHODS ============

//   // Login user
//   Future<Map<String, dynamic>> login({
//     required String email,
//     required String password,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGIN STARTED');
//       print('📤 Email: $email');
//       print('🌐 URL: $baseUrl/api/auth/login');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/login'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       if (response.body.length > 200) {
//         print('📥 Response preview: ${response.body.substring(0, 200)}...');
//       } else {
//         print('📥 Response: ${response.body}');
//       }

//       if (response.body.isEmpty) {
//         print('❌ ERROR: Empty response from server');
//         return {
//           'success': false,
//           'error': 'Server returned empty response',
//           'statusCode': response.statusCode,
//         };
//       }

//       Map<String, dynamic> data;
//       try {
//         data = jsonDecode(response.body);
//         print('✅ JSON parsed successfully');
//         print('📊 Response keys: ${data.keys.toList()}');
//       } catch (e) {
//         print('❌ JSON Parse Error: $e');
//         print('❌ Raw response: ${response.body}');
//         return {
//           'success': false,
//           'error': 'Invalid JSON response from server: $e',
//           'statusCode': response.statusCode,
//         };
//       }

//       if (response.statusCode == 200) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ LOGIN SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Login successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing or invalid in response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//             'statusCode': response.statusCode,
//           };
//         }
//       } else {
//         print('❌ ERROR: Server returned status ${response.statusCode}');
//         final errorMessage = data['error'] ?? 
//                            data['message'] ?? 
//                            'Login failed with status ${response.statusCode}';
        
//         return {
//           'success': false,
//           'error': errorMessage,
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Network error: $e',
//       };
//     }
//   }

//   // Register user
//   Future<Map<String, dynamic>> register({
//     required String email,
//     required String password,
//     required String name,
//     required String phone,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 REGISTRATION STARTED');
//       print('📤 Email: $email, Name: $name');
//       print('🌐 URL: $baseUrl/api/auth/register');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/register'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//           'name': name.trim(),
//           'phone': phone.trim(),
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 201) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ REGISTRATION SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Registration successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing in registration response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//           };
//         }
//       } else {
//         print('❌ ERROR: Registration failed');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Registration failed',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ IMAGE UPLOAD METHODS ============

//   Future<Map<String, dynamic>> uploadImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading image via web (base64)...');
//       print('📤 Base64 length: ${base64Image.length}');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/crops/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Upload response status: ${response.statusCode}');
//       print('📥 Upload response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadProfileImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading profile image via web...');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/profile/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {
//             ...currentUserData,
//             'profile_image_url': data['imageUrl'],
//           };
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User profile image updated locally');
//         }
        
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//           'user': data['user'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadCropImage(String imagePath) async {
//     try {
//       print('🔄 Uploading crop image...');
      
//       var request = http.MultipartRequest(
//         'POST',
//         Uri.parse('$baseUrl/api/crops/upload-image'),
//       );
      
//       request.headers.addAll(headers);
      
//       final file = await http.MultipartFile.fromPath('image', imagePath);
//       request.files.add(file);
      
//       final streamedResponse = await request.send();
//       final response = await http.Response.fromStream(streamedResponse);
      
//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload crop image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ USER METHODS ============

//   Future<Map<String, dynamic>> getCurrentUser() async {
//     try {
//       print('=' * 50);
//       print('🔄 GETTING CURRENT USER');
//       print('🌐 URL: $baseUrl/api/auth/me');
//       print('🔑 Using token: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
      
//       if (_token == null || _token!.isEmpty) {
//         print('❌ ERROR: No authentication token available');
//         return {
//           'success': false,
//           'error': 'Not authenticated',
//         };
//       }

//       final response = await http.get(
//         Uri.parse('$baseUrl/api/auth/me'),
//         headers: headers,
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 200 && data['success'] == true) {
//         print('✅ USER FETCH SUCCESS');
//         print('=' * 50);
//         return {
//           'success': true,
//           'user': data['user'],
//         };
//       } else {
//         print('❌ ERROR: Failed to fetch user');
//         print('❌ Server message: ${data['error']}');
        
//         if (response.statusCode == 401) {
//           print('⚠️ Token invalid, clearing...');
//           await clearToken();
//         }
        
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch user',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserProfile() async {
//     try {
//       print('🔄 Getting user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'profile': data['profile'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateUserProfile({
//     String? name,
//     String? bio,
//     String? location,
//     String? gardenName,
//     String? gardenSize,
//   }) async {
//     try {
//       print('🔄 Updating user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final Map<String, dynamic> updateData = {};
      
//       if (name != null) updateData['name'] = name;
//       if (bio != null) updateData['bio'] = bio;
//       if (location != null) updateData['location'] = location;
//       if (gardenName != null) updateData['garden_name'] = gardenName;
//       if (gardenSize != null) updateData['garden_size'] = gardenSize;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {...currentUserData, ...updateData};
          
//           if (data['user'] != null && data['user']['profile_image_url'] != null) {
//             updatedUser['profile_image_url'] = data['user']['profile_image_url'];
//           }
          
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User data updated locally');
          
//           return {
//             'success': true,
//             'user': updatedUser,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         } else {
//           return {
//             'success': true,
//             'user': data['user'] ?? updateData,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         }
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getImpactStats() async {
//     try {
//       print('🔄 Getting impact stats');
//       print('🌐 URL: $baseUrl/api/profile/stats/impact');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile/stats/impact'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'impact': data['impact'] ?? {},
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch impact stats',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get impact stats error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ GARDEN & CROPS METHODS ============

//   Future<Map<String, dynamic>> getUserCrops() async {
//     try {
//       print('🔄 Getting user crops');
//       print('🌐 URL: $baseUrl/api/crops');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/crops'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'crops': data['crops'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch crops',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get crops error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserGardens() async {
//     try {
//       print('🔄 Getting user gardens');
//       print('🌐 URL: $baseUrl/api/gardens');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/gardens'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'gardens': data['gardens'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch gardens',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get gardens error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ SHARED ITEMS METHODS ============

//   Future<Map<String, dynamic>> getSharedItems() async {
//     try {
//       print('🔄 Getting shared items');
//       print('🌐 URL: $baseUrl/api/shared-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getMySharedItems() async {
//     try {
//       print('🔄 Getting my shared items');
//       print('🌐 URL: $baseUrl/api/shared-items/my-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items/my-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch your shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get my shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> createSharedItem(Map<String, dynamic> itemData) async {
//     try {
//       print('🔄 Creating shared item');
//       print('📤 Data: $itemData');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//         body: jsonEncode(itemData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 201 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item shared successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to share item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Create shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemStatus(String itemId, String status) async {
//     try {
//       print('🔄 Updating shared item $itemId status to $status');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId/status'),
//         headers: headers,
//         body: jsonEncode({'status': status}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Status updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update status',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemQuantity(String itemId, int newQuantity) async {
//     try {
//       print('🔄 Updating shared item $itemId quantity to $newQuantity');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode({'quantity': newQuantity}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Quantity updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update quantity',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update quantity error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItem(String itemId, {int? quantity, String? status}) async {
//     try {
//       print('🔄 Updating shared item $itemId');
//       final Map<String, dynamic> updateData = {};
//       if (quantity != null) updateData['quantity'] = quantity;
//       if (status != null) updateData['status'] = status;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> deleteSharedItem(String itemId) async {
//     try {
//       print('🔄 Deleting shared item $itemId');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item deleted successfully',
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to delete item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Delete shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ CHAT METHODS ============

//   Future<Map<String, dynamic>> getUserChats() async {
//     try {
//       print('🔄 Getting user chats');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting chats: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> getChatMessages(String chatId) async {
//     try {
//       print('🔄 Getting chat messages for $chatId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats/$chatId/messages'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting messages: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> sendMessage({
//     required String chatId,
//     required String recipientId,
//     required String text,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Sending message to $recipientId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/messages'),
//         headers: headers,
//         body: jsonEncode({
//           'chatId': chatId,
//           'recipientId': recipientId,
//           'text': text,
//           'productId': productId,
//         }),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error sending message: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> markMessagesAsRead(String chatId, List<String> messageIds) async {
//     try {
//       print('🔄 Marking messages as read in $chatId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats/$chatId/read'),
//         headers: headers,
//         body: jsonEncode({'messageIds': messageIds}),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error marking messages as read: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> createOrGetChat({
//     required String recipientId,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Creating or getting chat with recipient: $recipientId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//         body: jsonEncode({
//           'recipientId': recipientId,
//           'productId': productId,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'chat': data['chat'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to create chat',
//         };
//       }
//     } catch (e) {
//       print('❌ Create chat error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ QUESTIONS & ANSWERS METHODS ============

//   // Get all questions with optional filters
//   Future<Map<String, dynamic>> getCropQuestions({
//     String? category,
//     String? search,
//     bool? solved,
//     int limit = 20,
//     int offset = 0,
//   }) async {
//     try {
//       print('🔄 Getting crop questions');
      
//       // Build query parameters
//       final Map<String, String> queryParams = {};
//       if (category != null && category != 'All') queryParams['category'] = category;
//       if (search != null && search.isNotEmpty) queryParams['search'] = search;
//       if (solved != null) queryParams['solved'] = solved.toString();
//       queryParams['limit'] = limit.toString();
//       queryParams['offset'] = offset.toString();
      
//       final uri = Uri.parse('$baseUrl/api/questions').replace(queryParameters: queryParams);
//       print('🌐 URL: $uri');
      
//       final response = await http.get(
//         uri,
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get crop questions error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//         'questions': [],
//       };
//     }
//   }

//   // Get a single question with its answers
//   Future<Map<String, dynamic>> getQuestionWithAnswers(String questionId) async {
//     try {
//       print('🔄 Getting question details for: $questionId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get question details error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post a new question
//   Future<Map<String, dynamic>> postCropQuestion({
//     required String title,
//     String? description,
//     required String category,
//     String? imageUrl,
//   }) async {
//     try {
//       print('🔄 Posting new question');
//       print('📤 Title: $title');
//       print('📤 Category: $category');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions'),
//         headers: headers,
//         body: jsonEncode({
//           'title': title,
//           'description': description ?? '',
//           'category': category,
//           'image_url': imageUrl,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post crop question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post an answer to a question
//   Future<Map<String, dynamic>> postAnswer({
//     required String questionId,
//     required String text,
//   }) async {
//     try {
//       print('🔄 Posting answer to question: $questionId');
//       print('📤 Answer: $text');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/answers'),
//         headers: headers,
//         body: jsonEncode({'text': text}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Get answers for a specific question
//   Future<Map<String, dynamic>> getQuestionAnswers(String questionId) async {
//     try {
//       print('🔄 Getting answers for question: $questionId');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final data = jsonDecode(response.body);
      
//       if (data['success'] == true && data['question'] != null) {
//         return {
//           'success': true,
//           'answers': data['question']['answers'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to get answers',
//         };
//       }
//     } catch (e) {
//       print('❌ Get answers error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Like a question - UPDATED
//   Future<Map<String, dynamic>> likeQuestion(String questionId) async {
//     try {
//       print('🔄 Liking question: $questionId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'likes': data['likes'] ?? 0,
//           'liked': data['liked'] ?? true,
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to like question',
//         };
//       }
//     } catch (e) {
//       print('❌ Like question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Unlike a question - UPDATED
//   Future<Map<String, dynamic>> unlikeQuestion(String questionId) async {
//     try {
//       print('🔄 Unliking question: $questionId');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/api/questions/$questionId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'likes': data['likes'] ?? 0,
//           'liked': false,
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to unlike question',
//         };
//       }
//     } catch (e) {
//       print('❌ Unlike question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Toggle like for question - NEW METHOD
//   Future<Map<String, dynamic>> toggleQuestionLike(String questionId) async {
//     try {
//       print('🔄 Toggling like for question: $questionId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/toggle-like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Toggle like error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Like an answer - UPDATED
//   Future<Map<String, dynamic>> likeAnswer(String answerId) async {
//     try {
//       print('🔄 Liking answer: $answerId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/answers/$answerId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'likes': data['likes'] ?? 0,
//           'liked': data['liked'] ?? true,
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to like answer',
//         };
//       }
//     } catch (e) {
//       print('❌ Like answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Unlike an answer - UPDATED
//   Future<Map<String, dynamic>> unlikeAnswer(String answerId) async {
//     try {
//       print('🔄 Unliking answer: $answerId');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/api/answers/$answerId/like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'likes': data['likes'] ?? 0,
//           'liked': false,
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to unlike answer',
//         };
//       }
//     } catch (e) {
//       print('❌ Unlike answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Toggle like for answer - NEW METHOD
//   Future<Map<String, dynamic>> toggleAnswerLike(String answerId) async {
//     try {
//       print('🔄 Toggling like for answer: $answerId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/answers/$answerId/toggle-like'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Toggle like error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Mark a question as solved
//   Future<Map<String, dynamic>> markQuestionSolved(String questionId) async {
//     try {
//       print('🔄 Marking question as solved: $questionId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//         body: jsonEncode({'solved': true}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Mark question solved error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Accept an answer as solution
//   Future<Map<String, dynamic>> acceptAnswer(String answerId) async {
//     try {
//       print('🔄 Accepting answer as solution: $answerId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/answers/$answerId/accept'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Accept answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ OTHER METHODS ============

//   Future<Map<String, dynamic>> logout() async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGOUT STARTED');
      
//       if (_token != null && _token!.isNotEmpty) {
//         final response = await http.post(
//           Uri.parse('$baseUrl/api/auth/logout'),
//           headers: headers,
//         );
//         print('📥 Logout HTTP Status: ${response.statusCode}');
//       }
      
//       await clearToken();
      
//       print('✅ LOGOUT COMPLETE');
//       print('=' * 50);
      
//       return {
//         'success': true,
//         'message': 'Logged out successfully',
//       };
//     } catch (e) {
//       await clearToken();
//       print('⚠️ Logout server call failed, but local data cleared: $e');
      
//       return {
//         'success': true,
//         'message': 'Logged out locally',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> forgotPassword(String email) async {
//     try {
//       print('=' * 50);
//       print('🔄 FORGOT PASSWORD');
//       print('📤 Email: $email');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/forgot-password'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': email.trim()}),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200) {
//         print('✅ PASSWORD RESET EMAIL SENT');
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Password reset email sent',
//         };
//       } else {
//         print('❌ ERROR: Failed to send reset email');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to send reset email',
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>?> getSavedUserData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final userDataString = prefs.getString('user_data');
      
//       if (userDataString != null && userDataString.isNotEmpty) {
//         return jsonDecode(userDataString);
//       }
//     } catch (e) {
//       print('❌ Error loading saved user data: $e');
//     }
//     return null;
//   }

//   bool isTokenValid(String? token) {
//     if (token == null || token.isEmpty) return false;
    
//     final parts = token.split('.');
//     if (parts.length != 3) return false;
    
//     if (!token.startsWith('eyJ')) return false;
    
//     return true;
//   }

//   Future<bool> checkTokenValidity() async {
//     if (_token == null || _token!.isEmpty) return false;
    
//     if (!isTokenValid(_token)) {
//       print('⚠️ Token format is invalid');
//       await clearToken();
//       return false;
//     }
    
//     return true;
//   }

//   // ============ HTTP METHODS ============

//   Future<Map<String, dynamic>> httpGet(String endpoint) async {
//     try {
//       print('🔄 GET $endpoint');
//       final response = await http.get(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP GET error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPost(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 POST $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP POST error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPut(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 PUT $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP PUT error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpDelete(String endpoint) async {
//     try {
//       print('🔄 DELETE $endpoint');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP DELETE error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }
// }














// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// class ApiService {
//   static final ApiService _instance = ApiService._internal();
//   factory ApiService() => _instance;
//   ApiService._internal();

//   // IMPORTANT: Uncomment the one you're using
//   static const String baseUrl = 'https://foodsharingbackend.onrender.com'; // Production
//   // static const String baseUrl = 'http://localhost:5000'; // Local development
//   // static const String baseUrl = 'http://10.0.2.2:5000'; // Android emulator sys
  
//   String? _token;
//   bool _isInitialized = false;

//   // PUBLIC GETTERS
//   String get apiBaseUrl => ApiService.baseUrl;
  
//   Map<String, String> get headers {
//     Map<String, String> headers = {
//       'Content-Type': 'application/json',
//     };
    
//     if (_token != null && _token!.isNotEmpty) {
//       headers['Authorization'] = 'Bearer $_token';
//     }
    
//     return headers;
//   }

//   bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  
//   String? get token => _token;

//   // Initialize - must be called at app startup
//   Future<void> initialize() async {
//     if (_isInitialized) return;
    
//     print('🔄 Initializing ApiService...');
//     await _loadToken();
//     _isInitialized = true;
    
//     print('✅ ApiService initialized');
//     print('🔑 Token loaded: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
//   }

//   // Load token from shared preferences
//   Future<void> _loadToken() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       _token = prefs.getString('auth_token');
      
//       if (_token != null) {
//         print('📁 Loaded token from storage: ${_token!.substring(0, 30)}...');
//       } else {
//         print('📁 No token found in storage');
//       }
//     } catch (e) {
//       print('❌ Error loading token: $e');
//       _token = null;
//     }
//   }

//   // Save token to shared preferences
//   Future<void> _saveToken(String token) async {
//     try {
//       _token = token;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('auth_token', token);
//       print('💾 Token saved to storage: ${token.substring(0, 30)}...');
//     } catch (e) {
//       print('❌ Error saving token: $e');
//     }
//   }

//   // Clear token (logout)
//   Future<void> clearToken() async {
//     try {
//       print('🗑️ Clearing token...');
//       _token = null;
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.remove('auth_token');
//       await prefs.remove('user_data');
//       print('✅ Token cleared');
//     } catch (e) {
//       print('❌ Error clearing token: $e');
//     }
//   }

//   // ============ AUTH METHODS ============

//   // Login user
//   Future<Map<String, dynamic>> login({
//     required String email,
//     required String password,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGIN STARTED');
//       print('📤 Email: $email');
//       print('🌐 URL: $baseUrl/api/auth/login');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/login'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       if (response.body.length > 200) {
//         print('📥 Response preview: ${response.body.substring(0, 200)}...');
//       } else {
//         print('📥 Response: ${response.body}');
//       }

//       if (response.body.isEmpty) {
//         print('❌ ERROR: Empty response from server');
//         return {
//           'success': false,
//           'error': 'Server returned empty response',
//           'statusCode': response.statusCode,
//         };
//       }

//       Map<String, dynamic> data;
//       try {
//         data = jsonDecode(response.body);
//         print('✅ JSON parsed successfully');
//         print('📊 Response keys: ${data.keys.toList()}');
//       } catch (e) {
//         print('❌ JSON Parse Error: $e');
//         print('❌ Raw response: ${response.body}');
//         return {
//           'success': false,
//           'error': 'Invalid JSON response from server: $e',
//           'statusCode': response.statusCode,
//         };
//       }

//       if (response.statusCode == 200) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ LOGIN SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Login successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing or invalid in response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//             'statusCode': response.statusCode,
//           };
//         }
//       } else {
//         print('❌ ERROR: Server returned status ${response.statusCode}');
//         final errorMessage = data['error'] ?? 
//                            data['message'] ?? 
//                            'Login failed with status ${response.statusCode}';
        
//         return {
//           'success': false,
//           'error': errorMessage,
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Network error: $e',
//       };
//     }
//   }

//   // Register user
//   Future<Map<String, dynamic>> register({
//     required String email,
//     required String password,
//     required String name,
//     required String phone,
//   }) async {
//     try {
//       print('=' * 50);
//       print('🔄 REGISTRATION STARTED');
//       print('📤 Email: $email, Name: $name');
//       print('🌐 URL: $baseUrl/api/auth/register');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/register'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'email': email.trim(),
//           'password': password,
//           'name': name.trim(),
//           'phone': phone.trim(),
//         }),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 201) {
//         final token = data['token'];
        
//         if (token != null && token is String && token.isNotEmpty) {
//           print('✅ Token found: ${token.substring(0, 50)}...');
          
//           await _saveToken(token);
          
//           if (data['user'] != null) {
//             try {
//               final prefs = await SharedPreferences.getInstance();
//               await prefs.setString('user_data', jsonEncode(data['user']));
//               print('✅ User data saved');
//             } catch (e) {
//               print('⚠️ Warning: Could not save user data: $e');
//             }
//           }
          
//           print('✅ REGISTRATION SUCCESS');
//           print('=' * 50);
          
//           return {
//             'success': true,
//             'token': token,
//             'user': data['user'],
//             'message': data['message'] ?? 'Registration successful',
//           };
//         } else {
//           print('❌ ERROR: Token missing in registration response');
//           return {
//             'success': false,
//             'error': 'Authentication token missing from server response',
//             'responseData': data,
//           };
//         }
//       } else {
//         print('❌ ERROR: Registration failed');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Registration failed',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ IMAGE UPLOAD METHODS ============

//   Future<Map<String, dynamic>> uploadImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading image via web (base64)...');
//       print('📤 Base64 length: ${base64Image.length}');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/crops/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Upload response status: ${response.statusCode}');
//       print('📥 Upload response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadProfileImageWeb(String base64Image, String fileName) async {
//     try {
//       print('🔄 Uploading profile image via web...');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/profile/upload-image-web'),
//         headers: headers,
//         body: jsonEncode({
//           'image': base64Image,
//           'fileName': fileName,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {
//             ...currentUserData,
//             'profile_image_url': data['imageUrl'],
//           };
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User profile image updated locally');
//         }
        
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//           'user': data['user'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> uploadCropImage(String imagePath) async {
//     try {
//       print('🔄 Uploading crop image...');
      
//       var request = http.MultipartRequest(
//         'POST',
//         Uri.parse('$baseUrl/api/crops/upload-image'),
//       );
      
//       request.headers.addAll(headers);
      
//       final file = await http.MultipartFile.fromPath('image', imagePath);
//       request.files.add(file);
      
//       final streamedResponse = await request.send();
//       final response = await http.Response.fromStream(streamedResponse);
      
//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'imageUrl': data['imageUrl'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to upload image',
//         };
//       }
//     } catch (e) {
//       print('❌ Upload crop image error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ USER METHODS ============

//   Future<Map<String, dynamic>> getCurrentUser() async {
//     try {
//       print('=' * 50);
//       print('🔄 GETTING CURRENT USER');
//       print('🌐 URL: $baseUrl/api/auth/me');
//       print('🔑 Using token: ${_token != null ? "YES (${_token!.substring(0, 30)}...)" : "NO"}');
      
//       if (_token == null || _token!.isEmpty) {
//         print('❌ ERROR: No authentication token available');
//         return {
//           'success': false,
//           'error': 'Not authenticated',
//         };
//       }

//       final response = await http.get(
//         Uri.parse('$baseUrl/api/auth/me'),
//         headers: headers,
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
//       print('📥 Response length: ${response.body.length} characters');
      
//       Map<String, dynamic> data = jsonDecode(response.body);
//       print('📊 Response keys: ${data.keys.toList()}');

//       if (response.statusCode == 200 && data['success'] == true) {
//         print('✅ USER FETCH SUCCESS');
//         print('=' * 50);
//         return {
//           'success': true,
//           'user': data['user'],
//         };
//       } else {
//         print('❌ ERROR: Failed to fetch user');
//         print('❌ Server message: ${data['error']}');
        
//         if (response.statusCode == 401) {
//           print('⚠️ Token invalid, clearing...');
//           await clearToken();
//         }
        
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch user',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       print('=' * 50);
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserProfile() async {
//     try {
//       print('🔄 Getting user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'profile': data['profile'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateUserProfile({
//     String? name,
//     String? bio,
//     String? location,
//     String? gardenName,
//     String? gardenSize,
//   }) async {
//     try {
//       print('🔄 Updating user profile');
//       print('🌐 URL: $baseUrl/api/profile');
      
//       final Map<String, dynamic> updateData = {};
      
//       if (name != null) updateData['name'] = name;
//       if (bio != null) updateData['bio'] = bio;
//       if (location != null) updateData['location'] = location;
//       if (gardenName != null) updateData['garden_name'] = gardenName;
//       if (gardenSize != null) updateData['garden_size'] = gardenSize;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/profile'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);
      
//       if (response.statusCode == 200 && data['success'] == true) {
//         final prefs = await SharedPreferences.getInstance();
//         final currentUserData = await getSavedUserData();
        
//         if (currentUserData != null) {
//           final updatedUser = {...currentUserData, ...updateData};
          
//           if (data['user'] != null && data['user']['profile_image_url'] != null) {
//             updatedUser['profile_image_url'] = data['user']['profile_image_url'];
//           }
          
//           await prefs.setString('user_data', jsonEncode(updatedUser));
//           print('✅ User data updated locally');
          
//           return {
//             'success': true,
//             'user': updatedUser,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         } else {
//           return {
//             'success': true,
//             'user': data['user'] ?? updateData,
//             'message': data['message'] ?? 'Profile updated successfully',
//           };
//         }
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update profile',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update profile error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getImpactStats() async {
//     try {
//       print('🔄 Getting impact stats');
//       print('🌐 URL: $baseUrl/api/profile/stats/impact');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/profile/stats/impact'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'impact': data['impact'] ?? {},
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch impact stats',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get impact stats error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ GARDEN & CROPS METHODS ============

//   Future<Map<String, dynamic>> getUserCrops() async {
//     try {
//       print('🔄 Getting user crops');
//       print('🌐 URL: $baseUrl/api/crops');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/crops'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'crops': data['crops'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch crops',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get crops error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getUserGardens() async {
//     try {
//       print('🔄 Getting user gardens');
//       print('🌐 URL: $baseUrl/api/gardens');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/gardens'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'gardens': data['gardens'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch gardens',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get gardens error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ SHARED ITEMS METHODS ============

//   Future<Map<String, dynamic>> getSharedItems() async {
//     try {
//       print('🔄 Getting shared items');
//       print('🌐 URL: $baseUrl/api/shared-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> getMySharedItems() async {
//     try {
//       print('🔄 Getting my shared items');
//       print('🌐 URL: $baseUrl/api/shared-items/my-items');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/shared-items/my-items'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'items': data['items'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to fetch your shared items',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Get my shared items error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> createSharedItem(Map<String, dynamic> itemData) async {
//     try {
//       print('🔄 Creating shared item');
//       print('📤 Data: $itemData');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/shared-items'),
//         headers: headers,
//         body: jsonEncode(itemData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 201 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item shared successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to share item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Create shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemStatus(String itemId, String status) async {
//     try {
//       print('🔄 Updating shared item $itemId status to $status');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId/status'),
//         headers: headers,
//         body: jsonEncode({'status': status}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Status updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update status',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItemQuantity(String itemId, int newQuantity) async {
//     try {
//       print('🔄 Updating shared item $itemId quantity to $newQuantity');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode({'quantity': newQuantity}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Quantity updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update quantity',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update quantity error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> updateSharedItem(String itemId, {int? quantity, String? status}) async {
//     try {
//       print('🔄 Updating shared item $itemId');
//       final Map<String, dynamic> updateData = {};
//       if (quantity != null) updateData['quantity'] = quantity;
//       if (status != null) updateData['status'] = status;
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//         body: jsonEncode(updateData),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item updated successfully',
//           'item': data['item'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to update item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Update item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> deleteSharedItem(String itemId) async {
//     try {
//       print('🔄 Deleting shared item $itemId');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/api/shared-items/$itemId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Item deleted successfully',
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to delete item',
//           'statusCode': response.statusCode,
//         };
//       }
//     } catch (e) {
//       print('❌ Delete shared item error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ CHAT METHODS ============

//   Future<Map<String, dynamic>> getUserChats() async {
//     try {
//       print('🔄 Getting user chats');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting chats: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> getChatMessages(String chatId) async {
//     try {
//       print('🔄 Getting chat messages for $chatId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/chats/$chatId/messages'),
//         headers: headers,
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error getting messages: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> sendMessage({
//     required String chatId,
//     required String recipientId,
//     required String text,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Sending message to $recipientId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/messages'),
//         headers: headers,
//         body: jsonEncode({
//           'chatId': chatId,
//           'recipientId': recipientId,
//           'text': text,
//           'productId': productId,
//         }),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error sending message: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> markMessagesAsRead(String chatId, List<String> messageIds) async {
//     try {
//       print('🔄 Marking messages as read in $chatId');
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats/$chatId/read'),
//         headers: headers,
//         body: jsonEncode({'messageIds': messageIds}),
//       );
//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Error marking messages as read: $e');
//       return {'success': false, 'error': e.toString()};
//     }
//   }

//   Future<Map<String, dynamic>> createOrGetChat({
//     required String recipientId,
//     String? productId,
//   }) async {
//     try {
//       print('🔄 Creating or getting chat with recipient: $recipientId');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/chats'),
//         headers: headers,
//         body: jsonEncode({
//           'recipientId': recipientId,
//           'productId': productId,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200 && data['success'] == true) {
//         return {
//           'success': true,
//           'chat': data['chat'],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to create chat',
//         };
//       }
//     } catch (e) {
//       print('❌ Create chat error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ QUESTIONS & ANSWERS METHODS ============

//   // Get all questions with optional filters
//   Future<Map<String, dynamic>> getCropQuestions({
//     String? category,
//     String? search,
//     bool? solved,
//     int limit = 20,
//     int offset = 0,
//   }) async {
//     try {
//       print('🔄 Getting crop questions');
      
//       // Build query parameters
//       final Map<String, String> queryParams = {};
//       if (category != null && category != 'All') queryParams['category'] = category;
//       if (search != null && search.isNotEmpty) queryParams['search'] = search;
//       if (solved != null) queryParams['solved'] = solved.toString();
//       queryParams['limit'] = limit.toString();
//       queryParams['offset'] = offset.toString();
      
//       final uri = Uri.parse('$baseUrl/api/questions').replace(queryParameters: queryParams);
//       print('🌐 URL: $uri');
      
//       final response = await http.get(
//         uri,
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get crop questions error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//         'questions': [],
//       };
//     }
//   }

//   // Get a single question with its answers
//   Future<Map<String, dynamic>> getQuestionWithAnswers(String questionId) async {
//     try {
//       print('🔄 Getting question details for: $questionId');
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Get question details error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post a new question
//   Future<Map<String, dynamic>> postCropQuestion({
//     required String title,
//     String? description,
//     required String category,
//     String? imageUrl,
//   }) async {
//     try {
//       print('🔄 Posting new question');
//       print('📤 Title: $title');
//       print('📤 Category: $category');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions'),
//         headers: headers,
//         body: jsonEncode({
//           'title': title,
//           'description': description ?? '',
//           'category': category,
//           'image_url': imageUrl,
//         }),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post crop question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Post an answer to a question
//   Future<Map<String, dynamic>> postAnswer({
//     required String questionId,
//     required String text,
//   }) async {
//     try {
//       print('🔄 Posting answer to question: $questionId');
//       print('📤 Answer: $text');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/questions/$questionId/answers'),
//         headers: headers,
//         body: jsonEncode({'text': text}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Post answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Get answers for a specific question
//   Future<Map<String, dynamic>> getQuestionAnswers(String questionId) async {
//     try {
//       print('🔄 Getting answers for question: $questionId');
      
//       final response = await http.get(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       final data = jsonDecode(response.body);
      
//       if (data['success'] == true && data['question'] != null) {
//         return {
//           'success': true,
//           'answers': data['question']['answers'] ?? [],
//         };
//       } else {
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to get answers',
//         };
//       }
//     } catch (e) {
//       print('❌ Get answers error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Like/Unlike a question
//   Future<Map<String, dynamic>> likeQuestion(String questionId, bool like) async {
//     try {
//       print('🔄 ${like ? 'Liking' : 'Unliking'} question: $questionId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//         body: jsonEncode({'likes': like ? 1 : -1}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Like question error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Mark a question as solved
//   Future<Map<String, dynamic>> markQuestionSolved(String questionId) async {
//     try {
//       print('🔄 Marking question as solved: $questionId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/questions/$questionId'),
//         headers: headers,
//         body: jsonEncode({'solved': true}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Mark question solved error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Like/Unlike an answer
//   Future<Map<String, dynamic>> likeAnswer(String answerId, bool like) async {
//     try {
//       print('🔄 ${like ? 'Liking' : 'Unliking'} answer: $answerId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/answers/$answerId/like'),
//         headers: headers,
//         body: jsonEncode({'like': like}),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Like answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // Accept an answer as solution
//   Future<Map<String, dynamic>> acceptAnswer(String answerId) async {
//     try {
//       print('🔄 Accepting answer as solution: $answerId');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/api/answers/$answerId/accept'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ Accept answer error: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   // ============ OTHER METHODS ============

//   Future<Map<String, dynamic>> logout() async {
//     try {
//       print('=' * 50);
//       print('🔄 LOGOUT STARTED');
      
//       if (_token != null && _token!.isNotEmpty) {
//         final response = await http.post(
//           Uri.parse('$baseUrl/api/auth/logout'),
//           headers: headers,
//         );
//         print('📥 Logout HTTP Status: ${response.statusCode}');
//       }
      
//       await clearToken();
      
//       print('✅ LOGOUT COMPLETE');
//       print('=' * 50);
      
//       return {
//         'success': true,
//         'message': 'Logged out successfully',
//       };
//     } catch (e) {
//       await clearToken();
//       print('⚠️ Logout server call failed, but local data cleared: $e');
      
//       return {
//         'success': true,
//         'message': 'Logged out locally',
//       };
//     }
//   }

//   Future<Map<String, dynamic>> forgotPassword(String email) async {
//     try {
//       print('=' * 50);
//       print('🔄 FORGOT PASSWORD');
//       print('📤 Email: $email');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/api/auth/forgot-password'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': email.trim()}),
//       );

//       print('📥 HTTP Status: ${response.statusCode}');
      
//       final Map<String, dynamic> data = jsonDecode(response.body);

//       if (response.statusCode == 200) {
//         print('✅ PASSWORD RESET EMAIL SENT');
//         return {
//           'success': true,
//           'message': data['message'] ?? 'Password reset email sent',
//         };
//       } else {
//         print('❌ ERROR: Failed to send reset email');
//         return {
//           'success': false,
//           'error': data['error'] ?? 'Failed to send reset email',
//         };
//       }
//     } catch (e) {
//       print('💥 EXCEPTION: $e');
//       return {
//         'success': false,
//         'error': 'Connection error: $e',
//       };
//     }
//   }

//   Future<Map<String, dynamic>?> getSavedUserData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final userDataString = prefs.getString('user_data');
      
//       if (userDataString != null && userDataString.isNotEmpty) {
//         return jsonDecode(userDataString);
//       }
//     } catch (e) {
//       print('❌ Error loading saved user data: $e');
//     }
//     return null;
//   }

//   bool isTokenValid(String? token) {
//     if (token == null || token.isEmpty) return false;
    
//     final parts = token.split('.');
//     if (parts.length != 3) return false;
    
//     if (!token.startsWith('eyJ')) return false;
    
//     return true;
//   }

//   Future<bool> checkTokenValidity() async {
//     if (_token == null || _token!.isEmpty) return false;
    
//     if (!isTokenValid(_token)) {
//       print('⚠️ Token format is invalid');
//       await clearToken();
//       return false;
//     }
    
//     return true;
//   }

//   // ============ HTTP METHODS ============

//   Future<Map<String, dynamic>> httpGet(String endpoint) async {
//     try {
//       print('🔄 GET $endpoint');
//       final response = await http.get(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP GET error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPost(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 POST $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.post(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP POST error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpPut(String endpoint, Map<String, dynamic> data) async {
//     try {
//       print('🔄 PUT $endpoint');
//       print('📤 Data: $data');
      
//       final response = await http.put(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//         body: jsonEncode(data),
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP PUT error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }

//   Future<Map<String, dynamic>> httpDelete(String endpoint) async {
//     try {
//       print('🔄 DELETE $endpoint');
      
//       final response = await http.delete(
//         Uri.parse('$baseUrl/$endpoint'),
//         headers: headers,
//       );

//       print('📥 Response status: ${response.statusCode}');
//       print('📥 Response body: ${response.body}');

//       return jsonDecode(response.body);
//     } catch (e) {
//       print('❌ HTTP DELETE error: $e');
//       return {'success': false, 'error': 'Connection error: $e'};
//     }
//   }
// }
