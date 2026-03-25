import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/services/share_handler_service.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';

/// Paste an Instagram post URL to run the same AI import as the Android share sheet.
///
/// Open from the Recipes tab (sparkle icon in the app bar).
class InstagramImportTestScreen extends ConsumerStatefulWidget {
  const InstagramImportTestScreen({super.key});

  @override
  ConsumerState<InstagramImportTestScreen> createState() =>
      _InstagramImportTestScreenState();
}

class _InstagramImportTestScreenState
    extends ConsumerState<InstagramImportTestScreen> {
  final _urlCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t != null && t.isNotEmpty) {
      setState(() => _urlCtrl.text = t);
    }
  }

  Future<void> _runImport() async {
    FocusScope.of(context).unfocus();
    await ref.read(shareImportNotifierProvider.notifier).manualImportFromPastedContent(
          url: _urlCtrl.text,
          caption: _captionCtrl.text.trim().isEmpty ? null : _captionCtrl.text,
        );
    // Loading + navigation to preview are handled globally in [LeckerlyApp].
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Instagram import'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Paste a public Instagram post link. The app only sends the URL '
            '(and optional text below) to Gemini—Instagram does not give your '
            'app the full post unless the user shares it from the app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Post URL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlCtrl,
                  minLines: 2,
                  maxLines: 4,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://www.instagram.com/p/…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _pasteUrl,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste from clipboard'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionCard(
            title: 'Optional caption or notes',
            subtitle:
                'If you copy text from the post elsewhere, paste it here to '
                'give Gemini more context.',
            child: TextField(
              controller: _captionCtrl,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: 'Ingredients, instructions…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _runImport,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Import with AI'),
          ),
        ],
      ),
    );
  }
}
