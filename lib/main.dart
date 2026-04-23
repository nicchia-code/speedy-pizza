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
const _accentDeep = Color(0xFFB63A1D);
const _accentSoft = Color(0xFFFFE4BE);
const _track = Color(0xFFE7D9CE);
const _brandInk = Color(0xFF57524E);
const _brandInkSoft = Color(0xFF6E6863);
const _surfaceWarm = Color(0xFFF7EFE8);

const _demoText = '''
Leggere veloce non vuol dire correre a caso.
Vuol dire ridurre le pause inutili e lasciare che gli occhi seguano un ritmo chiaro.
Questa demo mostra una parola alla volta, con la lettera centrale evidenziata, per mantenere il focus.
''';

void main() {
  runApp(const SpeedyReaderApp());
}

enum _AppTab { home, reader, settings }

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
      title: 'Speedy Pizza',
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

class _ReaderPageState extends State<ReaderPage> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController(
    text: _demoText,
  );
  final TextEditingController _draftTextController = TextEditingController();
  final TextSourcePicker _textSourcePicker = createTextSourcePicker();
  final ReadingSessionStore _sessionStore = createReadingSessionStore();

  late final Ticker _ticker;
  late final AnimationController _readerPlayHintController;
  late final PageController _pageController;

  List<String> _words = _tokenize(_demoText);
  List<String> _chapterTexts = const [_demoText];
  List<String> _chapterTitles = const ['Demo'];
  int _activeChapterIndex = 0;
  int _currentWordIndex = 0;
  int _playbackStartIndex = 0;
  double _wordsPerMinute = 320;
  bool _isPlaying = false;
  _AppTab _activeTab = _AppTab.home;
  String? _loadedFileName;
  String? _loadedFormatLabel;
  String _statusMessage =
      'Demo pronta. Incolla il testo oppure carica un ebook.';

  bool get _hasWords => _words.isNotEmpty;

  String get _currentWord => _hasWords ? _words[_currentWordIndex] : 'Pronto';

  double get _microsecondsPerWord => 60000000 / _wordsPerMinute;

  String get _etaLabel {
    if (!_hasWords) {
      return '--';
    }

    final seconds = ((_words.length / _wordsPerMinute) * 60).ceil();
    if (seconds < 60) {
      return '${seconds}s';
    }

    return '${(seconds / 60).round()}m';
  }

  String get _activeSourceLabel => _prettifySourceName(_loadedFileName);

  bool get _hasImportedSource => _loadedFileName != null;
  bool get _showReaderPlayTrigger =>
      _activeTab == _AppTab.reader && !_isPlaying;

  String get _chapterProgressLabel =>
      '${_activeChapterIndex + 1} / ${_chapterTexts.length}';

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
    _readerPlayHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _pageController = PageController(initialPage: _tabToIndex(_activeTab));
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
    _readerPlayHintController.dispose();
    _pageController.dispose();
    _textController.dispose();
    _draftTextController.dispose();
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
        _statusMessage = 'Fine del testo. Tocca Play per ricominciare.';
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
      _setActiveTab(_AppTab.reader, animate: false);
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
    _prepareText(
      message: 'Demo ricaricata. La lettera centrale resta ancorata al centro.',
      keepChapterContext: true,
    );
    _setActiveTab(_AppTab.reader, animate: false);
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
    _setActiveTab(_AppTab.reader, animate: false);
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
      _setActiveTab(_AppTab.reader);
    }
    if (_isPlaying) {
      _pausePlayback();
      return;
    }
    _startPlayback();
  }

  int _tabToIndex(_AppTab tab) => tab.index;

  _AppTab _indexToTab(int index) =>
      _AppTab.values[index.clamp(0, _AppTab.values.length - 1)];

  void _setActiveTab(_AppTab tab, {bool animate = true}) {
    if (_activeTab != tab) {
      setState(() {
        _activeTab = tab;
      });
    }
    _syncPageToTab(tab, animate: animate);
  }

  void _syncPageToTab(_AppTab tab, {bool animate = true}) {
    if (!_pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncPageToTab(tab, animate: false);
      });
      return;
    }

    final targetPage = _tabToIndex(tab);
    final currentPage =
        _pageController.page ?? _pageController.initialPage.toDouble();

    if (currentPage.round() == targetPage) {
      return;
    }

    if (animate) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _pageController.jumpToPage(targetPage);
  }

  void _navigateToTab(_AppTab tab) {
    _setActiveTab(tab);
  }

  void _setSpeed(double value) {
    final shouldResume = _isPlaying;
    if (_ticker.isActive) {
      _ticker.stop();
    }

    if (shouldResume) {
      setState(() {
        _wordsPerMinute = value;
        _statusMessage = 'Velocita impostata a ${value.round()} WPM.';
      });
      _playbackStartIndex = _currentWordIndex;
      _ticker.start();
      return;
    }

    setState(() {
      _wordsPerMinute = value;
      _isPlaying = false;
      _statusMessage = 'Velocita impostata a ${value.round()} WPM.';
    });
  }

  void _adjustSpeedBy(double delta) {
    final nextValue = (_wordsPerMinute + delta).clamp(120.0, 900.0);
    _setSpeed(nextValue);
  }

  void _rewindBySeconds(int seconds) {
    if (!_hasWords) {
      return;
    }

    final wordsToRewind = math.max(
      1,
      ((_wordsPerMinute / 60) * seconds).round(),
    );
    final targetIndex = math.max(0, _currentWordIndex - wordsToRewind);
    final shouldResume = _isPlaying;

    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _currentWordIndex = targetIndex;
      _isPlaying = shouldResume;
      _statusMessage = 'Riavvolto di ${seconds}s.';
    });

    if (shouldResume) {
      _playbackStartIndex = _currentWordIndex;
      _ticker.start();
    }

    _saveCurrentSession();
  }

  void _handleIdleReaderTrigger() {
    if (_activeTab == _AppTab.reader) {
      _togglePlayback();
      return;
    }
    _navigateToTab(_AppTab.reader);
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
                      _setActiveTab(_AppTab.reader);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: _buildBottomPlayerNavigation(context),
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
              return PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  final tab = _indexToTab(index);
                  if (tab == _activeTab) {
                    return;
                  }
                  setState(() {
                    _activeTab = tab;
                  });
                },
                children: [
                  _buildHomeTab(context, compact: isCompact),
                  _buildReaderTab(context, compact: isCompact),
                  _buildSettingsTab(context, compact: isCompact),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPlayerNavigation(BuildContext context) {
    final isPlayerMode = _isPlaying;
    final showSpeedBar = _activeTab == _AppTab.reader;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D1A15), Color(0xFF5E2C1F)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpeedBar) ...[
                _buildActiveSpeedBar(context),
                const SizedBox(height: 10),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(0, 0.18),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: isPlayerMode
                    ? _buildActivePlayerBar(context)
                    : _buildIdleNavigationBar(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleNavigationBar(BuildContext context) {
    return Row(
      key: const ValueKey('bottom-nav-idle'),
      children: [
        Expanded(
          child: _buildIdleNavButton(
            tab: _AppTab.home,
            icon: Icons.home_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _buildIdleReaderTriggerButton()),
        const SizedBox(width: 10),
        Expanded(
          child: _buildIdleNavButton(
            tab: _AppTab.settings,
            icon: Icons.settings_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildIdleReaderTriggerButton() {
    return SizedBox(
      height: 54,
      child: AnimatedBuilder(
        animation: _readerPlayHintController,
        builder: (context, child) {
          final showHint = _showReaderPlayTrigger;
          final cycle = _readerPlayHintController.value;
          final pulsePhase = (math.sin(cycle * math.pi * 2) + 1) / 2;
          final pulse = showHint ? 1 + (0.07 * pulsePhase) : 1.0;
          final borderRadius = BorderRadius.circular(showHint ? 22 : 18);

          return Transform.scale(
            scale: pulse,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: showHint
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_accent, _accentDeep],
                      )
                    : null,
                color: showHint ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: borderRadius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: showHint ? 0.28 : 0.12),
                ),
                boxShadow: showHint
                    ? const [
                        BoxShadow(
                          color: Color(0x3AE4542D),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: borderRadius,
                  onTap: _handleIdleReaderTrigger,
                  child: Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: showHint ? 31 : 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdleNavButton({required _AppTab tab, required IconData icon}) {
    final isSelected = _activeTab == tab;

    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: () => _navigateToTab(tab),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          elevation: 0,
          backgroundColor: isSelected
              ? const Color(0xFFFFF4EA)
              : Colors.white.withValues(alpha: 0.06),
          foregroundColor: isSelected ? _ink : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFFFFD9BE)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Icon(icon, size: isSelected ? 24 : 22),
      ),
    );
  }

  Widget _buildActiveSpeedBar(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPlayerModeButton(
              icon: Icons.remove_rounded,
              onPressed: () => _adjustSpeedBy(-20),
              tooltip: 'Rallenta di 20 WPM',
              compact: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_wordsPerMinute.round()} WPM',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
          Expanded(
            child: _buildPlayerModeButton(
              icon: Icons.add_rounded,
              onPressed: () => _adjustSpeedBy(20),
              tooltip: 'Velocizza di 20 WPM',
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlayerBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildPlayerModeButton(
            icon: Icons.replay_10_rounded,
            onPressed: _hasWords ? () => _rewindBySeconds(10) : null,
            tooltip: 'Torna indietro di 10 secondi',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _togglePlayback,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: Colors.white,
                foregroundColor: _ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _buildPlayerModePlaceholder()),
      ],
    );
  }

  Widget _buildPlayerModeButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    bool compact = false,
  }) {
    return SizedBox(
      height: compact ? 30 : 56,
      child: Tooltip(
        message: tooltip,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(compact ? 14 : 20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            padding: EdgeInsets.zero,
          ),
          child: Icon(icon, size: compact ? 18 : 24),
        ),
      ),
    );
  }

  Widget _buildPlayerModePlaceholder() {
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, {required bool compact}) {
    final textTheme = Theme.of(context).textTheme;
    final brandStyle =
        (compact ? textTheme.headlineMedium : textTheme.displaySmall)?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: compact ? -1.0 : -1.4,
          height: 0.92,
          fontFamily: switch (defaultTargetPlatform) {
            TargetPlatform.iOS || TargetPlatform.macOS => 'Marker Felt',
            _ => 'Comic Sans MS',
          },
          fontFamilyFallback: const ['Trebuchet MS', 'Arial'],
        );

    return KeyedSubtree(
      key: const ValueKey('home-tab'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 108),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 4 : 6,
                    compact ? 2 : 8,
                    compact ? 4 : 6,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: brandStyle,
                                children: const [
                                  TextSpan(
                                    text: 'Speedy\n',
                                    style: TextStyle(color: _brandInk),
                                  ),
                                  TextSpan(
                                    text: 'Pizza',
                                    style: TextStyle(color: _brandInkSoft),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Il reader piu veloce del west',
                              style: textTheme.titleSmall?.copyWith(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: EdgeInsets.only(top: compact ? 8 : 12),
                        child: Image.asset(
                          'web/pizzalogo.png',
                          width: compact ? 34 : 40,
                          height: compact ? 34 : 40,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => _navigateToTab(_AppTab.reader),
                      child: DecoratedBox(
                        decoration: _panelDecoration(radius: 28),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 20 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ultimo Libro',
                                style: textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _activeSourceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const Spacer(),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _InlineStatPill(
                                    label: 'Capitolo',
                                    value: _chapterProgressLabel,
                                  ),
                                  _InlineStatPill(
                                    label: 'ETA',
                                    value: _etaLabel,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openAddContentSheet,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Aggiungi contenuto'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderTab(BuildContext context, {required bool compact}) {
    final textTheme = Theme.of(context).textTheme;
    return KeyedSubtree(
      key: const ValueKey('reader-tab'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 108),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _activeSourceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _hasImportedSource ? 'Libro attivo' : 'Demo',
                              style: textTheme.bodyMedium?.copyWith(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: _panelDecoration(radius: compact ? 24 : 30),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 16 : 20),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _surfaceWarm,
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
                              height: compact ? 150 : 220,
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 12 : 18,
                                vertical: compact ? 14 : 18,
                              ),
                              child: _PivotAlignedWord(
                                word: _currentWord,
                                accentColor: _accent,
                                textColor: _ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _chapterTexts.length > 1 ? _openChapterSheet : null,
                  child: DecoratedBox(
                    decoration: _panelDecoration(radius: 30),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 18 : 20,
                        compact ? 16 : 18,
                        compact ? 18 : 20,
                        compact ? 14 : 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Capitolo attivo',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const Spacer(),
                              if (_chapterTexts.length > 1)
                                Icon(
                                  Icons.menu_book_rounded,
                                  size: 20,
                                  color: _accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 10 : 12,
                              vertical: compact ? 14 : 16,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceWarm,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: _panelBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _ReaderStatColumn(
                                    label: 'Capitolo',
                                    value: _chapterProgressLabel,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: compact ? 46 : 52,
                                  color: _panelBorder,
                                ),
                                Expanded(
                                  child: _ReaderStatColumn(
                                    label: 'WPM',
                                    value: '${_wordsPerMinute.round()}',
                                    highlight: true,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: compact ? 46 : 52,
                                  color: _panelBorder,
                                ),
                                Expanded(
                                  child: _ReaderStatColumn(
                                    label: 'ETA',
                                    value: _etaLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Slider(
                            min: 120,
                            max: 900,
                            divisions: 39,
                            value: _wordsPerMinute,
                            label: '${_wordsPerMinute.round()}',
                            onChanged: _setSpeed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab(BuildContext context, {required bool compact}) {
    final textTheme = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: const ValueKey('settings-tab'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 108),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: _panelDecoration(radius: compact ? 24 : 30),
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 18 : 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Indice',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.9,
                          ),
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
                                  : Icons.menu_book_rounded,
                              title:
                                  '${index + 1}. ${_compactChapterLabel(entry.value)}',
                              subtitle: isSelected
                                  ? 'Capitolo attivo'
                                  : 'Apri questo capitolo nel reader',
                              selected: isSelected,
                              onTap: () {
                                _selectChapter(index);
                                _navigateToTab(_AppTab.reader);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderStatColumn extends StatelessWidget {
  const _ReaderStatColumn({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(
              color: highlight ? _accent : _ink,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
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
  const _InlineStatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceWarm,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _panelBorder),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: textTheme.bodySmall?.copyWith(
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: textTheme.labelLarge?.copyWith(
                color: _ink,
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
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 80.0;
        final parts = _splitAroundPivot(word);
        final layout = _resolveLayout(parts, availableWidth, availableHeight);

        return SizedBox(
          width: availableWidth,
          height: availableHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            children: [
              Text(parts.pivot, style: layout.pivotStyle),
              Positioned(
                right: (availableWidth / 2) + (layout.pivotWidth / 2),
                child: Text(
                  parts.left,
                  style: layout.baseStyle,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
              Positioned(
                left: (availableWidth / 2) + (layout.pivotWidth / 2),
                child: Text(
                  parts.right,
                  style: layout.baseStyle,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
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
    final baseSize =
        _baseFontSizeFor(availableWidth, availableHeight) *
        _fontScaleForWordLength(word.length);
    final baseSpacing = baseSize >= 90
        ? -2.6
        : baseSize >= 68
        ? -2.0
        : -1.3;
    final baseStyle = TextStyle(
      fontSize: baseSize,
      height: 1,
      fontWeight: FontWeight.w900,
      color: textColor,
      letterSpacing: baseSpacing,
    );
    final pivotStyle = baseStyle.copyWith(color: accentColor);
    final pivotSize = _measureText(parts.pivot, pivotStyle);

    return _WordLayout(
      baseStyle: baseStyle,
      pivotStyle: pivotStyle,
      pivotWidth: pivotSize.width,
    );
  }

  double _baseFontSizeFor(double availableWidth, double availableHeight) {
    final widthBound = availableWidth * 0.24;
    final heightBound = availableHeight * 0.68;
    return math.min(math.max(44, widthBound), math.max(44, heightBound));
  }

  double _fontScaleForWordLength(int length) {
    if (length <= 8) {
      return 1.0;
    }
    if (length == 9) {
      return 0.97;
    }
    if (length == 10) {
      return 0.94;
    }
    if (length == 11) {
      return 0.91;
    }
    if (length == 12) {
      return 0.88;
    }
    if (length == 13) {
      return 0.84;
    }
    if (length == 14) {
      return 0.8;
    }
    if (length == 15) {
      return 0.76;
    }
    if (length == 16) {
      return 0.72;
    }
    return math.max(0.58, 0.72 - ((length - 16) * 0.035));
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
  });

  final TextStyle baseStyle;
  final TextStyle pivotStyle;
  final double pivotWidth;
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
