import 'package:epubx/epubx.dart';

import 'source_file_picker.dart';

const _wordPattern = r"\b[\w']+\b";

class ImportedEpubBook {
  const ImportedEpubBook({
    required this.title,
    required this.authors,
    required this.sourceFileName,
    required this.byteSize,
    required this.chapters,
  });

  final String title;
  final List<String> authors;
  final String sourceFileName;
  final int byteSize;
  final List<ImportedEpubChapter> chapters;

  int get wordCount {
    return chapters.fold(0, (sum, chapter) => sum + chapter.wordCount);
  }

  int get characterCount {
    return chapters.fold(0, (sum, chapter) => sum + chapter.characterCount);
  }

  Map<String, Object?> get metadata {
    return {
      'importer': 'cinder_epubx',
      'source_byte_size': byteSize,
      'chapter_count': chapters.length,
    };
  }
}

class ImportedEpubChapter {
  const ImportedEpubChapter({
    required this.index,
    required this.title,
    required this.text,
  });

  final int index;
  final String title;
  final String text;

  int get wordCount =>
      RegExp(_wordPattern, unicode: true).allMatches(text).length;
  int get characterCount => text.length;
}

Future<ImportedEpubBook> importEpubFile(PickedEpubFile file) async {
  if (file.extension != 'epub') {
    throw UnsupportedError(
      'Formato non supportato: ${file.extension.isEmpty ? file.name : '.${file.extension}'}',
    );
  }

  final epubBook = await EpubReader.readBook(file.bytes);
  final chapters = _extractChapters(epubBook);
  if (chapters.isEmpty) {
    throw const FormatException('EPUB senza capitoli leggibili.');
  }

  return ImportedEpubBook(
    title: _cleanText(epubBook.Title) ?? _titleFromFileName(file.name),
    authors: _authorsFromBook(epubBook),
    sourceFileName: file.name,
    byteSize: file.bytes.length,
    chapters: chapters,
  );
}

List<ImportedEpubChapter> _extractChapters(EpubBook book) {
  final chapters = <ImportedEpubChapter>[];
  final consumedContentFiles = <String>{};

  void appendChapter(EpubChapter chapter) {
    final html = chapter.HtmlContent ?? '';
    final text = _extractMarkupText(html);
    final contentKey = _chapterContentKey(chapter);

    if (text.isNotEmpty &&
        (contentKey == null || consumedContentFiles.add(contentKey))) {
      final index = chapters.length + 1;
      chapters.add(
        ImportedEpubChapter(
          index: index,
          title:
              _cleanText(chapter.Title) ??
              _extractFirstHeading(html) ??
              'Capitolo $index',
          text: text,
        ),
      );
    }

    for (final child in chapter.SubChapters ?? const <EpubChapter>[]) {
      appendChapter(child);
    }
  }

  for (final chapter in book.Chapters ?? const <EpubChapter>[]) {
    appendChapter(chapter);
  }

  if (chapters.isNotEmpty) {
    return chapters;
  }

  return _extractSpineChapters(book);
}

List<ImportedEpubChapter> _extractSpineChapters(EpubBook book) {
  final contentFiles =
      book.Content?.Html ?? const <String, EpubTextContentFile>{};
  if (contentFiles.isEmpty) {
    return const <ImportedEpubChapter>[];
  }

  final chapters = <ImportedEpubChapter>[];
  final consumedContentFiles = <String>{};
  final manifestById = <String, EpubManifestItem>{};
  for (final item
      in book.Schema?.Package?.Manifest?.Items ?? const <EpubManifestItem>[]) {
    final id = _cleanText(item.Id);
    if (id != null) {
      manifestById[id] = item;
    }
  }

  for (final itemRef
      in book.Schema?.Package?.Spine?.Items ?? const <EpubSpineItemRef>[]) {
    if (itemRef.IsLinear == false) {
      continue;
    }
    final idRef = _cleanText(itemRef.IdRef);
    if (idRef == null) {
      continue;
    }

    final manifestItem = manifestById[idRef];
    final href = manifestItem?.Href;
    final content = _contentFileForHref(contentFiles, href);
    if (content == null) {
      continue;
    }

    final contentKey = _normalizeContentFileName(content.FileName ?? href);
    if (contentKey != null && !consumedContentFiles.add(contentKey)) {
      continue;
    }

    final html = content.Content ?? '';
    final text = _extractMarkupText(html);
    if (text.isEmpty) {
      continue;
    }

    final index = chapters.length + 1;
    chapters.add(
      ImportedEpubChapter(
        index: index,
        title: _extractFirstHeading(html) ?? 'Capitolo $index',
        text: text,
      ),
    );
  }

  if (chapters.isNotEmpty) {
    return chapters;
  }

  for (final entry in contentFiles.entries) {
    final content = entry.value;
    final contentKey = _normalizeContentFileName(content.FileName ?? entry.key);
    if (contentKey != null && !consumedContentFiles.add(contentKey)) {
      continue;
    }

    final html = content.Content ?? '';
    final text = _extractMarkupText(html);
    if (text.isEmpty) {
      continue;
    }

    final index = chapters.length + 1;
    chapters.add(
      ImportedEpubChapter(
        index: index,
        title: _extractFirstHeading(html) ?? 'Capitolo $index',
        text: text,
      ),
    );
  }

  return chapters;
}

EpubTextContentFile? _contentFileForHref(
  Map<String, EpubTextContentFile> contentFiles,
  String? href,
) {
  final normalizedHref = _normalizeContentFileName(href);
  if (normalizedHref == null) {
    return null;
  }

  for (final entry in contentFiles.entries) {
    if (_normalizeContentFileName(entry.key) == normalizedHref ||
        _normalizeContentFileName(entry.value.FileName) == normalizedHref) {
      return entry.value;
    }
  }
  return null;
}

List<String> _authorsFromBook(EpubBook book) {
  final result = <String>[];
  final seen = <String>{};

  for (final author in book.AuthorList ?? const <String?>[]) {
    final normalized = _cleanText(author);
    if (normalized == null) {
      continue;
    }
    final key = normalized.toLowerCase();
    if (seen.add(key)) {
      result.add(normalized);
    }
  }

  if (result.isEmpty) {
    final combinedAuthor = _cleanText(book.Author);
    if (combinedAuthor != null) {
      result.add(combinedAuthor);
    }
  }

  return result;
}

String? _chapterContentKey(EpubChapter chapter) {
  return _normalizeContentFileName(chapter.ContentFileName);
}

String? _normalizeContentFileName(String? value) {
  final normalized = _cleanText(value)
      ?.split('#')
      .first
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+'), '/')
      .toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
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
  return _normalizeImportedText(_decodeHtmlEntities(text));
}

String? _extractFirstHeading(String source) {
  final match = RegExp(
    r'<h[1-6]\b[^>]*>([\s\S]*?)</h[1-6]>',
    caseSensitive: false,
  ).firstMatch(source);
  if (match == null) {
    return null;
  }
  return _cleanText(
    _decodeHtmlEntities(
      (match.group(1) ?? '').replaceAll(RegExp(r'<[^>]+>'), ' '),
    ),
  );
}

String _normalizeImportedText(String source) {
  return source
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String? _cleanText(String? value) {
  final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String _titleFromFileName(String fileName) {
  final normalizedPath = fileName.replaceAll('\\', '/');
  final slashIndex = normalizedPath.lastIndexOf('/');
  final baseName = slashIndex == -1
      ? normalizedPath
      : normalizedPath.substring(slashIndex + 1);
  final dotIndex = baseName.lastIndexOf('.');
  final withoutExtension = dotIndex > 0
      ? baseName.substring(0, dotIndex)
      : baseName;
  final cleaned = withoutExtension
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? fileName : cleaned;
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

const _namedEntities = <String, String>{
  'amp': '&',
  'apos': "'",
  'gt': '>',
  'lt': '<',
  'nbsp': ' ',
  'quot': '"',
};
