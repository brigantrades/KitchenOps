import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
import 'package:plateplan/core/services/recipe_image_storage.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

final shareImportNotifierProvider =
    NotifierProvider<ShareImportNotifier, ShareImportState>(
  ShareImportNotifier.new,
);

/// UI + navigation state for Instagram / share import.
@immutable
class ShareImportState {
  const ShareImportState({
    this.isLoading = false,
    this.recipeToNavigate,
    this.navigationSourcePayload,
    this.errorMessage,
    this.canRetry = false,
    this.lastCombinedPayload,
    this.lastImagePath,
    this.snackMessage,
    this.pendingCombined,
    this.pendingImagePath,
  });

  final bool isLoading;
  final Recipe? recipeToNavigate;
  /// Original shared text/URL for "Re-parse" on the preview screen.
  final String? navigationSourcePayload;
  final String? errorMessage;
  final bool canRetry;
  final String? lastCombinedPayload;
  final String? lastImagePath;
  final String? snackMessage;
  final String? pendingCombined;
  final String? pendingImagePath;

  static const idle = ShareImportState();

  ShareImportState copyWith({
    bool? isLoading,
    Recipe? recipeToNavigate,
    bool clearRecipeToNavigate = false,
    String? navigationSourcePayload,
    bool clearNavigationSourcePayload = false,
    String? errorMessage,
    bool clearError = false,
    bool? canRetry,
    String? lastCombinedPayload,
    String? lastImagePath,
    String? snackMessage,
    bool clearSnack = false,
    String? pendingCombined,
    String? pendingImagePath,
    bool clearPending = false,
  }) {
    return ShareImportState(
      isLoading: isLoading ?? this.isLoading,
      recipeToNavigate:
          clearRecipeToNavigate ? null : (recipeToNavigate ?? this.recipeToNavigate),
      navigationSourcePayload: clearNavigationSourcePayload
          ? null
          : (navigationSourcePayload ?? this.navigationSourcePayload),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      canRetry: canRetry ?? this.canRetry,
      lastCombinedPayload: lastCombinedPayload ?? this.lastCombinedPayload,
      lastImagePath: lastImagePath ?? this.lastImagePath,
      snackMessage: clearSnack ? null : (snackMessage ?? this.snackMessage),
      pendingCombined:
          clearPending ? null : (pendingCombined ?? this.pendingCombined),
      pendingImagePath:
          clearPending ? null : (pendingImagePath ?? this.pendingImagePath),
    );
  }
}

class ShareImportNotifier extends Notifier<ShareImportState> {
  StreamSubscription<List<SharedMediaFile>>? _mediaSub;
  StreamSubscription<Uri>? _linkSub;
  bool _initialized = false;
  final AppLinks _appLinks = AppLinks();

  @override
  ShareImportState build() {
    ref.onDispose(() {
      unawaited(_mediaSub?.cancel());
      unawaited(_linkSub?.cancel());
    });
    return ShareImportState.idle;
  }

  /// Call once after app start (e.g. post-frame). Android-only behavior.
  void ensureInitialized() {
    if (_initialized) return;
    if (kIsWeb) return;
    try {
      if (!Platform.isAndroid) return;
    } catch (_) {
      return;
    }
    _initialized = true;
    unawaited(_bootstrap());
  }

  void clearRecipeNavigation() {
    if (state.recipeToNavigate != null) {
      state = state.copyWith(
        clearRecipeToNavigate: true,
        clearNavigationSourcePayload: true,
      );
    }
  }

  void clearSnack() {
    if (state.snackMessage != null) {
      state = state.copyWith(clearSnack: true);
    }
  }

  /// After login, process deferred share payload.
  void flushPendingAfterLogin() {
    final pending = state.pendingCombined;
    if (pending == null || pending.trim().isEmpty) return;
    final img = state.pendingImagePath;
    state = state.copyWith(clearPending: true);
    unawaited(_runImport(pending, img));
  }

  Future<void> retryLastImport() async {
    final payload = state.lastCombinedPayload;
    if (payload == null || payload.trim().isEmpty) return;
    await _runImport(payload, state.lastImagePath);
  }

  /// Manual test: paste an Instagram post URL (and optional caption). Skips
  /// share-sheet heuristics and uses the same Gemini + preview flow as
  /// [ReceiveSharingIntent]. No image upload (URL-only).
  Future<void> manualImportFromPastedContent({
    required String url,
    String? caption,
  }) async {
    final u = url.trim();
    if (u.isEmpty) {
      state = state.copyWith(
        snackMessage: 'Paste a post URL first.',
      );
      return;
    }
    final cap = caption?.trim();
    final combined =
        cap == null || cap.isEmpty ? u : '$u\n\n$cap';

    if (!Env.hasGemini) {
      state = state.copyWith(
        errorMessage: 'Gemini is not configured.',
        canRetry: false,
        lastCombinedPayload: combined,
      );
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = state.copyWith(
        pendingCombined: combined,
        snackMessage: 'Sign in to finish importing this recipe.',
      );
      return;
    }

    await _runImport(combined, null);
  }

  Future<void> _bootstrap() async {
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      await _handleMediaBatch(initial);
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {}

    _mediaSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleMediaBatch,
      onError: (_) {},
    );

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleAppLink(initialUri);
      }
    } catch (_) {}

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleAppLink,
      onError: (_) {},
    );
  }

  Future<void> _handleAppLink(Uri? uri) async {
    if (uri == null) return;
    final h = uri.host.toLowerCase();
    final instagram = h == 'instagram.com' ||
        h == 'www.instagram.com' ||
        h.endsWith('.instagram.com');
    if (!instagram) return;
    final combined = uri.toString();
    await _considerImport(combined, null);
  }

  Future<void> _handleMediaBatch(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final combined = _combineSharedFiles(files);
    final imagePath = _firstImagePath(files);
    await _considerImport(combined, imagePath);
  }

  String _combineSharedFiles(List<SharedMediaFile> files) {
    final parts = <String>[];
    for (final f in files) {
      final p = f.path.trim();
      if (p.isNotEmpty) parts.add(p);
      final msg = f.message?.trim();
      if (msg != null && msg.isNotEmpty) parts.add(msg);
    }
    return parts.join('\n\n');
  }

  String? _firstImagePath(List<SharedMediaFile> files) {
    for (final f in files) {
      if (f.type == SharedMediaType.image) return f.path;
      final mime = f.mimeType;
      if (mime != null && mime.startsWith('image/')) return f.path;
    }
    return null;
  }

  bool _shouldAttemptImport(String combined) {
    final lower = combined.toLowerCase();
    if (lower.contains('instagram.com')) return true;
    for (final k in ['ingredients', 'recipe', 'instructions']) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  /// Android can surface the OAuth return URL (e.g. [leckerly://login-callback/])
  /// through [ReceiveSharingIntent] when coming back from the browser. That is
  /// not recipe content — ignore silently so we do not show "No recipe content detected."
  bool _looksLikeAuthOrAppRouting(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    if (lower.startsWith('leckerly://')) return true;
    if (lower.contains('login-callback')) return true;
    if (lower.contains('supabase.co') && lower.contains('/auth/')) return true;
    if (lower.contains('access_token=') || lower.contains('refresh_token=')) {
      return true;
    }
    return false;
  }

  Future<void> _considerImport(String combined, String? imagePath) async {
    final trimmed = combined.trim();
    if (_looksLikeAuthOrAppRouting(trimmed)) {
      return;
    }
    if (trimmed.isEmpty && (imagePath == null || imagePath.isEmpty)) {
      state = state.copyWith(
        snackMessage: 'No shared content to import.',
      );
      return;
    }
    if (!_shouldAttemptImport(trimmed)) {
      state = state.copyWith(
        snackMessage: 'No recipe content detected.',
      );
      return;
    }
    if (!Env.hasGemini) {
      state = state.copyWith(
        errorMessage: 'Gemini is not configured.',
        canRetry: false,
        lastCombinedPayload: trimmed,
        lastImagePath: imagePath,
      );
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = state.copyWith(
        pendingCombined: trimmed,
        pendingImagePath: imagePath,
        snackMessage: 'Sign in to finish importing this recipe.',
      );
      return;
    }

    await _runImport(trimmed, imagePath);
  }

  Future<void> _runImport(String combined, String? imagePath) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      canRetry: false,
      lastCombinedPayload: combined,
      lastImagePath: imagePath,
      clearSnack: true,
    );

    try {
      final gemini = ref.read(geminiServiceProvider);
      final map = await gemini.extractRecipeFromInstagramContent(combined);
      if (map == null || map.isEmpty) {
        final failure = gemini.lastGenerateFailure ?? '';
        if (failure.toLowerCase().contains('quota exceeded')) {
          throw Exception(
            'Gemini quota exceeded for this key/project. Enable billing or use a key with available quota, then retry.',
          );
        }
        if (failure.toLowerCase().contains('not found for api version')) {
          throw Exception(
            'Gemini model mismatch for this API key/project. Update to a supported model or key configuration.',
          );
        }
        final lower = combined.trim().toLowerCase();
        final looksLikeUrlOnly = (lower.startsWith('http') ||
                lower.startsWith('www.') ||
                lower.contains('instagram.com')) &&
            !(lower.contains('ingredients') ||
                lower.contains('instructions') ||
                lower.contains('recipe'));
        if (looksLikeUrlOnly) {
          throw Exception(
            'Could not extract a recipe from the URL alone. Paste the caption (ingredients/instructions) too, then retry.',
          );
        }
        throw Exception(
          'Gemini did not return valid recipe JSON. Tap Retry, or add more text from the post.',
        );
      }

      final sourceUrl = _extractFirstInstagramUrl(combined);
      var recipe = recipeFromInstagramGeminiMap(
        map,
        sourceUrl: sourceUrl,
        sharedContent: combined,
      );

      if (imagePath != null && imagePath.isNotEmpty) {
        final file = File(imagePath);
        if (await file.exists()) {
          final user = ref.read(currentUserProvider);
          if (user != null) {
            final mime = _mimeFromPath(imagePath);
            final url = await uploadRecipeImageFromFile(
              userId: user.id,
              file: file,
              contentType: mime,
            );
            if (url != null && url.isNotEmpty) {
              recipe = recipe.copyWith(imageUrl: url);
            }
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        recipeToNavigate: recipe,
        navigationSourcePayload: combined,
        clearError: true,
        canRetry: false,
      );
    } catch (e, st) {
      debugPrint('Share import failed: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
        canRetry: true,
        lastCombinedPayload: combined,
        lastImagePath: imagePath,
      );
    }
  }

  String? _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String? _extractFirstInstagramUrl(String raw) {
    final matches = RegExp(r'https?://[^\s)>\]]+', caseSensitive: false)
        .allMatches(raw);
    for (final m in matches) {
      final candidate = m.group(0);
      if (candidate == null) continue;
      final parsed = Uri.tryParse(candidate.trim());
      if (parsed == null || parsed.host.isEmpty) continue;
      final host = parsed.host.toLowerCase();
      final isInstagram = host == 'instagram.com' ||
          host == 'www.instagram.com' ||
          host.endsWith('.instagram.com');
      if (isInstagram) return parsed.toString();
    }
    return null;
  }
}
