import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AIService {
  static const String _openAIUrl = 'https://api.openai.com/v1/chat/completions';
  String? _apiKey;
  
  // Store training data locally for context
  List<Map<String, String>> _trainingData = [];
  
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('openai_api_key');
    
    // Load saved training data
    final savedData = prefs.getString('ai_training_data');
    if (savedData != null) {
      _trainingData = List<Map<String, String>>.from(jsonDecode(savedData));
      print('✅ Loaded ${_trainingData.length} training examples');
    }
  }
  
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    // Save to shared preferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('openai_api_key', apiKey);
    });
  }
  
  // Train AI with new Q&A pairs
  Future<void> trainWithData(String text) async {
    if (text.trim().isEmpty) return;
    
    // Extract question and answer from text
    final parts = text.split('\nA: ');
    if (parts.length >= 2) {
      final question = parts[0].replaceFirst('Q: ', '');
      final answer = parts[1];
      
      _trainingData.add({
        'question': question,
        'answer': answer,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Keep only last 500 examples to avoid bloat
      if (_trainingData.length > 500) {
        _trainingData = _trainingData.sublist(_trainingData.length - 500);
      }
      
      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_training_data', jsonEncode(_trainingData));
      print('✅ Trained AI with new data. Total: ${_trainingData.length} examples');
    }
  }
  
  // Get relevant context from training data
  String _getRelevantContext(String query) {
    if (_trainingData.isEmpty) return '';
    
    // Simple relevance scoring (can be improved with embeddings)
    final keywords = query.toLowerCase().split(' ');
    final relevantAnswers = <String>[];
    
    for (var data in _trainingData) {
      final question = data['question']?.toLowerCase() ?? '';
      final score = keywords.where((k) => question.contains(k)).length;
      if (score > 0) {
        relevantAnswers.add('Q: ${data['question']}\nA: ${data['answer']}');
      }
      if (relevantAnswers.length >= 3) break;
    }
    
    if (relevantAnswers.isEmpty) return '';
    
    return '\n\nHere are some relevant examples from our community:\n${relevantAnswers.join('\n\n')}';
  }
  
  // Ask AI a question (with context from training)
  Future<String> askQuestion(String question) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return 'Please add your OpenAI API key in settings to use the AI assistant.';
    }
    
    try {
      final context = _getRelevantContext(question);
      
      final systemPrompt = '''
You are a helpful gardening assistant for a community food sharing app called "Harvest Hub". 
You help users with:
- Gardening questions (planting, harvesting, pests, diseases)
- Crop growing advice
- Organic farming tips
- Soil preparation and maintenance
- Seasonal planting guides

Be friendly, knowledgeable, and practical. Use examples from the community when relevant.
${context.isNotEmpty ? '\nUse this community knowledge to inform your answer:\n$context' : ''}
''';
      
      final response = await http.post(
        Uri.parse(_openAIUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': question},
          ],
          'temperature': 0.7,
          'max_tokens': 500,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer = data['choices'][0]['message']['content'];
        
        // Store this Q&A for future training
        await trainWithData('Q: $question\nA: $answer');
        
        return answer;
      } else {
        final error = jsonDecode(response.body);
        return 'AI Error: ${error['error']['message'] ?? 'Unknown error'}';
      }
    } catch (e) {
      print('AI Error: $e');
      return 'Sorry, I had trouble connecting to the AI service. Please try again.';
    }
  }
  
  // Suggest post content based on user's topic
  Future<String> suggestPostContent(String topic) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return 'Please add your OpenAI API key to get AI suggestions.';
    }
    
    try {
      final response = await http.post(
        Uri.parse(_openAIUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system', 
              'content': 'You are a helpful assistant for a gardening community. Help users write engaging posts about their gardening experiences, questions, or tips. Suggest a well-structured post that includes a title and body. Keep it conversational and friendly.'
            },
            {
              'role': 'user', 
              'content': 'I want to write a post about: $topic. Please suggest a title and content for my post.'
            },
          ],
          'temperature': 0.8,
          'max_tokens': 300,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return 'Could not generate suggestion. Please try again.';
      }
    } catch (e) {
      print('Post suggestion error: $e');
      return 'Error generating suggestion. Please try again.';
    }
  }
  
  // Analyze and summarize a conversation
  Future<String> analyzeConversation(List<Map<String, String>> messages) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return 'AI analysis not available.';
    }
    
    try {
      final conversationText = messages.map((m) => 
        '${m['role']}: ${m['content']}'
      ).join('\n');
      
      final response = await http.post(
        Uri.parse(_openAIUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'system',
              'content': 'Summarize the key points from this gardening conversation. Identify the main question, any solutions suggested, and important takeaways.'
            },
            {
              'role': 'user',
              'content': conversationText,
            },
          ],
          'temperature': 0.5,
          'max_tokens': 200,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      }
      return 'Analysis not available.';
    } catch (e) {
      return 'Error analyzing conversation.';
    }
  }
  
  // Batch train from multiple Q&As
  Future<void> batchTrain(List<Map<String, dynamic>> qaPairs) async {
    for (var qa in qaPairs) {
      await trainWithData('Q: ${qa['question']}\nA: ${qa['answer']}');
    }
    print('✅ Batch trained with ${qaPairs.length} items');
  }
  
  // Get training statistics
  Map<String, dynamic> getTrainingStats() {
    return {
      'totalExamples': _trainingData.length,
      'lastUpdated': _trainingData.isNotEmpty 
          ? _trainingData.last['timestamp'] 
          : null,
    };
  }
  
  // Clear training data (for debugging)
  Future<void> clearTrainingData() async {
    _trainingData.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_training_data');
    print('🗑️ AI training data cleared');
  }
}







// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';

// class AIService {
//   // Use Google's Gemini API (free tier available)
//   static const String _geminiApiKey = 'AIzaSyCa-bwieSO8xd2T6mCUiEWm5Odv1ERssOw'; // Get from https://makersuite.google.com/app/apikey
//     // UPDATED: Correct Gemini API endpoint for version 1.5
//   static const String _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

//   // static const String _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent';
  
//   // Local training data storage
//   List<Map<String, String>> _trainingData = [];
  
//   Future<void> initialize() async {
//     await _loadTrainingData();
//   }
  
//   Future<void> _loadTrainingData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final dataString = prefs.getString('ai_training_data');
//       if (dataString != null) {
//         _trainingData = List<Map<String, String>>.from(jsonDecode(dataString));
//         print('✅ Loaded ${_trainingData.length} training examples');
//       }
//     } catch (e) {
//       print('Error loading training data: $e');
//     }
//   }
  
//   Future<void> _saveTrainingData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.setString('ai_training_data', jsonEncode(_trainingData));
//     } catch (e) {
//       print('Error saving training data: $e');
//     }
//   }
  
//   Future<void> trainWithData(String qaText) async {
//     // Add to training data
//     _trainingData.add({'text': qaText});
    
//     // Keep only last 1000 examples to avoid storage issues
//     if (_trainingData.length > 1000) {
//       _trainingData = _trainingData.sublist(_trainingData.length - 1000);
//     }
    
//     await _saveTrainingData();
//     print('✅ Trained AI with new data. Total: ${_trainingData.length} examples');
//   }
  
//   Future<String> askQuestion(String question) async {
//     try {
//       // Build context from training data
//       String context = _buildContextFromTraining();
      
//       final prompt = '''
// You are an expert gardening assistant. Use the following Q&A examples to help answer questions about crops, gardening, pests, soil, and farming.

// Training Examples:
// $context

// Now answer this gardening question: $question

// Provide helpful, practical advice based on real gardening knowledge. If you don't know something, be honest.
// ''';
      
//       final response = await http.post(
//         Uri.parse('$_geminiUrl?key=$_geminiApiKey'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'contents': [
//             {
//               'parts': [
//                 {'text': prompt}
//               ]
//             }
//           ]
//         }),
//       );
      
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final answer = data['candidates'][0]['content']['parts'][0]['text'];
//         return answer;
//       } else {
//         // Fallback to local response if API fails
//         return _getLocalResponse(question);
//       }
//     } catch (e) {
//       print('Error calling Gemini API: $e');
//       return _getLocalResponse(question);
//     }
//   }
  
//   Future<String> suggestAnswer(String question) async {
//     try {
//       String context = _buildContextFromTraining();
      
//       final prompt = '''
// You are an expert gardening assistant. Based on these Q&A examples:
// $context

// Suggest a helpful answer for this gardening question: "$question"

// Provide a concise, practical answer that would help the gardener.
// ''';
      
//       final response = await http.post(
//         Uri.parse('$_geminiUrl?key=$_geminiApiKey'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({
//           'contents': [
//             {
//               'parts': [
//                 {'text': prompt}
//               ]
//             }
//           ]
//         }),
//       );
      
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final answer = data['candidates'][0]['content']['parts'][0]['text'];
//         return answer;
//       } else {
//         return _getLocalSuggestion(question);
//       }
//     } catch (e) {
//       print('Error getting suggestion: $e');
//       return _getLocalSuggestion(question);
//     }
//   }
  
//   String _buildContextFromTraining() {
//     if (_trainingData.isEmpty) {
//       return 'No examples yet. Use general gardening knowledge.';
//     }
    
//     // Use last 20 examples for context
//     final recentExamples = _trainingData.length > 20 
//         ? _trainingData.sublist(_trainingData.length - 20)
//         : _trainingData;
    
//     return recentExamples.map((e) => e['text']).join('\n\n');
//   }
  
//   String _getLocalResponse(String question) {
//     final lowerQuestion = question.toLowerCase();
    
//     if (lowerQuestion.contains('tomato')) {
//       return 'Tomatoes need 6-8 hours of sunlight daily, well-draining soil, and consistent watering. Water at the base to prevent leaf diseases.';
//     } else if (lowerQuestion.contains('water')) {
//       return 'Most vegetables need 1-1.5 inches of water per week. Water deeply in the morning to reduce evaporation.';
//     } else if (lowerQuestion.contains('pest')) {
//       return 'For common pests, try neem oil or insecticidal soap. Encourage beneficial insects like ladybugs.';
//     } else if (lowerQuestion.contains('soil')) {
//       return 'Good garden soil should be rich in organic matter, well-draining, and have pH between 6.0-7.0. Add compost annually.';
//     } else if (lowerQuestion.contains('fertilizer')) {
//       return 'Use balanced fertilizer (10-10-10) for vegetables. Organic options include compost, manure, and fish emulsion.';
//     } else {
//       return 'For best gardening results, ensure proper sunlight, water, soil quality, and pest management. What specific crop are you growing?';
//     }
//   }
  
//   String _getLocalSuggestion(String question) {
//     return 'Based on similar questions in our community, you might want to consider:\n\n${_getLocalResponse(question)}\n\nWould you like more specific advice?';
//   }
// }
