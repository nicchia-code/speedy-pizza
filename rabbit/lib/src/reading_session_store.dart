import 'reading_session_store_base.dart';
import 'reading_session_store_stub.dart'
    if (dart.library.html) 'reading_session_store_web.dart';

export 'reading_session_store_base.dart';

ReadingSessionStore createReadingSessionStore() =>
    createPlatformReadingSessionStore();
