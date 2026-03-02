import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<types.Message> _messages = [];
  late types.User _user;
  final _bot = const types.User(
    id: '82091008-a484-4a89-ae75-a22bf8d6f3bd',
    firstName: 'Peely',
  );

  bool isDataLoading = false;
  final ChatService chatService = ChatService();

  String? _userPhotoBase64;
  String? _userName;
  bool _isLoadingUserData = true;

  @override
  void initState() {
    super.initState();
    _initializeUser().then((_) async {
      await _loadSavedMessages();
    });
  }

  Future<void> _initializeUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        final uid = currentUser.uid;

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data();
          _userPhotoBase64 = userData?['profile']?['info']?['photoUrl'];
          _userName = userData?['profile']?['info']?['name'] ?? 'User';
        }

        _user = types.User(id: uid, firstName: _userName);
      } else {
        _user = const types.User(
          id: '82091008-a484-4a89-ae75-a22bf8d6f3ac',
          firstName: 'User',
        );
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _user = const types.User(
        id: '82091008-a484-4a89-ae75-a22bf8d6f3ac',
        firstName: 'User',
      );
    } finally {
      setState(() => _isLoadingUserData = false);
    }
  }

  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = _messages.map((m) => m.toJson()).toList();
      final encoded = jsonEncode(messagesJson);
      await prefs.setString('chat_messages', encoded);
      debugPrint('💾 Saved ${_messages.length} messages');
    } catch (e) {
      debugPrint('⚠️ Error saving messages: $e');
    }
  }

  Future<void> _loadSavedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('chat_messages');

      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored) as List<dynamic>;
        final loadedMessages = decoded
            .map((e) => types.Message.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _messages = loadedMessages;
        });

        debugPrint('✅ Loaded ${_messages.length} messages');
      } else {
        debugPrint('ℹ️ No saved messages found');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading messages: $e');
    }
  }

  void _addMessage(types.Message message) {
    setState(() => _messages.insert(0, message));
    _saveMessages();
  }

  void _handleAttachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: Colors.green[700]),
                ),
                title: const Text(
                  'Photo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Choose from gallery',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleImageSelection();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.insert_drive_file, color: Colors.blue[700]),
                ),
                title: const Text(
                  'File',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Choose a document',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleFileSelection();
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null && result.files.single.path != null) {
      final message = types.FileMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        mimeType: lookupMimeType(result.files.single.path!),
        name: result.files.single.name,
        size: result.files.single.size,
        uri: result.files.single.path!,
      );

      _addMessage(message);
    }
  }

  void _handleImageSelection() async {
    final result = await ImagePicker().pickImage(
      imageQuality: 70,
      maxWidth: 1440,
      source: ImageSource.gallery,
    );

    if (result != null) {
      final bytes = await result.readAsBytes();
      final image = await decodeImageFromList(bytes);

      final message = types.ImageMessage(
        author: _user,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        height: image.height.toDouble(),
        id: const Uuid().v4(),
        name: result.name,
        size: bytes.length,
        uri: result.path,
        width: image.width.toDouble(),
      );

      _addMessage(message);
    }
  }

  void _handleMessageTap(BuildContext _, types.Message message) async {
    if (message is types.FileMessage) {
      var localPath = message.uri;

      if (message.uri.startsWith('http')) {
        try {
          final index = _messages.indexWhere((m) => m.id == message.id);
          final updatedMessage = (_messages[index] as types.FileMessage)
              .copyWith(isLoading: true);

          setState(() => _messages[index] = updatedMessage);

          final client = http.Client();
          final request = await client.get(Uri.parse(message.uri));
          final bytes = request.bodyBytes;
          final documentsDir = (await getApplicationDocumentsDirectory()).path;
          localPath = '$documentsDir/${message.name}';

          if (!File(localPath).existsSync()) {
            await File(localPath).writeAsBytes(bytes);
          }
        } finally {
          final index = _messages.indexWhere((m) => m.id == message.id);
          final updatedMessage = (_messages[index] as types.FileMessage)
              .copyWith(isLoading: null);

          setState(() => _messages[index] = updatedMessage);
        }
      }

      await OpenFilex.open(localPath);
    }
  }

  void _handlePreviewDataFetched(
    types.TextMessage message,
    types.PreviewData previewData,
  ) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    final updatedMessage = (_messages[index] as types.TextMessage).copyWith(
      previewData: previewData,
    );
    setState(() => _messages[index] = updatedMessage);
    _saveMessages();
  }

  Future<void> _handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: message.text,
    );

    _addMessage(textMessage);
    setState(() => isDataLoading = true);

    try {
      final aiResponse = await chatService.chatGPTAPI(message.text);

      final botMessage = types.TextMessage(
        author: _bot,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        text: aiResponse,
      );

      _addMessage(botMessage);
    } catch (e) {
      final errorMessage = types.TextMessage(
        author: _bot,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: const Uuid().v4(),
        text: 'Sorry, I encountered an error. Please try again.',
      );
      _addMessage(errorMessage);
    } finally {
      setState(() => isDataLoading = false);
    }
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear Chat History?'),
        content: const Text(
          'This will delete all messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_messages');
      setState(() => _messages.clear());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat cleared'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.green),
              SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.green[700],
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const CircleAvatar(
                radius: 18,
                backgroundImage: AssetImage('lib/assets/Peely.png'),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peely',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Your Food AI Assistant',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            tooltip: 'Clear chat',
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Chat(
        isAttachmentUploading: isDataLoading,
        theme: DefaultChatTheme(
          backgroundColor: const Color(0xFFF5F5F5),
          primaryColor: Colors.green[700]!,
          secondaryColor: Colors.white,
          receivedMessageBodyTextStyle: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            height: 1.5,
          ),
          sentMessageBodyTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            height: 1.5,
          ),
          inputBackgroundColor: Colors.white,
          inputTextColor: Colors.black87,
          inputBorderRadius: BorderRadius.circular(20),
          messageBorderRadius: 16,
          inputMargin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          inputPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
        ),
        l10n: ChatL10nEn(
          emptyChatPlaceholder: _messages.isEmpty
              ? '👋 Hi ${_userName ?? 'there'}!\n\nI\'m Peely, your food storage expert.\n\nAsk me about:\n• Food storage tips\n• Expiry dates\n• Recipe suggestions\n• Preservation methods'
              : '',
          inputPlaceholder: 'Ask Peely about food...',
        ),
        messages: _messages,
        onMessageTap: _handleMessageTap,
        onPreviewDataFetched: _handlePreviewDataFetched,
        onSendPressed: _handleSendPressed,
        showUserAvatars: true,
        showUserNames: true,
        user: _user,
        avatarBuilder: (types.User user) {
          if (user.id == _bot.id) {
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green[200]!, width: 2),
              ),
              child: const CircleAvatar(
                radius: 16,
                backgroundImage: AssetImage('lib/assets/Peely.png'),
              ),
            );
          }

          if (_userPhotoBase64 != null &&
              _userPhotoBase64!.isNotEmpty &&
              _userPhotoBase64 != 'null') {
            try {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green[200]!, width: 2),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: MemoryImage(base64Decode(_userPhotoBase64!)),
                ),
              );
            } catch (e) {
              debugPrint('Error decoding user avatar: $e');
            }
          }

          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green[200]!, width: 2),
            ),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green[600],
              child: Text(
                user.firstName?.substring(0, 1).toUpperCase() ?? 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
