# Local compatibility patch

This directory vendors `video_thumbnail` version 0.5.6 from https://pub.dev/packages/video_thumbnail. The upstream license is retained in `LICENSE`.

The Dart and native thumbnail behavior is unchanged. The Android Gradle file is locally adjusted only to replace the removed `jcenter()` repository with Maven Central and to compile against Android SDK 36, which is required by the current AndroidX AAR dependencies. The package is wired through the root `dependency_overrides` in `pubspec.yaml` so builds are reproducible.
