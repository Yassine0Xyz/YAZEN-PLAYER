import 'dart:async';

import 'package:flutter/widgets.dart';

/// Starts persisted playback restoration only after the app has rendered its
/// first frame, and prevents stale media from escaping as an unhandled error.
void schedulePlaybackRestoreAfterFirstFrame(Future<void> Function() restore) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      Future<void>.sync(
        restore,
      ).catchError((Object error, StackTrace stackTrace) {}),
    );
  });
}
