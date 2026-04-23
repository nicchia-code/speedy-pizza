import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'text_source_picker_base.dart';

class ImportedBook {
  const ImportedBook({
    required this.name,
    required this.text,
    required this.formatLabel,
    required this.chapterTexts,
    required this.chapterTitles,
  });

  final String name;
  final String text;
  final String formatLabel;
  final List<String> chapterTexts;
  final List<String> chapterTitles;
}

Future<ImportedBook> importBook(PickedSourceFile file) async {
  _log(
    'importBook start: name=${file.name}, extension=${file.extension}, bytes=${file.bytes.length}',
  );
  final extension = file.extension;

  switch (extension) {
    case 'txt':
    case 'md':
    case 'markdown':
      final text = _normalizeImportedText(_decodeTextBytes(file.bytes));
      final imported = ImportedBook(
        name: file.name,
        text: text,
        formatLabel: extension == 'txt' ? 'TXT' : 'Markdown',
        chapterTexts: [text],
        chapterTitles: ['Testo'],
      );
      _log(
        'importBook done: ${imported.formatLabel}, chars=${imported.text.length}',
      );
      return imported;
    case 'html':
    case 'htm':
      final text = _extractMarkupText(_decodeTextBytes(file.bytes));
      final imported = ImportedBook(
        name: file.name,
        text: text,
        formatLabel: 'HTML',
        chapterTexts: [text],
        chapterTitles: ['Testo'],
      );
      _log(
        'importBook done: ${imported.formatLabel}, chars=${imported.text.length}',
      );
      return imported;
    case 'fb2':
      final text = _extractFb2Text(_decodeTextBytes(file.bytes));
      final imported = ImportedBook(
        name: file.name,
        text: text,
        formatLabel: 'FB2',
        chapterTexts: [text],
        chapterTitles: ['Testo'],
      );
      _log(
        'importBook done: ${imported.formatLabel}, chars=${imported.text.length}',
      );
      return imported;
    case 'epub':
      final text = _extractEpubText(file.bytes);
      final imported = ImportedBook(
        name: file.name,
        text: text,
        formatLabel: 'EPUB',
        chapterTexts: [text],
        chapterTitles: ['Testo'],
      );
      _log(
        'importBook done: ${imported.formatLabel}, chars=${imported.text.length}',
      );
      return imported;
    case 'pb':
      final chapters = _extractPbChapters(file.bytes);
      final chapterTexts = <String>[];
      final chapterTitles = <String>[];

      for (final chapter in chapters) {
        chapterTexts.add(chapter.text);
        chapterTitles.add(chapter.title);
      }

      if (chapterTexts.isEmpty) {
        throw const FormatException('File .pb senza capitoli leggibili.');
      }

      final joinedText = _normalizeImportedText(chapterTexts.join('\n\n'));
      final imported = ImportedBook(
        name: file.name,
        text: joinedText,
        formatLabel: 'PB',
        chapterTexts: chapterTexts,
        chapterTitles: chapterTitles,
      );
      _log(
        'importBook done: ${imported.formatLabel}, chapters=${chapterTexts.length}, totalChars=${imported.text.length}',
      );
      return imported;
    default:
      final fallbackText = _normalizeImportedText(_decodeTextBytes(file.bytes));
      if (fallbackText.isNotEmpty) {
        final imported = ImportedBook(
          name: file.name,
          text: fallbackText,
          chapterTexts: [fallbackText],
          chapterTitles: ['Testo'],
          formatLabel: extension.isEmpty ? 'Text' : extension.toUpperCase(),
        );
        _log('importBook fallback used: ${imported.formatLabel}');
        return imported;
      }
      _log('importBook unsupported: .$extension');
      throw UnsupportedError(
        'Formato non supportato: ${extension.isEmpty ? file.name : '.$extension'}',
      );
  }
}

List<_PbChapter> _extractPbChapters(Uint8List bytes) {
  final source = _decodeTextBytes(bytes);
  final rawLines = source.replaceAll('\r\n', '\n').split('\n');
  final parsedChapters = <_PbChapter>[];

  var chapterTitle = 'Capitolo 1';
  var fallbackIndex = 2;
  final sectionBuffer = StringBuffer();
  var foundChapterMarker = false;
  final markerRegex = RegExp(r'^\s*={5,}\s*(.*?)\s*={5,}\s*$');

  void flushSection() {
    final normalizedText = _normalizeImportedText(sectionBuffer.toString());
    if (normalizedText.isEmpty) {
      sectionBuffer.clear();
      return;
    }

    if (normalizedText.isNotEmpty) {
      parsedChapters.add(_PbChapter(title: chapterTitle, text: normalizedText));
    }
    sectionBuffer.clear();
  }

  for (final line in rawLines) {
    final trimmed = line.trim();
    final markerMatch = markerRegex.firstMatch(trimmed);
    if (markerMatch == null || markerMatch.groupCount == 0) {
      sectionBuffer.writeln(line);
      continue;
    }

    final markerText = markerMatch.group(1)?.trim() ?? '';

    flushSection();

    if (markerText.isEmpty) {
      chapterTitle = 'Capitolo $fallbackIndex';
      fallbackIndex += 1;
    } else {
      chapterTitle = markerText;
    }
    foundChapterMarker = true;
  }

  flushSection();

  if (parsedChapters.isEmpty && !foundChapterMarker) {
    final fallbackText = _normalizeImportedText(source);
    if (fallbackText.isNotEmpty) {
      return [_PbChapter(title: 'Capitolo 1', text: fallbackText)];
    }
  }

  if (parsedChapters.isEmpty) {
    final fallbackText = _normalizeImportedText(source);
    if (fallbackText.isNotEmpty) {
      return [_PbChapter(title: 'Capitolo 1', text: fallbackText)];
    }
  }

  return parsedChapters;
}

class _PbChapter {
  const _PbChapter({required this.title, required this.text});

  final String title;
  final String text;
}

String _extractEpubText(Uint8List bytes) {
  _log('EPUB parse start: bytes=${bytes.length}');
  final archive = ZipDecoder().decodeBytes(bytes);
  _log('EPUB parse: archive entries=${archive.files.length}');
  final filesByPath = <String, ArchiveFile>{};

  for (final file in archive.files) {
    if (file.isFile) {
      final normalizedPath = _normalizeArchivePath(file.name);
      filesByPath[normalizedPath] = file;

      final decodedPath = _decodeArchivePath(normalizedPath);
      if (decodedPath != normalizedPath) {
        filesByPath[decodedPath] = file;
      }
    }
  }

  final containerFile = filesByPath['meta-inf/container.xml'];
  if (containerFile == null) {
    _log('EPUB parse: container.xml not found');
    throw const FormatException('EPUB senza META-INF/container.xml.');
  }
  _log('EPUB parse: container.xml found');

  final containerDocument = XmlDocument.parse(
    _decodeTextBytes(_archiveFileBytes(containerFile)),
  );
  final rootFile = _findFirstElement(containerDocument, 'rootfile');
  final packagePath = rootFile?.getAttribute('full-path');

  if (packagePath == null || packagePath.isEmpty) {
    _log('EPUB parse: rootfile missing full-path');
    throw const FormatException('EPUB senza rootfile nel container.');
  }
  _log('EPUB parse: package path=$packagePath');

  final normalizedPackagePath = _normalizeArchivePath(packagePath);
  final packageFile = filesByPath[normalizedPackagePath];

  if (packageFile == null) {
    _log('EPUB parse: package file not found for path=$packagePath');
    throw FormatException('Package EPUB non trovato: $packagePath');
  }
  _log('EPUB parse: package file found');

  final packageDirectory = _dirname(normalizedPackagePath);
  final packageDocument = XmlDocument.parse(
    _decodeTextBytes(_archiveFileBytes(packageFile)),
  );

  final manifestById = <String, String>{};
  for (final item in _findElements(packageDocument, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null && href.isNotEmpty) {
      manifestById[id] = _resolveArchivePath(packageDirectory, href);
    }
  }
  _log('EPUB parse: manifest entries=${manifestById.length}');

  final spineItemPaths = <String>[];
  for (final itemRef in _findElements(packageDocument, 'itemref')) {
    final idRef = itemRef.getAttribute('idref');
    if (idRef == null) {
      continue;
    }
    final path = manifestById[idRef];
    if (path != null) {
      spineItemPaths.add(path);
    }
  }
  _log('EPUB parse: spine entries=${spineItemPaths.length}');

  final chapterTexts = <String>[];
  final consumedPaths = <String>{};
  var fallbackPaths = <String>[];

  for (final path in spineItemPaths) {
    final chapterFile = filesByPath[path];
    if (chapterFile == null) {
      _log('EPUB parse: spine item not found in archive: $path');
      continue;
    }
    consumedPaths.add(path);
    final chapterText = _extractMarkupText(
      _decodeTextBytes(_archiveFileBytes(chapterFile)),
    );
    if (chapterText.isNotEmpty) {
      chapterTexts.add(chapterText);
    }
  }
  _log('EPUB parse: extracted chapters from spine=${chapterTexts.length}');

  if (chapterTexts.isEmpty) {
    fallbackPaths = <String>{
      for (final key in filesByPath.keys)
        if (!consumedPaths.contains(key) &&
            (key.endsWith('.xhtml') ||
                key.endsWith('.html') ||
                key.endsWith('.htm') ||
                key.endsWith('.xhtm')))
          key,
    }.toList()..sort();
    _log('EPUB parse: fallback html paths=${fallbackPaths.length}');

    for (final path in fallbackPaths) {
      final chapterFile = filesByPath[path];
      if (chapterFile == null) {
        _log('EPUB parse: fallback path missing=$path');
        continue;
      }
      final chapterText = _extractMarkupText(
        _decodeTextBytes(_archiveFileBytes(chapterFile)),
      );
      if (chapterText.isNotEmpty) {
        chapterTexts.add(chapterText);
      }
    }
    _log('EPUB parse: fallback chapters extracted=${chapterTexts.length}');
  }

  final normalized = _normalizeImportedText(chapterTexts.join('\n\n'));
  if (normalized.isNotEmpty) {
    _log('EPUB parse: final normalized text ok, length=${normalized.length}');
    return normalized;
  }

  final fallbackText = _extractMarkupText(
    _decodeTextBytes(
      _archiveFileBytes(
        fallbackPaths.isNotEmpty
            ? filesByPath[fallbackPaths.first]!
            : packageFile,
      ),
    ),
  );
  if (fallbackText.isNotEmpty) {
    _log(
      'EPUB parse: used direct fallback text, length=${fallbackText.length}',
    );
    return fallbackText;
  }

  _log('EPUB parse: failed to extract readable text');
  throw const FormatException('EPUB senza contenuto testuale leggibile.');
}

void _log(String message) {
  if (kDebugMode) {
    debugPrint('[SpeedyReader][Importer] $message');
  }
}

String _extractFb2Text(String source) {
  final document = XmlDocument.parse(source);
  final bodies = _findElements(document, 'body');
  if (bodies.isEmpty) {
    return _extractMarkupText(source);
  }

  final buffer = StringBuffer();
  for (final body in bodies) {
    _writeXmlText(body, buffer);
    buffer.write('\n\n');
  }

  return _normalizeImportedText(buffer.toString());
}

void _writeXmlText(XmlNode node, StringBuffer buffer) {
  if (node is XmlText) {
    buffer.write(node.value);
    return;
  }

  if (node is XmlElement) {
    if (_xmlBlockElements.contains(node.name.local)) {
      buffer.write('\n');
    }
    for (final child in node.children) {
      _writeXmlText(child, buffer);
    }
    if (_xmlBlockElements.contains(node.name.local)) {
      buffer.write('\n');
    }
  }
}

String _extractMarkupText(String source) {
  var text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final bodyMatch = RegExp(
    r'<body\b[^>]*>([\s\S]*?)</body>',
    caseSensitive: false,
  ).firstMatch(text);
  if (bodyMatch != null) {
    text = bodyMatch.group(1) ?? text;
  }

  text = text.replaceAll(
    RegExp(r'<(script|style|head|title)\b[\s\S]*?</\1>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(
      r'</?(p|div|section|article|li|ul|ol|h1|h2|h3|h4|h5|h6|blockquote|tr|table|br|hr)\b[^>]*>',
      caseSensitive: false,
    ),
    '\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = _decodeHtmlEntities(text);
  return _normalizeImportedText(text);
}

String _normalizeImportedText(String source) {
  return source
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }

  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  return file.content;
}

XmlElement? _findFirstElement(XmlNode node, String localName) {
  for (final element in node.descendants.whereType<XmlElement>()) {
    if (element.name.local.toLowerCase() == localName.toLowerCase()) {
      return element;
    }
  }
  return null;
}

Iterable<XmlElement> _findElements(XmlNode node, String localName) {
  return node.descendants.whereType<XmlElement>().where(
    (element) => element.name.local.toLowerCase() == localName.toLowerCase(),
  );
}

String _normalizeArchivePath(String path) {
  return path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+'), '/')
      .toLowerCase();
}

String _decodeArchivePath(String path) {
  try {
    return Uri.decodeComponent(path);
  } catch (_) {
    return path;
  }
}

String _dirname(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash <= 0) {
    return '';
  }
  return normalized.substring(0, lastSlash);
}

String _resolveArchivePath(String basePath, String relativePath) {
  final rawSegments = <String>[
    if (basePath.isNotEmpty) ...basePath.split('/'),
    ...relativePath.replaceAll('\\', '/').split('/'),
  ];

  final normalizedSegments = <String>[];
  for (final segment in rawSegments) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (normalizedSegments.isNotEmpty) {
        normalizedSegments.removeLast();
      }
      continue;
    }
    normalizedSegments.add(segment);
  }

  return normalizedSegments.join('/').toLowerCase();
}

String _decodeHtmlEntities(String source) {
  return source.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1);
    if (entity == null) {
      return match.group(0) ?? '';
    }

    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final value = int.tryParse(entity.substring(2), radix: 16);
      return value == null ? match.group(0)! : String.fromCharCode(value);
    }

    if (entity.startsWith('#')) {
      final value = int.tryParse(entity.substring(1));
      return value == null ? match.group(0)! : String.fromCharCode(value);
    }

    return _namedEntities[entity] ?? match.group(0)!;
  });
}

const _xmlBlockElements = {
  'section',
  'title',
  'subtitle',
  'p',
  'poem',
  'stanza',
  'v',
  'epigraph',
  'cite',
};

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '-',
  'mdash': '-',
  'hellip': '...',
  'laquo': '"',
  'raquo': '"',
  'lsquo': "'",
  'rsquo': "'",
  'ldquo': '"',
  'rdquo': '"',
};
