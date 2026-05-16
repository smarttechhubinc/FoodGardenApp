import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _currentUser;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _apiService.isLoggedIn;
  
  String? get token => _apiService.token;
  String? get userId => _currentUser?['id'];

  // Initialize auth state
  Future<void> initialize() async {
    print('🔄 Initializing AuthProvider...');
    await _apiService.initialize();
    
    print('🔑 ApiService isLoggedIn: ${_apiService.isLoggedIn}');
    print('🔑 ApiService token: ${_apiService.token?.substring(0, 50)}...');
    
    if (_apiService.isLoggedIn) {
      print('👤 User is logged in, loading user data...');
      await _loadCurrentUser();
    } else {
      print('👤 No user logged in');
    }
    
    notifyListeners();
  }

  // Load current user from API
  Future<void> _loadCurrentUser() async {
    final result = await _apiService.getCurrentUser();
    if (result['success'] == true) {
      _currentUser = result['user'];
    } else {
      // Token might be invalid, clear it
      await logout();
    }
    notifyListeners();
  }

  // NEW: Update user data from profile screen
  Future<void> updateUserData(Map<String, dynamic> updatedUser) async {
    _currentUser = updatedUser;
    notifyListeners();
    print('✅ AuthProvider user data updated');
    
    // Update local storage to keep it in sync
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(updatedUser));
  }

  // NEW: Refresh user data from API
  Future<void> refreshUserData() async {
    final result = await _apiService.getCurrentUser();
    if (result['success'] == true) {
      _currentUser = result['user'];
      notifyListeners();
      print('✅ AuthProvider user data refreshed');
    }
  }

  // Login method
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.login(
        email: email,
        password: password,
      );

      if (result['success'] == true) {
        _currentUser = result['user'];
        _error = null;
        notifyListeners();
        return {'success': true, 'user': result['user']};
      } else {
        _error = result['error'] ?? 'Login failed';
        notifyListeners();
        return {'success': false, 'error': _error};
      }
    } catch (e) {
      _error = 'An error occurred: $e';
      notifyListeners();
      return {'success': false, 'error': _error};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Register method
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
      );

      if (result['success'] == true) {
        print('✅ Registration successful, setting user data...');
        _currentUser = result['user'];
        _error = null;
        
        await _apiService.initialize();
        
        print('🔑 After registration - isLoggedIn: ${_apiService.isLoggedIn}');
        print('🔑 After registration - token: ${_apiService.token?.substring(0, 30)}...');
        
        if (_apiService.isLoggedIn) {
          await _loadCurrentUser();
        }
        
        notifyListeners();
        return {
          'success': true, 
          'user': result['user'],
          'message': result['message'] ?? 'Registration successful',
        };
      } else {
        _error = result['error'] ?? 'Registration failed';
        notifyListeners();
        return {'success': false, 'error': _error};
      }
    } catch (e) {
      _error = 'An error occurred: $e';
      notifyListeners();
      return {'success': false, 'error': _error};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Logout method
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    await _apiService.logout();
    
    _currentUser = null;
    _error = null;
    _isLoading = false;
    
    notifyListeners();
  }

  // Forgot password
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.forgotPassword(email);
      
      _isLoading = false;
      notifyListeners();
      
      if (result['success'] == true) {
        return {'success': true, 'message': result['message']};
      } else {
        _error = result['error'];
        notifyListeners();
        return {'success': false, 'error': _error};
      }
    } catch (e) {
      _isLoading = false;
      _error = 'An error occurred: $e';
      notifyListeners();
      return {'success': false, 'error': _error};
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
