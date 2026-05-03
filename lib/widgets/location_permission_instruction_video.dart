import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays the bundled instruction video in a loop with a 1 second pause between each play.
class LocationPermissionInstructionVideo extends StatefulWidget {
  const LocationPermissionInstructionVideo({super.key});

  @override
  State<LocationPermissionInstructionVideo> createState() =>
      _LocationPermissionInstructionVideoState();
}

class _LocationPermissionInstructionVideoState
    extends State<LocationPermissionInstructionVideo> {
  static const _assetPath = 'assets/videos/locationpermission.mp4';

  VideoPlayerController? _controller;
  bool _replaying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final c = VideoPlayerController.asset(_assetPath);
    _controller = c;
    try {
      await c.initialize();
    } catch (e, st) {
      debugPrint('Location instruction video init failed: $e\n$st');
      if (mounted) setState(() {});
      return;
    }
    await c.setLooping(false);
    c.addListener(_onVideoUpdate);
    await c.play();
    if (mounted) setState(() {});
  }

  void _onVideoUpdate() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _replaying) return;
    final duration = c.value.duration;
    if (duration == Duration.zero) return;
    // Some devices stop slightly short of [duration]; treat near-end as finished.
    final pos = c.value.position;
    if (pos + const Duration(milliseconds: 120) < duration) return;
    _replaying = true;
    unawaited(_gapAndReplay());
  }

  Future<void> _gapAndReplay() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _replaying = false;
      return;
    }
    await c.pause();
    await c.seekTo(Duration.zero);
    _replaying = false;
    await c.play();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }
}
