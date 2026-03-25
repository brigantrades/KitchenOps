import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/storage/local_cache.dart';

class MeasurementSystemNotifier extends Notifier<MeasurementSystem> {
  @override
  MeasurementSystem build() {
    final raw = ref.read(localCacheProvider).loadMeasurementSystem();
    if (raw == null) return MeasurementSystem.metric;
    return MeasurementSystem.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => MeasurementSystem.metric,
    );
  }

  void setSystem(MeasurementSystem system) {
    state = system;
    unawaited(ref.read(localCacheProvider).saveMeasurementSystem(system.name));
  }
}

final measurementSystemProvider =
    NotifierProvider<MeasurementSystemNotifier, MeasurementSystem>(
  MeasurementSystemNotifier.new,
);
