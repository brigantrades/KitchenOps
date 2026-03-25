import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';

/// Metric / US customary — lives in [measurementSystemProvider] unless
/// [onChanged] is set (e.g. recipe editor also converts ingredient rows).
class MeasurementSystemToggle extends ConsumerWidget {
  const MeasurementSystemToggle({super.key, this.onChanged});

  /// When non-null, called with the new system instead of updating the provider
  /// directly (caller should call [MeasurementSystemNotifier.setSystem]).
  final void Function(MeasurementSystem system)? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(measurementSystemProvider);
    return SegmentedButton<MeasurementSystem>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment<MeasurementSystem>(
          value: MeasurementSystem.metric,
          label: Text('Metric'),
          icon: Icon(Icons.straighten_rounded, size: 16),
        ),
        ButtonSegment<MeasurementSystem>(
          value: MeasurementSystem.imperial,
          label: Text('US'),
          icon: Icon(Icons.scale_rounded, size: 16),
        ),
      ],
      selected: {m},
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onSelectionChanged: (next) {
        if (next.isEmpty) return;
        final s = next.first;
        if (onChanged != null) {
          onChanged!(s);
        } else {
          ref.read(measurementSystemProvider.notifier).setSystem(s);
        }
      },
    );
  }
}
