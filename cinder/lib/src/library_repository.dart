import 'package:supabase_flutter/supabase_flutter.dart';

import 'epub_importer.dart';

class CinderUploadedBook {
  const CinderUploadedBook({
    required this.id,
    required this.title,
    required this.chapterCount,
  });

  final String id;
  final String title;
  final int chapterCount;
}

abstract class CinderLibraryRepository {
  Future<CinderUploadedBook> uploadEpubBook(ImportedEpubBook book);
}

class MissingCinderLibraryRepository implements CinderLibraryRepository {
  const MissingCinderLibraryRepository();

  @override
  Future<CinderUploadedBook> uploadEpubBook(ImportedEpubBook book) {
    throw StateError('Supabase non configurato.');
  }
}

class SupabaseCinderLibraryRepository implements CinderLibraryRepository {
  SupabaseCinderLibraryRepository(this._client);

  static const _booksTable = String.fromEnvironment(
    'CINDER_SUPABASE_BOOKS_TABLE',
    defaultValue: 'books',
  );
  static const _chaptersTable = String.fromEnvironment(
    'CINDER_SUPABASE_BOOK_CHAPTERS_TABLE',
    defaultValue: 'book_chapters',
  );

  final SupabaseClient _client;

  @override
  Future<CinderUploadedBook> uploadEpubBook(ImportedEpubBook book) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Accedi prima di caricare un libro.');
    }

    final insertedBook = await _client
        .from(_booksTable)
        .insert({
          'owner_id': user.id,
          'title': book.title,
          'authors': book.authors,
          'source_file_name': book.sourceFileName,
          'format': 'epub',
          'chapter_count': book.chapters.length,
          'word_count': book.wordCount,
          'character_count': book.characterCount,
          'metadata': book.metadata,
        })
        .select('id,title')
        .single();

    final bookId = insertedBook['id']?.toString();
    if (bookId == null || bookId.isEmpty) {
      throw StateError("Supabase non ha restituito l'ID del libro.");
    }

    final rows = [
      for (final chapter in book.chapters)
        {
          'book_id': bookId,
          'owner_id': user.id,
          'position': chapter.index,
          'title': chapter.title,
          'content': chapter.text,
          'word_count': chapter.wordCount,
          'character_count': chapter.characterCount,
        },
    ];
    if (rows.isNotEmpty) {
      await _client.from(_chaptersTable).insert(rows);
    }

    return CinderUploadedBook(
      id: bookId,
      title: insertedBook['title']?.toString() ?? book.title,
      chapterCount: book.chapters.length,
    );
  }
}
