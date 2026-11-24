import 'dart:typed_data';
import 'dart:ui' as ui;

const int _size = 256;

/// Center-crops an image to a square and returns it as a small PNG.
Future<Uint8List> imageToAvatar(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final side = image.width < image.height ? image.width : image.height;
    final source = ui.Rect.fromLTWH(
      (image.width - side) / 2,
      (image.height - side) / 2,
      side.toDouble(),
      side.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(_size, _size);
    try {
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      out.dispose();
    }
  } finally {
    image.dispose();
  }
}
