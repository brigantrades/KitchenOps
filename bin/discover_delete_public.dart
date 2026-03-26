import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');
  final dryRun = !args.contains('--execute');

  if (supabaseUrl == null || serviceRole == null) {
    stderr.writeln(
      'Missing required env vars: SUPABASE_URL and/or SUPABASE_SERVICE_ROLE_KEY',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  try {
    final jwtRole = _jwtRole(serviceRole) ?? 'unknown';
    stdout.writeln('auth jwt role: $jwtRole');
    if (jwtRole != 'service_role') {
      stderr.writeln(
        'WARNING: SUPABASE_SERVICE_ROLE_KEY does not appear to be a service role key. '
        'Deletes may be blocked by RLS.',
      );
    }

    final publicPreview = await _listPublicRows(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
    );
    final beforePublic = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'public',
    );
    final beforePersonal = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'personal',
    );
    final beforeHousehold = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'household',
    );

    stdout.writeln('=== Before Delete ===');
    stdout.writeln('public: $beforePublic');
    stdout.writeln('personal: $beforePersonal');
    stdout.writeln('household: $beforeHousehold');
    stdout.writeln('');
    stdout.writeln('=== Public Rows Preview (to be deleted) ===');
    if (publicPreview.isEmpty) {
      stdout.writeln('(none)');
    } else {
      for (final row in publicPreview) {
        stdout.writeln(
          '- id=${row['id']} | title=${row['title']} | source=${row['source']} | meal_type=${row['meal_type']}',
        );
      }
    }

    if (dryRun) {
      stdout.writeln('');
      stdout.writeln(
        'Dry run only. Re-run with --execute to delete visibility=public rows.',
      );
      return;
    }

    final deletedCount = await _deletePublic(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
    );

    final afterPublic = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'public',
    );
    final afterPersonal = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'personal',
    );
    final afterHousehold = await _count(
      client: client,
      supabaseUrl: supabaseUrl,
      serviceRole: serviceRole,
      visibility: 'household',
    );

    stdout.writeln('');
    stdout.writeln('=== After Delete ===');
    stdout.writeln('deleted public rows: $deletedCount');
    stdout.writeln('public: $afterPublic');
    stdout.writeln('personal: $afterPersonal');
    stdout.writeln('household: $afterHousehold');
  } finally {
    client.close();
  }
}

Future<List<Map<String, dynamic>>> _listPublicRows({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
}) async {
  final uri = Uri.parse(
    '$supabaseUrl/rest/v1/recipes?select=id,title,source,meal_type,visibility&visibility=eq.public&order=created_at.desc&limit=5000',
  );
  final response = await client.get(
    uri,
    headers: _headers(serviceRole),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
        'Preview query failed (${response.statusCode}): ${response.body}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Future<int> _count({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
  required String visibility,
}) async {
  final uri = Uri.parse(
    '$supabaseUrl/rest/v1/recipes?select=id&visibility=eq.$visibility',
  );
  final response = await client.get(
    uri,
    headers: <String, String>{
      ..._headers(serviceRole),
      'Prefer': 'count=exact',
      'Range': '0-0',
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Count failed (${response.statusCode}): ${response.body}');
  }
  final contentRange = response.headers['content-range'];
  if (contentRange == null) return 0;
  final slash = contentRange.lastIndexOf('/');
  if (slash < 0) return 0;
  return int.tryParse(contentRange.substring(slash + 1)) ?? 0;
}

Future<int> _deletePublic({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
}) async {
  final uri =
      Uri.parse('$supabaseUrl/rest/v1/recipes?visibility=eq.public&select=id');
  final response = await client.delete(
    uri,
    headers: <String, String>{
      ..._headers(serviceRole),
      'Prefer': 'return=representation',
    },
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Delete failed (${response.statusCode}): ${response.body}');
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) return 0;
  return decoded.length;
}

String? _jwtRole(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    final payload = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded);
    if (map is! Map<String, dynamic>) return null;
    return map['role']?.toString();
  } catch (_) {
    return null;
  }
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
