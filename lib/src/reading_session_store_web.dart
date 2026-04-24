import 'dart:convert';
import 'dart:html' as html;

import 'reading_session_store_base.dart';

const _sessionStorageKey = 'speedy_reader_session_v2';

ReadingSessionStore createPlatformReadingSessionStore() =>
    const _WebReadingSessionStore();

class _WebReadingSessionStore implements ReadingSessionStore {
  const _WebReadingSessionStore();

  @override
  Future<void> saveSession(SavedReadingSession? session) async {
    if (session == null) {
      html.window.localStorage.remove(_sessionStorageKey);
      return;
    }

    final encoded = jsonEncode(session.toJson());
    html.window.localStorage[_sessionStorageKey] = encoded;
  }

  @override
  Future<SavedReadingSession?> loadSession() async {
    final raw = html.window.localStorage[_sessionStorageKey];
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      return SavedReadingSession.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
