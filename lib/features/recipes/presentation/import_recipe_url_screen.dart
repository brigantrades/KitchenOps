import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/services/share_handler_service.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/section_card.dart';

/// Paste a recipe page URL to fetch plain text and run the same AI + preview flow as Instagram import.
class ImportRecipeUrlScreen extends ConsumerStatefulWidget {
  const ImportRecipeUrlScreen({super.key});

  @override
  ConsumerState<ImportRecipeUrlScreen> createState() =>
      _ImportRecipeUrlScreenState();
}

class _ImportRecipeUrlScreenState extends ConsumerState<ImportRecipeUrlScreen> {
  final _urlCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _notesCtrl.dispose();
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
    await ref.read(shareImportNotifierProvider.notifier).importFromWebsiteUrl(
          urlRaw: _urlCtrl.text,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from link'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Paste a link to a recipe on a blog or recipe site (e.g. AllRecipes, food.com). '
            'We load the page, extract text on your device, and use AI to fill ingredients and steps. '
            'Some sites load content only in a browser, use paywalls, or block automated requests—those may not work.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Recipe URL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlCtrl,
                  minLines: 2,
                  maxLines: 4,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: 'https://…',
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
            title: 'Optional notes',
            subtitle:
                'If something didn’t import well, add hints here and tap Re-parse on the next screen.',
            child: TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'e.g. double the sauce, gluten-free flour…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _runImport,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Import with AI'),
          ),
        ],
      ),
    );
  }
}
