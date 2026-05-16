import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'main_layout.dart';
import 'login_screen.dart';
import 'terms_privacy_modal.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsAccepted = false;
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    // Clear previous error
    setState(() {
      _errorMessage = null;
    });

    // Validate fields
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _nameController.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }
    
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }
    
    if (_passwordController.text.length < 8) {
      _showError('Password must be at least 8 characters long');
      return;
    }

    // Email validation
    if (!_isValidEmail(_emailController.text.trim())) {
      _showError('Please enter a valid email address');
      return;
    }

    // Check terms acceptance
    if (!_termsAccepted) {
      final bool? accepted = await _showTermsModal();
      if (accepted != true) {
        return;
      }
      setState(() {
        _termsAccepted = true;
      });
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await authProvider.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
    
      if (result['success'] == true && mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Welcome to Harvest Hub! 🌱'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // OPTION 1: Auto-login after registration (Recommended)
        // The user is already authenticated because register returns a token
        // So navigate directly to MainLayout
        if (authProvider.isAuthenticated) {
          // Clear all previous routes and go to main layout
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const MainLayout(),
            ),
            (route) => false, // This removes all previous routes
          );
        } else {
          // Fallback: Go to login screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
            (route) => false,
          );
        }
      } else {
        _showError(result['error'] ?? 'Registration failed');
      }
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _errorMessage = message;
      });
    }
  }

  Future<bool?> _showTermsModal() async {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TermsPrivacyModal(
        onAccept: () {
          Navigator.pop(context, true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            width: double.infinity,
            child: Column(
              children: [
                // Hero Section
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E8E4),
                    image: const DecorationImage(
                      image: NetworkImage(
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuAqKALFRp3tHZbCD5q27mlvLlDWEAPxQLnnkwyBaK9kl_rcOhik8GPbKoXCa8FCV9daZBAzjUln6oGaR0W8PyMxpxm913SPbMwEMCDfrl9-X76-0HyN334ZmDMcy8J-9klcu6pVCTr7yMt5jKdYVanWXURJCgceU1i1lah9_5ptVJyOihlziOjKOI1MnaivIxwEyaa567HSJ6lM7R4xKsdFEizzOvinwBSBVJy7mxrD2LLHxT8Wynpvw9oA3NRuOKvXb0YxjSgS7YXr',
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          isDarkMode 
                              ? const Color(0xFF212C28).withOpacity(0.9)
                              : const Color(0xFFF9F8F6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Error Message Display
                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Text(
                    'Create Your Garden Account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF101816),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Form Fields
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      // Full Name Field
                      _buildTextField(
                        isDarkMode,
                        controller: _nameController,
                        label: 'Full Name',
                        hint: 'John Doe',
                        icon: Icons.person,
                      ),
                      
                      const SizedBox(height: 16),

                      // Email Field
                      _buildTextField(
                        isDarkMode,
                        controller: _emailController,
                        label: 'Garden Email',
                        hint: 'your@garden.com',
                        icon: Icons.local_florist,
                        iconColor: const Color(0xFF39AC86),
                      ),

                      const SizedBox(height: 16),

                      // Phone Field
                      _buildTextField(
                        isDarkMode,
                        controller: _phoneController,
                        label: 'Phone Number',
                        hint: '+1 (555) 123-4567',
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                      ),

                      const SizedBox(height: 16),

                      // Password Field
                      _buildPasswordField(
                        isDarkMode,
                        controller: _passwordController,
                        label: 'Secure Password',
                        obscureText: _obscurePassword,
                        onToggle: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
                        child: Text(
                          'Tip: Use 8+ characters with a mix of letters and symbols.',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF5C8A7A),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Confirm Password Field
                      _buildPasswordField(
                        isDarkMode,
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        obscureText: _obscureConfirmPassword,
                        onToggle: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                // Sign Up Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isLoading ? const Color(0xFF39AC86).withOpacity(0.7) : const Color(0xFF39AC86),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _isLoading ? null : [
                        BoxShadow(
                          color: const Color(0xFF39AC86).withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _isLoading ? null : _handleSignup,
                        child: _isLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              )
                            : const Center(
                                child: Text(
                                  'Create Account',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

                // Login Link
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF5C8A7A),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF39AC86),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Terms Link
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: Text.rich(
                    TextSpan(
                      text: 'By creating an account, you agree to our ',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF5C8A7A),
                        height: 1.5,
                      ),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => TermsPrivacyModal(
                                  onAccept: () {
                                    setState(() {
                                      _termsAccepted = true;
                                    });
                                  },
                                ),
                              );
                            },
                            child: const Text(
                              'Terms',
                              style: TextStyle(
                                color: Color(0xFF39AC86),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => TermsPrivacyModal(
                                  onAccept: () {
                                    setState(() {
                                      _termsAccepted = true;
                                    });
                                  },
                                ),
                              );
                            },
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                color: Color(0xFF39AC86),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    bool isDarkMode, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    Color iconColor = const Color(0xFF5C8A7A),
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white : const Color(0xFF101816),
            ),
          ),
        ),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2D3A35) : const Color(0xFFFDFBF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDarkMode ? const Color(0xFF3D4D47) : const Color(0xFFD4E2DE),
            ),
          ),
          child: Stack(
            children: [
              TextField(
                controller: controller,
                keyboardType: keyboardType,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: Color(0xFFA1B8B0),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
                enabled: !_isLoading,
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(
    bool isDarkMode, {
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white : const Color(0xFF101816),
            ),
          ),
        ),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2D3A35) : const Color(0xFFFDFBF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDarkMode ? const Color(0xFF3D4D47) : const Color(0xFFD4E2DE),
            ),
          ),
          child: Stack(
            children: [
              TextField(
                controller: controller,
                obscureText: obscureText,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : const Color(0xFF101816),
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: const TextStyle(
                    color: Color(0xFFA1B8B0),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
                enabled: !_isLoading,
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: IconButton(
                  icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                    color: const Color(0xFF5C8A7A),
                    size: 24,
                  ),
                  onPressed: _isLoading ? null : onToggle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
