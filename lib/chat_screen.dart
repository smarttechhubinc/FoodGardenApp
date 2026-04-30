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
  
  // Request tracking - SPECIFIC to this chat/product
  Map<String, dynamic>? _currentRequest;
  bool _isProcessingRequest = false;
  bool _isLoadingRequest = true;
  
  static const String webSocketUrl = 'wss://foodsharingbackend.onrender.com';

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _loadMessages();
    _loadRequestData(); // Load request for THIS SPECIFIC product
  }

  Future<void> _loadRequestData() async {
    setState(() {
      _isLoadingRequest = true;
      _currentRequest = null; // Reset request when loading new chat
    });
    
    try {
      print('🔍 Loading request data for product: ${widget.productId}');
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
      
      // If no productId, no request to show
      if (widget.productId == null) {
        print('❌ No productId, skipping request load');
        setState(() {
          _isLoadingRequest = false;
        });
        return;
      }
      
      // Check API for existing request on THIS SPECIFIC product
      print('🔍 Checking API for request on product: ${widget.productId}');
      final result = await _apiService.getUserProductRequest(widget.productId!);
      print('📥 API Response: $result');
      
      if (result['success'] == true && result['request'] != null) {
        print('✅ Found request for this product: ${result['request']['status']}');
        setState(() {
          _currentRequest = result['request'];
        });
      } else {
        print('❌ No request found for this product');
        setState(() {
          _currentRequest = null;
        });
      }
    } catch (e) {
      print('❌ Error loading request: $e');
      setState(() {
        _currentRequest = null;
      });
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
          content: Text('✅ Request accepted!'),
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
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.userId;
    
    if (_currentRequest!['owner_id'] != currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the product owner can accept requests'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isProcessingRequest = true;
    });
    
    try {
      final result = await _apiService.acceptProductRequest(_currentRequest!['id']);
      
      if (result['success'] == true) {
        setState(() {
          _currentRequest!['status'] = 'accepted';
        });
        
        await _sendSystemMessage(
          '✅ Your request has been accepted! The produce has been reserved for you. Please arrange pickup.'
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
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.userId;
    
    if (_currentRequest!['owner_id'] != currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the product owner can decline requests'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isProcessingRequest = true;
    });
    
    try {
      final result = await _apiService.declineProductRequest(_currentRequest!['id']);
      
      if (result['success'] == true) {
        setState(() {
          _currentRequest!['status'] = 'declined';
        });
        
        await _sendSystemMessage(
          '❌ Your request has been declined. The produce is still available for others.'
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
    
    // Determine roles from the request data - but ONLY for THIS request
    bool isOwner = false;
    bool isRequester = false;
    bool isRequestForThisChat = false;
    
    if (_currentRequest != null && widget.productId != null) {
      // Check if this request belongs to this product
      isRequestForThisChat = _currentRequest!['product_id'] == widget.productId;
      
      if (isRequestForThisChat) {
        isOwner = _currentRequest!['owner_id'] == currentUserId;
        isRequester = _currentRequest!['requester_id'] == currentUserId;
      }
    }
    
    // Debug print
    print('🎨 Building ChatScreen...');
    print('📦 productId: ${widget.productId}');
    print('📦 _currentRequest product_id: ${_currentRequest?['product_id']}');
    print('📦 isRequestForThisChat: $isRequestForThisChat');
    print('👤 currentUserId: $currentUserId');
    print('👤 isOwner: $isOwner');
    print('👤 isRequester: $isRequester');
    print('📦 _currentRequest status: ${_currentRequest?['status']}');
    
    // Show request card ONLY if the request belongs to THIS product
    final bool showRequestCard = !_isLoadingRequest && 
        isRequestForThisChat &&
        _currentRequest != null && 
        _currentRequest!['status'] == 'pending' &&
        isOwner;
    
    final bool showRequesterStatus = !_isLoadingRequest && 
        isRequestForThisChat &&
        _currentRequest != null && 
        _currentRequest!['status'] != 'pending' &&
        isRequester;
    
    final bool showPendingRequesterStatus = !_isLoadingRequest && 
        isRequestForThisChat &&
        _currentRequest != null && 
        _currentRequest!['status'] == 'pending' &&
        isRequester;
    
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

            // Request Pending Card (for Requester - while waiting)
            if (showPendingRequesterStatus)
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.hourglass_empty,
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
                              'Request Pending... ⏳',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.orange,
                              ),
                            ),
                            Text(
                              'Your request for ${_currentRequest!['quantity']} ${widget.itemName} has been sent. Waiting for the gardener to respond.',
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

            // Request Accepted Card (for Requester)
            if (showRequesterStatus && _currentRequest!['status'] == 'accepted')
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Request Accepted! 🎉',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Your request for ${_currentRequest!['quantity']} ${widget.itemName} has been accepted. Message the gardener to arrange pickup.',
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

            // Request Declined Card (for Requester)
            if (showRequesterStatus && _currentRequest!['status'] == 'declined')
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.cancel,
                          color: Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Request Declined ❌',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red,
                              ),
                            ),
                            Text(
                              'Your request for ${_currentRequest!['quantity']} ${widget.itemName} was declined.',
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
