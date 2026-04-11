import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../debug_agent_log.dart';

/// Override with: `--dart-define=TRACKING_API_BASE=https://yoursite.com/php`
const String kReservationTrackingApiBase = String.fromEnvironment(
  'TRACKING_API_BASE',
  defaultValue: 'https://foodnpals.com/php',
);

const double kArrivalRadiusMeters = 150;

enum _LocationPostOutcome { posted, stopTracking, failed }

/// Result of [fetchReservationTrackingMeta] (GET tracking-allowed).
class ReservationTrackingMeta {
  const ReservationTrackingMeta({
    required this.track,
    this.restaurantLat,
    this.restaurantLng,
    this.status,
  });

  final bool track;
  final double? restaurantLat;
  final double? restaurantLng;
  final String? status;
}

Future<void> initBackgroundService() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  if (Platform.isAndroid) {
    const channel = AndroidNotificationChannel(
      'foodnpals_tracking_v2',
      'Journey tracking',
      description: 'FoodnPals is tracking your journey to the restaurant',
      importance: Importance.high,
    );
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onTrackingServiceStart,
      isForegroundMode: true,
      autoStart: false,
      autoStartOnBoot: false,
      initialNotificationTitle: 'On my way',
      initialNotificationContent: 'FoodnPals is tracking your journey',
      foregroundServiceTypes: const [AndroidForegroundType.location],
      foregroundServiceNotificationId: 888,
      notificationChannelId: 'foodnpals_tracking_v2',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onTrackingServiceStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onTrackingServiceStart(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();

  Timer? pollTimer;
  Timer? maxTimer;

  String? reservationId;
  double? restaurantLat;
  double? restaurantLng;
  String? bearerToken;

  /// Successful server syncs / failed attempts (GPS or network).
  int locationSuccessCount = 0;
  int locationFailCount = 0;

  Future<void> cleanup() async {
    pollTimer?.cancel();
    maxTimer?.cancel();
    pollTimer = null;
    maxTimer = null;
    reservationId = null;
    restaurantLat = null;
    restaurantLng = null;
    bearerToken = null;
    locationSuccessCount = 0;
    locationFailCount = 0;
  }

  Future<void> refreshForegroundNotification() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final android = service as AndroidServiceInstance;
      final title = 'On my way ($locationSuccessCount/$locationFailCount)';
      final content =
          'FoodnPals is tracking your journey · $locationSuccessCount updated'
          '${locationFailCount > 0 ? ', $locationFailCount failed' : ''}';
      await android.setForegroundNotificationInfo(
        title: title,
        content: content,
      );
    } catch (_) {}
  }

  Future<_LocationPostOutcome> postLocation(
    Dio dio, {
    required double lat,
    required double lng,
    required double? accuracy,
    required bool arrived,
  }) async {
    if (reservationId == null || bearerToken == null) {
      return _LocationPostOutcome.failed;
    }
    final url =
        '$kReservationTrackingApiBase/post_reservation_location.php?reservationId=${Uri.encodeQueryComponent(reservationId!)}';
    try {
      final resp = await dio.post<dynamic>(
        url,
        data: <String, dynamic>{
          'lat': lat,
          'lng': lng,
          if (accuracy != null) 'accuracy': accuracy,
          'arrived': arrived,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        options: Options(
          headers: <String, dynamic>{
            Headers.contentTypeHeader: Headers.jsonContentType,
            HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
          },
          validateStatus: (s) => s != null && s < 600,
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code == 403 || code == 404) {
        return _LocationPostOutcome.stopTracking;
      }
      if (code >= 200 && code < 300) {
        return _LocationPostOutcome.posted;
      }
      return _LocationPostOutcome.failed;
    } catch (_) {
      return _LocationPostOutcome.failed;
    }
  }

  Future<void> tick() async {
    if (reservationId == null ||
        restaurantLat == null ||
        restaurantLng == null ||
        bearerToken == null) {
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        restaurantLat!,
        restaurantLng!,
      );
      final arrived = dist < kArrivalRadiusMeters;
      final dio = Dio();
      final outcome = await postLocation(
        dio,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        arrived: arrived,
      );
      switch (outcome) {
        case _LocationPostOutcome.stopTracking:
          await cleanup();
          await service.stopSelf();
          return;
        case _LocationPostOutcome.posted:
          locationSuccessCount++;
          await refreshForegroundNotification();
          if (arrived) {
            await cleanup();
            await service.stopSelf();
          }
          return;
        case _LocationPostOutcome.failed:
          locationFailCount++;
          await refreshForegroundNotification();
          return;
      }
    } catch (_) {
      locationFailCount++;
      await refreshForegroundNotification();
    }
  }

  void armTimers() {
    pollTimer?.cancel();
    unawaited(tick());
    pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(tick()));

    maxTimer?.cancel();
    maxTimer = Timer(const Duration(minutes: 60), () async {
      await cleanup();
      await service.stopSelf();
    });
  }

  service.on('start_tracking').listen((Map<String, dynamic>? event) async {
    final data = event ?? <String, dynamic>{};
    final id = data['reservationId']?.toString();
    final lat = (data['restaurantLat'] as num?)?.toDouble();
    final lng = (data['restaurantLng'] as num?)?.toDouble();
    final token = data['authToken']?.toString();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H4',
      location: 'location_tracking_service.dart:start_tracking_listener',
      message: 'isolate_received_start_tracking',
      data: <String, Object?>{
        'hasReservationId': id != null,
        'hasLat': lat != null,
        'hasLng': lng != null,
        'hasAuthToken': token != null && token.isNotEmpty,
      },
    );
    // #endregion agent log
    if (id == null || lat == null || lng == null || token == null) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H4',
        location: 'location_tracking_service.dart:start_tracking_listener',
        message: 'start_tracking_payload_incomplete',
        data: const <String, Object?>{},
      );
      // #endregion agent log
      return;
    }
    await cleanup();
    reservationId = id;
    restaurantLat = lat;
    restaurantLng = lng;
    bearerToken = token;

    if (Platform.isAndroid) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H5',
        location: 'location_tracking_service.dart:android_foreground',
        message: 'before_android_foreground',
        data: <String, Object?>{
          'runtimeType': service.runtimeType.toString(),
        },
      );
      // #endregion agent log
      try {
        final android = service as AndroidServiceInstance;
        await android.setAsForegroundService();
        await refreshForegroundNotification();
        // #region agent log
        agentDebugLog(
          hypothesisId: 'H5',
          location: 'location_tracking_service.dart:android_foreground',
          message: 'foreground_notification_set',
          data: const <String, Object?>{'ok': true},
        );
        // #endregion agent log
      } catch (e, st) {
        // #region agent log
        agentDebugLog(
          hypothesisId: 'H5',
          location: 'location_tracking_service.dart:android_foreground',
          message: 'foreground_notification_failed',
          data: <String, Object?>{
            'error': e.toString(),
            'stack': st.toString().length > 200
                ? st.toString().substring(0, 200)
                : st.toString(),
          },
        );
        // #endregion agent log
      }
    }

    armTimers();
  });

  service.on('stop_tracking').listen((_) async {
    await cleanup();
    await service.stopSelf();
  });
}

Future<ReservationTrackingMeta?> fetchReservationTrackingMeta({
  required String reservationId,
  required String bearerToken,
}) async {
  final dio = Dio();
  final url =
      '$kReservationTrackingApiBase/get_reservation_tracking_allowed.php?reservationId=${Uri.encodeQueryComponent(reservationId)}';
  try {
    final resp = await dio.get<Map<String, dynamic>>(
      url,
      options: Options(
        headers: <String, dynamic>{
          HttpHeaders.authorizationHeader: 'Bearer $bearerToken',
        },
        validateStatus: (s) => s != null && s < 600,
      ),
    );
    final data = resp.data;
    final code = resp.statusCode ?? 0;
    final track = data != null && data['track'] == true;
    final lat = (data?['restaurantLat'] as num?)?.toDouble();
    final lng = (data?['restaurantLng'] as num?)?.toDouble();
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H2',
      location: 'location_tracking_service.dart:fetchReservationTrackingMeta',
      message: 'preflight_response',
      data: <String, Object?>{
        'statusCode': code,
        'track': track,
        'hasRestaurantLat': lat != null,
        'hasRestaurantLng': lng != null,
        'apiBase': kReservationTrackingApiBase,
      },
    );
    // #endregion agent log
    if (data == null) {
      return null;
    }
    return ReservationTrackingMeta(
      track: track,
      restaurantLat: lat,
      restaurantLng: lng,
      status: data['status']?.toString(),
    );
  } catch (e) {
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H2',
      location: 'location_tracking_service.dart:fetchReservationTrackingMeta',
      message: 'preflight_exception',
      data: <String, Object?>{'errorType': e.runtimeType.toString()},
    );
    // #endregion agent log
    return null;
  }
}

Future<bool> preflightReservationTracking({
  required String reservationId,
  required String bearerToken,
}) async {
  final meta = await fetchReservationTrackingMeta(
    reservationId: reservationId,
    bearerToken: bearerToken,
  );
  return meta?.track ?? false;
}

/// Starts tracking using server meta only (one GET). Used after confirmation URL.
Future<bool> startReservationTrackingUsingFetchedMeta({
  required String reservationId,
  required String bearerToken,
}) async {
  final meta = await fetchReservationTrackingMeta(
    reservationId: reservationId,
    bearerToken: bearerToken,
  );
  if (meta == null || !meta.track) {
    return false;
  }
  if (meta.restaurantLat == null || meta.restaurantLng == null) {
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H1_auto',
      location: 'location_tracking_service.dart:startReservationTrackingUsingFetchedMeta',
      message: 'missing_restaurant_coords_in_db',
      data: const <String, Object?>{},
    );
    // #endregion agent log
    return false;
  }
  return startReservationTracking(
    reservationId: reservationId,
    restaurantLat: meta.restaurantLat!,
    restaurantLng: meta.restaurantLng!,
    bearerToken: bearerToken,
    skipPreflight: true,
  );
}

/// Android sometimes returns false from [FlutterBackgroundService.startService] transiently (e.g. after stop).
Future<bool> _startBackgroundServiceWithRetries(FlutterBackgroundService bg) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    final ok = await bg.startService();
    if (ok) {
      return true;
    }
  }
  return false;
}

Future<bool> startReservationTracking({
  required String reservationId,
  required double restaurantLat,
  required double restaurantLng,
  required String bearerToken,
  bool skipPreflight = false,
}) async {
  if (!skipPreflight) {
    final allowed = await preflightReservationTracking(
      reservationId: reservationId,
      bearerToken: bearerToken,
    );
    if (!allowed) {
      // #region agent log
      agentDebugLog(
        hypothesisId: 'H2',
        location: 'location_tracking_service.dart:startReservationTracking',
        message: 'preflight_not_allowed_abort',
        data: const <String, Object?>{},
      );
      // #endregion agent log
      return false;
    }
  }

  final bg = FlutterBackgroundService();
  final wasRunning = await bg.isRunning();
  // #region agent log
  agentDebugLog(
    hypothesisId: 'H4',
    location: 'location_tracking_service.dart:startReservationTracking',
    message: 'before_startService',
    data: <String, Object?>{'wasRunning': wasRunning},
  );
  // #endregion agent log
  var running = wasRunning;
  if (!running) {
    running = await _startBackgroundServiceWithRetries(bg);
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H4',
      location: 'location_tracking_service.dart:startReservationTracking',
      message: 'after_startService',
      data: <String, Object?>{'startServiceOk': running},
    );
    // #endregion agent log
    if (!running) {
      return false;
    }
    // Let the background isolate run onStart and register service.on() listeners
    // before we send events. Invoking stop_tracking on a fresh service would
    // call stopSelf() and tear down before start_tracking is handled.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  } else {
    // stop_tracking calls stopSelf() — service dies; must start again before new work.
    bg.invoke('stop_tracking');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    running = await _startBackgroundServiceWithRetries(bg);
    // #region agent log
    agentDebugLog(
      hypothesisId: 'H4',
      location: 'location_tracking_service.dart:startReservationTracking',
      message: 'after_restartService',
      data: <String, Object?>{'startServiceOk': running},
    );
    // #endregion agent log
    if (!running) {
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  bg.invoke(
    'start_tracking',
    <String, dynamic>{
      'reservationId': reservationId,
      'restaurantLat': restaurantLat,
      'restaurantLng': restaurantLng,
      'authToken': bearerToken,
    },
  );
  // #region agent log
  agentDebugLog(
    hypothesisId: 'H4',
    location: 'location_tracking_service.dart:startReservationTracking',
    message: 'invoke_start_tracking_sent',
    data: const <String, Object?>{},
  );
  // #endregion agent log
  return true;
}

void stopReservationTracking() {
  FlutterBackgroundService().invoke('stop_tracking');
}
