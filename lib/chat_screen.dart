import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String itemName;
  final String userName;
  final String userImage;
  final String? productId;
  final String? productStatus;
  final int quantity;
  final String recipientId;
  final String chatId;
  final Map<String, dynamic>? requestData;
  
  const ChatScreen({
    Key? key,
    required this.itemName,
    required this.userName,
    required this.userImage,
    this.productId,
    this.productStatus,
    this.quantity = 0,
    required this.recipientId,
    required this.chatId,
    this.requestData,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;
  final ApiService _apiService = ApiService();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isConnected = false;
  String? _connectionError;
  
  // Request tracking
  Map<String, dynamic>? _currentRequest;
  bool _isProcessingRequest = false;
  bool _isLoadingRequest = true;
  
  static const String webSocketUrl = 'wss://foodsharingbackend.onrender.com';

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _loadMessages();
    _loadRequestData(); // Load request data immediately
  }

  Future<void> _loadRequestData() async {
    setState(() {
      _isLoadingRequest = true;
    });
    
    try {
      print('🔍 Loading request data...');
      print('📦 productId: ${widget.productId}');
      print('📦 requestData from constructor: ${widget.requestData}');
      
      // First check if requestData was passed from constructor
      if (widget.requestData != null && widget.requestData!.isNotEmpty) {
        print('✅ Using requestData from constructor: ${widget.requestData!['status']}');
        setState(() {
          _currentRequest = widget.requestData;
          _isLoadingRequest = false;
        });
        return;
      }
      
      // If not, check API for existing pending request
      if (widget.productId != null) {
        print('🔍 Checking API for existing request on product: ${widget.productId}');
        final result = await _apiService.getUserProductRequest(widget.productId!);
        print('📥 API Response: $result');
        
        if (result['success'] == true && result['request'] != null) {
          print('✅ Found existing request: ${result['request']['status']}');
          setState(() {
            _currentRequest = result['request'];
          });
        } else {
          print('❌ No existing request found');
        }
      }
    } catch (e) {
      print('❌ Error loading request: $e');
    } finally {
      setState(() {
        _isLoadingRequest = false;
      });
    }
  }

  void _connectWebSocket() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token;
      
      if (token == null) {
        setState(() {
          _connectionError = 'Not authenticated';
          _isConnected = false;
        });
        return;
      }
      
      _channel = WebSocketChannel.connect(
        Uri.parse('$webSocketUrl/ws?token=$token'),
      );

      _channel!.stream.listen(
        (message) {
          print('📨 WebSocket message received: $message');
          final data = jsonDecode(message);
          _handleIncomingMessage(data);
        },
        onError: (error) {
          print('WebSocket error: $error');
          setState(() {
            _connectionError = 'Connection error: $error';
            _isConnected = false;
          });
        },
        onDone: () {
          setState(() {
            _isConnected = false;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _connectWebSocket();
          });
        },
      );

      setState(() {
        _isConnected = true;
        _connectionError = null;
      });
      
      // Subscribe to the chat
      _channel!.sink.add(jsonEncode({
        'type': 'subscribe',
        'chatId': widget.chatId,
      }));
      
    } catch (e) {
      print('Failed to connect WebSocket: $e');
      setState(() {
        _connectionError = 'Failed to connect: $e';
        _isConnected = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _apiService.getChatMessages(widget.chatId);
      print('📥 Messages response: $result');
      
      if (result['success'] == true) {
        final messages = result['messages'] ?? [];
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUserId = authProvider.userId;
        
        setState(() {
          _messages = messages.map((msg) {
            final timestamp = DateTime.tryParse(msg['created_at'] ?? msg['timestamp'] ?? DateTime.now().toIso8601String());
            final isSystemMessage = msg['is_system_message'] == true;
            final requestId = msg['request_id'];
            
            return {
              'id': msg['id'],
              'text': msg['text'],
              'isMe': msg['sender_id'] == currentUserId,
              'time': _formatTime(timestamp ?? DateTime.now()),
              'userName': msg['sender']?['name'] ?? 
                          (msg['sender_id'] == currentUserId ? 'You' : widget.userName),
              'userImage': msg['sender']?['profile_image_url'] ?? 
                          (msg['sender_id'] == currentUserId ? '' : widget.userImage),
              'isRead': msg['is_read'] ?? false,
              'isSending': false,
              'isFailed': false,
              'isSystemMessage': isSystemMessage,
              'requestId': requestId,
            };
          }).toList();
        });
        
        _scrollToBottom();
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (_messages.isEmpty) {
        setState(() {
          _messages.add({
            'id': 'welcome',
            'text': 'Start a conversation with ${widget.userName} about ${widget.itemName}!',
            'isMe': false,
            'time': _formatTime(DateTime.now()),
            'userName': 'System',
            'userImage': '',
            'isRead': true,
            'isSending': false,
            'isFailed': false,
            'isSystemMessage': true,
          });
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    print('📨 Handling incoming message: ${data['type']}');
    
    if (data['type'] == 'new_message') {
      final messageData = data['message'];
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.userId;
      
      final bool exists = _messages.any((m) => m['id'] == messageData['id']);
      
      if (!exists && messageData['senderId'] != currentUserId) {
        setState(() {
          _messages.add({
            'id': messageData['id'],
            'text': messageData['text'],
            'isMe': false,
            'time': _formatTime(DateTime.parse(messageData['timestamp'])),
            'userName': messageData['senderName'] ?? widget.userName,
            'userImage': messageData['senderImage'] ?? widget.userImage,
            'isRead': false,
            'isSending': false,
            'isFailed': false,
            'isSystemMessage': messageData['isSystemMessage'] ?? false,
            'requestId': messageData['requestId'],
          });
        });
        
        _scrollToBottom();
        _markAsRead(messageData['id']);
      }
    } 
    else if (data['type'] == 'message_sent') {
      final messageData = data['message'];
      print('✅ Message sent confirmation: ${messageData['id']}');
      
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == messageData['id'] || m['tempId'] == messageData['id']);
        if (index != -1) {
          _messages[index]['isSending'] = false;
          _messages[index]['id'] = messageData['id'];
          _messages[index]['time'] = _formatTime(DateTime.parse(messageData['timestamp']));
          _messages[index]['isFailed'] = false;
        }
      });
    }
    else if (data['type'] == 'request_accepted') {
      final requestData = data['request'];
      print('✅ Request accepted: $requestData');
      setState(() {
        if (_currentRequest != null && _currentRequest!['id'] == requestData['id']) {
          _currentRequest!['status'] = 'accepted';
        }
      });
      _loadMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Request accepted! You can now arrange pickup.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    else if (data['type'] == 'request_declined') {
      final requestData = data['request'];
      print('❌ Request declined: $requestData');
      setState(() {
        if (_currentRequest != null && _currentRequest!['id'] == requestData['id']) {
          _currentRequest!['status'] = 'declined';
        }
      });
      _loadMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Request was declined.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    else if (data['type'] == 'messages_read') {
      final messageIds = data['messageIds'] as List;
      setState(() {
        for (var message in _messages) {
          if (messageIds.contains(message['id'])) {
            message['isRead'] = true;
          }
        }
      });
    }
  }

  Future<void> _acceptRequest() async {
    if (_currentRequest == null || _isProcessingRequest) return;
    
    setState(() {
      _isProcessingRequest = true;
    });
    
    try {
      final result = await _apiService.acceptProductRequest(_currentRequest!['id']);
      
      if (result['success'] == true) {
        setState(() {
          _currentRequest!['status'] = 'accepted';
        });
        
        // Send a system message
        await _sendSystemMessage(
          '✅ Request accepted! The produce has been reserved for you. Please arrange pickup.'
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request accepted! User has been notified.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(result['error']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isProcessingRequest = false;
      });
    }
  }

  Future<void> _declineRequest() async {
    if (_currentRequest == null || _isProcessingRequest) return;
    
    setState(() {
      _isProcessingRequest = true;
    });
    
    try {
      final result = await _apiService.declineProductRequest(_currentRequest!['id']);
      
      if (result['success'] == true) {
        setState(() {
          _currentRequest!['status'] = 'declined';
        });
        
        // Send a system message
        await _sendSystemMessage(
          '❌ Request declined. The produce is still available for others.'
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request declined.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        throw Exception(result['error']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to decline request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isProcessingRequest = false;
      });
    }
  }

  Future<void> _sendSystemMessage(String message) async {
    try {
      await _apiService.sendMessage(
        chatId: widget.chatId,
        recipientId: widget.recipientId,
        text: message,
        productId: widget.productId,
      );
      await _loadMessages();
    } catch (e) {
      print('Error sending system message: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _markAsRead(String messageId) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({
        'type': 'mark_read',
        'chatId': widget.chatId,
        'messageIds': [messageId],
      }));
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final currentUserId = authProvider.userId;
    
    final messageText = _messageController.text.trim();
    _messageController.clear();

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
    final tempMessage = {
      'id': tempId,
      'tempId': tempId,
      'text': messageText,
      'isMe': true,
      'time': 'Sending...',
      'userName': currentUser?['name'] ?? 'You',
      'userImage': currentUser?['profile_image_url'] ?? '',
      'isRead': false,
      'isSending': true,
      'isFailed': false,
      'isSystemMessage': false,
    };

    setState(() {
      _messages.add(tempMessage);
    });
    _scrollToBottom();

    try {
      if (_channel != null && _isConnected) {
        _channel!.sink.add(jsonEncode({
          'type': 'message',
          'chatId': widget.chatId,
          'recipientId': widget.recipientId,
          'text': messageText,
          'productId': widget.productId,
        }));
        
        print('📤 Message sent via WebSocket: $tempId');
      } else {
        print('⚠️ WebSocket not connected, using API fallback');
        final result = await _apiService.sendMessage(
          chatId: widget.chatId,
          recipientId: widget.recipientId,
          text: messageText,
          productId: widget.productId,
        );
        
        if (result['success'] == true) {
          setState(() {
            final index = _messages.indexWhere((m) => m['id'] == tempId);
            if (index != -1) {
              _messages[index]['id'] = result['data']['message']['id'];
              _messages[index]['isSending'] = false;
              _messages[index]['time'] = _formatTime(DateTime.now());
            }
          });
        } else {
          throw Exception(result['error']);
        }
      }
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          _messages[index]['isSending'] = false;
          _messages[index]['isFailed'] = true;
          _messages[index]['time'] = 'Failed';
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${time.day}/${time.month}';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  Color _getStatusColor() {
    switch(widget.productStatus) {
      case 'In Progress':
        return const Color(0xFFFFC300);
      case 'Claimed':
        return const Color(0xFF29A366);
      case 'Completed':
        return const Color(0xFF668799);
      default:
        return const Color(0xFF29A366);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    if (_channel != null) {
      if (_isConnected) {
        _channel!.sink.add(jsonEncode({
          'type': 'unsubscribe',
          'chatId': widget.chatId,
        }));
      }
      _channel!.sink.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor();
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.userId;
    final isOwner = currentUserId == widget.recipientId;
    
    // Debug print
    print('🎨 Building ChatScreen...');
    print('👤 isOwner: $isOwner, currentUserId: $currentUserId, recipientId: ${widget.recipientId}');
    print('📦 _currentRequest: $_currentRequest');
    print('📦 _isLoadingRequest: $_isLoadingRequest');
    
    // Determine if request card should be shown
    final bool showRequestCard = !_isLoadingRequest && 
        _currentRequest != null && 
        _currentRequest!['status'] == 'pending' &&
        isOwner;
    
    final bool showRequesterStatus = !_isLoadingRequest && 
        _currentRequest != null && 
        _currentRequest!['status'] != 'pending' &&
        _currentRequest!['requester_id'] == currentUserId;
    
    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                color: isDarkMode 
                    ? const Color(0xFF201712).withOpacity(0.95)
                    : const Color(0xFFF6F5F3).withOpacity(0.95),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withOpacity(0.05),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_ios,
                      color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: widget.userImage.isNotEmpty
                        ? NetworkImage(widget.userImage)
                        : null,
                    backgroundColor: statusColor.withOpacity(0.1),
                    child: widget.userImage.isEmpty
                        ? Text(
                            widget.userName[0].toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isConnected ? Colors.green : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isConnected ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _isConnected ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.quantity > 0 
                          ? '${widget.quantity} left'
                          : 'Claimed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Request Card for Owner (to Accept/Decline)
            if (showRequestCard)
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.request_page,
                              color: Colors.orange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Pending Request',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.orange,
                                  ),
                                ),
                                Text(
                                  '${_currentRequest!['quantity']} ${widget.itemName}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_currentRequest!['message'] != null && _currentRequest!['message'].toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '"${_currentRequest!['message']}"',
                            style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isProcessingRequest ? null : _declineRequest,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: _isProcessingRequest
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isProcessingRequest ? null : _acceptRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF29A366),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: _isProcessingRequest
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Accept Request'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Request Status Card (for Requester)
            if (showRequesterStatus)
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _currentRequest!['status'] == 'accepted'
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _currentRequest!['status'] == 'accepted'
                        ? Colors.green.withOpacity(0.3)
                        : Colors.red.withOpacity(0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _currentRequest!['status'] == 'accepted'
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _currentRequest!['status'] == 'accepted'
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: _currentRequest!['status'] == 'accepted'
                              ? Colors.green
                              : Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentRequest!['status'] == 'accepted'
                                  ? 'Request Accepted! 🎉'
                                  : 'Request Declined ❌',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _currentRequest!['status'] == 'accepted'
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            Text(
                              _currentRequest!['status'] == 'accepted'
                                  ? 'Your request for ${_currentRequest!['quantity']} ${widget.itemName} has been accepted. Message the gardener to arrange pickup.'
                                  : 'Your request for ${_currentRequest!['quantity']} ${widget.itemName} was declined. You can try requesting again.',
                              style: const TextStyle(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading indicator for request
            if (_isLoadingRequest)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Loading request status...'),
                  ],
                ),
              ),

            // Connection Error Banner
            if (_connectionError != null)
              Container(
                margin: const EdgeInsets.all(16),
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
                        _connectionError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _connectWebSocket,
                      child: const Text(
                        'Reconnect',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Chat Messages
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF29A366)))
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: statusColor.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start a conversation with ${widget.userName}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _buildMessageBubble(message, isDarkMode, statusColor);
                          },
                        ),
            ),

            // Message Input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode 
                        ? Colors.white.withOpacity(0.1) 
                        : Colors.black.withOpacity(0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF333333) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: statusColor.withOpacity(0.3),
                        ),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.3),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
                          fontSize: 14,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _messageController.text.isEmpty 
                          ? statusColor.withOpacity(0.5)
                          : statusColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _messageController.text.isEmpty ? null : _sendMessage,
                      icon: Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isDarkMode, Color statusColor) {
    final isMe = message['isMe'] == true;
    final isSending = message['isSending'] == true;
    final isFailed = message['isFailed'] == true;
    final isSystemMessage = message['isSystemMessage'] == true;
    
    if (isSystemMessage) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: isDarkMode ? Colors.white54 : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message['text'],
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.white70 : Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 18,
                backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
                    ? NetworkImage(message['userImage'])
                    : null,
                backgroundColor: statusColor.withOpacity(0.1),
                child: message['userImage'] == null || message['userImage'].isEmpty
                    ? Text(
                        message['userName'][0].toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
            ),
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Text(
                      message['userName'] ?? 'User',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe
                        ? (isDarkMode ? const Color(0xFF333333) : const Color(0xFFC4D3BB))
                        : statusColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                      bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message['text'],
                        style: TextStyle(
                          fontSize: 14,
                          color: isMe
                              ? (isDarkMode ? Colors.white : const Color(0xFF3D2B1F))
                              : Colors.white,
                          height: 1.4,
                        ),
                      ),
                      if (isSending || isFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSending)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                ),
                              if (isFailed)
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 12,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                isSending ? 'Sending...' : 'Failed',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe
                                      ? (isDarkMode ? Colors.white70 : Colors.black54)
                                      : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                
                if (isMe && message['isRead'] == true && !isSending && !isFailed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: Text(
                      'Read',
                      style: TextStyle(
                        fontSize: 10,
                        color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          if (isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                radius: 18,
                backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
                    ? NetworkImage(message['userImage'])
                    : null,
                backgroundColor: statusColor.withOpacity(0.1),
                child: message['userImage'] == null || message['userImage'].isEmpty
                    ? const Icon(Icons.person, size: 16, color: Color(0xFF29A366))
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}





// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:provider/provider.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class ChatScreen extends StatefulWidget {
//   final String itemName;
//   final String userName;
//   final String userImage;
//   final String? productId;
//   final String? productStatus;
//   final int quantity;
//   final String recipientId;
//   final String chatId;
//   final Map<String, dynamic>? requestData; // New: for pending request
  
//   const ChatScreen({
//     Key? key,
//     required this.itemName,
//     required this.userName,
//     required this.userImage,
//     this.productId,
//     this.productStatus,
//     this.quantity = 0,
//     required this.recipientId,
//     required this.chatId,
//     this.requestData,
//   }) : super(key: key);

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _messageController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   WebSocketChannel? _channel;
//   final ApiService _apiService = ApiService();
  
//   List<Map<String, dynamic>> _messages = [];
//   bool _isLoading = true;
//   bool _isConnected = false;
//   String? _connectionError;
  
//   // Request tracking
//   Map<String, dynamic>? _currentRequest;
//   bool _isProcessingRequest = false;
  
//   static const String webSocketUrl = 'wss://foodsharingbackend.onrender.com';

//   @override
//   void initState() {
//     super.initState();
//     _connectWebSocket();
//     _loadMessages();
//     _loadRequestIfNeeded();
//   }

//   void _loadRequestIfNeeded() async {
//     if (widget.requestData != null) {
//       setState(() {
//         _currentRequest = widget.requestData;
//       });
//     } else if (widget.productId != null) {
//       // Check for existing pending request
//       try {
//         final result = await _apiService.getUserProductRequest(widget.productId!);
//         if (result['success'] == true && result['request'] != null) {
//           setState(() {
//             _currentRequest = result['request'];
//           });
//         }
//       } catch (e) {
//         print('Error loading request: $e');
//       }
//     }
//   }

//   void _connectWebSocket() {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final token = authProvider.token;
      
//       if (token == null) {
//         setState(() {
//           _connectionError = 'Not authenticated';
//           _isConnected = false;
//         });
//         return;
//       }
      
//       _channel = WebSocketChannel.connect(
//         Uri.parse('$webSocketUrl/ws?token=$token'),
//       );

//       _channel!.stream.listen(
//         (message) {
//           print('📨 WebSocket message received: $message');
//           final data = jsonDecode(message);
//           _handleIncomingMessage(data);
//         },
//         onError: (error) {
//           print('WebSocket error: $error');
//           setState(() {
//             _connectionError = 'Connection error: $error';
//             _isConnected = false;
//           });
//         },
//         onDone: () {
//           setState(() {
//             _isConnected = false;
//           });
//           Future.delayed(const Duration(seconds: 3), () {
//             if (mounted) _connectWebSocket();
//           });
//         },
//       );

//       setState(() {
//         _isConnected = true;
//         _connectionError = null;
//       });
      
//       // Subscribe to the chat
//       _channel!.sink.add(jsonEncode({
//         'type': 'subscribe',
//         'chatId': widget.chatId,
//       }));
      
//     } catch (e) {
//       print('Failed to connect WebSocket: $e');
//       setState(() {
//         _connectionError = 'Failed to connect: $e';
//         _isConnected = false;
//       });
//     }
//   }

//   Future<void> _loadMessages() async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final result = await _apiService.getChatMessages(widget.chatId);
//       print('📥 Messages response: $result');
      
//       if (result['success'] == true) {
//         final messages = result['messages'] ?? [];
//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         final currentUserId = authProvider.userId;
        
//         setState(() {
//           _messages = messages.map((msg) {
//             final timestamp = DateTime.tryParse(msg['created_at'] ?? msg['timestamp'] ?? DateTime.now().toIso8601String());
//             final isSystemMessage = msg['is_system_message'] == true;
//             final requestId = msg['request_id'];
            
//             return {
//               'id': msg['id'],
//               'text': msg['text'],
//               'isMe': msg['sender_id'] == currentUserId,
//               'time': _formatTime(timestamp ?? DateTime.now()),
//               'userName': msg['sender']?['name'] ?? 
//                           (msg['sender_id'] == currentUserId ? 'You' : widget.userName),
//               'userImage': msg['sender']?['profile_image_url'] ?? 
//                           (msg['sender_id'] == currentUserId ? '' : widget.userImage),
//               'isRead': msg['is_read'] ?? false,
//               'isSending': false,
//               'isFailed': false,
//               'isSystemMessage': isSystemMessage,
//               'requestId': requestId,
//             };
//           }).toList();
//         });
        
//         // Load any request cards from messages
//         await _loadRequestCards();
        
//         _scrollToBottom();
//       }
//     } catch (e) {
//       print('Error loading messages: $e');
//       if (_messages.isEmpty) {
//         setState(() {
//           _messages.add({
//             'id': 'welcome',
//             'text': 'Start a conversation with ${widget.userName} about ${widget.itemName}!',
//             'isMe': false,
//             'time': _formatTime(DateTime.now()),
//             'userName': 'System',
//             'userImage': '',
//             'isRead': true,
//             'isSending': false,
//             'isFailed': false,
//             'isSystemMessage': true,
//           });
//         });
//       }
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _loadRequestCards() async {
//     // Find messages with request IDs
//     final requestMessages = _messages.where((m) => m['requestId'] != null).toList();
    
//     for (var msg in requestMessages) {
//       final requestId = msg['requestId'];
//       if (requestId != null && _currentRequest == null) {
//         try {
//           final result = await _apiService.getRequestDetails(requestId);
//           if (result['success'] == true) {
//             setState(() {
//               _currentRequest = result['request'];
//             });
//           }
//         } catch (e) {
//           print('Error loading request: $e');
//         }
//       }
//     }
//   }

//   void _handleIncomingMessage(Map<String, dynamic> data) {
//     print('📨 Handling incoming message: ${data['type']}');
    
//     if (data['type'] == 'new_message') {
//       final messageData = data['message'];
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUserId = authProvider.userId;
      
//       final bool exists = _messages.any((m) => m['id'] == messageData['id']);
      
//       if (!exists && messageData['senderId'] != currentUserId) {
//         setState(() {
//           _messages.add({
//             'id': messageData['id'],
//             'text': messageData['text'],
//             'isMe': false,
//             'time': _formatTime(DateTime.parse(messageData['timestamp'])),
//             'userName': messageData['senderName'] ?? widget.userName,
//             'userImage': messageData['senderImage'] ?? widget.userImage,
//             'isRead': false,
//             'isSending': false,
//             'isFailed': false,
//             'isSystemMessage': messageData['isSystemMessage'] ?? false,
//             'requestId': messageData['requestId'],
//           });
//         });
        
//         _scrollToBottom();
        
//         // Mark as read
//         _markAsRead(messageData['id']);
        
//         // Reload request if this is a request message
//         if (messageData['requestId'] != null) {
//           _loadRequestCards();
//         }
//       }
//     } 
//     else if (data['type'] == 'message_sent') {
//       final messageData = data['message'];
//       print('✅ Message sent confirmation: ${messageData['id']}');
      
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == messageData['id'] || m['tempId'] == messageData['id']);
//         if (index != -1) {
//           _messages[index]['isSending'] = false;
//           _messages[index]['id'] = messageData['id'];
//           _messages[index]['time'] = _formatTime(DateTime.parse(messageData['timestamp']));
//           _messages[index]['isFailed'] = false;
//         }
//       });
//     }
//     else if (data['type'] == 'request_accepted') {
//       // Request was accepted
//       final requestData = data['request'];
//       setState(() {
//         if (_currentRequest != null && _currentRequest!['id'] == requestData['id']) {
//           _currentRequest!['status'] = 'accepted';
//         }
//       });
//       _loadMessages(); // Refresh to get acceptance message
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('✅ Request accepted! You can now arrange pickup.'),
//           backgroundColor: Colors.green,
//         ),
//       );
//     }
//     else if (data['type'] == 'request_declined') {
//       // Request was declined
//       final requestData = data['request'];
//       setState(() {
//         if (_currentRequest != null && _currentRequest!['id'] == requestData['id']) {
//           _currentRequest!['status'] = 'declined';
//         }
//       });
//       _loadMessages(); // Refresh to get decline message
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('❌ Request was declined.'),
//           backgroundColor: Colors.orange,
//         ),
//       );
//     }
//     else if (data['type'] == 'messages_read') {
//       final messageIds = data['messageIds'] as List;
//       setState(() {
//         for (var message in _messages) {
//           if (messageIds.contains(message['id'])) {
//             message['isRead'] = true;
//           }
//         }
//       });
//     }
//   }

//   Future<void> _acceptRequest() async {
//     if (_currentRequest == null || _isProcessingRequest) return;
    
//     setState(() {
//       _isProcessingRequest = true;
//     });
    
//     try {
//       final result = await _apiService.acceptProductRequest(_currentRequest!['id']);
      
//       if (result['success'] == true) {
//         setState(() {
//           _currentRequest!['status'] = 'accepted';
//         });
        
//         // Send a system message
//         await _sendSystemMessage(
//           '✅ Request accepted! The produce has been reserved for you. Please arrange pickup.'
//         );
        
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Request accepted! User has been notified.'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       } else {
//         throw Exception(result['error']);
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to accept request: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       setState(() {
//         _isProcessingRequest = false;
//       });
//     }
//   }

//   Future<void> _declineRequest() async {
//     if (_currentRequest == null || _isProcessingRequest) return;
    
//     setState(() {
//       _isProcessingRequest = true;
//     });
    
//     try {
//       final result = await _apiService.declineProductRequest(_currentRequest!['id']);
      
//       if (result['success'] == true) {
//         setState(() {
//           _currentRequest!['status'] = 'declined';
//         });
        
//         // Send a system message
//         await _sendSystemMessage(
//           '❌ Request declined. The produce is still available for others.'
//         );
        
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Request declined.'),
//             backgroundColor: Colors.orange,
//           ),
//         );
//       } else {
//         throw Exception(result['error']);
//       }
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to decline request: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       setState(() {
//         _isProcessingRequest = false;
//       });
//     }
//   }

//   Future<void> _sendSystemMessage(String message) async {
//     try {
//       await _apiService.sendMessage(
//         chatId: widget.chatId,
//         recipientId: widget.recipientId,
//         text: message,
//         productId: widget.productId,
//       );
      
//       // Refresh messages
//       await _loadMessages();
//     } catch (e) {
//       print('Error sending system message: $e');
//     }
//   }

//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       Future.delayed(const Duration(milliseconds: 100), () {
//         if (_scrollController.hasClients) {
//           _scrollController.animateTo(
//             _scrollController.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 300),
//             curve: Curves.easeOut,
//           );
//         }
//       });
//     }
//   }

//   void _markAsRead(String messageId) {
//     if (_channel != null && _isConnected) {
//       _channel!.sink.add(jsonEncode({
//         'type': 'mark_read',
//         'chatId': widget.chatId,
//         'messageIds': [messageId],
//       }));
//     }
//   }

//   Future<void> _sendMessage() async {
//     if (_messageController.text.trim().isEmpty) return;

//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;
//     final currentUserId = authProvider.userId;
    
//     final messageText = _messageController.text.trim();
//     _messageController.clear();

//     final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
//     final tempMessage = {
//       'id': tempId,
//       'tempId': tempId,
//       'text': messageText,
//       'isMe': true,
//       'time': 'Sending...',
//       'userName': currentUser?['name'] ?? 'You',
//       'userImage': currentUser?['profile_image_url'] ?? '',
//       'isRead': false,
//       'isSending': true,
//       'isFailed': false,
//       'isSystemMessage': false,
//     };

//     setState(() {
//       _messages.add(tempMessage);
//     });
//     _scrollToBottom();

//     try {
//       if (_channel != null && _isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'message',
//           'chatId': widget.chatId,
//           'recipientId': widget.recipientId,
//           'text': messageText,
//           'productId': widget.productId,
//         }));
        
//         print('📤 Message sent via WebSocket: $tempId');
//       } else {
//         print('⚠️ WebSocket not connected, using API fallback');
//         final result = await _apiService.sendMessage(
//           chatId: widget.chatId,
//           recipientId: widget.recipientId,
//           text: messageText,
//           productId: widget.productId,
//         );
        
//         if (result['success'] == true) {
//           setState(() {
//             final index = _messages.indexWhere((m) => m['id'] == tempId);
//             if (index != -1) {
//               _messages[index]['id'] = result['data']['message']['id'];
//               _messages[index]['isSending'] = false;
//               _messages[index]['time'] = _formatTime(DateTime.now());
//             }
//           });
//         } else {
//           throw Exception(result['error']);
//         }
//       }
//     } catch (e) {
//       print('Error sending message: $e');
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == tempId);
//         if (index != -1) {
//           _messages[index]['isSending'] = false;
//           _messages[index]['isFailed'] = true;
//           _messages[index]['time'] = 'Failed';
//         }
//       });

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to send message: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   String _formatTime(DateTime time) {
//     final now = DateTime.now();
//     final difference = now.difference(time);

//     if (difference.inMinutes < 1) {
//       return 'Just now';
//     } else if (difference.inHours < 1) {
//       return '${difference.inMinutes}m ago';
//     } else if (difference.inDays < 1) {
//       return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
//     } else if (difference.inDays == 1) {
//       return 'Yesterday';
//     } else if (difference.inDays < 7) {
//       return '${time.day}/${time.month}';
//     } else {
//       return '${time.day}/${time.month}/${time.year}';
//     }
//   }

//   Color _getStatusColor() {
//     switch(widget.productStatus) {
//       case 'In Progress':
//         return const Color(0xFFFFC300);
//       case 'Claimed':
//         return const Color(0xFF29A366);
//       case 'Completed':
//         return const Color(0xFF668799);
//       default:
//         return const Color(0xFF29A366);
//     }
//   }

//   @override
//   void dispose() {
//     _messageController.dispose();
//     _scrollController.dispose();
//     if (_channel != null) {
//       if (_isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'unsubscribe',
//           'chatId': widget.chatId,
//         }));
//       }
//       _channel!.sink.close();
//     }
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final statusColor = _getStatusColor();
//     final authProvider = Provider.of<AuthProvider>(context);
//     final currentUserId = authProvider.userId;
//     final isOwner = currentUserId == widget.recipientId;
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // Top Navigation Bar
//             Container(
//               padding: EdgeInsets.only(
//                 top: MediaQuery.of(context).padding.top + 8,
//                 left: 8,
//                 right: 16,
//                 bottom: 12,
//               ),
//               decoration: BoxDecoration(
//                 color: isDarkMode 
//                     ? const Color(0xFF201712).withOpacity(0.95)
//                     : const Color(0xFFF6F5F3).withOpacity(0.95),
//                 border: Border(
//                   bottom: BorderSide(
//                     color: Colors.black.withOpacity(0.05),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   IconButton(
//                     onPressed: () => Navigator.pop(context),
//                     icon: Icon(
//                       Icons.arrow_back_ios,
//                       color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                       size: 20,
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   CircleAvatar(
//                     radius: 20,
//                     backgroundImage: widget.userImage.isNotEmpty
//                         ? NetworkImage(widget.userImage)
//                         : null,
//                     backgroundColor: statusColor.withOpacity(0.1),
//                     child: widget.userImage.isEmpty
//                         ? Text(
//                             widget.userName[0].toUpperCase(),
//                             style: TextStyle(
//                               color: statusColor,
//                               fontWeight: FontWeight.bold,
//                               fontSize: 16,
//                             ),
//                           )
//                         : null,
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           widget.userName,
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                             color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                           ),
//                         ),
//                         Row(
//                           children: [
//                             Container(
//                               width: 8,
//                               height: 8,
//                               decoration: BoxDecoration(
//                                 color: _isConnected ? Colors.green : Colors.red,
//                                 shape: BoxShape.circle,
//                               ),
//                             ),
//                             const SizedBox(width: 4),
//                             Text(
//                               _isConnected ? 'Online' : 'Offline',
//                               style: TextStyle(
//                                 fontSize: 10,
//                                 fontWeight: FontWeight.w500,
//                                 color: _isConnected ? Colors.green : Colors.red,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                   Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                     decoration: BoxDecoration(
//                       color: statusColor,
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: Text(
//                       widget.quantity > 0 
//                           ? '${widget.quantity} left'
//                           : 'Claimed',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Request Card (if pending and owner)
//             if (_currentRequest != null && _currentRequest!['status'] == 'pending' && isOwner)
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   gradient: const LinearGradient(
//                     colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   ),
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(color: Colors.orange.withOpacity(0.3)),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.orange.withOpacity(0.2),
//                       blurRadius: 8,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: Padding(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           Container(
//                             padding: const EdgeInsets.all(8),
//                             decoration: BoxDecoration(
//                               color: Colors.orange.withOpacity(0.2),
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             child: const Icon(
//                               Icons.request_page,
//                               color: Colors.orange,
//                               size: 24,
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 const Text(
//                                   'Pending Request',
//                                   style: TextStyle(
//                                     fontWeight: FontWeight.bold,
//                                     fontSize: 16,
//                                     color: Colors.orange,
//                                   ),
//                                 ),
//                                 Text(
//                                   '${_currentRequest!['quantity']} ${widget.itemName}',
//                                   style: const TextStyle(
//                                     fontSize: 14,
//                                     fontWeight: FontWeight.w500,
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 12),
//                       if (_currentRequest!['message'] != null && _currentRequest!['message'].toString().isNotEmpty)
//                         Container(
//                           padding: const EdgeInsets.all(12),
//                           margin: const EdgeInsets.only(bottom: 12),
//                           decoration: BoxDecoration(
//                             color: Colors.white.withOpacity(0.7),
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           child: Text(
//                             '"${_currentRequest!['message']}"',
//                             style: const TextStyle(
//                               fontSize: 13,
//                               fontStyle: FontStyle.italic,
//                             ),
//                           ),
//                         ),
//                       const SizedBox(height: 12),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: OutlinedButton(
//                               onPressed: _isProcessingRequest ? null : _declineRequest,
//                               style: OutlinedButton.styleFrom(
//                                 foregroundColor: Colors.red,
//                                 side: const BorderSide(color: Colors.red),
//                                 padding: const EdgeInsets.symmetric(vertical: 12),
//                               ),
//                               child: _isProcessingRequest
//                                   ? const SizedBox(
//                                       width: 20,
//                                       height: 20,
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                       ),
//                                     )
//                                   : const Text('Decline'),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: ElevatedButton(
//                               onPressed: _isProcessingRequest ? null : _acceptRequest,
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: const Color(0xFF29A366),
//                                 padding: const EdgeInsets.symmetric(vertical: 12),
//                               ),
//                               child: _isProcessingRequest
//                                   ? const SizedBox(
//                                       width: 20,
//                                       height: 20,
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                         color: Colors.white,
//                                       ),
//                                     )
//                                   : const Text('Accept Request'),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),

//             // Request Status Card (for requester)
//             if (_currentRequest != null && _currentRequest!['status'] != 'pending' && !isOwner)
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: _currentRequest!['status'] == 'accepted'
//                       ? Colors.green.withOpacity(0.1)
//                       : Colors.red.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(
//                     color: _currentRequest!['status'] == 'accepted'
//                         ? Colors.green.withOpacity(0.3)
//                         : Colors.red.withOpacity(0.3),
//                   ),
//                 ),
//                 child: Padding(
//                   padding: const EdgeInsets.all(16),
//                   child: Row(
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: _currentRequest!['status'] == 'accepted'
//                               ? Colors.green.withOpacity(0.2)
//                               : Colors.red.withOpacity(0.2),
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: Icon(
//                           _currentRequest!['status'] == 'accepted'
//                               ? Icons.check_circle
//                               : Icons.cancel,
//                           color: _currentRequest!['status'] == 'accepted'
//                               ? Colors.green
//                               : Colors.red,
//                           size: 24,
//                         ),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               _currentRequest!['status'] == 'accepted'
//                                   ? 'Request Accepted! 🎉'
//                                   : 'Request Declined ❌',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 16,
//                                 color: _currentRequest!['status'] == 'accepted'
//                                     ? Colors.green
//                                     : Colors.red,
//                               ),
//                             ),
//                             Text(
//                               _currentRequest!['status'] == 'accepted'
//                                   ? 'Your request for ${_currentRequest!['quantity']} ${widget.itemName} has been accepted. Message the gardener to arrange pickup.'
//                                   : 'Your request for ${_currentRequest!['quantity']} ${widget.itemName} was declined. You can try requesting again.',
//                               style: const TextStyle(
//                                 fontSize: 13,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),

//             // Connection Error Banner
//             if (_connectionError != null)
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: Colors.red.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(color: Colors.red.withOpacity(0.3)),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.error_outline, color: Colors.red, size: 20),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _connectionError!,
//                         style: const TextStyle(color: Colors.red, fontSize: 12),
//                       ),
//                     ),
//                     TextButton(
//                       onPressed: _connectWebSocket,
//                       child: const Text(
//                         'Reconnect',
//                         style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//             // Chat Messages
//             Expanded(
//               child: _isLoading
//                   ? const Center(child: CircularProgressIndicator(color: Color(0xFF29A366)))
//                   : _messages.isEmpty
//                       ? Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(
//                                 Icons.chat_bubble_outline,
//                                 size: 64,
//                                 color: statusColor.withOpacity(0.3),
//                               ),
//                               const SizedBox(height: 16),
//                               Text(
//                                 'No messages yet',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                               Text(
//                                 'Start a conversation with ${widget.userName}',
//                                 style: TextStyle(
//                                   fontSize: 14,
//                                   color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         )
//                       : ListView.builder(
//                           controller: _scrollController,
//                           padding: const EdgeInsets.all(16),
//                           itemCount: _messages.length,
//                           itemBuilder: (context, index) {
//                             final message = _messages[index];
//                             return _buildMessageBubble(message, isDarkMode, statusColor);
//                           },
//                         ),
//             ),

//             // Message Input
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//                 border: Border(
//                   top: BorderSide(
//                     color: isDarkMode 
//                         ? Colors.white.withOpacity(0.1) 
//                         : Colors.black.withOpacity(0.1),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 16),
//                       decoration: BoxDecoration(
//                         color: isDarkMode ? const Color(0xFF333333) : Colors.white,
//                         borderRadius: BorderRadius.circular(24),
//                         border: Border.all(
//                           color: statusColor.withOpacity(0.3),
//                         ),
//                       ),
//                       child: TextField(
//                         controller: _messageController,
//                         decoration: InputDecoration(
//                           hintText: 'Type a message...',
//                           hintStyle: TextStyle(
//                             color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.3),
//                             fontSize: 14,
//                           ),
//                           border: InputBorder.none,
//                         ),
//                         style: TextStyle(
//                           color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                           fontSize: 14,
//                         ),
//                         onSubmitted: (_) => _sendMessage(),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   Container(
//                     width: 44,
//                     height: 44,
//                     decoration: BoxDecoration(
//                       color: _messageController.text.isEmpty 
//                           ? statusColor.withOpacity(0.5)
//                           : statusColor,
//                       shape: BoxShape.circle,
//                     ),
//                     child: IconButton(
//                       onPressed: _messageController.text.isEmpty ? null : _sendMessage,
//                       icon: Icon(
//                         Icons.send,
//                         color: Colors.white,
//                         size: 20,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMessageBubble(Map<String, dynamic> message, bool isDarkMode, Color statusColor) {
//     final isMe = message['isMe'] == true;
//     final isSending = message['isSending'] == true;
//     final isFailed = message['isFailed'] == true;
//     final isSystemMessage = message['isSystemMessage'] == true;
    
//     // Style for system messages
//     if (isSystemMessage) {
//       return Container(
//         margin: const EdgeInsets.symmetric(vertical: 8),
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//         decoration: BoxDecoration(
//           color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Row(
//           children: [
//             Icon(
//               Icons.info_outline,
//               size: 14,
//               color: isDarkMode ? Colors.white54 : Colors.grey[600],
//             ),
//             const SizedBox(width: 8),
//             Expanded(
//               child: Text(
//                 message['text'],
//                 style: TextStyle(
//                   fontSize: 12,
//                   color: isDarkMode ? Colors.white70 : Colors.grey[700],
//                   fontStyle: FontStyle.italic,
//                 ),
//                 textAlign: TextAlign.center,
//               ),
//             ),
//           ],
//         ),
//       );
//     }
    
//     return Container(
//       margin: EdgeInsets.only(bottom: 16),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.end,
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           if (!isMe)
//             Padding(
//               padding: const EdgeInsets.only(right: 8),
//               child: CircleAvatar(
//                 radius: 18,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? Text(
//                         message['userName'][0].toUpperCase(),
//                         style: TextStyle(
//                           color: statusColor,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 14,
//                         ),
//                       )
//                     : null,
//               ),
//             ),
          
//           Flexible(
//             child: Column(
//               crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
//               children: [
//                 if (!isMe)
//                   Padding(
//                     padding: const EdgeInsets.only(left: 8, bottom: 4),
//                     child: Text(
//                       message['userName'] ?? 'User',
//                       style: TextStyle(
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                       ),
//                     ),
//                   ),
                
//                 Container(
//                   constraints: BoxConstraints(
//                     maxWidth: MediaQuery.of(context).size.width * 0.7,
//                   ),
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: isMe
//                         ? (isDarkMode ? const Color(0xFF333333) : const Color(0xFFC4D3BB))
//                         : statusColor,
//                     borderRadius: BorderRadius.only(
//                       topLeft: const Radius.circular(12),
//                       topRight: const Radius.circular(12),
//                       bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
//                       bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
//                     ),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         message['text'],
//                         style: TextStyle(
//                           fontSize: 14,
//                           color: isMe
//                               ? (isDarkMode ? Colors.white : const Color(0xFF3D2B1F))
//                               : Colors.white,
//                           height: 1.4,
//                         ),
//                       ),
//                       if (isSending || isFailed)
//                         Padding(
//                           padding: const EdgeInsets.only(top: 4),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               if (isSending)
//                                 const SizedBox(
//                                   width: 12,
//                                   height: 12,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     color: Colors.white70,
//                                   ),
//                                 ),
//                               if (isFailed)
//                                 const Icon(
//                                   Icons.error_outline,
//                                   color: Colors.red,
//                                   size: 12,
//                                 ),
//                               const SizedBox(width: 4),
//                               Text(
//                                 isSending ? 'Sending...' : 'Failed',
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   color: isMe
//                                       ? (isDarkMode ? Colors.white70 : Colors.black54)
//                                       : Colors.white70,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
                
//                 if (isMe && message['isRead'] == true && !isSending && !isFailed)
//                   Padding(
//                     padding: const EdgeInsets.only(right: 8, top: 4),
//                     child: Text(
//                       'Read',
//                       style: TextStyle(
//                         fontSize: 10,
//                         color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.4),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
          
//           if (isMe)
//             Padding(
//               padding: const EdgeInsets.only(left: 8),
//               child: CircleAvatar(
//                 radius: 18,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? const Icon(Icons.person, size: 16, color: Color(0xFF29A366))
//                     : null,
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }










// Old


// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:provider/provider.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class ChatScreen extends StatefulWidget {
//   final String itemName;
//   final String userName;
//   final String userImage;
//   final String? productId;
//   final String? productStatus;
//   final int quantity;
//   final String recipientId;
//   final String chatId;
  
//   const ChatScreen({
//     Key? key,
//     required this.itemName,
//     required this.userName,
//     required this.userImage,
//     this.productId,
//     this.productStatus,
//     this.quantity = 0,
//     required this.recipientId,
//     required this.chatId,
//   }) : super(key: key);

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _messageController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   WebSocketChannel? _channel;
//   final ApiService _apiService = ApiService();
  
//   List<Map<String, dynamic>> _messages = [];
//   bool _isLoading = true;
//   bool _isConnected = false;
//   String? _connectionError;
  
//   static const String webSocketUrl = 'wss://foodsharingbackend.onrender.com';

//   @override
//   void initState() {
//     super.initState();
//     _connectWebSocket();
//     _loadMessages();
//   }

//   void _connectWebSocket() {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final token = authProvider.token;
      
//       if (token == null) {
//         setState(() {
//           _connectionError = 'Not authenticated';
//           _isConnected = false;
//         });
//         return;
//       }
      
//       _channel = WebSocketChannel.connect(
//         Uri.parse('$webSocketUrl/ws?token=$token'),
//       );

//       _channel!.stream.listen(
//         (message) {
//           print('📨 WebSocket message received: $message');
//           final data = jsonDecode(message);
//           _handleIncomingMessage(data);
//         },
//         onError: (error) {
//           print('WebSocket error: $error');
//           setState(() {
//             _connectionError = 'Connection error: $error';
//             _isConnected = false;
//           });
//         },
//         onDone: () {
//           setState(() {
//             _isConnected = false;
//           });
//           Future.delayed(const Duration(seconds: 3), () {
//             if (mounted) _connectWebSocket();
//           });
//         },
//       );

//       setState(() {
//         _isConnected = true;
//         _connectionError = null;
//       });
      
//       // Subscribe to the chat
//       _channel!.sink.add(jsonEncode({
//         'type': 'subscribe',
//         'chatId': widget.chatId,
//       }));
      
//     } catch (e) {
//       print('Failed to connect WebSocket: $e');
//       setState(() {
//         _connectionError = 'Failed to connect: $e';
//         _isConnected = false;
//       });
//     }
//   }

//   Future<void> _loadMessages() async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final result = await _apiService.getChatMessages(widget.chatId);
//       print('📥 Messages response: $result');
      
//       if (result['success'] == true) {
//         final messages = result['messages'] ?? [];
//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         final currentUserId = authProvider.userId;
        
//         setState(() {
//           _messages = messages.map((msg) {
//             final timestamp = DateTime.tryParse(msg['created_at'] ?? msg['timestamp'] ?? DateTime.now().toIso8601String());
            
//             return {
//               'id': msg['id'],
//               'text': msg['text'],
//               'isMe': msg['sender_id'] == currentUserId,
//               'time': _formatTime(timestamp ?? DateTime.now()),
//               'userName': msg['sender']?['name'] ?? 
//                           (msg['sender_id'] == currentUserId ? 'You' : widget.userName),
//               'userImage': msg['sender']?['profile_image_url'] ?? 
//                           (msg['sender_id'] == currentUserId ? '' : widget.userImage),
//               'isRead': msg['is_read'] ?? false,
//               'isSending': false,
//               'isFailed': false,
//             };
//           }).toList();
//         });
        
//         _scrollToBottom();
//       }
//     } catch (e) {
//       print('Error loading messages: $e');
//       if (_messages.isEmpty) {
//         setState(() {
//           _messages.add({
//             'id': 'welcome',
//             'text': 'Start a conversation with ${widget.userName} about ${widget.itemName}!',
//             'isMe': false,
//             'time': _formatTime(DateTime.now()),
//             'userName': 'System',
//             'userImage': '',
//             'isRead': true,
//             'isSending': false,
//             'isFailed': false,
//           });
//         });
//       }
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   void _handleIncomingMessage(Map<String, dynamic> data) {
//     print('📨 Handling incoming message: ${data['type']}');
    
//     if (data['type'] == 'new_message') {
//       final messageData = data['message'];
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUserId = authProvider.userId;
      
//       // Check if message already exists (prevent duplicates)
//       final bool exists = _messages.any((m) => m['id'] == messageData['id']);
      
//       if (!exists && messageData['senderId'] != currentUserId) {
//         setState(() {
//           _messages.add({
//             'id': messageData['id'],
//             'text': messageData['text'],
//             'isMe': false,
//             'time': _formatTime(DateTime.parse(messageData['timestamp'])),
//             'userName': messageData['senderName'] ?? widget.userName,
//             'userImage': messageData['senderImage'] ?? widget.userImage,
//             'isRead': false,
//             'isSending': false,
//             'isFailed': false,
//           });
//         });
        
//         _scrollToBottom();
        
//         // Mark as read
//         _markAsRead(messageData['id']);
//       }
//     } 
//     else if (data['type'] == 'message_sent') {
//       // This is the confirmation for a message we sent
//       final messageData = data['message'];
//       print('✅ Message sent confirmation: ${messageData['id']}');
      
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == messageData['id'] || m['tempId'] == messageData['id']);
//         if (index != -1) {
//           _messages[index]['isSending'] = false;
//           _messages[index]['id'] = messageData['id'];
//           _messages[index]['time'] = _formatTime(DateTime.parse(messageData['timestamp']));
//           _messages[index]['isFailed'] = false;
//         }
//       });
//     }
//     else if (data['type'] == 'messages_read') {
//       final messageIds = data['messageIds'] as List;
//       setState(() {
//         for (var message in _messages) {
//           if (messageIds.contains(message['id'])) {
//             message['isRead'] = true;
//           }
//         }
//       });
//     }
//     else if (data['type'] == 'message_failed') {
//       final chatId = data['chatId'];
//       print('❌ Message failed to send');
      
//       setState(() {
//         // Find the last unsent message
//         for (var message in _messages.reversed) {
//           if (message['isSending'] == true) {
//             message['isSending'] = false;
//             message['isFailed'] = true;
//             break;
//           }
//         }
//       });
//     }
//   }

//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       Future.delayed(const Duration(milliseconds: 100), () {
//         if (_scrollController.hasClients) {
//           _scrollController.animateTo(
//             _scrollController.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 300),
//             curve: Curves.easeOut,
//           );
//         }
//       });
//     }
//   }

//   void _markAsRead(String messageId) {
//     if (_channel != null && _isConnected) {
//       _channel!.sink.add(jsonEncode({
//         'type': 'mark_read',
//         'chatId': widget.chatId,
//         'messageIds': [messageId],
//       }));
//     }
//   }

//   Future<void> _sendMessage() async {
//     if (_messageController.text.trim().isEmpty) return;

//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;
//     final currentUserId = authProvider.userId;
    
//     final messageText = _messageController.text.trim();
//     _messageController.clear();

//     // Create temporary ID
//     final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
//     // Add message optimistically
//     final tempMessage = {
//       'id': tempId,
//       'tempId': tempId,
//       'text': messageText,
//       'isMe': true,
//       'time': 'Sending...',
//       'userName': currentUser?['name'] ?? 'You',
//       'userImage': currentUser?['profile_image_url'] ?? '',
//       'isRead': false,
//       'isSending': true,
//       'isFailed': false,
//     };

//     setState(() {
//       _messages.add(tempMessage);
//     });
//     _scrollToBottom();

//     try {
//       // Send via WebSocket
//       if (_channel != null && _isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'message',
//           'chatId': widget.chatId,
//           'recipientId': widget.recipientId,
//           'text': messageText,
//           'productId': widget.productId,
//         }));
        
//         // The message will be confirmed via 'message_sent' event
//         print('📤 Message sent via WebSocket: $tempId');
//       } else {
//         // Fallback to API if WebSocket is not connected
//         print('⚠️ WebSocket not connected, using API fallback');
//         final result = await _apiService.sendMessage(
//           chatId: widget.chatId,
//           recipientId: widget.recipientId,
//           text: messageText,
//           productId: widget.productId,
//         );
        
//         if (result['success'] == true) {
//           setState(() {
//             final index = _messages.indexWhere((m) => m['id'] == tempId);
//             if (index != -1) {
//               _messages[index]['id'] = result['data']['message']['id'];
//               _messages[index]['isSending'] = false;
//               _messages[index]['time'] = _formatTime(DateTime.now());
//             }
//           });
//         } else {
//           throw Exception(result['error']);
//         }
//       }
//     } catch (e) {
//       print('Error sending message: $e');
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == tempId);
//         if (index != -1) {
//           _messages[index]['isSending'] = false;
//           _messages[index]['isFailed'] = true;
//           _messages[index]['time'] = 'Failed';
//         }
//       });

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to send message: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   String _formatTime(DateTime time) {
//     final now = DateTime.now();
//     final difference = now.difference(time);

//     if (difference.inMinutes < 1) {
//       return 'Just now';
//     } else if (difference.inHours < 1) {
//       return '${difference.inMinutes}m ago';
//     } else if (difference.inDays < 1) {
//       return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
//     } else if (difference.inDays == 1) {
//       return 'Yesterday';
//     } else if (difference.inDays < 7) {
//       return '${time.day}/${time.month}';
//     } else {
//       return '${time.day}/${time.month}/${time.year}';
//     }
//   }

//   Color _getStatusColor() {
//     switch(widget.productStatus) {
//       case 'In Progress':
//         return const Color(0xFFFFC300);
//       case 'Claimed':
//         return const Color(0xFF29A366);
//       case 'Completed':
//         return const Color(0xFF668799);
//       default:
//         return const Color(0xFF29A366);
//     }
//   }

//   @override
//   void dispose() {
//     _messageController.dispose();
//     _scrollController.dispose();
//     if (_channel != null) {
//       if (_isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'unsubscribe',
//           'chatId': widget.chatId,
//         }));
//       }
//       _channel!.sink.close();
//     }
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final statusColor = _getStatusColor();
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // Top Navigation Bar
//             Container(
//               padding: EdgeInsets.only(
//                 top: MediaQuery.of(context).padding.top + 8,
//                 left: 8,
//                 right: 16,
//                 bottom: 12,
//               ),
//               decoration: BoxDecoration(
//                 color: isDarkMode 
//                     ? const Color(0xFF201712).withOpacity(0.95)
//                     : const Color(0xFFF6F5F3).withOpacity(0.95),
//                 border: Border(
//                   bottom: BorderSide(
//                     color: Colors.black.withOpacity(0.05),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   IconButton(
//                     onPressed: () => Navigator.pop(context),
//                     icon: Icon(
//                       Icons.arrow_back_ios,
//                       color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                       size: 20,
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   CircleAvatar(
//                     radius: 20,
//                     backgroundImage: widget.userImage.isNotEmpty
//                         ? NetworkImage(widget.userImage)
//                         : null,
//                     backgroundColor: statusColor.withOpacity(0.1),
//                     child: widget.userImage.isEmpty
//                         ? Text(
//                             widget.userName[0].toUpperCase(),
//                             style: TextStyle(
//                               color: statusColor,
//                               fontWeight: FontWeight.bold,
//                               fontSize: 16,
//                             ),
//                           )
//                         : null,
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           widget.userName,
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                             color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                           ),
//                         ),
//                         Row(
//                           children: [
//                             Container(
//                               width: 8,
//                               height: 8,
//                               decoration: BoxDecoration(
//                                 color: _isConnected ? Colors.green : Colors.red,
//                                 shape: BoxShape.circle,
//                               ),
//                             ),
//                             const SizedBox(width: 4),
//                             Text(
//                               _isConnected ? 'Online' : 'Offline',
//                               style: TextStyle(
//                                 fontSize: 10,
//                                 fontWeight: FontWeight.w500,
//                                 color: _isConnected ? Colors.green : Colors.red,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                   Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//                     decoration: BoxDecoration(
//                       color: statusColor,
//                       borderRadius: BorderRadius.circular(20),
//                     ),
//                     child: Text(
//                       widget.quantity > 0 
//                           ? '${widget.quantity} left'
//                           : 'Claimed',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Connection Error Banner
//             if (_connectionError != null)
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: Colors.red.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(color: Colors.red.withOpacity(0.3)),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.error_outline, color: Colors.red, size: 20),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _connectionError!,
//                         style: const TextStyle(color: Colors.red, fontSize: 12),
//                       ),
//                     ),
//                     TextButton(
//                       onPressed: _connectWebSocket,
//                       child: const Text(
//                         'Reconnect',
//                         style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//             // Chat Messages
//             Expanded(
//               child: _isLoading
//                   ? const Center(child: CircularProgressIndicator(color: Color(0xFF29A366)))
//                   : _messages.isEmpty
//                       ? Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(
//                                 Icons.chat_bubble_outline,
//                                 size: 64,
//                                 color: statusColor.withOpacity(0.3),
//                               ),
//                               const SizedBox(height: 16),
//                               Text(
//                                 'No messages yet',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                               Text(
//                                 'Start a conversation with ${widget.userName}',
//                                 style: TextStyle(
//                                   fontSize: 14,
//                                   color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         )
//                       : ListView.builder(
//                           controller: _scrollController,
//                           padding: const EdgeInsets.all(16),
//                           itemCount: _messages.length,
//                           itemBuilder: (context, index) {
//                             final message = _messages[index];
//                             return _buildMessageBubble(message, isDarkMode, statusColor);
//                           },
//                         ),
//             ),

//             // Message Input
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//                 border: Border(
//                   top: BorderSide(
//                     color: isDarkMode 
//                         ? Colors.white.withOpacity(0.1) 
//                         : Colors.black.withOpacity(0.1),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 16),
//                       decoration: BoxDecoration(
//                         color: isDarkMode ? const Color(0xFF333333) : Colors.white,
//                         borderRadius: BorderRadius.circular(24),
//                         border: Border.all(
//                           color: statusColor.withOpacity(0.3),
//                         ),
//                       ),
//                       child: TextField(
//                         controller: _messageController,
//                         decoration: InputDecoration(
//                           hintText: 'Type a message...',
//                           hintStyle: TextStyle(
//                             color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.3),
//                             fontSize: 14,
//                           ),
//                           border: InputBorder.none,
//                         ),
//                         style: TextStyle(
//                           color: isDarkMode ? Colors.white : const Color(0xFF3D2B1F),
//                           fontSize: 14,
//                         ),
//                         onSubmitted: (_) => _sendMessage(),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(width: 8),
//                   Container(
//                     width: 44,
//                     height: 44,
//                     decoration: BoxDecoration(
//                       color: _messageController.text.isEmpty 
//                           ? statusColor.withOpacity(0.5)
//                           : statusColor,
//                       shape: BoxShape.circle,
//                     ),
//                     child: IconButton(
//                       onPressed: _messageController.text.isEmpty ? null : _sendMessage,
//                       icon: Icon(
//                         Icons.send,
//                         color: Colors.white,
//                         size: 20,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMessageBubble(Map<String, dynamic> message, bool isDarkMode, Color statusColor) {
//     final isMe = message['isMe'] == true;
//     final isSending = message['isSending'] == true;
//     final isFailed = message['isFailed'] == true;
    
//     return Container(
//       margin: EdgeInsets.only(bottom: 16),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.end,
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           if (!isMe)
//             Padding(
//               padding: const EdgeInsets.only(right: 8),
//               child: CircleAvatar(
//                 radius: 18,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? Text(
//                         message['userName'][0].toUpperCase(),
//                         style: TextStyle(
//                           color: statusColor,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 14,
//                         ),
//                       )
//                     : null,
//               ),
//             ),
          
//           Flexible(
//             child: Column(
//               crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
//               children: [
//                 if (!isMe)
//                   Padding(
//                     padding: const EdgeInsets.only(left: 8, bottom: 4),
//                     child: Text(
//                       message['userName'] ?? 'User',
//                       style: TextStyle(
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                       ),
//                     ),
//                   ),
                
//                 Container(
//                   constraints: BoxConstraints(
//                     maxWidth: MediaQuery.of(context).size.width * 0.7,
//                   ),
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: isMe
//                         ? (isDarkMode ? const Color(0xFF333333) : const Color(0xFFC4D3BB))
//                         : statusColor,
//                     borderRadius: BorderRadius.only(
//                       topLeft: const Radius.circular(12),
//                       topRight: const Radius.circular(12),
//                       bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
//                       bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
//                     ),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         message['text'],
//                         style: TextStyle(
//                           fontSize: 14,
//                           color: isMe
//                               ? (isDarkMode ? Colors.white : const Color(0xFF3D2B1F))
//                               : Colors.white,
//                           height: 1.4,
//                         ),
//                       ),
//                       if (isSending || isFailed)
//                         Padding(
//                           padding: const EdgeInsets.only(top: 4),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               if (isSending)
//                                 const SizedBox(
//                                   width: 12,
//                                   height: 12,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     color: Colors.white70,
//                                   ),
//                                 ),
//                               if (isFailed)
//                                 const Icon(
//                                   Icons.error_outline,
//                                   color: Colors.red,
//                                   size: 12,
//                                 ),
//                               const SizedBox(width: 4),
//                               Text(
//                                 isSending ? 'Sending...' : 'Failed',
//                                 style: TextStyle(
//                                   fontSize: 10,
//                                   color: isMe
//                                       ? (isDarkMode ? Colors.white70 : Colors.black54)
//                                       : Colors.white70,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
                
//                 if (isMe && message['isRead'] == true && !isSending && !isFailed)
//                   Padding(
//                     padding: const EdgeInsets.only(right: 8, top: 4),
//                     child: Text(
//                       'Read',
//                       style: TextStyle(
//                         fontSize: 10,
//                         color: (isDarkMode ? Colors.white : const Color(0xFF3D2B1F)).withOpacity(0.4),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
          
//           if (isMe)
//             Padding(
//               padding: const EdgeInsets.only(left: 8),
//               child: CircleAvatar(
//                 radius: 18,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? const Icon(Icons.person, size: 16, color: Color(0xFF29A366))
//                     : null,
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }











// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:provider/provider.dart';
// import 'providers/auth_provider.dart';
// import 'services/api_service.dart';

// class ChatScreen extends StatefulWidget {
//   final String itemName;
//   final String userName;
//   final String userImage;
//   final String? productId;
//   final String? productStatus;
//   final int quantity;
//   final String recipientId;
//   final String chatId;
  
//   const ChatScreen({
//     Key? key,
//     required this.itemName,
//     required this.userName,
//     required this.userImage,
//     this.productId,
//     this.productStatus,
//     this.quantity = 0,
//     required this.recipientId,
//     required this.chatId,
//   }) : super(key: key);

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _messageController = TextEditingController();
//   final ScrollController _scrollController = ScrollController();
//   WebSocketChannel? _channel;
//   final ApiService _apiService = ApiService();
  
//   List<Map<String, dynamic>> _messages = [];
//   bool _isLoading = true;
//   bool _isConnected = false;
//   String? _connectionError;
  
//   // WebSocket server URL
//   static const String webSocketUrl = 'wss://foodsharingbackend.onrender.com';

//   @override
//   void initState() {
//     super.initState();
//     _connectWebSocket();
//     _loadMessages();
//   }

//   void _connectWebSocket() {
//     try {
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final token = authProvider.token;
      
//       if (token == null) {
//         setState(() {
//           _connectionError = 'Not authenticated';
//           _isConnected = false;
//         });
//         return;
//       }
      
//       _channel = WebSocketChannel.connect(
//         Uri.parse('$webSocketUrl/ws?token=$token'),
//       );

//       _channel!.stream.listen(
//         (message) {
//           final data = jsonDecode(message);
//           _handleIncomingMessage(data);
//         },
//         onError: (error) {
//           print('WebSocket error: $error');
//           setState(() {
//             _connectionError = 'Connection error: $error';
//             _isConnected = false;
//           });
//         },
//         onDone: () {
//           setState(() {
//             _isConnected = false;
//           });
//           Future.delayed(const Duration(seconds: 3), () {
//             if (mounted) _connectWebSocket();
//           });
//         },
//       );

//       setState(() {
//         _isConnected = true;
//         _connectionError = null;
//       });
      
//       // Subscribe to the chat
//       _channel!.sink.add(jsonEncode({
//         'type': 'subscribe',
//         'chatId': widget.chatId,
//       }));
      
//     } catch (e) {
//       print('Failed to connect WebSocket: $e');
//       setState(() {
//         _connectionError = 'Failed to connect: $e';
//         _isConnected = false;
//       });
//     }
//   }

//   Future<void> _loadMessages() async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final result = await _apiService.getChatMessages(widget.chatId);
//       if (result['success'] == true) {
//         final messages = result['messages'] ?? [];
//         final authProvider = Provider.of<AuthProvider>(context, listen: false);
//         final currentUserId = authProvider.userId;
        
//         setState(() {
//           _messages = messages.map((msg) {
//             final timestamp = _parseTimestamp(msg['created_at'] ?? msg['timestamp']);
            
//             return {
//               'id': msg['id'],
//               'text': msg['text'],
//               'isMe': msg['sender_id'] == currentUserId,
//               'time': _formatTime(timestamp),
//               'userName': msg['sender']?['name'] ?? 
//                           (msg['sender_id'] == currentUserId ? 'You' : widget.userName),
//               'userImage': msg['sender']?['profile_image_url'] ?? 
//                           (msg['sender_id'] == currentUserId ? '' : widget.userImage),
//               'isRead': msg['is_read'] ?? false,
//             };
//           }).toList();
//         });
        
//         WidgetsBinding.instance.addPostFrameCallback((_) {
//           _scrollToBottom();
//         });
//       }
//     } catch (e) {
//       print('Error loading messages: $e');
//       if (_messages.isEmpty) {
//         setState(() {
//           _messages.add({
//             'id': 'welcome',
//             'text': 'Start a conversation with ${widget.userName} about ${widget.itemName}!',
//             'isMe': false,
//             'time': _formatTime(DateTime.now()),
//             'userName': 'System',
//             'userImage': '',
//             'isRead': true,
//           });
//         });
//       }
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   DateTime _parseTimestamp(String? timestamp) {
//     if (timestamp == null || timestamp.isEmpty) return DateTime.now();
//     try {
//       if (timestamp.contains('+')) {
//         final baseTime = timestamp.split('+')[0];
//         return DateTime.parse(baseTime);
//       } else if (timestamp.contains('Z')) {
//         return DateTime.parse(timestamp);
//       } else {
//         return DateTime.parse(timestamp);
//       }
//     } catch (e) {
//       print('Error parsing timestamp: $timestamp, error: $e');
//       return DateTime.now();
//     }
//   }

//   void _handleIncomingMessage(Map<String, dynamic> data) {
//     if (data['type'] == 'new_message') {
//       final messageData = data['message'];
//       final authProvider = Provider.of<AuthProvider>(context, listen: false);
//       final currentUserId = authProvider.userId;
      
//       // Check if message already exists (to prevent duplicates)
//       final bool exists = _messages.any((m) => m['id'] == messageData['id']);
//       if (!exists) {
//         setState(() {
//           _messages.add({
//             'id': messageData['id'],
//             'text': messageData['text'],
//             'isMe': messageData['senderId'] == currentUserId,
//             'time': _formatTime(_parseTimestamp(messageData['timestamp'])),
//             'userName': messageData['senderName'] ?? widget.userName,
//             'userImage': messageData['senderImage'] ?? widget.userImage,
//             'isRead': false,
//           });
//         });
        
//         _scrollToBottom();
        
//         if (messageData['senderId'] != currentUserId) {
//           _markAsRead(messageData['id']);
//         }
//       }
//     } else if (data['type'] == 'message_sent') {
//       final messageData = data['message'];
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == messageData['id']);
//         if (index != -1) {
//           _messages[index]['isSending'] = false;
//           _messages[index]['time'] = _formatTime(DateTime.now());
//         }
//       });
//     } else if (data['type'] == 'messages_read') {
//       final messageIds = data['messageIds'] as List;
//       setState(() {
//         for (var message in _messages) {
//           if (messageIds.contains(message['id'])) {
//             message['isRead'] = true;
//           }
//         }
//       });
//     }
//   }

//   void _scrollToBottom() {
//     if (_scrollController.hasClients) {
//       Future.delayed(const Duration(milliseconds: 100), () {
//         if (_scrollController.hasClients) {
//           _scrollController.animateTo(
//             _scrollController.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 300),
//             curve: Curves.easeOut,
//           );
//         }
//       });
//     }
//   }

//   void _markAsRead(String messageId) {
//     if (_channel != null && _isConnected) {
//       _channel!.sink.add(jsonEncode({
//         'type': 'mark_read',
//         'chatId': widget.chatId,
//         'messageIds': [messageId],
//       }));
//     }
//   }

//   Future<void> _sendMessage() async {
//     if (_messageController.text.trim().isEmpty) return;

//     final authProvider = Provider.of<AuthProvider>(context, listen: false);
//     final currentUser = authProvider.currentUser;
//     final currentUserId = authProvider.userId;
    
//     final messageText = _messageController.text.trim();
//     _messageController.clear();

//     // Create temporary ID
//     final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    
//     // Add message optimistically
//     final tempMessage = {
//       'id': tempId,
//       'text': messageText,
//       'isMe': true,
//       'time': 'Sending...',
//       'userName': currentUser?['name'] ?? 'You',
//       'userImage': currentUser?['profile_image_url'] ?? '',
//       'isRead': false,
//       'isSending': true,
//     };

//     setState(() {
//       _messages.add(tempMessage);
//     });
//     _scrollToBottom();

//     try {
//       // Send ONLY via WebSocket (not both)
//       if (_channel != null && _isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'message',
//           'chatId': widget.chatId,
//           'recipientId': widget.recipientId,
//           'text': messageText,
//           'productId': widget.productId,
//         }));
//       } else {
//         // Fallback to API if WebSocket is not connected
//         final result = await _apiService.sendMessage(
//           chatId: widget.chatId,
//           recipientId: widget.recipientId,
//           text: messageText,
//           productId: widget.productId,
//         );
        
//         if (result['success'] == true) {
//           setState(() {
//             final index = _messages.indexWhere((m) => m['id'] == tempId);
//             if (index != -1) {
//               _messages[index]['id'] = result['message']['id'];
//               _messages[index]['isSending'] = false;
//               _messages[index]['time'] = _formatTime(DateTime.now());
//             }
//           });
//         } else {
//           throw Exception(result['error']);
//         }
//       }
//     } catch (e) {
//       print('Error sending message: $e');
//       setState(() {
//         final index = _messages.indexWhere((m) => m['id'] == tempId);
//         if (index != -1) {
//           _messages[index]['isFailed'] = true;
//           _messages[index]['isSending'] = false;
//           _messages[index]['time'] = 'Failed';
//         }
//       });

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to send message: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   String _formatTime(DateTime time) {
//     final now = DateTime.now();
//     final difference = now.difference(time);

//     if (difference.inMinutes < 1) {
//       return 'Just now';
//     } else if (difference.inHours < 1) {
//       return '${difference.inMinutes}m ago';
//     } else if (difference.inDays < 1) {
//       return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
//     } else if (difference.inDays == 1) {
//       return 'Yesterday';
//     } else if (difference.inDays < 7) {
//       return '${time.day}/${time.month}';
//     } else {
//       return '${time.day}/${time.month}/${time.year}';
//     }
//   }

//   Color _getStatusColor() {
//     switch(widget.productStatus) {
//       case 'In Progress':
//         return const Color(0xFFFFC300);
//       case 'Claimed':
//         return const Color(0xFF29A366);
//       case 'Completed':
//         return const Color(0xFF668799);
//       default:
//         return const Color(0xFF29A366);
//     }
//   }

//   String _getStatusText() {
//     if (widget.quantity == 0) return 'Claimed';
//     if (widget.productStatus != null) return widget.productStatus!;
//     return 'Available';
//   }

//   @override
//   void dispose() {
//     _messageController.dispose();
//     _scrollController.dispose();
//     if (_channel != null) {
//       if (_isConnected) {
//         _channel!.sink.add(jsonEncode({
//           'type': 'unsubscribe',
//           'chatId': widget.chatId,
//         }));
//       }
//       _channel!.sink.close();
//     }
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final statusColor = _getStatusColor();
//     final statusText = _getStatusText();
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // Top Navigation Bar with Status
//             Container(
//               padding: EdgeInsets.only(
//                 top: MediaQuery.of(context).padding.top + 16,
//                 left: 16,
//                 right: 16,
//                 bottom: 12,
//               ),
//               decoration: BoxDecoration(
//                 color: isDarkMode 
//                     ? const Color(0xFF201712).withOpacity(0.8)
//                     : const Color(0xFFF6F5F3).withOpacity(0.8),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   IconButton(
//                     onPressed: () => Navigator.pop(context),
//                     icon: Icon(
//                       Icons.arrow_back_ios,
//                       color: isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F),
//                       size: 20,
//                     ),
//                   ),
//                   Column(
//                     children: [
//                       Text(
//                         widget.userName,
//                         style: TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F),
//                         ),
//                       ),
//                       const SizedBox(height: 2),
//                       Row(
//                         children: [
//                           Container(
//                             width: 8,
//                             height: 8,
//                             decoration: BoxDecoration(
//                               color: _isConnected ? Colors.green : Colors.red,
//                               shape: BoxShape.circle,
//                             ),
//                           ),
//                           const SizedBox(width: 4),
//                           Text(
//                             _isConnected ? 'Online' : 'Offline',
//                             style: TextStyle(
//                               fontSize: 10,
//                               fontWeight: FontWeight.bold,
//                               color: _isConnected ? Colors.green : Colors.red,
//                               letterSpacing: 1,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                   IconButton(
//                     onPressed: () {
//                       _showOptionsDialog(context);
//                     },
//                     icon: Icon(
//                       Icons.more_horiz,
//                       color: isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F),
//                       size: 24,
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Produce Banner with Status
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 16),
//               child: Container(
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFFBF9F8),
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(
//                     color: statusColor.withOpacity(0.1),
//                   ),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.05),
//                       blurRadius: 4,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: Row(
//                   children: [
//                     Container(
//                       width: 56,
//                       height: 56,
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(8),
//                         image: widget.userImage.isNotEmpty
//                             ? DecorationImage(
//                                 image: NetworkImage(widget.userImage),
//                                 fit: BoxFit.cover,
//                               )
//                             : null,
//                         color: statusColor.withOpacity(0.1),
//                       ),
//                       child: widget.userImage.isEmpty
//                           ? Icon(Icons.person, color: statusColor, size: 28)
//                           : null,
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             widget.itemName,
//                             style: TextStyle(
//                               fontSize: 14,
//                               fontWeight: FontWeight.bold,
//                               color: isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F),
//                             ),
//                           ),
//                           const SizedBox(height: 2),
//                           Row(
//                             children: [
//                               Container(
//                                 width: 6,
//                                 height: 6,
//                                 decoration: BoxDecoration(
//                                   color: statusColor,
//                                   shape: BoxShape.circle,
//                                 ),
//                               ),
//                               const SizedBox(width: 4),
//                               Text(
//                                 widget.quantity > 0 
//                                     ? '${widget.quantity} left for pickup'
//                                     : 'Ready for pickup',
//                                 style: TextStyle(
//                                   fontSize: 12,
//                                   fontWeight: FontWeight.w500,
//                                   color: statusColor,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                       decoration: BoxDecoration(
//                         color: statusColor,
//                         borderRadius: BorderRadius.circular(8),
//                         boxShadow: [
//                           BoxShadow(
//                             color: statusColor.withOpacity(0.2),
//                             blurRadius: 8,
//                             offset: const Offset(0, 2),
//                           ),
//                         ],
//                       ),
//                       child: Text(
//                         widget.quantity == 0 ? 'Claimed' : 'Claim',
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontSize: 12,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             // Connection Error Banner
//             if (_connectionError != null)
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 padding: const EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: Colors.red.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(8),
//                   border: Border.all(color: Colors.red.withOpacity(0.3)),
//                 ),
//                 child: Row(
//                   children: [
//                     const Icon(Icons.error_outline, color: Colors.red, size: 20),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         _connectionError!,
//                         style: const TextStyle(color: Colors.red, fontSize: 12),
//                       ),
//                     ),
//                     TextButton(
//                       onPressed: _connectWebSocket,
//                       child: const Text(
//                         'Reconnect',
//                         style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//             // Chat Messages
//             Expanded(
//               child: _isLoading
//                   ? const Center(child: CircularProgressIndicator(color: Color(0xFF29A366)))
//                   : _messages.isEmpty
//                       ? Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(
//                                 Icons.chat_bubble_outline,
//                                 size: 64,
//                                 color: statusColor.withOpacity(0.3),
//                               ),
//                               const SizedBox(height: 16),
//                               Text(
//                                 'No messages yet',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: isDarkMode ? Colors.white70 : const Color(0xFF5C8A7A),
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                               Text(
//                                 'Start a conversation with ${widget.userName}',
//                                 style: TextStyle(
//                                   fontSize: 14,
//                                   color: isDarkMode ? Colors.white38 : const Color(0xFF808080),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         )
//                       : ListView.builder(
//                           controller: _scrollController,
//                           padding: const EdgeInsets.all(16),
//                           itemCount: _messages.length,
//                           itemBuilder: (context, index) {
//                             final message = _messages[index];
//                             return _buildMessageBubble(message, isDarkMode, statusColor);
//                           },
//                         ),
//             ),

//             // Message Input
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: isDarkMode ? const Color(0xFF201712) : const Color(0xFFF6F5F3),
//                 border: Border(
//                   top: BorderSide(
//                     color: isDarkMode 
//                         ? Colors.white.withOpacity(0.1) 
//                         : Colors.black.withOpacity(0.1),
//                   ),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Container(
//                     width: 40,
//                     height: 40,
//                     decoration: BoxDecoration(
//                       color: statusColor.withOpacity(0.1),
//                       shape: BoxShape.circle,
//                     ),
//                     child: IconButton(
//                       onPressed: () {
//                         _showAttachmentOptions(context);
//                       },
//                       icon: Icon(
//                         Icons.add_photo_alternate,
//                         color: statusColor,
//                         size: 20,
//                       ),
//                       padding: EdgeInsets.zero,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: Container(
//                       decoration: BoxDecoration(
//                         color: isDarkMode ? const Color(0xFF333333) : const Color(0xFFFBF9F8),
//                         borderRadius: BorderRadius.circular(24),
//                         border: Border.all(
//                           color: statusColor.withOpacity(0.3),
//                         ),
//                       ),
//                       child: Row(
//                         children: [
//                           Expanded(
//                             child: Padding(
//                               padding: const EdgeInsets.only(left: 16),
//                               child: TextField(
//                                 controller: _messageController,
//                                 decoration: InputDecoration(
//                                   hintText: 'Type a message...',
//                                   hintStyle: TextStyle(
//                                     color: (isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F)).withOpacity(0.3),
//                                     fontSize: 14,
//                                   ),
//                                   border: InputBorder.none,
//                                 ),
//                                 style: TextStyle(
//                                   color: isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F),
//                                   fontSize: 14,
//                                 ),
//                                 onSubmitted: (_) => _sendMessage(),
//                               ),
//                             ),
//                           ),
//                           Container(
//                             width: 32,
//                             height: 32,
//                             margin: const EdgeInsets.only(right: 4),
//                             decoration: BoxDecoration(
//                               color: _messageController.text.isEmpty 
//                                   ? statusColor.withOpacity(0.5)
//                                   : statusColor,
//                               shape: BoxShape.circle,
//                               boxShadow: [
//                                 BoxShadow(
//                                   color: statusColor.withOpacity(0.3),
//                                   blurRadius: 4,
//                                   offset: const Offset(0, 2),
//                                 ),
//                               ],
//                             ),
//                             child: IconButton(
//                               onPressed: _messageController.text.isEmpty ? null : _sendMessage,
//                               icon: Icon(
//                                 Icons.send,
//                                 color: Colors.white,
//                                 size: 16,
//                               ),
//                               padding: EdgeInsets.zero,
//                               iconSize: 16,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMessageBubble(Map<String, dynamic> message, bool isDarkMode, Color statusColor) {
//     final isMe = message['isMe'] == true;
//     final isSending = message['isSending'] == true;
//     final isFailed = message['isFailed'] == true;
    
//     return Container(
//       margin: EdgeInsets.only(bottom: 16),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.end,
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           if (!isMe)
//             Padding(
//               padding: const EdgeInsets.only(right: 8),
//               child: CircleAvatar(
//                 radius: 16,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? Text(
//                         message['userName'][0].toUpperCase(),
//                         style: TextStyle(
//                           color: statusColor,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       )
//                     : null,
//               ),
//             ),
          
//           Flexible(
//             child: Column(
//               crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
//               children: [
//                 if (!isMe)
//                   Padding(
//                     padding: const EdgeInsets.only(left: 8, bottom: 4),
//                     child: Text(
//                       message['userName'] ?? 'User',
//                       style: TextStyle(
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                         letterSpacing: 0.5,
//                       ),
//                     ),
//                   ),
                
//                 Container(
//                   constraints: BoxConstraints(
//                     maxWidth: MediaQuery.of(context).size.width * 0.7,
//                   ),
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: isMe
//                         ? (isDarkMode ? const Color(0xFF333333) : const Color(0xFFC4D3BB))
//                         : statusColor,
//                     borderRadius: BorderRadius.only(
//                       topLeft: const Radius.circular(12),
//                       topRight: const Radius.circular(12),
//                       bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
//                       bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
//                     ),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.black.withOpacity(0.05),
//                         blurRadius: 2,
//                         offset: const Offset(0, 2),
//                       ),
//                     ],
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         message['text'],
//                         style: TextStyle(
//                           fontSize: 14,
//                           color: isMe
//                               ? (isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F))
//                               : const Color(0xFFFBF9F8),
//                           height: 1.4,
//                         ),
//                       ),
//                       if (isSending || isFailed)
//                         Padding(
//                           padding: const EdgeInsets.only(top: 4),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               if (isSending)
//                                 const SizedBox(
//                                   width: 12,
//                                   height: 12,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     color: Colors.white,
//                                   ),
//                                 ),
//                               if (isFailed)
//                                 const Icon(
//                                   Icons.error_outline,
//                                   color: Colors.red,
//                                   size: 12,
//                                 ),
//                               const SizedBox(width: 4),
//                               Text(
//                                 isSending ? 'Sending...' : 'Failed',
//                                 style: TextStyle(
//                                   fontSize: 8,
//                                   color: isMe
//                                       ? (isDarkMode ? Colors.white70 : Colors.black54)
//                                       : Colors.white70,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                     ],
//                   ),
//                 ),
                
//                 if (isMe && message['isRead'] == true && !isSending && !isFailed)
//                   Padding(
//                     padding: const EdgeInsets.only(right: 8, top: 4),
//                     child: Text(
//                       'Read ${message['time']}',
//                       style: TextStyle(
//                         fontSize: 10,
//                         color: (isDarkMode ? const Color(0xFFFBF9F8) : const Color(0xFF3D2B1F)).withOpacity(0.4),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
          
//           if (isMe)
//             Padding(
//               padding: const EdgeInsets.only(left: 8),
//               child: CircleAvatar(
//                 radius: 16,
//                 backgroundImage: message['userImage'] != null && message['userImage'].isNotEmpty
//                     ? NetworkImage(message['userImage'])
//                     : null,
//                 backgroundColor: statusColor.withOpacity(0.1),
//                 child: message['userImage'] == null || message['userImage'].isEmpty
//                     ? const Icon(Icons.person, size: 16, color: Color(0xFF29A366))
//                     : null,
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   void _showOptionsDialog(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Chat Options'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               leading: const Icon(Icons.block, color: Colors.red),
//               title: const Text('Block User'),
//               onTap: () {
//                 Navigator.pop(context);
//               },
//             ),
//             ListTile(
//               leading: const Icon(Icons.report, color: Colors.orange),
//               title: const Text('Report'),
//               onTap: () {
//                 Navigator.pop(context);
//               },
//             ),
//             ListTile(
//               leading: const Icon(Icons.delete, color: Colors.red),
//               title: const Text('Delete Chat'),
//               onTap: () {
//                 Navigator.pop(context);
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _showAttachmentOptions(BuildContext context) {
//     showModalBottomSheet(
//       context: context,
//       builder: (context) => Container(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               leading: const Icon(Icons.photo, color: Color(0xFF29A366)),
//               title: const Text('Send Photo'),
//               onTap: () {
//                 Navigator.pop(context);
//               },
//             ),
//             ListTile(
//               leading: const Icon(Icons.location_on, color: Color(0xFF29A366)),
//               title: const Text('Share Location'),
//               onTap: () {
//                 Navigator.pop(context);
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }






// import 'package:flutter/material.dart';

// class ChatScreen extends StatefulWidget {
//   final String itemName;
//   final String userName;
//   final String userImage;
//   final String? productId;
//   final String? productStatus;
//   final int quantity;
  
//   const ChatScreen({
//     Key? key,
//     required this.itemName,
//     required this.userName,
//     required this.userImage,
//     this.productId,
//     this.productStatus,
//     this.quantity = 0,
//   }) : super(key: key);

//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _messageController = TextEditingController();
//   final List<Map<String, dynamic>> _messages = [
//     {
//       'id': 1,
//       'text': 'Hi! I\'ve just harvested the tomatoes. They are in a wooden crate by the white fence. Help yourself!',
//       'isMe': false,
//       'time': '2:14 PM',
//       'userName': 'Elena (Gardener)',
//       'userImage': 'https://lh3.googleusercontent.com/aida-public/AB6AXuAdPHnwnHUI18gefKHIHNMB_aEGbFy_Cij0jU0ZG26mdH0KE2LoZW1Q6gVoh9Sh8hQeCBBjpv4re6y9y9Z5LJlLLe730zp6B8Wmdtuk9SgFF_ONFCZer10S5PMQZ-aEBaxHgca1607mCNMy94gegz8Ubc_ka_xbQn8GG92VASXwcNHhx35R86cz7hww3eOQ0dWD3RLONlA0MpuFGBAOzNS--BB-83CoHeEYKLT0X7sDsJyN5lOgkxaLyslSUzyxGRrlOqMkFj80UCzc',
//     },
//     {
//       'id': 2,
//       'text': 'Perfect timing! I\'m about 10 minutes away. Is there anything else you\'d like me to clear out? 🌿',
//       'isMe': true,
//       'time': '2:15 PM',
//       'isRead': true,
//     },
//     {
//       'id': 3,
//       'text': 'Actually, I have some fresh basil too. I tucked it inside the crate so it stays out of the sun.',
//       'isMe': false,
//       'time': '2:16 PM',
//       'userName': 'Elena (Gardener)',
//       'userImage': 'https://lh3.googleusercontent.com/aida-public/AB6AXuBMEJVj2IOFnpcYJhHj38lJfO9xDQPtr2fJhVH2D5trBaYygs9lwco3frg0gYpNr2ywUacyBM_gZjpDK27Lbok9_9m7yRrRvicvRdGNfIS7nEjoA3tpyeNw9b6X1vby2oTtk6TKpRdKfAhUb90i0Fpaq_9azVKtd__E-EmsB38SD6s8FhjuMWOjIp2xvFG_3wZA4yuj4-5GedVhz3URKClYuKhfV3x7uWqhgFKnm00A5_uPHH3zNfn8Rby2F-n5hUCIjJiI_MYDUTgq',
//     },
//   ];

//   Color _getStatusColor() {
//     switch(widget.productStatus) {
//       case 'In Progress':
//         return Color(0xFFFFC300);
//       case 'Claimed':
//         return Color(0xFF29A366);
//       case 'Completed':
//         return Color(0xFF668799);
//       default:
//         return Color(0xFF29A366);
//     }
//   }

//   String _getStatusText() {
//     if (widget.quantity == 0) return 'Claimed';
//     if (widget.productStatus != null) return widget.productStatus!;
//     return 'Available';
//   }

//   @override
//   void dispose() {
//     _messageController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final statusColor = _getStatusColor();
//     final statusText = _getStatusText();
    
//     return Scaffold(
//       backgroundColor: isDarkMode ? Color(0xFF201712) : Color(0xFFF6F5F3),
//       body: SafeArea(
//         child: Column(
//           children: [
//             // Top Navigation Bar with Status
//             Container(
//               padding: EdgeInsets.only(
//                 top: MediaQuery.of(context).padding.top + 16,
//                 left: 16,
//                 right: 16,
//                 bottom: 12,
//               ),
//               decoration: BoxDecoration(
//                 color: isDarkMode 
//                     ? Color(0xFF201712).withOpacity(0.8)
//                     : Color(0xFFF6F5F3).withOpacity(0.8),
//               ),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   IconButton(
//                     onPressed: () => Navigator.pop(context),
//                     icon: Icon(
//                       Icons.arrow_back_ios,
//                       color: isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F),
//                       size: 20,
//                     ),
//                   ),
//                   Column(
//                     children: [
//                       Text(
//                         'Gardener Chat',
//                         style: TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F),
//                         ),
//                       ),
//                       SizedBox(height: 2),
//                       Row(
//                         children: [
//                           Container(
//                             width: 8,
//                             height: 8,
//                             decoration: BoxDecoration(
//                               color: statusColor,
//                               shape: BoxShape.circle,
//                             ),
//                           ),
//                           SizedBox(width: 4),
//                           Text(
//                             statusText,
//                             style: TextStyle(
//                               fontSize: 10,
//                               fontWeight: FontWeight.bold,
//                               color: statusColor,
//                               letterSpacing: 2,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                   IconButton(
//                     onPressed: () {
//                       // TODO: More options
//                     },
//                     icon: Icon(
//                       Icons.more_horiz,
//                       color: isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F),
//                       size: 24,
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             // Produce Banner with Status
//             Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16),
//               child: Container(
//                 padding: EdgeInsets.all(12),
//                 decoration: BoxDecoration(
//                   color: isDarkMode ? Color(0xFF333333) : Color(0xFFFBF9F8),
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(
//                     color: statusColor.withOpacity(0.1),
//                   ),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.05),
//                       blurRadius: 4,
//                       offset: Offset(0, 2),
//                     ),
//                   ],
//                 ),
//                 child: Row(
//                   children: [
//                     Container(
//                       width: 56,
//                       height: 56,
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(8),
//                         image: DecorationImage(
//                           image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuBv4kobyLKCZCjnbR5WXOpOJ04bxBrznnV9fRzOCOnHK_2m72HzRB9uCgnzamD_1CZCFZJP7QmHc-rP_VNipSsmdI7VBlL1jNcqsWkV0JtS8o8qwxwMGf-vDxKZ_zS_Q355QrWHfZ-ylNaGEhjAktGPlblKMA6aE7KjGU7cHvsYHhWmgBDBEmZQL6dRWsdKeSIB2c1HqnkQyGBjhd_xa35mICN6qAsG6-zFNqimLnWjNA_y1jXrYit7y8PWN10rkfv7llmSo-y_UZ8u'),
//                           fit: BoxFit.cover,
//                         ),
//                         border: Border.all(
//                           color: statusColor.withOpacity(0.05),
//                         ),
//                       ),
//                     ),
//                     SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             widget.itemName,
//                             style: TextStyle(
//                               fontSize: 14,
//                               fontWeight: FontWeight.bold,
//                               color: isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F),
//                             ),
//                           ),
//                           SizedBox(height: 2),
//                           Row(
//                             children: [
//                               Container(
//                                 width: 6,
//                                 height: 6,
//                                 decoration: BoxDecoration(
//                                   color: statusColor,
//                                   shape: BoxShape.circle,
//                                 ),
//                               ),
//                               SizedBox(width: 4),
//                               Text(
//                                 widget.quantity > 0 
//                                     ? '${widget.quantity} left for pickup'
//                                     : 'Ready for pickup',
//                                 style: TextStyle(
//                                   fontSize: 12,
//                                   fontWeight: FontWeight.w500,
//                                   color: statusColor,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//                     Container(
//                       padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//                       decoration: BoxDecoration(
//                         color: statusColor,
//                         borderRadius: BorderRadius.circular(8),
//                         boxShadow: [
//                           BoxShadow(
//                             color: statusColor.withOpacity(0.2),
//                             blurRadius: 8,
//                             offset: Offset(0, 2),
//                           ),
//                         ],
//                       ),
//                       child: Text(
//                         widget.quantity == 0 ? 'Claimed' : 'Claim',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 12,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             // Chat Messages
//             Expanded(
//               child: ListView(
//                 padding: EdgeInsets.all(16),
//                 children: [
//                   // Today Divider
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Divider(
//                           color: statusColor.withOpacity(0.1),
//                           thickness: 1,
//                         ),
//                       ),
//                       Padding(
//                         padding: EdgeInsets.symmetric(horizontal: 12),
//                         child: Text(
//                           'TODAY',
//                           style: TextStyle(
//                             fontSize: 10,
//                             fontWeight: FontWeight.bold,
//                             color: (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F)).withOpacity(0.4),
//                             letterSpacing: 2,
//                           ),
//                         ),
//                       ),
//                       Expanded(
//                         child: Divider(
//                           color: statusColor.withOpacity(0.1),
//                           thickness: 1,
//                         ),
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: 16),
                  
//                   // Messages
//                   ..._messages.map((message) {
//                     return _buildMessageBubble(message, isDarkMode);
//                   }).toList(),
//                 ],
//               ),
//             ),

//             // Message Input
//             Container(
//               padding: EdgeInsets.all(16),
//               child: Column(
//                 children: [
//                   Row(
//                     children: [
//                       // Photo Button
//                       Container(
//                         width: 40,
//                         height: 40,
//                         decoration: BoxDecoration(
//                           color: statusColor.withOpacity(0.1),
//                           shape: BoxShape.circle,
//                         ),
//                         child: IconButton(
//                           onPressed: () {
//                             // TODO: Add photo
//                           },
//                           icon: Icon(
//                             Icons.add_a_photo,
//                             color: statusColor,
//                             size: 20,
//                           ),
//                           padding: EdgeInsets.zero,
//                         ),
//                       ),
//                       SizedBox(width: 12),
                      
//                       // Location Button
//                       Container(
//                         width: 40,
//                         height: 40,
//                         decoration: BoxDecoration(
//                           color: Color(0xFFC4D3BB).withOpacity(0.3),
//                           shape: BoxShape.circle,
//                         ),
//                         child: IconButton(
//                           onPressed: () {
//                             // TODO: Share location
//                           },
//                           icon: Icon(
//                             Icons.location_on,
//                             color: (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F)).withOpacity(0.7),
//                             size: 20,
//                           ),
//                           padding: EdgeInsets.zero,
//                         ),
//                       ),
//                       SizedBox(width: 12),
                      
//                       // Message Input
//                       Expanded(
//                         child: Container(
//                           decoration: BoxDecoration(
//                             color: isDarkMode ? Color(0xFF333333) : Color(0xFFFBF9F8),
//                             borderRadius: BorderRadius.circular(24),
//                           ),
//                           child: Row(
//                             children: [
//                               Expanded(
//                                 child: Padding(
//                                   padding: EdgeInsets.only(left: 16),
//                                   child: TextField(
//                                     controller: _messageController,
//                                     decoration: InputDecoration(
//                                       hintText: 'Type a message...',
//                                       hintStyle: TextStyle(
//                                         color: (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F)).withOpacity(0.3),
//                                         fontSize: 14,
//                                       ),
//                                       border: InputBorder.none,
//                                     ),
//                                     style: TextStyle(
//                                       color: isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F),
//                                       fontSize: 14,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                               Container(
//                                 width: 32,
//                                 height: 32,
//                                 margin: EdgeInsets.only(right: 4),
//                                 decoration: BoxDecoration(
//                                   color: statusColor,
//                                   shape: BoxShape.circle,
//                                   boxShadow: [
//                                     BoxShadow(
//                                       color: statusColor.withOpacity(0.3),
//                                       blurRadius: 4,
//                                       offset: Offset(0, 2),
//                                     ),
//                                   ],
//                                 ),
//                                 child: IconButton(
//                                   onPressed: () {
//                                     if (_messageController.text.isNotEmpty) {
//                                       // TODO: Send message
//                                       _messageController.clear();
//                                     }
//                                   },
//                                   icon: Icon(
//                                     Icons.arrow_upward,
//                                     color: Colors.white,
//                                     size: 16,
//                                   ),
//                                   padding: EdgeInsets.zero,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: 12),
                  
//                   // Home Indicator
//                   Container(
//                     width: 32,
//                     height: 3,
//                     decoration: BoxDecoration(
//                       color: (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F)).withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(2),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMessageBubble(Map<String, dynamic> message, bool isDarkMode) {
//     final isMe = message['isMe'] == true;
//     final statusColor = _getStatusColor();
    
//     return Container(
//       margin: EdgeInsets.only(bottom: 16),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.end,
//         mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           if (!isMe)
//             Padding(
//               padding: EdgeInsets.only(right: 8),
//               child: CircleAvatar(
//                 radius: 16,
//                 backgroundImage: NetworkImage(message['userImage']),
//                 backgroundColor: Colors.transparent,
//               ),
//             ),
          
//           Flexible(
//             child: Column(
//               crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
//               children: [
//                 if (!isMe)
//                   Padding(
//                     padding: EdgeInsets.only(left: 8, bottom: 4),
//                     child: Text(
//                       message['userName'],
//                       style: TextStyle(
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                         letterSpacing: 0.5,
//                       ),
//                     ),
//                   ),
                
//                 Container(
//                   constraints: BoxConstraints(
//                     maxWidth: MediaQuery.of(context).size.width * 0.75,
//                   ),
//                   padding: EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: isMe
//                         ? Color(0xFFC4D3BB).withOpacity(isDarkMode ? 0.2 : 1)
//                         : statusColor,
//                     borderRadius: BorderRadius.only(
//                       topLeft: Radius.circular(12),
//                       topRight: Radius.circular(12),
//                       bottomLeft: isMe ? Radius.circular(12) : Radius.circular(0),
//                       bottomRight: isMe ? Radius.circular(0) : Radius.circular(12),
//                     ),
//                     boxShadow: [
//                       BoxShadow(
//                         color: Colors.black.withOpacity(0.05),
//                         blurRadius: 2,
//                         offset: Offset(0, 2),
//                       ),
//                     ],
//                   ),
//                   child: Text(
//                     message['text'],
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: isMe
//                           ? (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F))
//                           : Color(0xFFFBF9F8),
//                       height: 1.4,
//                     ),
//                   ),
//                 ),
                
//                 if (isMe && message['isRead'] == true)
//                   Padding(
//                     padding: EdgeInsets.only(right: 8, top: 4),
//                     child: Text(
//                       'Read ${message['time']}',
//                       style: TextStyle(
//                         fontSize: 10,
//                         color: (isDarkMode ? Color(0xFFFBF9F8) : Color(0xFF3D2B1F)).withOpacity(0.4),
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//           ),
          
//           if (isMe)
//             Padding(
//               padding: EdgeInsets.only(left: 8),
//               child: CircleAvatar(
//                 radius: 16,
//                 backgroundImage: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuBCbsLE69S5DmBN2cgdz6jDYi-NkzS3r1Ia17D_iXPwBwqb1sK6-_CxRiKd1jqEs8SFsTvfAdGNrIfjtsQU0pxzIdVAGS59fckxmwpa02PrYa6a2AItNUm3N1qSziKh_9EkfLvKFkB9HbuFzBhCwrI-xWkZxiaKFaaFtEAodff81dY6UOuUrcUXzKv8mr5HVDiFWIlBNQVFdwcAKrIiDnBg8H257_-0ltgJGGeKlv0s4TD_ZrTDjoouDiRF_RSeHzOXpx9mEs_ColbQ'),
//                 backgroundColor: Colors.transparent,
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }
