import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cinder_reading/src/book_importer.dart';
import 'package:cinder_reading/src/text_source_picker_base.dart';

void main() {
  test('imports plain text files', () async {
    final imported = await importBook(
      PickedSourceFile(
        name: 'sample.txt',
        bytes: Uint8List.fromList(utf8.encode('Uno\n\nDue')),
      ),
    );

    expect(imported.formatLabel, 'TXT');
    expect(imported.text, 'Uno\n\nDue');
  });

  test('imports epub spine content in order', () async {
    final archive = Archive()
      ..add(
        ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
      )
      ..add(
        ArchiveFile.string('OPS/content.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf">
  <manifest>
    <item id="chapter-1" href="chapter1.xhtml" media-type="application/xhtml+xml" />
    <item id="chapter-2" href="chapter2.xhtml" media-type="application/xhtml+xml" />
  </manifest>
  <spine>
    <itemref idref="chapter-1" />
    <itemref idref="chapter-2" />
  </spine>
</package>
'''),
      )
      ..add(
        ArchiveFile.string(
          'OPS/chapter1.xhtml',
          '<html><body><h1>Capitolo Uno</h1><p>Prima frase.</p></body></html>',
        ),
      )
      ..add(
        ArchiveFile.string(
          'OPS/chapter2.xhtml',
          '<html><body><p>Seconda frase.</p></body></html>',
        ),
      );

    final imported = await importBook(
      PickedSourceFile(
        name: 'book.epub',
        bytes: Uint8List.fromList(ZipEncoder().encodeBytes(archive)),
      ),
    );

    expect(imported.formatLabel, 'EPUB');
    expect(imported.text, contains('Capitolo Uno'));
    expect(imported.text, contains('Prima frase.'));
    expect(imported.text, contains('Seconda frase.'));
    expect(
      imported.text.indexOf('Prima frase.') <
          imported.text.indexOf('Seconda frase.'),
      isTrue,
    );
  });

  test('imports pb files and splits chapters by markers', () async {
    final imported = await importBook(
      PickedSourceFile(
        name: 'book.pb',
        bytes: Uint8List.fromList(
          utf8.encode('''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 1,
  "title": "Libro Test",
  "authors": ["Autore Test"],
  "spoiler_free_summary": "Una descrizione senza spoiler."
}
;;;PB-METADATA-END;;;

===== CAPITOLO 1 =====
Prima parte.

===== CAPITOLO 2 =====
Seconda parte.
'''),
        ),
      ),
    );

    expect(imported.formatLabel, 'PB');
    expect(imported.name, 'Libro Test');
    expect(imported.authors, ['Autore Test']);
    expect(imported.spoilerFreeSummary, 'Una descrizione senza spoiler.');
    expect(imported.chapterTexts.length, 2);
    expect(imported.chapterTitles, ['CAPITOLO 1', 'CAPITOLO 2']);
    expect(imported.text, contains('Prima parte.'));
    expect(imported.text, contains('Seconda parte.'));
  });

  test('imports pb files with generic ===== markers', () async {
    final imported = await importBook(
      PickedSourceFile(
        name: 'generic.pb',
        bytes: Uint8List.fromList(
          utf8.encode('''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 1,
  "title": "Libro Generico",
  "authors": ["Autrice"],
  "spoiler_free_summary": "Una descrizione breve."
}
;;;PB-METADATA-END;;;

===== PROLOGO =====
Intro.

===== PARTE DUE =====
Testo finale.
'''),
        ),
      ),
    );

    expect(imported.formatLabel, 'PB');
    expect(imported.name, 'Libro Generico');
    expect(imported.chapterTexts.length, 2);
    expect(imported.chapterTitles, ['PROLOGO', 'PARTE DUE']);
    expect(imported.chapterTexts.first, 'Intro.');
    expect(imported.chapterTexts.last, 'Testo finale.');
  });

  test('imports pb v2 concepts as reader sections', () async {
    final imported = await importBook(
      PickedSourceFile(
        name: 'concepts.pb',
        bytes: Uint8List.fromList(
          utf8.encode('''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 2,
  "title": "Libro a concetti",
  "authors": ["Autrice"],
  "spoiler_free_summary": "Una descrizione breve.",
  "chapter_count": 1,
  "concept_count": 2,
  "chapters": [
    {
      "index": 1,
      "title": "Le nozze di Sandokan",
      "concept_count": 2,
      "concepts": [
        {"index": 1, "global_index": 1, "title": "Ingresso", "word_count": 320},
        {"index": 2, "global_index": 2, "title": "Decisione", "word_count": 340}
      ]
    }
  ]
}
;;;PB-METADATA-END;;;

===== CHAPTER 001: Le nozze di Sandokan =====

----- CONCEPT 001.001: Ingresso -----
Prima parte del testo reale.

----- CONCEPT 001.002: Decisione -----
Seconda parte del testo reale.
'''),
        ),
      ),
    );

    expect(imported.formatLabel, 'PB');
    expect(imported.name, 'Libro a concetti');
    expect(imported.sectionSingularLabel, 'Frammento');
    expect(imported.sectionPluralLabel, 'Frammenti');
    expect(imported.chapterTitles, [
      'Le nozze di Sandokan - Ingresso',
      'Le nozze di Sandokan - Decisione',
    ]);
    expect(imported.chapterTexts, [
      'Prima parte del testo reale.',
      'Seconda parte del testo reale.',
    ]);
    expect(imported.text, isNot(contains('CONCEPT 001.001')));
    expect(imported.text, isNot(contains('CHAPTER 001')));
  });

  test('rejects pb files without current metadata', () async {
    expect(
      () => importBook(
        PickedSourceFile(
          name: 'legacy.pb',
          bytes: Uint8List.fromList(
            utf8.encode('''
===== CAPITOLO 1 =====
Prima parte.
'''),
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test('imports pb metadata title and authors', () async {
    final imported = await importBook(
      PickedSourceFile(
        name: 'metadata.pb',
        bytes: Uint8List.fromList(
          utf8.encode('''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 1,
  "title": "Libro dai metadata",
  "authors": ["Autrice Test", "Coautore Test"],
  "spoiler_free_summary": "Una descrizione senza spoiler del libro."
}
;;;PB-METADATA-END;;;

===== PRIMO =====
Contenuto.
'''),
        ),
      ),
    );

    expect(imported.name, 'Libro dai metadata');
    expect(imported.formatLabel, 'PB');
    expect(imported.authors, ['Autrice Test', 'Coautore Test']);
    expect(
      imported.spoilerFreeSummary,
      'Una descrizione senza spoiler del libro.',
    );
    expect(imported.metadata['authors'], ['Autrice Test', 'Coautore Test']);
    expect(imported.chapterTitles, ['PRIMO']);
    expect(imported.chapterTexts, ['Contenuto.']);
  });
}
