class SavedReadingSession {
  const SavedReadingSession({
    required this.bookName,
    required this.formatLabel,
    required this.bookText,
    required this.chapterTexts,
    required this.chapterTitles,
    required this.resumeChapterIndex,
    required this.resumeWordIndex,
    required this.totalWords,
    required this.savedAt,
  });

  final String? bookName;
  final String? formatLabel;
  final String? bookText;
  final List<String> chapterTexts;
  final List<String> chapterTitles;
  final int resumeChapterIndex;
  final int? resumeWordIndex;
  final int totalWords;
  final int savedAt;

  Map<String, dynamic> toJson() => {
    'bookName': bookName,
    'formatLabel': formatLabel,
    'bookText': bookText,
    'chapterTexts': chapterTexts,
    'chapterTitles': chapterTitles,
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
    final chapterTexts = <String>[];
    final chapterTitles = <String>[];

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

    if (chapterTexts.isEmpty) {
      if (value['bookText'] is String) {
        chapterTexts.add(value['bookText'] as String);
      }
    }

    if (chapterTitles.isEmpty) {
      chapterTitles.add('Capitolo');
    }

    return SavedReadingSession(
      bookName: value['bookName'] is String
          ? value['bookName'] as String
          : null,
      formatLabel: value['formatLabel'] is String
          ? value['formatLabel'] as String
          : null,
      bookText: value['bookText'] is String
          ? value['bookText'] as String
          : null,
      chapterTexts: chapterTexts,
      chapterTitles: chapterTitles,
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
