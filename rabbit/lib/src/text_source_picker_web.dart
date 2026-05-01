// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'text_source_picker_base.dart';

TextSourcePicker createPlatformTextSourcePicker() =>
    const _WebTextSourcePicker();

class _WebTextSourcePicker implements TextSourcePicker {
  const _WebTextSourcePicker();

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CinderReading][WebPicker] $message');
    }
  }

  @override
  Future<PickedSourceFile?> pickTextFile() {
    _log('open file input');
    final completer = Completer<PickedSourceFile?>();
    final input = html.FileUploadInputElement()
      ..accept = const [
        'text/*',
        '.txt',
        '.md',
        '.markdown',
        '.html',
        '.htm',
        '.fb2',
        '.epub',
        '.pb',
        'application/epub+zip',
        '*/*',
      ].join(',')
      ..multiple = false;
    input.style.display = 'none';
    html.document.body?.append(input);

    StreamSubscription<html.Event>? changeSubscription;

    void finish(PickedSourceFile? value) {
      if (!completer.isCompleted) {
        _log(
          value == null
              ? 'finish: null file selected'
              : 'finish: ${value.name} (${value.bytes.length} bytes)',
        );
        completer.complete(value);
      }
      changeSubscription?.cancel();
      input.remove();
    }

    void finishError(Object error) {
      if (!completer.isCompleted) {
        _log('finishError: $error');
        completer.completeError(error);
      }
      changeSubscription?.cancel();
      input.remove();
    }

    void completeFromReaderResult(String fileName, Object? result) {
      if (result is ByteBuffer) {
        _log('reader result ByteBuffer for $fileName');
        finish(PickedSourceFile(name: fileName, bytes: result.asUint8List()));
        return;
      }

      if (result is Uint8List) {
        _log('reader result Uint8List for $fileName');
        finish(PickedSourceFile(name: fileName, bytes: result));
        return;
      }

      if (result is String) {
        _log(
          'reader result string for $fileName: '
          'startsWithData=${result.startsWith("data:")}',
        );
        if (result.startsWith('data:')) {
          final base64Marker = result.indexOf(',');
          if (base64Marker != -1 && base64Marker + 1 < result.length) {
            try {
              final bytes = base64Decode(result.substring(base64Marker + 1));
              finish(PickedSourceFile(name: fileName, bytes: bytes));
              return;
            } catch (_) {}
          }
        } else {
          _log('reader result plain text for $fileName');
          finish(
            PickedSourceFile(
              name: fileName,
              bytes: const Utf8Encoder().convert(result),
            ),
          );
          return;
        }
      }

      _log(
        'reader result unsupported type for $fileName: ${result.runtimeType}',
      );
      finish(null);
    }

    changeSubscription = input.onChange.listen((_) {
      _log('input onChange fired');
      final file = input.files?.first;
      if (file == null) {
        _log('onChange: no file in input.files');
        finish(null);
        return;
      }
      _log(
        'onChange: selected ${file.name} size=${file.size} type=${file.type}',
      );

      final reader = html.FileReader();

      reader.onError.listen((_) {
        _log('reader onError');
        finishError(StateError('Unable to read the selected file.'));
      });

      reader.onAbort.listen((_) {
        _log('reader onAbort');
        finishError(StateError('File read aborted.'));
      });
      reader.onLoad.listen((_) {
        _log('reader onLoad for ${file.name}');
        completeFromReaderResult(file.name, reader.result);
      });
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        _log(
          'reader onLoadEnd for ${file.name} resultType=${result?.runtimeType}',
        );
        if (result == null && !completer.isCompleted) {
          _log('reader onLoadEnd: no result payload');
          finishError(StateError('No data while reading file.'));
        }
      });

      _log('reader readAsArrayBuffer start');
      reader.readAsArrayBuffer(file);
    });

    input.click();
    return completer.future;
  }
}
