import 'dart:convert';

import 'package:http/http.dart' as http;

/// Talking to the Diary Keeper, the small server that writes down every night.
class DiaryKeeper {
  DiaryKeeper(this.baseUrl);

  final String baseUrl;

  /// Checkpoint 00: wave, and get a wave back. Returns the server's message, or throws.
  Future<String> wave() async {
    final response = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 5));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return '${body['message']} (${body['time']})';
  }
}
