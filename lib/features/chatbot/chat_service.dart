import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  final List<Map<String, String>> messages = [];

  // ✅ OpenAI API endpoint
  static const apiUri = 'https://api.openai.com/v1/chat/completions';


  static const chatBotApiKey = 'chatBotApiKey';

  Future<String> chatGPTAPI(String prompt) async {
    // Add user message
    messages.add({
      "role": "user",
      "content":
      "You are a helpful assistant called FoodBot. You should only talk about topics related to food storage, shelf life, expiry dates, preservation methods, and food freshness tips. "
          "If a user asks something unrelated to food storage or expiry, politely remind them that you can only assist with food storage and expiry-related questions. "
          "$prompt",
    });

    try {
      final response = await http.post(
        Uri.parse(apiUri),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $chatBotApiKey',
        },
        body: jsonEncode({
          "model": "gpt-4o-mini", // ✅ Use gpt-4o-mini or gpt-4o for best results
          "messages": messages,
          "temperature": 0.7,
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'].trim();

        messages.add({'role': 'assistant', 'content': content});
        return content;
      } else {
        return 'Error ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'Exception: $e';
    }
  }
}