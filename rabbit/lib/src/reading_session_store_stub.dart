import 'reading_session_store_base.dart';

ReadingSessionStore createPlatformReadingSessionStore() =>
    const _NoopReadingSessionStore();

class _NoopReadingSessionStore implements ReadingSessionStore {
  const _NoopReadingSessionStore();

  @override
  Future<void> saveSession(SavedReadingSession? session) async {}

  @override
  Future<SavedReadingSession?> loadSession() async => null;
}
