import 'dart:io';
import 'dart:ui' as ui;

import 'package:cinder_reading/src/ember_logo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generates cinder logo assets', () async {
    const progress = 0.68;

    Future<void> writeLogo(String path, int size) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      EmberLogoPainter(
        progress: progress,
      ).paint(canvas, ui.Size.square(size.toDouble()));
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Failed to encode $path');
      }

      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      image.dispose();
      picture.dispose();
    }

    await writeLogo('assets/brand/cinder_icon.png', 512);
    await writeLogo(
      'android/app/src/main/res/drawable-nodpi/launch_image.png',
      512,
    );
    await writeLogo('android/app/src/main/res/mipmap-mdpi/ic_launcher.png', 48);
    await writeLogo('android/app/src/main/res/mipmap-hdpi/ic_launcher.png', 72);
    await writeLogo(
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
      96,
    );
    await writeLogo(
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
      144,
    );
    await writeLogo(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      192,
    );
    await writeLogo('web/favicon.png', 32);
    await writeLogo('web/icons/Icon-192.png', 192);
    await writeLogo('web/icons/Icon-512.png', 512);
    await writeLogo('web/icons/Icon-maskable-192.png', 192);
    await writeLogo('web/icons/Icon-maskable-512.png', 512);
  });
}
