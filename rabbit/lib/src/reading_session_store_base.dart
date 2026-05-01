class SavedReadingSession {
  const SavedReadingSession({
    required this.bookName,
    this.bookAuthors = const <String>[],
    this.bookSummary,
    required this.formatLabel,
    required this.bookText,
    required this.chapterTexts,
    required this.chapterTitles,
    this.sectionSingularLabel = 'Capitolo',
    this.sectionPluralLabel = 'Capitoli',
    required this.resumeChapterIndex,
    required this.resumeWordIndex,
    required this.totalWords,
    required this.savedAt,
  });

  final String? bookName;
  final List<String> bookAuthors;
  final String? bookSummary;
  final String? formatLabel;
  final String? bookText;
  final List<String> chapterTexts;
  final List<String> chapterTitles;
  final String sectionSingularLabel;
  final String sectionPluralLabel;
  final int resumeChapterIndex;
  final int? resumeWordIndex;
  final int totalWords;
  final int savedAt;

  Map<String, dynamic> toJson() => {
    'bookName': bookName,
    'bookAuthors': bookAuthors,
    'bookSummary': bookSummary,
    'formatLabel': formatLabel,
    'bookText': bookText,
    'chapterTexts': chapterTexts,
    'chapterTitles': chapterTitles,
    'sectionSingularLabel': sectionSingularLabel,
    'sectionPluralLabel': sectionPluralLabel,
    'resumeChapterIndex': resumeChapterIndex,
    'resumeWordIndex': resumeWordIndex,
    'totalWords': totalWords,
    'savedAt': savedAt,
  };

  static SavedReadingSession? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final rawWordIndex = value['resumeWordIndex'];
    final rawTotalWords = value['totalWords'];
    if (rawTotalWords is! int) {
      return null;
    }

    final rawChapterTexts = value['chapterTexts'];
    final rawChapterTitles = value['chapterTitles'];
    final rawBookAuthors = value['bookAuthors'];
    final chapterTexts = <String>[];
    final chapterTitles = <String>[];
    final bookAuthors = <String>[];

    if (rawChapterTexts is List) {
      for (final item in rawChapterTexts) {
        if (item is String) {
          chapterTexts.add(item);
        }
      }
    }

    if (rawChapterTitles is List) {
      for (final item in rawChapterTitles) {
        if (item is String) {
          chapterTitles.add(item);
        }
      }
    }

    if (rawBookAuthors is List) {
      for (final item in rawBookAuthors) {
        if (item is String && item.trim().isNotEmpty) {
          bookAuthors.add(item.trim());
        }
      }
    }

    if (chapterTexts.isEmpty) {
      if (value['bookText'] is String) {
        chapterTexts.add(value['bookText'] as String);
      }
    }

    final sectionSingularLabel =
        value['sectionSingularLabel'] is String &&
            (value['sectionSingularLabel'] as String).trim().isNotEmpty
        ? (value['sectionSingularLabel'] as String).trim()
        : 'Capitolo';
    final sectionPluralLabel =
        value['sectionPluralLabel'] is String &&
            (value['sectionPluralLabel'] as String).trim().isNotEmpty
        ? (value['sectionPluralLabel'] as String).trim()
        : 'Capitoli';

    if (chapterTitles.isEmpty) {
      chapterTitles.add(sectionSingularLabel);
    }

    return SavedReadingSession(
      bookName: value['bookName'] is String
          ? value['bookName'] as String
          : null,
      bookAuthors: bookAuthors,
      bookSummary: value['bookSummary'] is String
          ? value['bookSummary'] as String
          : null,
      formatLabel: value['formatLabel'] is String
          ? value['formatLabel'] as String
          : null,
      bookText: value['bookText'] is String
          ? value['bookText'] as String
          : null,
      chapterTexts: chapterTexts,
      chapterTitles: chapterTitles,
      sectionSingularLabel: sectionSingularLabel,
      sectionPluralLabel: sectionPluralLabel,
      resumeChapterIndex: value['resumeChapterIndex'] is int
          ? value['resumeChapterIndex'] as int
          : int.tryParse('${value['resumeChapterIndex']}') ?? 0,
      resumeWordIndex: rawWordIndex is int
          ? rawWordIndex
          : int.tryParse('$rawWordIndex'),
      totalWords: rawTotalWords,
      savedAt: value['savedAt'] is int
          ? value['savedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

abstract class ReadingSessionStore {
  Future<void> saveSession(SavedReadingSession? session);
  Future<SavedReadingSession?> loadSession();
}
