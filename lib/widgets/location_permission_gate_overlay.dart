import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_permission_instruction_video.dart';

/// Blocks the screen until journey location permission is granted (Android: "Allow all the time").
/// Shows the how-to instruction video ([LocationPermissionInstructionVideo]).
class LocationPermissionGateOverlay extends StatelessWidget {
  const LocationPermissionGateOverlay({
    super.key,
    this.onGoBack,
    this.showGoBack = true,
  });

  final VoidCallback? onGoBack;
  final bool showGoBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 56,
                  color: Color(0xFF4CBB17),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Location access required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We need your location permission to track your journey to the restaurant, '
                  'so the restaurant can prepare your table for your arrival. '
                  'On Android, choose "Allow all the time".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade800,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                const LocationPermissionInstructionVideo(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CBB17),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showGoBack && onGoBack != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onGoBack,
                    child: const Text('Go back'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
