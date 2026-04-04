import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/features/recipes/presentation/recipe_editor_modals.dart';

/// Regression: ingredient editor uses [TextField]s with row-owned [FocusNode]s.
/// Synchronous [Navigator.pop] in the same turn as [unfocus] can leave gesture /
/// focus machinery touching disposed nodes. Production uses a deferred pop; this
/// test mirrors that contract.
void main() {
  testWidgets('deferred dialog pop after unfocus does not throw', (tester) async {
    FlutterErrorDetails? caught;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      caught ??= details;
      previousOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    final row = RecipeIngredientFormRow(
      name: '',
      unitOptions: const ['g', 'custom'],
      selectedUnit: 'g',
    );
    row.amountCtrl.text = '1';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (dialogCtx) {
                      return AlertDialog(
                        content: TextField(
                          controller: row.nameCtrl,
                          focusNode: row.nameFocusNode,
                          decoration: const InputDecoration(
                            hintText: 'Ingredient name',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              FocusScope.of(dialogCtx).unfocus();
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (dialogCtx.mounted) {
                                  Navigator.of(dialogCtx).pop();
                                }
                              });
                            },
                            child: const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Butter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    row.dispose();
    await tester.pump();

    expect(caught, isNull, reason: caught?.toString());
  });
}
