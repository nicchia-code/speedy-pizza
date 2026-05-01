import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cinder/src/epub_importer.dart';
import 'package:cinder/src/source_file_picker.dart';

void main() {
  test('imports epub metadata and splits readable spine items', () async {
    final imported = await importEpubFile(
      PickedEpubFile(name: 'libro-test.epub', bytes: _epubBytes()),
    );

    expect(imported.title, 'Libro Test');
    expect(imported.authors, ['Autrice Test']);
    expect(imported.sourceFileName, 'libro-test.epub');
    expect(imported.chapters, hasLength(2));
    expect(imported.chapters[0].index, 1);
    expect(imported.chapters[0].title, 'Capitolo Uno');
    expect(imported.chapters[0].text, contains('Prima frase.'));
    expect(imported.chapters[1].index, 2);
    expect(imported.chapters[1].title, 'Capitolo Due');
    expect(imported.chapters[1].text, contains('Seconda frase.'));
    expect(imported.wordCount, greaterThan(3));
    expect(imported.metadata['importer'], 'cinder_epubx');
  });

  test('rejects non-epub files', () async {
    expect(
      () => importEpubFile(
        PickedEpubFile(
          name: 'sample.txt',
          bytes: Uint8List.fromList(const [65, 66]),
        ),
      ),
      throwsUnsupportedError,
    );
  });
}

Uint8List _epubBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
    )
    ..addFile(
      ArchiveFile.string('OPS/content.opf', '''
<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata>
    <dc:title>Libro Test</dc:title>
    <dc:creator>Autrice Test</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
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
    ..addFile(
      ArchiveFile.string('OPS/nav.xhtml', '''
<html>
  <head><title>Indice</title></head>
  <body>
    <nav>
      <ol>
        <li><a href="chapter1.xhtml">Capitolo Uno</a></li>
        <li><a href="chapter2.xhtml">Capitolo Due</a></li>
      </ol>
    </nav>
  </body>
</html>
'''),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/chapter1.xhtml',
        '<html><body><h1>Capitolo Uno</h1><p>Prima frase.</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OPS/chapter2.xhtml',
        '<html><body><h1>Capitolo Due</h1><p>Seconda frase.</p></body></html>',
      ),
    );

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
