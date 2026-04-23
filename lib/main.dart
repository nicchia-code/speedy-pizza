import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'src/book_importer.dart';
import 'src/reading_session_store.dart';
import 'src/text_source_picker.dart';
import 'src/text_source_picker_base.dart';

const _bgTop = Color(0xFFFFF4E8);
const _bgBottom = Color(0xFFF1E3D5);
const _panel = Color(0xFFFFFBF7);
const _panelBorder = Color(0xFFE7D6C8);
const _ink = Color(0xFF211A16);
const _muted = Color(0xFF726158);
const _accent = Color(0xFFE4542D);
const _accentSoft = Color(0xFFFFE1D6);
const _track = Color(0xFFE7D9CE);

const _demoText = '''
Leggere veloce non vuol dire correre a caso.
Vuol dire ridurre le pause inutili e lasciare che gli occhi seguano un ritmo chiaro.
Questa demo mostra una parola alla volta, con la lettera centrale evidenziata, per mantenere il focus.
''';

void main() {
  runApp(const SpeedyReaderApp());
}

enum _AppTab { home, reader }

class SpeedyReaderApp extends StatelessWidget {
  const SpeedyReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.light,
      surface: _panel,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Speedy Reader',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: _ink,
          displayColor: _ink,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7EFE8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _panelBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _panelBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: _accent, width: 1.4),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _accent,
          inactiveTrackColor: _track,
          thumbColor: _accent,
          overlayColor: _accent.withValues(alpha: 0.12),
          valueIndicatorColor: _ink,
          valueIndicatorTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: const ReaderPage(),
    );
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(
    text: _demoText,
  );
  final TextEditingController _draftTextController = TextEditingController();
  final TextEditingController _resumeController = TextEditingController(
    text: '1',
  );
  final TextSourcePicker _textSourcePicker = createTextSourcePicker();
  final ReadingSessionStore _sessionStore = createReadingSessionStore();

  late final Ticker _ticker;

  List<String> _words = _tokenize(_demoText);
  List<String> _chapterTexts = const [_demoText];
  List<String> _chapterTitles = const ['Demo'];
  int _activeChapterIndex = 0;
  int _currentWordIndex = 0;
  int _playbackStartIndex = 0;
  double _wordsPerMinute = 320;
  bool _isPlaying = false;
  bool _showCompactSpeedSlider = false;
  _AppTab _activeTab = _AppTab.home;
  String? _loadedFileName;
  String? _loadedFormatLabel;
  String _statusMessage =
      'Demo pronta. Incolla il testo oppure carica un ebook.';

  bool get _hasWords => _words.isNotEmpty;

  String get _currentWord => _hasWords ? _words[_currentWordIndex] : 'Pronto';

  double get _progress {
    if (!_hasWords) {
      return 0;
    }
    return (_currentWordIndex + 1) / _words.length;
  }

  int get _remainingWords {
    if (!_hasWords) {
      return 0;
    }
    return _words.length - (_currentWordIndex + 1);
  }

  double get _microsecondsPerWord => 60000000 / _wordsPerMinute;

  String get _etaLabel {
    if (!_hasWords) {
      return '--';
    }

    final seconds = ((_remainingWords / _wordsPerMinute) * 60).ceil();
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (minutes == 0) {
      return '${remainingSeconds}s';
    }

    return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  String get _activeChapterLabel {
    if (_chapterTitles.isEmpty) {
      return 'Capitolo ${_activeChapterIndex + 1}';
    }

    final safeIndex = _clampChapterIndex(
      _activeChapterIndex,
      _chapterTitles.length,
    );
    final title = _chapterTitles[safeIndex].trim();
    if (title.isEmpty) {
      return 'Capitolo ${safeIndex + 1}';
    }
    return title;
  }

  String get _activeSourceLabel => _prettifySourceName(_loadedFileName);

  bool get _hasImportedSource => _loadedFileName != null;

  String get _resumePointLabel => _hasWords ? '${_currentWordIndex + 1}' : '--';

  String _prettifySourceName(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) {
      return 'Demo';
    }

    final withoutExtension = rawName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final normalized = withoutExtension
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return 'Demo';
    }

    return normalized
        .split(' ')
        .map((token) => token.isEmpty ? token : _capitalizeToken(token))
        .join(' ');
  }

  String _capitalizeToken(String token) {
    final lower = token.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    _log('initState: reader ready');
    _restoreSession();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[SpeedyReader][ReaderPage] $message');
    }
  }

  @override
  void dispose() {
    _saveCurrentSession();
    _ticker.dispose();
    _textController.dispose();
    _draftTextController.dispose();
    _resumeController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    _log('restoreSession: load start');
    final session = await _sessionStore.loadSession();
    if (!mounted || session == null) {
      _log('restoreSession: nothing to restore');
      return;
    }

    final chapterTexts = _coerceChapterTexts(session.chapterTexts);
    final chapterTitles = _coerceChapterTitles(
      session.chapterTitles,
      chapterTexts.length,
    );
    final chapterIndex = _clampChapterIndex(
      session.resumeChapterIndex,
      chapterTexts.length,
    );

    if (chapterTexts.isEmpty) {
      _log('restoreSession: no chapter texts in storage');
      return;
    }

    _chapterTexts = chapterTexts;
    _chapterTitles = chapterTitles;
    _activeChapterIndex = chapterIndex;

    final words = _tokenize(chapterTexts[chapterIndex]);
    if (words.isEmpty) {
      _log('restoreSession: saved text has no words');
      return;
    }

    final restoredIndex = _clampResumeIndex(
      session.resumeWordIndex ?? 0,
      words.length,
    );

    _textController.text = chapterTexts[chapterIndex];
    _draftTextController.clear();
    _loadedFileName = session.bookName ?? 'Ultimo libro';
    _loadedFormatLabel = session.formatLabel;
    _resumeController.text = (restoredIndex + 1).toString();
    _log(
      'restoreSession: '
      'book=${_loadedFileName}, format=${_loadedFormatLabel ?? 'unknown'}, '
      'index=${restoredIndex + 1}/${words.length}',
    );
    _prepareText(
      message:
          'Ripristinata sessione precedente (${_loadedFileName}). Capitolo '
          '${_activeChapterIndex + 1}/${_chapterTexts.length}, '
          'posizione ${restoredIndex + 1} / ${words.length}.',
      initialIndex: restoredIndex,
      keepChapterContext: true,
    );
  }

  int _clampChapterIndex(int index, int length) {
    if (length <= 0) {
      return 0;
    }
    return index.clamp(0, length - 1);
  }

  List<String> _coerceChapterTexts(List<String>? input) {
    if (input == null || input.isEmpty) {
      return [];
    }

    final normalized = input
        .map((text) => _normalizeText(text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);

    if (normalized.isEmpty) {
      return [];
    }

    return normalized;
  }

  List<String> _coerceChapterTitles(List<String> input, int count) {
    final result = <String>[];
    for (var index = 0; index < count; index += 1) {
      final title = index < input.length && input[index].trim().isNotEmpty
          ? input[index].trim()
          : 'Capitolo ${index + 1}';
      result.add(title);
    }
    return result;
  }

  String _normalizeText(String source) {
    return source
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  int _clampResumeIndex(int index, int wordsLength) {
    if (wordsLength <= 0) {
      return 0;
    }
    return index.clamp(0, wordsLength - 1);
  }

  Future<void> _saveCurrentSession() async {
    if (!_hasWords) {
      _log('saveCurrentSession: skipped (no words)');
      return;
    }
    _log(
      'saveCurrentSession: position=${_currentWordIndex + 1}/${_words.length}',
    );
    await _sessionStore.saveSession(
      SavedReadingSession(
        bookName: _loadedFileName,
        formatLabel: _loadedFormatLabel,
        chapterTexts: _chapterTexts,
        chapterTitles: _chapterTitles,
        resumeChapterIndex: _activeChapterIndex,
        bookText: _textController.text,
        resumeWordIndex: _currentWordIndex,
        totalWords: _words.length,
        savedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _handleTick(Duration elapsed) {
    if (!_hasWords) {
      return;
    }

    final advancedWords = (elapsed.inMicroseconds / _microsecondsPerWord)
        .floor();
    final nextIndex = (_playbackStartIndex + advancedWords)
        .clamp(0, _words.length - 1)
        .toInt();
    final reachedEnd = nextIndex >= _words.length - 1;

    if (nextIndex == _currentWordIndex && !reachedEnd) {
      return;
    }

    final shouldPersist =
        nextIndex != _currentWordIndex && (nextIndex % 5 == 0 || reachedEnd);

    setState(() {
      _currentWordIndex = nextIndex;
      if (reachedEnd) {
        _isPlaying = false;
        _statusMessage = 'Fine del testo. Premi Restart per ricominciare.';
      }
    });

    if (shouldPersist) {
      _saveCurrentSession();
    }

    if (reachedEnd) {
      _ticker.stop();
    }
  }

  Future<void> _pickTextFile() async {
    _log('pickTextFile: user action start');
    setState(() {
      _statusMessage = 'Caricamento file in corso...';
    });
    try {
      final pickedFile = await _textSourcePicker.pickTextFile();
      if (!mounted || pickedFile == null) {
        _log('pickTextFile: no file selected');
        if (!mounted) {
          return;
        }
        return;
      }
      _log(
        'pickTextFile: picked ${pickedFile.name} '
        '(${pickedFile.bytes.length} bytes)',
      );

      final importedBook = await importBook(pickedFile);
      _log(
        'pickTextFile: imported ${importedBook.name} as '
        '${importedBook.formatLabel} (${importedBook.text.length} chars), '
        'chapters=${importedBook.chapterTexts.length}',
      );
      _loadBookChapters(importedBook);
      final importedWords = _tokenize(importedBook.text);
      if (importedWords.isEmpty) {
        _log('pickTextFile: tokenized empty text');
        setState(() {
          _statusMessage =
              'Caricato ${importedBook.name}, ma non ho trovato parole leggibili nel file.';
        });
        return;
      }

      if (!mounted) {
        return;
      }
      _log('pickTextFile: loaded ${importedWords.length} words');
      _log('pickTextFile: auto save session after load');

      final chapterCount = importedBook.chapterTexts.length;
      final loadedMessage = chapterCount > 1
          ? 'Caricato ${importedBook.name} (${importedBook.formatLabel}) con $chapterCount capitoli.'
          : 'Caricato ${importedBook.name} (${importedBook.formatLabel}). ${importedWords.length} parole pronte.';
      _prepareText(message: loadedMessage, keepChapterContext: true);
      setState(() {
        _activeTab = _AppTab.reader;
      });
      _saveCurrentSession();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _log('pickTextFile: failed with $error');
      setState(() {
        _statusMessage = 'Import fallito: $error';
      });
    } finally {
      if (!mounted) {
        return;
      }
      if (_statusMessage == 'Caricamento file in corso...') {
        setState(() {
          _statusMessage = 'Nessun file selezionato.';
        });
      }
      _log('pickTextFile: finished with status=${_statusMessage}');
    }
  }

  void _loadDemoText() {
    _textController.text = _demoText;
    _draftTextController.clear();
    _chapterTexts = const [_demoText];
    _chapterTitles = const ['Demo'];
    _activeChapterIndex = 0;
    _loadedFileName = null;
    _loadedFormatLabel = null;
    _resumeController.text = '1';
    _prepareText(
      message: 'Demo ricaricata. La lettera centrale resta ancorata al centro.',
      keepChapterContext: true,
    );
    setState(() {
      _activeTab = _AppTab.reader;
    });
  }

  void _loadBookChapters(ImportedBook importedBook) {
    final chapters = importedBook.chapterTexts
        .map(_normalizeText)
        .where((text) => text.isNotEmpty)
        .toList();
    final titles = _coerceChapterTitles(
      importedBook.chapterTitles,
      chapters.isNotEmpty ? chapters.length : 1,
    );

    _chapterTexts = chapters.isNotEmpty
        ? chapters
        : [_normalizeText(importedBook.text)];

    if (_chapterTexts.isEmpty) {
      _chapterTexts = const [''];
    }

    _chapterTitles = titles.length == _chapterTexts.length
        ? titles
        : _coerceChapterTitles(titles, _chapterTexts.length);
    _activeChapterIndex = _chapterTexts.length > 1 ? 0 : 0;
    _loadedFileName = importedBook.name;
    _loadedFormatLabel = importedBook.formatLabel;
    _textController.text = _chapterTexts[_activeChapterIndex];
    _draftTextController.clear();
  }

  void _loadDraftText() {
    final normalized = _normalizeText(_draftTextController.text);
    if (normalized.isEmpty) {
      setState(() {
        _statusMessage =
            'Testo vuoto. Incolla qualcosa prima di preparare il reader.';
      });
      return;
    }

    _textController.text = normalized;
    _chapterTexts = [normalized];
    _chapterTitles = const ['Testo'];
    _activeChapterIndex = 0;
    _loadedFileName = 'Testo incollato';
    _loadedFormatLabel = 'Testo';
    _prepareText(
      message:
          '${_tokenize(normalized).length} parole pronte dal testo incollato.',
      keepChapterContext: true,
    );
    setState(() {
      _activeTab = _AppTab.reader;
    });
  }

  void _prepareText({
    String? message,
    int? initialIndex,
    bool keepChapterContext = false,
  }) {
    if (_ticker.isActive) {
      _ticker.stop();
    }

    if (!keepChapterContext) {
      final normalized = _normalizeText(_textController.text);
      _chapterTexts = normalized.isEmpty ? const [''] : [normalized];
      _chapterTitles = const ['Testo'];
      _activeChapterIndex = 0;
    }

    final words = _tokenize(_textController.text);
    final startIndex = words.isEmpty
        ? 0
        : _clampResumeIndex(initialIndex ?? 0, words.length);

    setState(() {
      _words = words;
      _currentWordIndex = startIndex;
      _resumeController.text = words.isNotEmpty ? '${startIndex + 1}' : '';
      _isPlaying = false;
      _statusMessage =
          message ??
          (words.isEmpty
              ? 'Nessuna parola trovata. Formati supportati: EPUB, FB2, TXT, MD, HTML, PB.'
              : '${words.length} parole pronte. Premi Play per iniziare.');
    });

    _saveCurrentSession();
  }

  void _selectChapter(int chapterIndex) {
    if (_chapterTexts.isEmpty) {
      return;
    }

    final targetIndex = _clampChapterIndex(chapterIndex, _chapterTexts.length);
    if (targetIndex == _activeChapterIndex && _hasWords) {
      return;
    }

    if (_ticker.isActive) {
      _ticker.stop();
    }

    _activeChapterIndex = targetIndex;
    _textController.text = _chapterTexts[targetIndex];
    final title = _chapterTitles[targetIndex];
    _prepareText(
      message: 'Capitolo ${targetIndex + 1}: $title selezionato.',
      initialIndex: 0,
      keepChapterContext: true,
    );
  }

  void _setResumeFromCurrent() {
    if (!_hasWords) {
      return;
    }
    _resumeController.text = (_currentWordIndex + 1).toString();
    setState(() {
      _statusMessage =
          'Numero di ripresa impostato: ${_resumeController.text}. Copialo e riparti da qui.';
    });
    _saveCurrentSession();
  }

  void _resumeFromInput() {
    if (!_hasWords) {
      return;
    }

    final parsed = int.tryParse(_resumeController.text.trim());
    if (parsed == null) {
      setState(() {
        _statusMessage =
            'Numero di ripresa non valido. Inserisci un numero tra 1 e ${_words.length}.';
      });
      return;
    }

    final targetIndex = (parsed - 1).clamp(0, _words.length - 1);
    if (targetIndex != parsed - 1) {
      _resumeController.text = (targetIndex + 1).toString();
      setState(() {
        _statusMessage =
            'Numero fuori range. Usato automaticamente ${targetIndex + 1}.';
      });
    }

    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _currentWordIndex = targetIndex.toInt();
      _isPlaying = false;
      _activeTab = _AppTab.reader;
      _statusMessage = 'Ripreso da ${targetIndex + 1} / ${_words.length}.';
    });
    _saveCurrentSession();
  }

  void _startPlayback() {
    if (!_hasWords) {
      _prepareText();
      return;
    }

    if (_ticker.isActive) {
      _ticker.stop();
    }

    if (_currentWordIndex >= _words.length - 1) {
      _currentWordIndex = 0;
    }

    _playbackStartIndex = _currentWordIndex;
    _ticker.start();

    setState(() {
      _isPlaying = true;
      _statusMessage = 'Lettura attiva a ${_wordsPerMinute.round()} WPM.';
    });
  }

  void _pausePlayback() {
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _isPlaying = false;
      _statusMessage = _hasWords
          ? 'In pausa su ${_currentWordIndex + 1} / ${_words.length}.'
          : 'Reader in pausa.';
    });
    _saveCurrentSession();
  }

  void _togglePlayback() {
    if (_activeTab != _AppTab.reader) {
      setState(() {
        _activeTab = _AppTab.reader;
      });
    }
    if (_isPlaying) {
      _pausePlayback();
      return;
    }
    _startPlayback();
  }

  void _restartPlayback() {
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _currentWordIndex = 0;
      _isPlaying = false;
      _statusMessage = 'Reader riportato all inizio.';
    });
    _saveCurrentSession();
  }

  void _skipWords(int delta) {
    if (!_hasWords) {
      return;
    }

    final shouldResume = _isPlaying;
    if (_ticker.isActive) {
      _ticker.stop();
    }

    final nextIndex = (_currentWordIndex + delta)
        .clamp(0, _words.length - 1)
        .toInt();

    setState(() {
      _currentWordIndex = nextIndex;
      _isPlaying = false;
      _statusMessage = 'Posizione ${nextIndex + 1} / ${_words.length}.';
      _resumeController.text = (nextIndex + 1).toString();
    });
    _saveCurrentSession();

    if (shouldResume) {
      _startPlayback();
    }
  }

  void _setSpeed(double value) {
    final shouldResume = _isPlaying;
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _wordsPerMinute = value;
      _isPlaying = false;
      _statusMessage = 'Velocita impostata a ${value.round()} WPM.';
    });

    if (shouldResume) {
      _startPlayback();
    }
  }

  Future<void> _openAddContentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        return _buildSheetFrame(
          context: sheetContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aggiungi contenuto',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Importa un ebook, incolla un estratto oppure apri la demo. Da qui in poi il reader resta la vista principale.',
                style: textTheme.bodyLarge?.copyWith(
                  color: _muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _QuickActionTile(
                icon: Icons.upload_file_rounded,
                title: 'Carica ebook',
                subtitle: 'EPUB, FB2, TXT, MD, HTML, PB',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickTextFile();
                },
              ),
              const SizedBox(height: 12),
              _QuickActionTile(
                icon: Icons.notes_rounded,
                title: 'Incolla testo',
                subtitle: 'Per estratti, articoli o testi veloci',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openPasteTextSheet();
                },
              ),
              const SizedBox(height: 12),
              _QuickActionTile(
                icon: Icons.auto_stories_rounded,
                title: 'Usa la demo',
                subtitle: 'Riparti subito con il testo di esempio',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _loadDemoText();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPasteTextSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        return _buildSheetFrame(
          context: sheetContext,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Incolla testo',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Questo testo diventa una sessione dedicata e viene salvato come contenuto separato.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: _muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _draftTextController,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: 'Testo',
                    alignLabelWithHint: true,
                    hintText: 'Incolla qui il testo da preparare.',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        _loadDraftText();
                        Navigator.of(sheetContext).pop();
                      },
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Prepara reader'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _draftTextController.clear();
                      },
                      icon: const Icon(Icons.clear_rounded),
                      label: const Text('Svuota'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openChapterSheet() async {
    if (_chapterTexts.length <= 1) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        return _buildSheetFrame(
          context: sheetContext,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Capitoli',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Salta subito in un altro punto del libro. Le statistiche restano riferite al capitolo attivo.',
                style: textTheme.bodyLarge?.copyWith(
                  color: _muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              ..._chapterTitles.asMap().entries.map((entry) {
                final index = entry.key;
                final isSelected = index == _activeChapterIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuickActionTile(
                    icon: isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.menu_book_rounded,
                    title: '${index + 1}. ${entry.value}',
                    subtitle: isSelected
                        ? 'Capitolo attivo'
                        : 'Apri questo capitolo nel reader',
                    selected: isSelected,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _selectChapter(index);
                      setState(() {
                        _activeTab = _AppTab.reader;
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final textTheme = Theme.of(sheetContext).textTheme;
            return _buildSheetFrame(
              context: sheetContext,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Opzioni reader',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.9,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Qui restano velocita, ripresa, capitoli e azioni di servizio. La vista principale rimane pulita.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: _muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          label: 'Capitolo',
                          value:
                              '${_activeChapterIndex + 1} / ${_chapterTexts.length}',
                          compact: true,
                        ),
                        _MetricCard(
                          label: 'Parole',
                          value: _words.length.toString(),
                          compact: true,
                        ),
                        _MetricCard(
                          label: 'Posizione',
                          value: _hasWords
                              ? '${_currentWordIndex + 1} / ${_words.length}'
                              : '--',
                          compact: true,
                        ),
                        _MetricCard(
                          label: 'Tempo',
                          value: _etaLabel,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          'Velocita',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_wordsPerMinute.round()} WPM',
                            style: textTheme.titleSmall?.copyWith(
                              color: _accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      min: 120,
                      max: 900,
                      divisions: 39,
                      value: _wordsPerMinute,
                      label: '${_wordsPerMinute.round()}',
                      onChanged: (value) {
                        _setSpeed(value);
                        setSheetState(() {});
                      },
                    ),
                    Text(
                      'Il ticker segue il tempo reale, cosi la cadenza resta stabile anche su device meno performanti.',
                      style: textTheme.bodySmall?.copyWith(
                        color: _muted,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Riprendi da posizione',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _resumeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Posizione parola (1 ...)',
                        hintText: 'Es. 120',
                        suffixIcon: Icon(Icons.pin_end_rounded),
                      ),
                      onSubmitted: (_) {
                        _resumeFromInput();
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            _resumeFromInput();
                            setSheetState(() {});
                          },
                          icon: const Icon(
                            Icons.playlist_add_check_circle_rounded,
                          ),
                          label: const Text('Riprendi'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _setResumeFromCurrent();
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.bookmark_added_rounded),
                          label: Text('Punto $_resumePointLabel'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _restartPlayback();
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Dall inizio'),
                        ),
                      ],
                    ),
                    if (_chapterTexts.length > 1) ...[
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text(
                            'Capitoli',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_chapterTexts.length} totali',
                            style: textTheme.bodyMedium?.copyWith(
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._chapterTitles.asMap().entries.map((entry) {
                        final index = entry.key;
                        final isSelected = index == _activeChapterIndex;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _QuickActionTile(
                            icon: isSelected
                                ? Icons.radio_button_checked_rounded
                                : Icons.chevron_right_rounded,
                            title:
                                '${index + 1}. ${_compactChapterLabel(entry.value)}',
                            subtitle: isSelected
                                ? 'Capitolo attivo'
                                : 'Apri questo capitolo',
                            selected: isSelected,
                            onTap: () {
                              _selectChapter(index);
                              setSheetState(() {});
                            },
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 22),
                    Text(
                      'Contenuto',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _openAddContentSheet();
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nuovo contenuto'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _openPasteTextSheet();
                          },
                          icon: const Icon(Icons.notes_rounded),
                          label: const Text('Incolla testo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7EFE8),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _panelBorder),
                      ),
                      child: Text(
                        _statusMessage,
                        style: textTheme.bodyMedium?.copyWith(
                          color: _muted,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetFrame({
    required BuildContext context,
    required Widget child,
  }) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, viewInsets.bottom + 12),
        child: DecoratedBox(
          decoration: _panelDecoration(radius: 30),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(BuildContext context, {required bool compact}) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 16 : 18,
        compact ? 16 : 20,
        compact ? 14 : 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D1A15), Color(0xFF5E2C1F)],
        ),
        borderRadius: BorderRadius.circular(compact ? 24 : 28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeSourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_loadedFormatLabel ?? 'Testo'} · ${_compactChapterLabel(_activeChapterLabel)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _showCompactSpeedSlider = !_showCompactSpeedSlider;
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFFFFD5C2),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Text(
                  '${_wordsPerMinute.round()} WPM',
                  style: textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFFFD5C2),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (_showCompactSpeedSlider) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Velocita',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFFFFB089),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                      thumbColor: const Color(0xFFFFE1D6),
                      overlayColor: const Color(
                        0xFFFFE1D6,
                      ).withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      min: 120,
                      max: 900,
                      divisions: 39,
                      value: _wordsPerMinute,
                      label: '${_wordsPerMinute.round()}',
                      onChanged: _setSpeed,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _progress,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              color: const Color(0xFFFFB089),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                _hasWords
                    ? '${_currentWordIndex + 1} / ${_words.length}'
                    : '--',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _etaLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildPlayerActionButton(
                icon: Icons.replay_10_rounded,
                onPressed: _hasWords ? () => _skipWords(-10) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: const Color(0xFFFFE1D6),
                    foregroundColor: _ink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildPlayerActionButton(
                icon: Icons.forward_10_rounded,
                onPressed: _hasWords ? () => _skipWords(10) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_chapterTexts.length > 1)
                OutlinedButton.icon(
                  onPressed: _openChapterSheet,
                  icon: const Icon(Icons.library_books_rounded),
                  label: const Text('Capitoli'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _setResumeFromCurrent,
                icon: const Icon(Icons.bookmark_added_rounded),
                label: Text('Punto $_resumePointLabel'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openOptionsSheet,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Opzioni'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.74),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddContentSheet,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _activeTab == _AppTab.reader ? 'Nuovo' : 'Aggiungi',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _activeTab.index,
        onDestinationSelected: (index) {
          setState(() {
            _activeTab = _AppTab.values[index];
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline_rounded),
            selectedIcon: Icon(Icons.play_circle_filled_rounded),
            label: 'Reader',
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 760;
              final page = AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _activeTab == _AppTab.home
                    ? _buildHomeTab(context, compact: isCompact)
                    : _buildReaderTab(context, compact: isCompact),
              );

              return page;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, {required bool compact}) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      key: const ValueKey('home-tab'),
      padding: EdgeInsets.fromLTRB(14, 14, 14, compact ? 108 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  compact ? 18 : 24,
                  compact ? 18 : 22,
                  compact ? 18 : 24,
                  compact ? 18 : 22,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D1A15), Color(0xFF6B3522)],
                  ),
                  borderRadius: BorderRadius.circular(compact ? 28 : 34),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'SPEEDY READER',
                            style: textTheme.labelLarge?.copyWith(
                              color: const Color(0xFFFFD5C2),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: _openOptionsSheet,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _hasImportedSource
                          ? _activeSourceLabel
                          : 'Pronto per la prossima sessione',
                      style:
                          (compact
                                  ? textTheme.headlineMedium
                                  : textTheme.displaySmall)
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: compact ? -1.2 : -1.8,
                                height: 0.95,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _hasImportedSource
                          ? 'Riprendi da ${_activeChapterLabel}, parola ${_currentWordIndex + 1}. Il reader resta il cuore dell app, il resto e solo contorno.'
                          : 'Importa un ebook, incolla un testo oppure apri la demo e passa subito alla lettura.',
                      style: textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.76),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _activeTab = _AppTab.reader;
                            });
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE1D6),
                            foregroundColor: _ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                          ),
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: Text(
                            _hasImportedSource
                                ? 'Continua lettura'
                                : 'Apri reader',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openAddContentSheet,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                          ),
                          icon: const Icon(Icons.library_add_rounded),
                          label: const Text('Aggiungi contenuto'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: _progress,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        color: const Color(0xFFFFB089),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InlineStatPill(
                          label: 'Posizione',
                          value: _hasWords
                              ? '${_currentWordIndex + 1} / ${_words.length}'
                              : '--',
                          dark: true,
                        ),
                        _InlineStatPill(
                          label: 'Capitolo',
                          value:
                              '${_activeChapterIndex + 1} / ${_chapterTexts.length}',
                          dark: true,
                        ),
                        _InlineStatPill(
                          label: 'WPM',
                          value: '${_wordsPerMinute.round()}',
                          dark: true,
                        ),
                        _InlineStatPill(
                          label: 'ETA',
                          value: _etaLabel,
                          dark: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Scorciatoie',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Azioni veloci da app: poche, chiare e sempre nello stesso posto.',
                style: textTheme.bodyLarge?.copyWith(
                  color: _muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, actionConstraints) {
                  final tileWidth = compact
                      ? (actionConstraints.maxWidth - 12) / 2
                      : 230.0;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          icon: Icons.play_circle_fill_rounded,
                          title: 'Apri reader',
                          subtitle: 'Torna subito alla lettura',
                          onTap: () {
                            setState(() {
                              _activeTab = _AppTab.reader;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          icon: Icons.upload_file_rounded,
                          title: 'Aggiungi ebook',
                          subtitle: 'Import rapido dal device',
                          onTap: _openAddContentSheet,
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          icon: Icons.notes_rounded,
                          title: 'Incolla testo',
                          subtitle: 'Per note, articoli o estratti',
                          onTap: _openPasteTextSheet,
                        ),
                      ),
                      SizedBox(
                        width: tileWidth,
                        child: _QuickActionTile(
                          icon: _chapterTexts.length > 1
                              ? Icons.library_books_rounded
                              : Icons.tune_rounded,
                          title: _chapterTexts.length > 1
                              ? 'Capitoli'
                              : 'Opzioni',
                          subtitle: _chapterTexts.length > 1
                              ? 'Apri la mappa del libro'
                              : 'Velocita, ripresa e stato',
                          onTap: _chapterTexts.length > 1
                              ? _openChapterSheet
                              : _openOptionsSheet,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              DecoratedBox(
                decoration: _panelDecoration(radius: compact ? 24 : 30),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sessione attiva',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${_activeSourceLabel} · ${_loadedFormatLabel ?? 'Testo'}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _accentSoft,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Riprendi da',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _resumePointLabel,
                                  style: textTheme.headlineSmall?.copyWith(
                                    color: _accent,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MetricCard(
                            label: 'Capitolo',
                            value:
                                '${_activeChapterIndex + 1} / ${_chapterTexts.length}',
                            compact: compact,
                          ),
                          _MetricCard(
                            label: 'Parole',
                            value: _words.length.toString(),
                            compact: compact,
                          ),
                          _MetricCard(
                            label: 'WPM',
                            value: '${_wordsPerMinute.round()}',
                            compact: compact,
                          ),
                          _MetricCard(
                            label: 'Tempo',
                            value: _etaLabel,
                            compact: compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_chapterTexts.length > 1) ...[
                const SizedBox(height: 22),
                Text(
                  'Mappa capitoli',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tocca un capitolo per saltare subito nel reader.',
                  style: textTheme.bodyLarge?.copyWith(
                    color: _muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _chapterTitles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final selected = index == _activeChapterIndex;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index == _chapterTitles.length - 1 ? 0 : 10,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () {
                            _selectChapter(index);
                            setState(() {
                              _activeTab = _AppTab.reader;
                            });
                          },
                          child: Container(
                            width: compact ? 190 : 220,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: selected ? _accentSoft : _panel,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: selected ? _accent : _panelBorder,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Capitolo ${index + 1}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: selected ? _accent : _muted,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  entry.value,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              DecoratedBox(
                decoration: _panelDecoration(radius: compact ? 24 : 30),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 18 : 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stato attuale',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _statusMessage,
                        style: textTheme.bodyLarge?.copyWith(
                          color: _muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderTab(BuildContext context, {required bool compact}) {
    final screenSize = MediaQuery.sizeOf(context);
    final readerHeight = compact
        ? (screenSize.height * 0.36).clamp(250.0, 360.0)
        : (screenSize.height * 0.44).clamp(340.0, 520.0);
    final textTheme = Theme.of(context).textTheme;
    final sectionPadding = compact ? 16.0 : 24.0;

    return SingleChildScrollView(
      key: const ValueKey('reader-tab'),
      padding: EdgeInsets.fromLTRB(14, 14, 14, compact ? 108 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: _panelDecoration(radius: compact ? 24 : 30),
                child: Padding(
                  padding: EdgeInsets.all(sectionPadding),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _activeSourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (compact
                                          ? textTheme.headlineSmall
                                          : textTheme.headlineMedium)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.0,
                                      ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${_loadedFormatLabel ?? 'Testo'} · ${_activeChapterLabel}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                color: _muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: () {
                          setState(() {
                            _activeTab = _AppTab.home;
                          });
                        },
                        icon: const Icon(Icons.grid_view_rounded),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _openOptionsSheet,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: _panelDecoration(radius: compact ? 24 : 30),
                child: Padding(
                  padding: EdgeInsets.all(sectionPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _InlineStatPill(
                            label: 'Capitolo',
                            value:
                                '${_activeChapterIndex + 1} / ${_chapterTexts.length}',
                          ),
                          _InlineStatPill(
                            label: 'Posizione',
                            value: _hasWords
                                ? '${_currentWordIndex + 1} / ${_words.length}'
                                : '--',
                          ),
                          _InlineStatPill(label: 'ETA', value: _etaLabel),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        height: readerHeight,
                        padding: EdgeInsets.all(compact ? 16 : 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7EFE8),
                          borderRadius: BorderRadius.circular(
                            compact ? 22 : 28,
                          ),
                          border: Border.all(color: _panelBorder),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 2,
                              height: compact ? 140 : 200,
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Una parola alla volta',
                                  style: textTheme.labelLarge?.copyWith(
                                    color: _muted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                SizedBox(height: compact ? 18 : 28),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 4 : 12,
                                      vertical: compact ? 6 : 10,
                                    ),
                                    child: RepaintBoundary(
                                      child: SizedBox.expand(
                                        child: _PivotAlignedWord(
                                          word: _currentWord,
                                          accentColor: _accent,
                                          textColor: _ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: compact ? 12 : 24,
                                  runSpacing: 12,
                                  children: [
                                    _MiniHint(
                                      label: 'Index',
                                      value: _hasWords
                                          ? '${_currentWordIndex + 1} / ${_words.length}'
                                          : '--',
                                      compact: compact,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildPlayerCard(context, compact: compact),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(minWidth: compact ? 92 : 100),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7EFE8),
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: (compact ? textTheme.titleMedium : textTheme.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8),
          ),
        ],
      ),
    );
  }
}

class _MiniHint extends StatelessWidget {
  const _MiniHint({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: (compact ? textTheme.titleSmall : textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? _accentSoft : _panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? _accent : _panelBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? _accent : const Color(0xFFF7EFE8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: selected ? Colors.white : _accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: _muted,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineStatPill extends StatelessWidget {
  const _InlineStatPill({
    required this.label,
    required this.value,
    this.dark = false,
  });

  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final background = dark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFF7EFE8);
    final foreground = dark ? Colors.white : _ink;
    final muted = dark ? Colors.white.withValues(alpha: 0.68) : _muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.08) : _panelBorder,
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PivotAlignedWord extends StatelessWidget {
  const _PivotAlignedWord({
    required this.word,
    required this.accentColor,
    required this.textColor,
  });

  final String word;
  final Color accentColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(160.0, constraints.maxWidth);
        final availableHeight = math.max(80.0, constraints.maxHeight);
        final parts = _splitAroundPivot(word);
        final layout = _resolveLayout(parts, availableWidth, availableHeight);

        return SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Text(parts.pivot, style: layout.pivotStyle),
              Positioned(
                right: (availableWidth / 2) + (layout.pivotWidth / 2),
                child: Text(
                  parts.left,
                  style: layout.baseStyle,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
              Positioned(
                left: (availableWidth / 2) + (layout.pivotWidth / 2),
                child: Text(
                  parts.right,
                  style: layout.baseStyle,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _WordLayout _resolveLayout(
    _PivotParts parts,
    double availableWidth,
    double availableHeight,
  ) {
    final baseSize = _baseFontSizeFor(availableWidth, availableHeight);
    final baseSpacing = baseSize >= 90
        ? -2.6
        : baseSize >= 68
        ? -2.0
        : -1.3;
    final targetWidth = availableWidth * 0.92;
    final targetHeight = availableHeight * 0.76;

    _WordLayout buildLayout(double scale) {
      final fittedFontSize = baseSize * scale;
      final fittedSpacing = baseSpacing * math.max(0.4, scale);
      final baseStyle = TextStyle(
        fontSize: fittedFontSize,
        height: 1,
        fontWeight: FontWeight.w900,
        color: textColor,
        letterSpacing: fittedSpacing,
      );
      final pivotStyle = baseStyle.copyWith(color: accentColor);
      final leftSize = _measureText(parts.left, baseStyle);
      final pivotSize = _measureText(parts.pivot, pivotStyle);
      final rightSize = _measureText(parts.right, baseStyle);

      return _WordLayout(
        baseStyle: baseStyle,
        pivotStyle: pivotStyle,
        pivotWidth: pivotSize.width,
        totalWidth: leftSize.width + pivotSize.width + rightSize.width,
        maxHeight: math.max(
          pivotSize.height,
          math.max(leftSize.height, rightSize.height),
        ),
      );
    }

    bool fits(_WordLayout layout) =>
        layout.totalWidth <= targetWidth && layout.maxHeight <= targetHeight;

    final fullSizeLayout = buildLayout(1);
    if (fits(fullSizeLayout)) {
      return fullSizeLayout;
    }

    var low = 0.16;
    var high = 1.0;
    var best = buildLayout(low);

    for (var i = 0; i < 14; i += 1) {
      final mid = (low + high) / 2;
      final candidate = buildLayout(mid);

      if (fits(candidate)) {
        best = candidate;
        low = mid;
      } else {
        high = mid;
      }
    }

    return best;
  }

  double _baseFontSizeFor(double availableWidth, double availableHeight) {
    final widthBound = availableWidth * 0.24;
    final heightBound = availableHeight * 0.68;
    return math.min(math.max(44, widthBound), math.max(44, heightBound));
  }

  Size _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.size;
  }
}

class _WordLayout {
  const _WordLayout({
    required this.baseStyle,
    required this.pivotStyle,
    required this.pivotWidth,
    required this.totalWidth,
    required this.maxHeight,
  });

  final TextStyle baseStyle;
  final TextStyle pivotStyle;
  final double pivotWidth;
  final double totalWidth;
  final double maxHeight;
}

String _compactChapterLabel(String title) {
  final normalized = title.trim();
  if (normalized.length <= 28) {
    return normalized;
  }
  return '${normalized.substring(0, 25)}...';
}

class _PivotParts {
  const _PivotParts({
    required this.left,
    required this.pivot,
    required this.right,
  });

  final String left;
  final String pivot;
  final String right;
}

_PivotParts _splitAroundPivot(String value) {
  if (value.isEmpty) {
    return const _PivotParts(left: '', pivot: '', right: '');
  }

  final pivotIndex = value.length ~/ 2;
  return _PivotParts(
    left: value.substring(0, pivotIndex),
    pivot: value.substring(pivotIndex, pivotIndex + 1),
    right: value.substring(pivotIndex + 1),
  );
}

List<String> _tokenize(String source) {
  final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) {
    return const [];
  }
  return normalized
      .split(' ')
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
}

BoxDecoration _panelDecoration({required double radius}) {
  return BoxDecoration(
    color: _panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _panelBorder),
    boxShadow: const [
      BoxShadow(
        color: Color(0x16000000),
        blurRadius: 28,
        offset: Offset(0, 18),
      ),
    ],
  );
}
