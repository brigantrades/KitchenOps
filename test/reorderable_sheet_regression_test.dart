import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: Material [ReorderableListView] with [buildDefaultDragHandles]=true
/// shows no icon on iOS/Android (long-press only). Bottom sheets often break that.
/// App uses explicit [ReorderableDragStartListener] + [Icons.drag_handle_rounded].
void main() {
  testWidgets('bottom sheet reorder list shows two drag_handle icons on Android',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.android,
          useMaterial3: true,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (c) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 280,
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 2,
                          onReorder: (_, __) {},
                          itemBuilder: (context, index) {
                            return Material(
                              key: ValueKey<int>(index),
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                                title: Text('Item $index'),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
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

    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
  });
}
