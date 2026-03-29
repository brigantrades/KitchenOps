// Repair recipe ingredients where the full line was stored in `name` with
// amount 0 and empty unit (e.g. discover imports using raw recipeIngredient strings).
//
// Run from repo root:
//   export SUPABASE_URL=...
//   export SUPABASE_SERVICE_ROLE_KEY=...
//   dart run bin/fix_recipe_ingredients_from_inline_quantity.dart
//
// Dry run (default): prints summary and writes tmp/fix_recipe_ingredients_preview.csv
// Add --execute to PATCH recipes. Optional: --limit=N (recipes), --recipe-id=uuid

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:plateplan/core/recipes/ingredient_line_parser.dart';

Future<void> main(List<String> args) async {
  final execute = args.contains('--execute');
  final limit = _parseIntArg(args, '--limit');
  final singleId = _parseStringArg(args, '--recipe-id');

  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final serviceRole = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      serviceRole == null ||
      serviceRole.isEmpty) {
    stderr.writeln(
      'Missing env: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (service role).',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  var recipesFetched = 0;
  var recipesChanged = 0;
  var linesFixed = 0;
  final previewRows = <String>[];

  try {
    if (singleId != null) {
      final row = await _fetchRecipe(client, supabaseUrl, serviceRole, singleId);
      if (row == null) {
        stderr.writeln('Recipe not found: $singleId');
        exitCode = 1;
        return;
      }
      recipesFetched = 1;
      final r = await _processRecipe(
        row,
        execute: execute,
        client: client,
        supabaseUrl: supabaseUrl,
        serviceRole: serviceRole,
        previewRows: previewRows,
      );
      if (r.changed) recipesChanged = 1;
      linesFixed += r.linesFixed;
    } else {
      var offset = 0;
      const page = 200;
      while (true) {
        if (limit != null && recipesFetched >= limit) break;
        final take = limit == null
            ? page
            : (limit - recipesFetched).clamp(1, page);
        final batch = await _fetchRecipePage(
          client,
          supabaseUrl,
          serviceRole,
          offset: offset,
          limit: take,
        );
        if (batch.isEmpty) break;
        for (final row in batch) {
          if (limit != null && recipesFetched >= limit) break;
          recipesFetched++;
          final r = await _processRecipe(
            row,
            execute: execute,
            client: client,
            supabaseUrl: supabaseUrl,
            serviceRole: serviceRole,
            previewRows: previewRows,
          );
          if (r.changed) recipesChanged++;
          linesFixed += r.linesFixed;
        }
        if (batch.length < take) break;
        offset += take;
      }
    }

    stdout.writeln(
      'Recipes scanned: $recipesFetched | recipes with fixes: $recipesChanged | '
      'ingredient lines fixed: $linesFixed | execute=$execute',
    );

    const csvPath = 'tmp/fix_recipe_ingredients_preview.csv';
    await _writePreviewCsv(csvPath, previewRows);
    stdout.writeln('Preview CSV: $csvPath (${previewRows.length} rows)');
  } finally {
    client.close();
  }
}

Future<({bool changed, int linesFixed})> _processRecipe(
  Map<String, dynamic> row, {
  required bool execute,
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
  required List<String> previewRows,
}) async {
  final id = row['id']?.toString() ?? '';
  final title = row['title']?.toString() ?? '';
  final rawList = row['ingredients'];
  if (rawList is! List) {
    return (changed: false, linesFixed: 0);
  }

  var anyChange = false;
  var fixed = 0;
  final next = <dynamic>[];

  for (final e in rawList) {
    if (e is! Map) {
      next.add(e);
      continue;
    }
    final map = Map<String, dynamic>.from(e);
    final repaired = tryRepairCollapsedIngredient(map);
    if (repaired != null) {
      anyChange = true;
      fixed++;
      final oldName = map['name']?.toString() ?? '';
      previewRows.add(
        '${_csv(id)},${_csv(title)},${_csv(oldName)},'
        '${_csv(repaired['name']?.toString() ?? '')},'
        '${repaired['amount']},${_csv(repaired['unit']?.toString() ?? '')}',
      );
      next.add(repaired);
    } else {
      next.add(map);
    }
  }

  if (anyChange && execute) {
    final ok = await _patchRecipeIngredients(
      client,
      supabaseUrl,
      serviceRole,
      id,
      next,
    );
    if (!ok) {
      stderr.writeln('PATCH failed for recipe $id');
    }
  }

  return (changed: anyChange, linesFixed: fixed);
}

/// When amount is 0, unit empty, and [name] parses as quantity + unit + name.
Map<String, dynamic>? tryRepairCollapsedIngredient(Map<String, dynamic> raw) {
  final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
  final unit = raw['unit']?.toString().trim() ?? '';
  final name = raw['name']?.toString().trim() ?? '';
  if (amount != 0) return null;
  if (unit.isNotEmpty) return null;
  if (name.isEmpty) return null;

  final parsed = tryParseMeasuredIngredientLine(name);
  if (parsed == null) return null;

  final out = Map<String, dynamic>.from(raw);
  out['name'] = parsed.name;
  out['amount'] = parsed.amount;
  out['unit'] = parsed.unit;
  out.remove('qualitative');
  if (out['category'] == null || (out['category']?.toString().isEmpty ?? true)) {
    out['category'] = 'other';
  }
  return out;
}

Future<List<Map<String, dynamic>>> _fetchRecipePage(
  http.Client client,
  String supabaseUrl,
  String serviceRole, {
  required int offset,
  required int limit,
}) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/recipes').replace(
    queryParameters: <String, String>{
      'select': 'id,title,ingredients',
      'offset': '$offset',
      'limit': '$limit',
      'order': 'id.asc',
    },
  );
  final response = await client.get(
    uri,
    headers: _headers(serviceRole),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    stderr.writeln(
      'List recipes failed (${response.statusCode}): ${response.body}',
    );
    return const [];
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List) return const [];
  return decoded
      .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
      .toList();
}

Future<Map<String, dynamic>?> _fetchRecipe(
  http.Client client,
  String supabaseUrl,
  String serviceRole,
  String id,
) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/recipes').replace(
    queryParameters: <String, String>{
      'select': 'id,title,ingredients',
      'id': 'eq.$id',
    },
  );
  final response = await client.get(uri, headers: _headers(serviceRole));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    stderr.writeln(
      'Fetch recipe failed (${response.statusCode}): ${response.body}',
    );
    return null;
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! List || decoded.isEmpty) return null;
  return Map<String, dynamic>.from(
    decoded.first as Map<dynamic, dynamic>,
  );
}

Future<bool> _patchRecipeIngredients(
  http.Client client,
  String supabaseUrl,
  String serviceRole,
  String id,
  List<dynamic> ingredients,
) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/recipes').replace(
    queryParameters: <String, String>{'id': 'eq.$id'},
  );
  final response = await client.patch(
    uri,
    headers: {
      ..._headers(serviceRole),
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    },
    body: jsonEncode(<String, dynamic>{'ingredients': ingredients}),
  );
  if (response.statusCode >= 200 && response.statusCode < 300) return true;
  stderr.writeln(
    'PATCH ${response.statusCode} for $id: ${response.body}',
  );
  return false;
}

Map<String, String> _headers(String serviceRole) => <String, String>{
      'apikey': serviceRole,
      'Authorization': 'Bearer $serviceRole',
    };

Future<void> _writePreviewCsv(String path, List<String> rows) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final b = StringBuffer()
    ..writeln('recipe_id,title,old_name,new_name,new_amount,new_unit');
  for (final line in rows) {
    b.writeln(line);
  }
  await file.writeAsString(b.toString());
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

int? _parseIntArg(List<String> args, String prefix) {
  for (final a in args) {
    if (a.startsWith('$prefix=')) {
      return int.tryParse(a.substring(prefix.length + 1));
    }
  }
  return null;
}

String? _parseStringArg(List<String> args, String prefix) {
  for (final a in args) {
    if (a.startsWith('$prefix=')) {
      final v = a.substring(prefix.length + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}
