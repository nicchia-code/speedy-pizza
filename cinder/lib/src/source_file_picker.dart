import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedEpubFile {
  const PickedEpubFile({required this.name, required this.bytes});

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

abstract class CinderSourcePicker {
  Future<PickedEpubFile?> pickEpubFile();
}

class FilePickerCinderSourcePicker implements CinderSourcePicker {
  const FilePickerCinderSourcePicker();

  @override
  Future<PickedEpubFile?> pickEpubFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError('Impossibile leggere il file selezionato.');
    }

    return PickedEpubFile(name: file.name, bytes: bytes);
  }
}
