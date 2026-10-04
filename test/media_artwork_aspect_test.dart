import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yazen/core/theme/theme_provider.dart';
import 'package:yazen/models/media_track.dart';
import 'package:yazen/widgets/media_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('portrait cover is contained over a subdued edge fill', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAADAAAABgCAIAAADU7mYnAAAAV0lEQVR42u3OAQ0AMAgAIH0c05nVRK/hHCQguyY2ebGMkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQ0M3QB+1VAixvMLRzAAAAAElFTkSuQmCC',
      ),
    );

    const channel = MethodChannel('yazen/local_media');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readOriginalArtwork') return bytes;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final track = MediaTrack(
      id: 'portrait-art',
      title: 'Portrait cover',
      artist: 'Test artist',
      album: 'Test album',
      source: TrackSource.local,
      uri: Uri.parse('content://media/external/audio/media/portrait-art'),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: 96,
                child: YazenMediaArtwork(track: track, size: 96),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final imageWidgets = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(imageWidgets, hasLength(2));
    expect(imageWidgets[0].fit, BoxFit.cover);
    expect(imageWidgets[1].fit, BoxFit.contain);
  });
}
