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

  Future<Map<String, dynamic>> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    final response = await http.post(
      uri,
      headers: merged,
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
