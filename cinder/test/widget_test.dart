import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinder/main.dart';
import 'package:cinder/src/epub_importer.dart';
import 'package:cinder/src/library_repository.dart';
import 'package:cinder/src/source_file_picker.dart';

void main() {
  testWidgets('shows branded boot screen before the home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CinderApp());

    expect(find.text('Cinder'), findsOneWidget);
    expect(find.byKey(const ValueKey('cinder-logo-loading')), findsOneWidget);
    expect(find.text('Rabbit companion'), findsNothing);
    expect(find.text('Reader'), findsNothing);
    expect(find.text('Accensione'), findsNothing);
    expect(find.text('Caricamento'), findsNothing);
    expect(find.text('Pronto'), findsNothing);
    expect(find.text('Configura Supabase'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byKey(const ValueKey('send-email-code-button')), findsNothing);
    expect(find.byKey(const ValueKey('open-library-button')), findsNothing);

    await _finishBoot(tester);

    expect(find.byKey(const ValueKey('cinder-logo-loading')), findsNothing);
    expect(find.text('Cinder'), findsOneWidget);
    expect(find.text('Rabbit companion'), findsOneWidget);
    expect(find.text('Companion'), findsOneWidget);
    expect(find.text('Reader'), findsNothing);
    expect(find.text('Configura Supabase'), findsOneWidget);
    expect(find.textContaining('CINDER_SUPABASE_URL'), findsWidgets);
  });

  testWidgets('requires passwordless email login before opening the library', (
    WidgetTester tester,
  ) async {
    final authController = _FakeAuthController();
    final sourcePicker = _FakeSourcePicker();
    final libraryRepository = _FakeLibraryRepository();

    await tester.pumpWidget(
      CinderApp(
        authController: authController,
        sourcePicker: sourcePicker,
        libraryRepository: libraryRepository,
      ),
    );
    await _finishBoot(tester);

    expect(find.text('Accedi al companion'), findsOneWidget);
    expect(find.text('Invia codice'), findsOneWidget);
    expect(find.byKey(const ValueKey('signed-in-email-label')), findsNothing);
    expect(find.byKey(const ValueKey('upload-book-button')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('email-login-email-field')),
      'reader@example.com',
    );
    await tester.tap(find.byKey(const ValueKey('send-email-code-button')));
    await tester.pump();

    expect(authController.codeRequestCount, 1);
    expect(find.text('Verifica codice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('email-login-code-field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('email-login-code-field')),
      '123456',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('verify-email-code-button')),
    );
    await tester.tap(find.byKey(const ValueKey('verify-email-code-button')));
    await tester.pump();

    expect(authController.verifyCount, 1);
    expect(find.byKey(const ValueKey('signed-in-email-label')), findsOneWidget);
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(find.textContaining('Connesso come'), findsNothing);
    expect(find.textContaining('libreria Cinder'), findsNothing);
    expect(find.byKey(const ValueKey('upload-book-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-player-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('fullscreen-reader-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('upload-book-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(sourcePicker.pickCount, 1);
    expect(libraryRepository.uploadedBook?.title, 'Libro Test');
    expect(libraryRepository.uploadedBook?.chapters.length, 2);
    expect(find.textContaining('Libro caricato: Libro Test'), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-player-view')), findsNothing);
  });
}

Future<void> _finishBoot(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 301));
}

class _FakeAuthController extends CinderAuthController {
  int codeRequestCount = 0;
  int verifyCount = 0;
  CinderUser? _currentUser;
  bool _isAwaitingEmailCode = false;
  String? _pendingEmail;

  @override
  bool get isConfigured => true;

  @override
  bool get isBusy => false;

  @override
  bool get isAwaitingEmailCode => _isAwaitingEmailCode;

  @override
  CinderUser? get currentUser => _currentUser;

  @override
  String? get errorMessage => null;

  @override
  String? get noticeMessage => null;

  @override
  String? get pendingEmail => _pendingEmail;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestEmailCode(String email) async {
    codeRequestCount += 1;
    _pendingEmail = email;
    _isAwaitingEmailCode = true;
    notifyListeners();
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    verifyCount += 1;
    _isAwaitingEmailCode = false;
    _pendingEmail = null;
    _currentUser = CinderUser(email: email);
    notifyListeners();
  }
}

class _FakeSourcePicker implements CinderSourcePicker {
  int pickCount = 0;

  @override
  Future<PickedEpubFile?> pickEpubFile() async {
    pickCount += 1;
    return PickedEpubFile(name: 'libro-test.epub', bytes: _epubBytes());
  }
}

class _FakeLibraryRepository implements CinderLibraryRepository {
  ImportedEpubBook? uploadedBook;

  @override
  Future<CinderUploadedBook> uploadEpubBook(ImportedEpubBook book) async {
    uploadedBook = book;
    return CinderUploadedBook(
      id: 'book-1',
      title: book.title,
      chapterCount: book.chapters.length,
    );
  }
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
