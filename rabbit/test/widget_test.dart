import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinder_reading/main.dart';
import 'package:cinder_reading/src/reading_session_store_base.dart';
import 'package:cinder_reading/src/text_source_picker_base.dart';

const _legacyDemoText = '''
Leggere veloce non vuol dire correre a caso.
Vuol dire ridurre le pause inutili e lasciare che gli occhi seguano un ritmo chiaro.
Questa demo mostra una parola alla volta, con la lettera centrale evidenziata, per mantenere il focus.
''';

void main() {
  testWidgets('home shows the Cinder Reading shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CinderReadingApp());

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Cinder\nReading',
      ),
      findsOneWidget,
    );
    expect(find.text('Ultimo Libro'), findsNothing);
    expect(find.text('Aggiungi contenuto'), findsNothing);
    expect(find.byIcon(Icons.upload_file_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Aggiungi contenuto'), findsOneWidget);
    expect(find.text('Carica ebook'), findsOneWidget);
  });

  testWidgets('loads Alice as the default book', (WidgetTester tester) async {
    final store = _MemoryReadingSessionStore();

    await tester.pumpWidget(CinderReadingApp(sessionStore: store));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Alice Nel Paese Delle Meraviglie'), findsOneWidget);
    expect(find.textContaining('Lewis Carroll'), findsOneWidget);
    expect(store._session?.sectionSingularLabel, 'Frammento');
    expect(store._session?.sectionPluralLabel, 'Frammenti');
  });

  testWidgets('uses the Rabbit reader-only layout on the R1 viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CinderReadingApp(sessionStore: _MemoryReadingSessionStore()),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const ValueKey('rabbit-reader-tab')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-nav-idle')), findsNothing);
    expect(find.byKey(const ValueKey('rabbit-book-tab')), findsNothing);
    expect(find.text('Alice Nel Paese Delle Meraviglie'), findsNothing);
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    expect(find.text('WPM'), findsNothing);
    expect(find.text('ETA'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(find.text('340'), findsOneWidget);
    expect(find.text('WPM'), findsOneWidget);
  });

  testWidgets('double clicking the Rabbit side button opens word navigation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CinderReadingApp(sessionStore: _MemoryReadingSessionStore()),
    );
    await tester.pump(const Duration(milliseconds: 700));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 90));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('rabbit-word-navigator')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('rabbit-word-navigator-selected-0')),
      findsOneWidget,
    );
    expect(find.text('Parole'), findsOneWidget);
    expect(find.text('Carica libro'), findsNothing);
    expect(find.text('Aggiungi contenuto'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const ValueKey('rabbit-word-navigator-selected-1')),
      findsOneWidget,
    );
  });

  testWidgets('replaces a saved demo session with Alice', (
    WidgetTester tester,
  ) async {
    final store = _MemoryReadingSessionStore()
      .._session = SavedReadingSession(
        bookName: null,
        formatLabel: null,
        bookText: _legacyDemoText,
        chapterTexts: const [_legacyDemoText],
        chapterTitles: const ['Demo'],
        resumeChapterIndex: 0,
        resumeWordIndex: 0,
        totalWords: 39,
        savedAt: 123,
      );

    await tester.pumpWidget(CinderReadingApp(sessionStore: store));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Alice Nel Paese Delle Meraviglie'), findsOneWidget);
    expect(find.text('Leg'), findsNothing);
    expect(store._session?.bookName, 'Alice nel paese delle meraviglie');
  });

  testWidgets('the demo action reloads Alice', (WidgetTester tester) async {
    final store = _MemoryReadingSessionStore()
      .._session = SavedReadingSession(
        bookName: 'Libro vecchio',
        formatLabel: 'TXT',
        bookText: 'Sandokan corre verso Mompracem.',
        chapterTexts: const ['Sandokan corre verso Mompracem.'],
        chapterTitles: const ['Capitolo 1'],
        resumeChapterIndex: 0,
        resumeWordIndex: 0,
        totalWords: 4,
        savedAt: 123,
      );

    await tester.pumpWidget(CinderReadingApp(sessionStore: store));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Libro Vecchio'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Usa la demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Alice Nel Paese Delle Meraviglie'), findsOneWidget);
    expect(store._session?.bookName, 'Alice nel paese delle meraviglie');
  });

  testWidgets('loading a file replaces the default reader text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CinderReadingApp(
        textSourcePicker: _FakeTextSourcePicker(
          PickedSourceFile(
            name: 'libro.txt',
            bytes: Uint8List.fromList(
              utf8.encode('Sandokan corre veloce verso Mompracem.'),
            ),
          ),
        ),
        sessionStore: _MemoryReadingSessionStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Carica ebook'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Leg'), findsNothing);
    expect(find.text('Sa'), findsOneWidget);
    expect(find.text('dokan'), findsOneWidget);
    expect(find.text('Libro'), findsOneWidget);
  });

  testWidgets('pb v2 opens the book screen with scrollable fragments', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CinderReadingApp(
        textSourcePicker: _FakeTextSourcePicker(
          PickedSourceFile(
            name: 'frammenti.pb',
            bytes: Uint8List.fromList(utf8.encode(_pbV2WithFragments(20))),
          ),
        ),
        sessionStore: _MemoryReadingSessionStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Carica ebook'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Frammento attivo'), findsOneWidget);
    expect(find.text('Concetto attivo'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Libro'), findsOneWidget);
    expect(find.textContaining('frammenti'), findsWidgets);
    expect(find.text('Capitoli'), findsNothing);

    final listFinder = find.byType(SingleChildScrollView).last;
    await tester.dragUntilVisible(
      find.textContaining('Parte 20'),
      listFinder,
      const Offset(0, -500),
      maxIteration: 20,
    );

    expect(find.textContaining('Parte 20'), findsOneWidget);
  });

  testWidgets('reader navbar shows next at the end of a fragment', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CinderReadingApp(
        textSourcePicker: _FakeTextSourcePicker(
          PickedSourceFile(
            name: 'next.pb',
            bytes: Uint8List.fromList(
              utf8.encode(_pbV2WithSingleWordFragments()),
            ),
          ),
        ),
        sessionStore: _MemoryReadingSessionStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Carica ebook'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('D'), findsOneWidget);
    expect(find.text('e'), findsOneWidget);
  });
}

String _pbV2WithFragments(int count) {
  final buffer = StringBuffer('''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 2,
  "title": "Libro Spezzato",
  "authors": ["Autrice"],
  "spoiler_free_summary": "Una descrizione breve.",
  "chapter_count": 1,
  "concept_count": $count
}
;;;PB-METADATA-END;;;

===== CHAPTER 001: Libro Spezzato =====
''');

  for (var index = 1; index <= count; index += 1) {
    buffer.writeln();
    buffer.writeln(
      '----- CONCEPT 001.${index.toString().padLeft(3, '0')}: Parte $index -----',
    );
    buffer.writeln('Parola$index corre nel frammento numero $index.');
  }

  return buffer.toString();
}

String _pbV2WithSingleWordFragments() {
  return '''
;;;PB-METADATA-BEGIN;;;
{
  "metadata_version": 2,
  "title": "Libro Next",
  "authors": ["Autrice"],
  "spoiler_free_summary": "Una descrizione breve.",
  "chapter_count": 1,
  "concept_count": 2
}
;;;PB-METADATA-END;;;

===== CHAPTER 001: Libro Next =====

----- CONCEPT 001.001: Uno -----
Uno

----- CONCEPT 001.002: Due -----
Due
''';
}

class _FakeTextSourcePicker implements TextSourcePicker {
  const _FakeTextSourcePicker(this.file);

  final PickedSourceFile file;

  @override
  Future<PickedSourceFile?> pickTextFile() async => file;
}

class _MemoryReadingSessionStore implements ReadingSessionStore {
  SavedReadingSession? _session;

  @override
  Future<SavedReadingSession?> loadSession() async => _session;

  @override
  Future<void> saveSession(SavedReadingSession? session) async {
    _session = session;
  }
}
