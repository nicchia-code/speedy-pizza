import 'package:flutter_test/flutter_test.dart';
import 'package:cinder_reading/src/reading_session_store_base.dart';

void main() {
  test('persists book authors in saved reading sessions', () {
    final session = SavedReadingSession(
      bookName: 'Libro',
      bookAuthors: const ['Autrice Test', 'Coautore Test'],
      bookSummary: 'Una descrizione senza spoiler.',
      formatLabel: 'PB',
      bookText: 'Una frase.',
      chapterTexts: const ['Una frase.'],
      chapterTitles: const ['Capitolo 1'],
      sectionSingularLabel: 'Frammento',
      sectionPluralLabel: 'Frammenti',
      resumeChapterIndex: 0,
      resumeWordIndex: 1,
      totalWords: 2,
      savedAt: 123,
    );

    final restored = SavedReadingSession.fromJson(session.toJson());

    expect(restored?.bookAuthors, ['Autrice Test', 'Coautore Test']);
    expect(restored?.bookSummary, 'Una descrizione senza spoiler.');
    expect(restored?.sectionSingularLabel, 'Frammento');
    expect(restored?.sectionPluralLabel, 'Frammenti');
  });
}
