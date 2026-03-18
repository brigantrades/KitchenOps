import 'dart:convert';

import 'package:http/http.dart' as http;

class HttpClient {
  const HttpClient();

  Future<Map<String, dynamic>> getJson(Uri uri, {Map<String, String>? headers}) async {
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
