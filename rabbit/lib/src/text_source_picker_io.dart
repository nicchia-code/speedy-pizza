import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'text_source_picker_base.dart';

TextSourcePicker createPlatformTextSourcePicker() =>
    const _NativeTextSourcePicker();

class _NativeTextSourcePicker implements TextSourcePicker {
  const _NativeTextSourcePicker();

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CinderReading][NativePicker] $message');
    }
  }

  @override
  Future<PickedSourceFile?> pickTextFile() async {
    _log('open native file picker');

    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'txt',
        'md',
        'markdown',
        'html',
        'htm',
        'fb2',
        'epub',
        'pb',
      ],
    );

    if (result == null || result.files.isEmpty) {
      _log('native picker: no file selected');
      return null;
    }

    final file = result.files.single;
    final inMemoryBytes = file.bytes;

    if (inMemoryBytes != null) {
      _log(
        'native picker: selected ${file.name} (${inMemoryBytes.length} bytes)',
      );
      return PickedSourceFile(name: file.name, bytes: inMemoryBytes);
    }

    final path = file.path;
    if (path == null || path.isEmpty) {
      _log('native picker: missing bytes and path for ${file.name}');
      return null;
    }

    final diskBytes = await io.File(path).readAsBytes();
    _log('native picker: selected ${file.name} (${diskBytes.length} bytes)');
    return PickedSourceFile(name: file.name, bytes: diskBytes);
  }
}
