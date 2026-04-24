import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speedy_pizza/main.dart';
import 'package:speedy_pizza/src/reading_session_store_base.dart';
import 'package:speedy_pizza/src/text_source_picker_base.dart';

void main() {
  testWidgets('home shows the Speedy Pizza shell', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedyReaderApp());

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == 'Speedy\nPizza',
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

  testWidgets('loading a file replaces the demo reader text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SpeedyReaderApp(
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
    expect(find.text('Sand'), findsOneWidget);
    expect(find.text('kan'), findsOneWidget);
    expect(find.text('Libro'), findsOneWidget);
  });

  testWidgets('pb v2 opens the book screen with scrollable fragments', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SpeedyReaderApp(
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
      SpeedyReaderApp(
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
