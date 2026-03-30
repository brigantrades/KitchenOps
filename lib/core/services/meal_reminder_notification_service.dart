import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Bump id if channel importance / behavior must change (Android caches channel settings).
const _channelId = 'leckerly_meal_reminders_v2';
const _channelName = 'Meal prep reminders';
const _channelDescription = 'Reminders for planned meals';

/// Shared instance; call [initMealReminderNotifications] from [main] before [runApp].
final MealReminderNotificationService mealReminderNotificationService =
    MealReminderNotificationService._();

final mealReminderNotificationServiceProvider =
    Provider<MealReminderNotificationService>(
        (ref) => mealReminderNotificationService);

Future<void> initMealReminderNotifications() =>
    mealReminderNotificationService.init();

/// Outcome of [MealReminderNotificationService.getReminderPermissionState].
class MealReminderPermissionState {
  const MealReminderPermissionState({
    required this.notificationsEnabled,
    required this.exactAlarmsAllowed,
  });

  /// Post notifications / alert permission (platform-specific).
  final bool notificationsEnabled;

  /// Android exact alarm permission; always true on iOS/macOS.
  final bool exactAlarmsAllowed;

  bool get isSufficient => notificationsEnabled && exactAlarmsAllowed;
}

/// Schedules one-shot local notifications from [MealPlanSlot.reminderAt] / [MealPlanSlot.reminderMessage].
class MealReminderNotificationService {
  MealReminderNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  final Set<String> _scheduledSlotIds = {};

  static int notificationIdForSlot(String slotId) {
    final hex = slotId.replaceAll('-', '');
    final slice = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
    return int.parse(slice, radix: 16) & 0x7FFFFFFF;
  }

  bool get _canSchedule {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  /// Cancels the scheduled local notification for this slot, if any.
  Future<void> cancelScheduledReminderForSlot(String slotId) async {
    if (!_canSchedule) return;
    if (!_initialized) {
      await init();
    }
    if (!_initialized) return;
    await _plugin.cancel(id: notificationIdForSlot(slotId));
    _scheduledSlotIds.remove(slotId);
  }

  Future<void> init() async {
    if (!_canSchedule || _initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    try {
      await _plugin.initialize(settings: initSettings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.requestNotificationsPermission();
        await android.requestExactAlarmsPermission();
        if (kDebugMode) {
          final enabled = await android.areNotificationsEnabled();
          final exactOk = await android.canScheduleExactNotifications();
          debugPrint(
            'MealReminderNotificationService: Android notificationsEnabled=$enabled '
            'canScheduleExactAlarms=$exactOk — if false, open system Settings for this app '
            '(Notifications + Alarms & reminders).',
          );
        }
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await mac?.requestPermissions(alert: true, badge: true, sound: true);

      _initialized = true;
    } on MissingPluginException catch (e, st) {
      debugPrint(
        'MealReminderNotificationService: plugin not linked (full restart '
        'after adding native plugins, or unsupported embedder): $e\n$st',
      );
    } catch (e, st) {
      debugPrint('MealReminderNotificationService: init failed: $e\n$st');
    }
  }

  /// Whether [getReminderPermissionState] is meaningful (skip gating on web / after init failure).
  bool get isPermissionCheckAvailable => _canSchedule && _initialized;

  /// Current permission state for meal reminders. Call [init] first.
  Future<MealReminderPermissionState> getReminderPermissionState() async {
    if (!_canSchedule || !_initialized) {
      return const MealReminderPermissionState(
        notificationsEnabled: true,
        exactAlarmsAllowed: true,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidReminderPermissionState();
      case TargetPlatform.iOS:
        return _iosReminderPermissionState();
      case TargetPlatform.macOS:
        return _macosReminderPermissionState();
      default:
        return const MealReminderPermissionState(
          notificationsEnabled: true,
          exactAlarmsAllowed: true,
        );
    }
  }

  Future<MealReminderPermissionState> _androidReminderPermissionState() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: false,
      );
    }
    try {
      final notifications = await android.areNotificationsEnabled();
      final exact = await android.canScheduleExactNotifications();
      // Treat null as allowed when the OS/plugin does not report (pre–notification-runtime).
      return MealReminderPermissionState(
        notificationsEnabled: notifications != false,
        exactAlarmsAllowed: exact != false,
      );
    } catch (e, st) {
      debugPrint(
          'MealReminderNotificationService: Android permission read failed: $e\n$st');
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: false,
      );
    }
  }

  Future<MealReminderPermissionState> _iosReminderPermissionState() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) {
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: true,
      );
    }
    try {
      final opts = await ios.checkPermissions();
      if (opts == null) {
        return const MealReminderPermissionState(
          notificationsEnabled: false,
          exactAlarmsAllowed: true,
        );
      }
      final enabled =
          (opts.isEnabled || opts.isProvisionalEnabled) && opts.isAlertEnabled;
      return MealReminderPermissionState(
        notificationsEnabled: enabled,
        exactAlarmsAllowed: true,
      );
    } catch (e, st) {
      debugPrint(
          'MealReminderNotificationService: iOS permission read failed: $e\n$st');
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: true,
      );
    }
  }

  Future<MealReminderPermissionState> _macosReminderPermissionState() async {
    final mac = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (mac == null) {
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: true,
      );
    }
    try {
      final opts = await mac.checkPermissions();
      if (opts == null) {
        return const MealReminderPermissionState(
          notificationsEnabled: false,
          exactAlarmsAllowed: true,
        );
      }
      final enabled =
          (opts.isEnabled || opts.isProvisionalEnabled) && opts.isAlertEnabled;
      return MealReminderPermissionState(
        notificationsEnabled: enabled,
        exactAlarmsAllowed: true,
      );
    } catch (e, st) {
      debugPrint(
          'MealReminderNotificationService: macOS permission read failed: $e\n$st');
      return const MealReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmsAllowed: true,
      );
    }
  }

  /// Re-run OS permission prompts where supported.
  Future<void> requestReminderPermissions() async {
    if (!_canSchedule || !_initialized) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await mac?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e, st) {
      debugPrint(
          'MealReminderNotificationService: requestReminderPermissions failed: $e\n$st');
    }
  }

  Future<AndroidScheduleMode> _androidScheduleMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final canExact = await android.canScheduleExactNotifications();
      if (canExact == true) {
        return AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (e, st) {
      debugPrint(
          'MealReminderNotificationService: canScheduleExactNotifications failed: $e\n$st');
    }
    if (kDebugMode) {
      debugPrint(
        'MealReminderNotificationService: using inexact alarms (exact not permitted). '
        'Delivery may be delayed a few minutes on some devices.',
      );
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  bool _shouldSchedule(MealPlanSlot slot) {
    final msg = slot.reminderMessage?.trim() ?? '';
    if (msg.isEmpty || slot.reminderAt == null) return false;
    return slot.reminderAt!.isAfter(DateTime.now().toUtc());
  }

  String _titleFor(
    MealPlanSlot slot,
    String weekdayLabel,
    List<MealPlanSlot> allSlots,
  ) {
    final meal = plannerSlotDisplayLabelForWeek(allSlots, slot);
    return '$weekdayLabel · $meal';
  }

  Future<void> syncFromSlots(List<MealPlanSlot> slots) async {
    if (!_canSchedule) return;
    if (!_initialized) {
      await init();
    }
    if (!_initialized) return;

    final desired = <String>{};
    for (final s in slots) {
      if (_shouldSchedule(s)) desired.add(s.id);
    }

    for (final id in _scheduledSlotIds.difference(desired)) {
      await _plugin.cancel(id: notificationIdForSlot(id));
    }
    _scheduledSlotIds
      ..clear()
      ..addAll(desired);

    final androidMode = await _androidScheduleMode();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    for (final slot in slots) {
      if (!_shouldSchedule(slot)) continue;

      final whenUtc = slot.reminderAt!.toUtc();
      // Same wall-clock instant as stored UTC; no device timezone plugin required.
      final scheduled = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC,
        whenUtc.millisecondsSinceEpoch,
      );
      final weekdayLabel = _weekdayFromSlot(slot);
      final title = _titleFor(slot, weekdayLabel, slots);
      final body = slot.reminderMessage!.trim();

      try {
        await _plugin.zonedSchedule(
          id: notificationIdForSlot(slot.id),
          title: title,
          body: body,
          scheduledDate: scheduled,
          notificationDetails: details,
          androidScheduleMode: androidMode,
        );
        if (kDebugMode) {
          debugPrint(
            'MealReminderNotificationService: scheduled id=${notificationIdForSlot(slot.id)} '
            'at=${scheduled.toIso8601String()} mode=$androidMode',
          );
        }
      } catch (e, st) {
        debugPrint(
            'MealReminderNotificationService zonedSchedule failed: $e\n$st');
        if (androidMode != AndroidScheduleMode.inexactAllowWhileIdle) {
          try {
            await _plugin.zonedSchedule(
              id: notificationIdForSlot(slot.id),
              title: title,
              body: body,
              scheduledDate: scheduled,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
            if (kDebugMode) {
              debugPrint(
                'MealReminderNotificationService: retry with inexact succeeded',
              );
            }
          } catch (e2, st2) {
            debugPrint(
                'MealReminderNotificationService inexact schedule failed: $e2\n$st2');
          }
        }
      }
    }

    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      final pending = await _plugin.pendingNotificationRequests();
      debugPrint(
        'MealReminderNotificationService: pendingNotificationRequests=${pending.length}',
      );
    }
  }

  String _weekdayFromSlot(MealPlanSlot slot) {
    final date = slot.weekStart.add(Duration(days: slot.dayOfWeek));
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final i = date.weekday - 1;
    if (i >= 0 && i < names.length) return names[i];
    return 'Meal';
  }
}
