import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/debug/share_import_debug_log.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
import 'package:plateplan/core/recipes/recipe_import_reparse_kind.dart';
import 'package:plateplan/core/recipes/recipe_web_import_fetcher.dart';
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
    this.navigationReparseKind,
    this.errorMessage,
    this.canRetry = false,
    this.lastCombinedPayload,
    this.lastImagePath,
    this.lastImportReparseKind = RecipeImportReparseKind.instagramCaption,
    this.snackMessage,
    this.pendingCombined,
    this.pendingImagePath,
  });

  final bool isLoading;
  final Recipe? recipeToNavigate;
  /// Original shared text/URL for "Re-parse" on the preview screen.
  final String? navigationSourcePayload;
  /// How [ImportRecipePreviewScreen] should re-parse [navigationSourcePayload].
  final RecipeImportReparseKind? navigationReparseKind;
  final String? errorMessage;
  final bool canRetry;
  final String? lastCombinedPayload;
  final String? lastImagePath;
  /// Last import path (for Retry after failure).
  final RecipeImportReparseKind lastImportReparseKind;
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
    RecipeImportReparseKind? navigationReparseKind,
    bool clearNavigationReparseKind = false,
    String? errorMessage,
    bool clearError = false,
    bool? canRetry,
    String? lastCombinedPayload,
    String? lastImagePath,
    RecipeImportReparseKind? lastImportReparseKind,
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
      navigationReparseKind: clearNavigationReparseKind
          ? null
          : (navigationReparseKind ?? this.navigationReparseKind),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      canRetry: canRetry ?? this.canRetry,
      lastCombinedPayload: lastCombinedPayload ?? this.lastCombinedPayload,
      lastImagePath: lastImagePath ?? this.lastImagePath,
      lastImportReparseKind: lastImportReparseKind ?? this.lastImportReparseKind,
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
        clearNavigationReparseKind: true,
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
    final img = state.pendingImagePath;
    final text = pending?.trim() ?? '';
    final hasText = text.isNotEmpty;
    final hasImg = img != null && img.trim().isNotEmpty;
    if (!hasText && !hasImg) return;
    state = state.copyWith(clearPending: true);
    unawaited(_runImport(text, img));
  }

  Future<void> retryLastImport() async {
    if (state.lastImportReparseKind == RecipeImportReparseKind.webPage) {
      final raw = state.lastCombinedPayload;
      final decoded =
          raw != null ? decodeWebRecipeImportPayload(raw) : null;
      if (decoded != null) {
        await _retryWebImportGeminiOnly(decoded);
        return;
      }
    }
    final payload = state.lastCombinedPayload;
    final img = state.lastImagePath;
    final text = payload?.trim() ?? '';
    final hasText = text.isNotEmpty;
    final hasImg = img != null && img.trim().isNotEmpty;
    if (!hasText && !hasImg) return;
    await _runImport(text, img);
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

  /// Fetches a recipe page, extracts plain text, runs Gemini, then navigates to
  /// import preview (same global loading dialog as Instagram paste test).
  Future<void> importFromWebsiteUrl({
    required String urlRaw,
    String? notes,
  }) async {
    final parsed = parseRecipePageUrl(urlRaw);
    if (!parsed.isOk) {
      state = state.copyWith(
        snackMessage: parsed.errorMessage ?? 'Invalid URL.',
      );
      return;
    }
    if (!Env.hasGemini) {
      state = state.copyWith(
        errorMessage: 'Gemini is not configured.',
        canRetry: false,
      );
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = state.copyWith(
        snackMessage: 'Sign in to finish importing this recipe.',
      );
      return;
    }

    final n = notes?.trim();
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      canRetry: false,
      lastImportReparseKind: RecipeImportReparseKind.webPage,
      clearSnack: true,
    );

    String? encodedPayload;
    try {
      final fetch = await fetchRecipePagePlainText(parsed.uri!);
      if (!fetch.isOk) {
        throw Exception(fetch.errorMessage ?? 'Could not load the page.');
      }
      encodedPayload = encodeWebRecipeImportPayload(
        canonicalUrl: fetch.canonicalUrl!,
        pageText: fetch.plainText!,
        notes: n,
      );
      state = state.copyWith(lastCombinedPayload: encodedPayload);

      final gemini = ref.read(geminiServiceProvider);
      var map = await gemini.extractRecipeFromWebPageText(
        canonicalUrl: fetch.canonicalUrl!,
        pagePlainText: fetch.plainText!,
        userNotes: n,
      );
      if (map != null && map.isNotEmpty) {
        map = supplementWebImportJsonWithEmbeddedSauceFromPlainText(
          map,
          fetch.plainText!,
        );
      }
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
        throw Exception(
          'Could not extract a recipe from this page. Try another page or add the recipe manually.',
        );
      }
      var recipe = recipeFromInstagramGeminiMap(
        map,
        imageUrl: fetch.heroImageUrl,
        sourceUrl: fetch.canonicalUrl,
        sharedContent: null,
        source: 'web_import',
      );

      state = state.copyWith(
        isLoading: false,
        recipeToNavigate: recipe,
        navigationSourcePayload: encodedPayload,
        navigationReparseKind: RecipeImportReparseKind.webPage,
        clearError: true,
        canRetry: false,
      );
    } catch (e, st) {
      debugPrint('Web recipe import failed: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
        canRetry: encodedPayload != null,
        lastCombinedPayload: encodedPayload ?? state.lastCombinedPayload,
        lastImportReparseKind: RecipeImportReparseKind.webPage,
      );
    }
  }

  Future<void> _retryWebImportGeminiOnly(WebRecipeImportPayload decoded) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      canRetry: false,
      clearSnack: true,
    );
    try {
      final gemini = ref.read(geminiServiceProvider);
      var map = await gemini.extractRecipeFromWebPageText(
        canonicalUrl: decoded.canonicalUrl,
        pagePlainText: decoded.pageText,
        userNotes: decoded.notes,
      );
      if (map != null && map.isNotEmpty) {
        map = supplementWebImportJsonWithEmbeddedSauceFromPlainText(
          map,
          decoded.pageText,
        );
      }
      if (map == null || map.isEmpty) {
        final failure = gemini.lastGenerateFailure ?? '';
        if (failure.toLowerCase().contains('quota exceeded')) {
          throw Exception(
            'Gemini quota exceeded for this key/project. Enable billing or use a key with available quota, then retry.',
          );
        }
        throw Exception(
          'Could not extract a recipe from this page. Try again or add the recipe manually.',
        );
      }
      final payload = encodeWebRecipeImportPayload(
        canonicalUrl: decoded.canonicalUrl,
        pageText: decoded.pageText,
        notes: decoded.notes,
      );
      String? heroImageUrl;
      try {
        final refetch = await fetchRecipePagePlainText(
          Uri.parse(decoded.canonicalUrl),
        );
        if (refetch.isOk) heroImageUrl = refetch.heroImageUrl;
      } catch (_) {}
      final recipe = recipeFromInstagramGeminiMap(
        map,
        imageUrl: heroImageUrl,
        sourceUrl: decoded.canonicalUrl,
        sharedContent: null,
        source: 'web_import',
      );
      state = state.copyWith(
        isLoading: false,
        recipeToNavigate: recipe,
        navigationSourcePayload: payload,
        navigationReparseKind: RecipeImportReparseKind.webPage,
        lastCombinedPayload: payload,
        clearError: true,
        canRetry: false,
      );
    } catch (e, st) {
      debugPrint('Web recipe import retry failed: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
        canRetry: true,
        lastImportReparseKind: RecipeImportReparseKind.webPage,
      );
    }
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
    debugPrint(
      'Share import: received ${files.length} item(s): '
      '${files.map((f) => '{type:${f.type.value}, mime:${f.mimeType}, pathLen:${f.path.length}, hasMsg:${(f.message ?? '').trim().isNotEmpty}}').join(', ')}',
    );
    // Prefer the share-sheet message (text/URL/caption) over file paths.
    // Paths are not useful input for Gemini and can confuse heuristics.
    final combined = _combineSharedPayload(files);
    final imagePath = _firstImagePath(files);
    await _considerImport(combined, imagePath);
  }

  String _combineSharedPayload(List<SharedMediaFile> files) {
    final parts = <String>[];
    for (final f in files) {
      // Android: text shares arrive in `path` with type=text (message is iOS-only).
      // iOS: caption/message may arrive in `message`.
      final msg = f.message?.trim();
      if (msg != null && msg.isNotEmpty) parts.add(msg);

      if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
        final p = f.path.trim();
        if (p.isNotEmpty) parts.add(p);
      } else if ((f.mimeType ?? '').startsWith('text/')) {
        final p = f.path.trim();
        if (p.isNotEmpty) parts.add(p);
      }
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

  bool _shouldAttemptImport(String combined, String? imagePath) {
    // Instagram often shares an image without a helpful caption payload. If we
    // have an image path, attempt an import (Gemini vision fallback handles it).
    // This prevents false "No recipe content detected." for image-only shares.
    if (imagePath != null && imagePath.trim().isNotEmpty) return true;
    final lower = combined.toLowerCase();
    if (lower.contains('instagram.com')) return true;
    if (lower.contains('ig.me')) return true;
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
    debugPrint(
      'Share import: considerImport textLen=${trimmed.length} imagePath=${imagePath == null ? '<null>' : (imagePath.isEmpty ? '<empty>' : '<set>')}',
    );
    if (_looksLikeAuthOrAppRouting(trimmed)) {
      return;
    }
    if (trimmed.isEmpty && (imagePath == null || imagePath.isEmpty)) {
      state = state.copyWith(
        snackMessage: 'No shared content to import.',
      );
      return;
    }
    if (!_shouldAttemptImport(trimmed, imagePath)) {
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
        pendingCombined: trimmed.isEmpty ? null : trimmed,
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
      lastImportReparseKind: RecipeImportReparseKind.instagramCaption,
      clearSnack: true,
    );

    try {
      // When the payload is URL-only (no caption text from the share intent),
      // fetch the Instagram page and extract the caption from OG meta tags.
      var textForGemini = combined;
      final stripped = captionForInstagramGemini(combined).trim();
      final isUrlOnly =
          stripped.isEmpty || stripped == combined.trim();
      if (isUrlOnly) {
        final url = _extractFirstInstagramUrl(combined);
        if (url != null) {
          debugPrint('Share import: URL-only payload detected, fetching $url');
          final fetched = await _fetchInstagramCaption(url);
          if (fetched != null && fetched.trim().isNotEmpty) {
            textForGemini = '$url\n\n$fetched';
            debugPrint(
              'Share import: enriched payload with fetched caption '
              '(${fetched.length} chars)',
            );
          }
        }
      }

      // #region agent log
      final low = textForGemini.toLowerCase();
      final captionPreview = captionForInstagramGemini(textForGemini);
      agentDebugLogShareImport(
        hypothesisId: 'H1',
        location: 'share_handler_service._runImport',
        message: 'payload_before_gemini',
        data: {
          'combinedLen': textForGemini.length,
          'captionLen': captionPreview.length,
          'captionEmptyAfterStrip': captionPreview.trim().isEmpty,
          'urlOnlyDetected': isUrlOnly,
          'captionHasFishKw': [
            'fish',
            'cod',
            'tilapia',
            'haddock',
            'salmon',
            'fillet',
          ].any((k) => low.contains(k)),
          'captionHasChickenKw': low.contains('chicken'),
        },
      );
      // #endregion
      final gemini = ref.read(geminiServiceProvider);
      Map<String, dynamic>? map;
      if (textForGemini.trim().isNotEmpty) {
        map = await gemini.extractRecipeFromInstagramContent(textForGemini);
      }

      // If Instagram share payload contains no usable caption text, fall back to
      // Gemini vision using the shared image (when available).
      if ((map == null || map.isEmpty) &&
          imagePath != null &&
          imagePath.trim().isNotEmpty) {
        try {
          final file = File(imagePath);
          if (await file.exists()) {
            final mime = _mimeFromPath(imagePath);
            final bytes = await file.readAsBytes();
            map = await gemini.extractRecipeFromInstagramShareImage(
              imageBytes: bytes,
              mimeType: mime ?? 'image/jpeg',
              sharedTextHint: textForGemini,
            );
          }
        } catch (_) {
          // If vision fallback fails, continue into the existing error path.
        }
      }
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
        final captionCheck = captionForInstagramGemini(textForGemini);
        // #region agent log
        final lineCount = textForGemini
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .length;
        agentDebugLogShareImport(
          hypothesisId: 'H5',
          location: 'share_handler_service._runImport',
          message: 'gemini_map_null_branch',
          data: {
            'captionEmptyAfterStrip': captionCheck.trim().isEmpty,
            'captionLen': captionCheck.length,
            'combinedLen': textForGemini.length,
            'nonEmptyLineCount': lineCount,
          },
        );
        // #endregion
        throw Exception(
          'Could not import this recipe. Instagram often does not include the full caption in share '
          'payloads. Open the post, use Copy caption (or copy the recipe text), then paste it into '
          "the app's import screen. Otherwise tap Retry.",
        );
      }

      final sourceUrl = _extractFirstInstagramUrl(combined);
      var recipe = recipeFromInstagramGeminiMap(
        map,
        sourceUrl: sourceUrl,
        sharedContent: textForGemini,
      );
      // #region agent log
      final nameLowers =
          recipe.ingredients.map((e) => e.name.toLowerCase()).toList();
      agentDebugLogShareImport(
        hypothesisId: 'H3',
        location: 'share_handler_service._runImport',
        message: 'recipe_after_gemini_map',
        data: {
          'finalIngCount': recipe.ingredients.length,
          'finalHasFish': nameLowers.any(
            (n) =>
                n.contains('fish') ||
                n.contains('cod') ||
                n.contains('tilapia') ||
                n.contains('haddock') ||
                n.contains('salmon'),
          ),
          'finalHasChicken': nameLowers.any((n) => n.contains('chicken')),
        },
      );
      // #endregion

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
        navigationSourcePayload: textForGemini,
        clearNavigationReparseKind: true,
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
        lastImportReparseKind: RecipeImportReparseKind.instagramCaption,
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

  /// Fetches the Instagram post caption via the public oEmbed API.
  /// Returns null on any failure (network, private post, 404).
  Future<String?> _fetchInstagramCaption(String url) async {
    try {
      final oembedUri = Uri.parse(
        'https://www.instagram.com/api/v1/oembed/?url=${Uri.encodeComponent(url)}',
      );
      final response = await http.get(
        oembedUri,
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint(
          'Share import: oEmbed returned ${response.statusCode}',
        );
        return null;
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      final title = json['title']?.toString().trim();
      debugPrint(
        'Share import: oEmbed caption ${title == null ? 'missing' : '${title.length} chars'}',
      );
      return (title != null && title.isNotEmpty) ? title : null;
    } catch (e) {
      debugPrint('Share import: oEmbed fetch failed: $e');
      return null;
    }
  }
}
