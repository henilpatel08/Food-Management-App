import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CloudVisionService {
  CloudVisionService({required this.apiKey});
  final String apiKey;

  Future<String?> ocrBytes(Uint8List imgBytes) async {
    if (apiKey.isEmpty) return null;
    final uri = Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey');
    final body = {
      "requests": [
        {
          "image": {"content": base64Encode(imgBytes)},
          "features": [{"type": "DOCUMENT_TEXT_DETECTION"}]
        }
      ]
    };
    final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (res.statusCode != 200) return null;
    final data = (jsonDecode(res.body) as Map<String, dynamic>);
    final txt = data['responses']?[0]?['fullTextAnnotation']?['text']?.toString() ?? '';
    return txt.trim().isEmpty ? null : txt.trim();
  }
}
