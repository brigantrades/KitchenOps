import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
import 'package:plateplan/core/services/recipe_image_storage.dart';
import 'package:plateplan/core/theme/app_brand.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/recipes/presentation/import_recipe_preview_screen.dart';

/// Picks a cookbook page photo, runs Gemini vision extraction, then opens
/// [ImportRecipePreviewScreen].
class ScanRecipeBookScreen extends ConsumerStatefulWidget {
  const ScanRecipeBookScreen({super.key});

  @override
  ConsumerState<ScanRecipeBookScreen> createState() =>
      _ScanRecipeBookScreenState();
}

class _ScanRecipeBookScreenState extends ConsumerState<ScanRecipeBookScreen> {
  final _picker = ImagePicker();
  bool _busy = false;
  File? _previewFile;
  String? _errorMessage;

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _pickAndProcess(ImageSource source) async {
    final xFile = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (xFile == null) return;

    if (!kIsWeb) {
      CroppedFile? cropped;
      try {
        cropped = await ImageCropper().cropImage(
          sourcePath: xFile.path,
          maxWidth: 2048,
          maxHeight: 2048,
          compressQuality: 85,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop to one recipe',
              toolbarColor: AppBrand.deepTeal,
              toolbarWidgetColor: AppBrand.offWhite,
              lockAspectRatio: false,
            ),
            IOSUiSettings(
              title: 'Crop to one recipe',
              aspectRatioLockEnabled: false,
            ),
          ],
        );
      } catch (e, st) {
        debugPrint('ScanRecipeBookScreen: crop failed: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open crop. Rebuild the app after updating, or try another photo.',
              ),
            ),
          );
        }
        return;
      }
      if (cropped == null) return;
      await _runExtraction(XFile(cropped.path));
      return;
    }

    await _runExtraction(xFile);
  }

  Future<void> _runExtraction(XFile xFile) async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _previewFile = File(xFile.path);
    });

    try {
      if (!Env.hasGemini) {
        if (mounted) {
          setState(() {
            _errorMessage = 'AI import is not configured for this build.';
          });
        }
        return;
      }

      final bytes = await xFile.readAsBytes();
      final mime = xFile.mimeType ?? _mimeFromPath(xFile.path);
      final gemini = ref.read(geminiServiceProvider);
      final map = await gemini.extractRecipeFromBookPhoto(
        imageBytes: bytes,
        mimeType: mime,
      );

      if (map == null) {
        final hint = gemini.lastGenerateFailure?.trim();
        if (mounted) {
          setState(() {
            _errorMessage = hint != null && hint.isNotEmpty
                ? 'Could not read the recipe. $hint'
                : 'Could not read the recipe. Try a clearer photo or better lighting.';
          });
        }
        return;
      }

      final user = ref.read(currentUserProvider);
      String? imageUrl;
      if (user != null) {
        imageUrl = await uploadRecipeImageFromFile(
          userId: user.id,
          file: File(xFile.path),
          contentType: mime,
        );
      }

      final recipe = recipeFromInstagramGeminiMap(
        map,
        source: 'book_scan',
        imageUrl: imageUrl,
      );

      if (!mounted) return;
      context.pushReplacement(
        '/import-recipe-preview',
        extra: ImportRecipePreviewArgs(recipe: recipe),
      );
    } catch (e, st) {
      debugPrint('ScanRecipeBookScreen: extraction failed: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Something went wrong while reading the recipe. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _retake() {
    setState(() {
      _previewFile = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppBrand.paleMint,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppBrand.deepTeal,
        title: Text(
          'Scan from book',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppBrand.deepTeal,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _busy ? null : () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppBrand.offWhite,
                      borderRadius: AppRadius.lg,
                      border: Border.all(
                        color: AppBrand.mutedAqua.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              color: scheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Photo a cookbook page, then crop to the recipe you want',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppBrand.deepTeal,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Fill the frame, avoid glare, and keep text sharp. '
                          'Some books show several recipes on one page—use the crop step to '
                          'isolate just one. You can retake or pick from your gallery if needed.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_previewFile != null) ...[
                    ClipRRect(
                      borderRadius: AppRadius.md,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Image.file(
                          _previewFile!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_errorMessage != null) ...[
                    Material(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: AppRadius.md,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: scheme.error,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _retake,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retake or choose another'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy || _previewFile == null
                          ? null
                          : () => _runExtraction(XFile(_previewFile!.path)),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Retry extraction'),
                    ),
                    const SizedBox(height: 20),
                  ],
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickAndProcess(ImageSource.camera),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppBrand.deepTeal,
                      foregroundColor: AppBrand.offWhite,
                    ),
                    icon: const Icon(Icons.photo_camera_rounded),
                    label: const Text('Take photo'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _pickAndProcess(ImageSource.gallery),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: const Text('Choose from gallery'),
                  ),
                ],
              ),
            ),
            if (_busy)
              ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppBrand.offWhite,
                      borderRadius: AppRadius.lg,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Extracting recipe with AI…',
                          textAlign: TextAlign.center,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppBrand.deepTeal,
                          ),
                        ),
                        if (_previewFile != null) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: AppRadius.sm,
                            child: SizedBox(
                              height: 100,
                              width: double.infinity,
                              child: Image.file(
                                _previewFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
