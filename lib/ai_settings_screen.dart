// ai_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';

class AISettingsScreen extends StatefulWidget {
  const AISettingsScreen({super.key});

  @override
  State<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends State<AISettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final AIService _aiService = AIService();
  bool _isLoading = false;
  String? _currentKeyPreview;
  
  @override
  void initState() {
    super.initState();
    _loadCurrentKey();
  }
  
  Future<void> _loadCurrentKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('openai_api_key');
    if (key != null && key.isNotEmpty) {
      setState(() {
        _currentKeyPreview = '${key.substring(0, 20)}...${key.substring(key.length - 10)}';
      });
    }
  }
  
  Future<void> _saveApiKey() async {
    if (_apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an API key'), backgroundColor: Colors.red),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      _aiService.setApiKey(_apiKeyController.text.trim());
      await _loadCurrentKey();
      _apiKeyController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key saved successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving key: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await _aiService.askQuestion('Hello! Are you working?');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI is working! Response: ${response.substring(0, 50)}...'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF212C28) : const Color(0xFFF9F8F6),
      appBar: AppBar(
        title: const Text('AI Assistant Settings'),
        backgroundColor: const Color(0xFF39AC86),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.psychology, size: 48, color: Color(0xFF39AC86)),
            const SizedBox(height: 16),
            const Text(
              'OpenAI API Key',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your OpenAI API key to enable AI features. Your key is stored locally on your device.',
              style: TextStyle(fontSize: 14, color: Color(0xFF5C8A7A)),
            ),
            const SizedBox(height: 24),
            
            if (_currentKeyPreview != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('API Key Configured', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(_currentKeyPreview!, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'OpenAI API Key',
                hintText: 'sk-proj-...',
                border: OutlineInputBorder(),
                helperText: 'Get your key from platform.openai.com/api-keys',
              ),
              obscureText: true,
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveApiKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF39AC86),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save API Key'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _testConnection,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF39AC86)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Test Connection'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('How to get your API Key', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '1. Go to platform.openai.com\n'
                    '2. Sign in or create an account\n'
                    '3. Click on your profile → "API Keys"\n'
                    '4. Click "Create new secret key"\n'
                    '5. Copy the key starting with "sk-proj-"\n'
                    '6. Paste it here and save',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
