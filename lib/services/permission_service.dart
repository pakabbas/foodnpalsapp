import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class PermissionService {
  /// Android: requires "Allow all the time" for background journey tracking.
  /// iOS: while-in-use or always is sufficient.
  static Future<bool> hasRequiredLocationForJourneyTracking() async {
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      return false;
    }
    if (Platform.isAndroid) {
      return p == LocationPermission.always;
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  static Future<bool> requestLocationPermission(BuildContext context) async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }

    if (p == LocationPermission.deniedForever) {
      if (!context.mounted) return false;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location needed'),
          content: const Text(
            'FoodnPals needs location access so the restaurant can see when you are on your way. '
            'Please enable location in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (open == true) {
        await Geolocator.openAppSettings();
        p = await Geolocator.checkPermission();
      }
    }

    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return false;
    }

    if (Platform.isAndroid) {
      if (p == LocationPermission.whileInUse) {
        if (!context.mounted) return false;
        final upgrade = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Background location'),
            content: const Text(
              'To share your journey while the app is in the background or when the screen is off, '
              'please set location permission to "Allow all the time" for FoodnPals.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
        if (upgrade == true) {
          await Geolocator.openAppSettings();
          p = await Geolocator.checkPermission();
        }
      }
      return p == LocationPermission.always;
    }

    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }
}
