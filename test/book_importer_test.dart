import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speedy_pizza/src/book_importer.dart';
import 'package:speedy_pizza/src/text_source_picker_base.dart';

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
===== CAPITOLO 1 =====
Prima parte.

===== CAPITOLO 2 =====
Seconda parte.
'''),
        ),
      ),
    );

    expect(imported.formatLabel, 'PB');
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
===== PROLOGO =====
Intro.

===== PARTE DUE =====
Testo finale.
'''),
        ),
      ),
    );

    expect(imported.formatLabel, 'PB');
    expect(imported.chapterTexts.length, 2);
    expect(imported.chapterTitles, ['PROLOGO', 'PARTE DUE']);
    expect(imported.chapterTexts.first, 'Intro.');
    expect(imported.chapterTexts.last, 'Testo finale.');
  });
}
