import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');

  if (supabaseUrl == null || serviceRole == null) {
    stderr.writeln(
      'Missing required env vars: SUPABASE_URL and/or SUPABASE_SERVICE_ROLE_KEY',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  try {
    final publicRows = await _fetchRows(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      query:
          'select=id,visibility,source,meal_type,is_favorite,is_to_try,user_id&visibility=eq.public&order=created_at.desc',
    );
    final personalRows = await _fetchRows(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      query: 'select=id,visibility&visibility=eq.personal',
    );
    final householdRows = await _fetchRows(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      query: 'select=id,visibility&visibility=eq.household',
    );

    final publicBySource = <String, int>{};
    final publicByMeal = <String, int>{};
    for (final row in publicRows) {
      final source = (row['source']?.toString() ?? 'unknown').trim();
      final meal = (row['meal_type']?.toString() ?? 'unknown').trim();
      publicBySource[source] = (publicBySource[source] ?? 0) + 1;
      publicByMeal[meal] = (publicByMeal[meal] ?? 0) + 1;
    }

    stdout.writeln('=== Discover Audit ===');
    stdout.writeln('public rows: ${publicRows.length}');
    stdout.writeln('personal rows: ${personalRows.length}');
    stdout.writeln('household rows: ${householdRows.length}');
    stdout.writeln('');

    stdout.writeln('public by source:');
    for (final e in publicBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      stdout.writeln('  ${e.key}: ${e.value}');
    }

    stdout.writeln('');
    stdout.writeln('public by meal_type:');
    for (final e in publicByMeal.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      stdout.writeln('  ${e.key}: ${e.value}');
    }
  } finally {
    client.close();
  }
}

Future<List<Map<String, dynamic>>> _fetchRows({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
  required String query,
}) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/recipes?$query');
  final response = await client.get(
    uri,
    headers: _headers(serviceRole),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
        'Audit query failed (${response.statusCode}): ${response.body}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Map<String, String> _headers(String serviceRole) => <String, String>{
      'apikey': serviceRole,
      'Authorization': 'Bearer $serviceRole',
      'Content-Type': 'application/json',
    };

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
