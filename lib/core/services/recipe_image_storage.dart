import 'dart:io';
import 'dart:math';

import 'package:plateplan/core/config/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kRecipeImagesBucket = 'recipe-images';

/// Uploads a local image file to Supabase Storage and returns a public URL, or null on failure.
Future<String?> uploadRecipeImageFromFile({
  required String userId,
  required File file,
  String? contentType,
}) async {
  if (!Env.hasSupabase) return null;
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final ext = _guessExtension(file.path, contentType);
    final objectPath =
        '$userId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 30)}$ext';
    final mime = contentType ?? _mimeFromExtension(ext);
    await Supabase.instance.client.storage.from(kRecipeImagesBucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            upsert: true,
          ),
        );
    return Supabase.instance.client.storage
        .from(kRecipeImagesBucket)
        .getPublicUrl(objectPath);
  } catch (_) {
    return null;
  }
}

String _guessExtension(String path, String? contentType) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return '.png';
  if (lower.endsWith('.webp')) return '.webp';
  if (lower.endsWith('.gif')) return '.gif';
  if (lower.endsWith('.heic')) return '.heic';
  if (contentType != null) {
    if (contentType.contains('png')) return '.png';
    if (contentType.contains('webp')) return '.webp';
    if (contentType.contains('gif')) return '.gif';
  }
  return '.jpg';
}

String _mimeFromExtension(String ext) {
  return switch (ext) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    '.heic' => 'image/heic',
    _ => 'image/jpeg',
  };
}
