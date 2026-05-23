import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Explains why FoodnPals needs location access (before login / permission setup).
class WhyPermissionScreen extends StatefulWidget {
  const WhyPermissionScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<WhyPermissionScreen> createState() => _WhyPermissionScreenState();
}

class _WhyPermissionScreenState extends State<WhyPermissionScreen> {
  static const _assetPath = 'assets/videos/why_permission.mp4';

  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_initVideo());
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.asset(_assetPath);
    _controller = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
    } catch (e, st) {
      debugPrint('Why permission video init failed: $e\n$st');
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Why we need your location',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Watch this short video to see how location helps us time your table and food when you\'re on your way.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: c != null && c.value.isInitialized
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4CBB17),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: widget.onComplete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CBB17),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
