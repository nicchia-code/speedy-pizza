import 'dart:typed_data';

class PickedSourceFile {
  const PickedSourceFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }
}

abstract class TextSourcePicker {
  Future<PickedSourceFile?> pickTextFile();
}
