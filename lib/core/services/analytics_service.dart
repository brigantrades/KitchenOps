import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AnalyticsService {
  AnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  Future<void> logScreen(String screenName) {
    return _analytics.logScreenView(screenName: screenName);
  }

  Future<void> logEvent(String name, [Map<String, Object>? params]) {
    return _analytics.logEvent(name: name, parameters: params);
  }

  void recordError(Object error, StackTrace stackTrace, {String? reason}) {
    FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
  }
}
