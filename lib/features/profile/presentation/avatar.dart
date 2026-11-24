import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).take(2).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).join();

/// Round profile picture, or the name's initials when there is none.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.size, this.picture});

  final String name;
  final Uint8List? picture;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (picture != null) {
      return ClipOval(
        child: Image.memory(picture!, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
      child: Text(
        _initials(name),
        style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w700, color: c.brandTintInk),
      ),
    );
  }
}
