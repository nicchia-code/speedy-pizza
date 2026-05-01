import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/epub_importer.dart';
import 'src/library_repository.dart';
import 'src/source_file_picker.dart';

const _ash = Color(0xFF201816);
const _ember = Color(0xFFE75B2C);
const _emberDeep = Color(0xFF9F321C);
const _paper = Color(0xFFFFF8F0);
const _paperWarm = Color(0xFFF5E8DC);
const _line = Color(0xFFE0C9B7);
const _muted = Color(0xFF776158);
const _readerPivotFraction = 0.44;

WidgetStateProperty<Color?> _mobileButtonOverlay(Color pressedColor) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return pressedColor;
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return Colors.transparent;
    }
    return null;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supabaseConfig = CinderSupabaseConfig.fromEnvironment();
  final CinderAuthController authController;
  final CinderLibraryRepository libraryRepository;
  if (supabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: supabaseConfig.url,
      anonKey: supabaseConfig.publishableKey,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    final supabaseClient = Supabase.instance.client;
    authController = SupabaseCinderAuthController(supabaseClient);
    libraryRepository = SupabaseCinderLibraryRepository(supabaseClient);
  } else {
    authController = MissingSupabaseAuthController();
    libraryRepository = const MissingCinderLibraryRepository();
  }

  runApp(
    CinderApp(
      authController: authController,
      libraryRepository: libraryRepository,
    ),
  );
}

class CinderApp extends StatefulWidget {
  const CinderApp({
    super.key,
    this.authController,
    this.libraryRepository,
    this.sourcePicker,
  });

  final CinderAuthController? authController;
  final CinderLibraryRepository? libraryRepository;
  final CinderSourcePicker? sourcePicker;

  @override
  State<CinderApp> createState() => _CinderAppState();
}

class _CinderAppState extends State<CinderApp> {
  late final CinderAuthController _authController =
      widget.authController ?? MissingSupabaseAuthController();
  late final CinderLibraryRepository _libraryRepository =
      widget.libraryRepository ?? const MissingCinderLibraryRepository();
  late final CinderSourcePicker _sourcePicker =
      widget.sourcePicker ?? const FilePickerCinderSourcePicker();

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _ember,
      brightness: Brightness.light,
      surface: _paper,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cinder',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _paper,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: _ash,
          displayColor: _ash,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style:
              FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: _ember,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ).copyWith(
                overlayColor: _mobileButtonOverlay(
                  Colors.white.withValues(alpha: 0.1),
                ),
              ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: _ember.withValues(alpha: 0.12),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: _ember,
          inactiveTrackColor: _line,
          thumbColor: _ember,
          overlayColor: _ember.withValues(alpha: 0.12),
          valueIndicatorColor: _ash,
          valueIndicatorTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      home: CinderBootPage(
        authController: _authController,
        libraryRepository: _libraryRepository,
        sourcePicker: _sourcePicker,
      ),
    );
  }
}

class CinderBootPage extends StatefulWidget {
  const CinderBootPage({
    super.key,
    required this.authController,
    required this.libraryRepository,
    required this.sourcePicker,
  });

  final CinderAuthController authController;
  final CinderLibraryRepository libraryRepository;
  final CinderSourcePicker sourcePicker;

  @override
  State<CinderBootPage> createState() => _CinderBootPageState();
}

class _CinderBootPageState extends State<CinderBootPage> {
  static const _minimumBootDuration = Duration(milliseconds: 900);

  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_completeBoot());
  }

  Future<void> _completeBoot() async {
    await Future.wait([
      widget.authController.initialize(),
      Future<void>.delayed(_minimumBootDuration),
    ]);

    if (!mounted) {
      return;
    }

    setState(() {
      _isReady = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isReady
          ? CinderHomePage(
              key: const ValueKey('cinder-home-page'),
              authController: widget.authController,
              libraryRepository: widget.libraryRepository,
              sourcePicker: widget.sourcePicker,
            )
          : const _CinderLogoLoadingPage(key: ValueKey('cinder-logo-loading')),
    );
  }
}

class _CinderLogoLoadingPage extends StatelessWidget {
  const _CinderLogoLoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF2E3), Color(0xFFEED5C0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _AnimatedEmberLogo(size: 116),
                const SizedBox(height: 18),
                Text(
                  'Cinder',
                  style: textTheme.displaySmall?.copyWith(
                    color: _ash,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
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

class CinderHomePage extends StatefulWidget {
  const CinderHomePage({
    super.key,
    required this.authController,
    required this.libraryRepository,
    required this.sourcePicker,
  });

  final CinderAuthController authController;
  final CinderLibraryRepository libraryRepository;
  final CinderSourcePicker sourcePicker;

  @override
  State<CinderHomePage> createState() => _CinderHomePageState();
}

class _CinderHomePageState extends State<CinderHomePage> {
  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_handleAuthChanged);
  }

  @override
  void dispose() {
    widget.authController.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF2E3), Color(0xFFEED5C0)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final phoneLandscape =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxHeight < 560;
            final compact = constraints.maxWidth < 680 || phoneLandscape;
            final pagePadding = phoneLandscape
                ? const EdgeInsets.fromLTRB(14, 10, 14, 12)
                : EdgeInsets.all(compact ? 18 : 28);
            final maxWidth = phoneLandscape ? 1120.0 : 860.0;
            final headerHeight = compact ? 58.0 : 72.0;
            final headerGap = phoneLandscape
                ? 10.0
                : compact
                ? 18.0
                : 24.0;

            return SafeArea(
              top: true,
              bottom: true,
              child: Padding(
                padding: pagePadding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      key: const ValueKey('cinder-shell'),
                      children: [
                        SizedBox(
                          height: headerHeight,
                          child: _CinderHeader(
                            compact: compact,
                            userLabel: widget.authController.currentUser?.label,
                          ),
                        ),
                        SizedBox(height: headerGap),
                        Expanded(
                          child: _CinderHomeContent(
                            key: const ValueKey('cinder-home-wrap'),
                            compact: compact,
                            phoneLandscape: phoneLandscape,
                            authController: widget.authController,
                            libraryRepository: widget.libraryRepository,
                            sourcePicker: widget.sourcePicker,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CinderHomeContent extends StatelessWidget {
  const _CinderHomeContent({
    super.key,
    required this.compact,
    required this.phoneLandscape,
    required this.authController,
    required this.libraryRepository,
    required this.sourcePicker,
  });

  final bool compact;
  final bool phoneLandscape;
  final CinderAuthController authController;
  final CinderLibraryRepository libraryRepository;
  final CinderSourcePicker sourcePicker;

  @override
  Widget build(BuildContext context) {
    final preview = const _ReaderCard(word: 'Rabbit', progress: 1);
    final panel = _AuthLibraryPanel(
      authController: authController,
      libraryRepository: libraryRepository,
      sourcePicker: sourcePicker,
      compact: compact,
    );

    return KeyedSubtree(
      key: const ValueKey('cinder-home'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (phoneLandscape && constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: preview),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: panel),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: compact ? 138 : 168, child: preview),
              SizedBox(height: compact ? 16 : 22),
              Expanded(child: panel),
            ],
          );
        },
      ),
    );
  }
}

class _HomePanelSurface extends StatelessWidget {
  const _HomePanelSurface({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _paper.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(compact ? 22 : 28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
      ),
      child: Padding(padding: EdgeInsets.all(compact ? 16 : 22), child: child),
    );
  }
}

class _AuthLibraryPanel extends StatelessWidget {
  const _AuthLibraryPanel({
    required this.authController,
    required this.libraryRepository,
    required this.sourcePicker,
    required this.compact,
  });

  final CinderAuthController authController;
  final CinderLibraryRepository libraryRepository;
  final CinderSourcePicker sourcePicker;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!authController.isConfigured) {
      return _HomePanelSurface(
        compact: compact,
        child: _PanelContent(
          title: 'Configura Supabase',
          body:
              'Avvia Cinder con CINDER_SUPABASE_URL e CINDER_SUPABASE_PUBLISHABLE_KEY per abilitare account e sincronizzazione companion.',
          child: SelectableText(
            '--dart-define=CINDER_SUPABASE_URL=...\n'
            '--dart-define=CINDER_SUPABASE_PUBLISHABLE_KEY=...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _ash,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (!authController.isSignedIn) {
      return _HomePanelSurface(
        compact: compact,
        child: _PanelContent(
          title: 'Accedi al companion',
          body:
              'Inserisci la tua email: sara lo stesso account usato dal Rabbit.',
          child: _PasswordlessEmailForm(authController: authController),
        ),
      );
    }

    return _HomePanelSurface(
      compact: compact,
      child: _LibraryUploadPanel(
        libraryRepository: libraryRepository,
        sourcePicker: sourcePicker,
        compact: compact,
      ),
    );
  }
}

class _LibraryUploadPanel extends StatefulWidget {
  const _LibraryUploadPanel({
    required this.libraryRepository,
    required this.sourcePicker,
    required this.compact,
  });

  final CinderLibraryRepository libraryRepository;
  final CinderSourcePicker sourcePicker;
  final bool compact;

  @override
  State<_LibraryUploadPanel> createState() => _LibraryUploadPanelState();
}

class _LibraryUploadPanelState extends State<_LibraryUploadPanel> {
  _UploadStage _stage = _UploadStage.idle;
  String? _statusMessage;
  ImportedEpubBook? _lastBook;
  CinderUploadedBook? _lastUploadedBook;

  bool get _isBusy {
    return _stage == _UploadStage.picking ||
        _stage == _UploadStage.parsing ||
        _stage == _UploadStage.uploading;
  }

  Future<void> _pickParseAndUpload() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _stage = _UploadStage.picking;
      _statusMessage = null;
      _lastBook = null;
      _lastUploadedBook = null;
    });

    try {
      final file = await widget.sourcePicker.pickEpubFile();
      if (!mounted) {
        return;
      }
      if (file == null) {
        setState(() {
          _stage = _UploadStage.idle;
        });
        return;
      }

      setState(() {
        _stage = _UploadStage.parsing;
        _statusMessage = 'Lettura EPUB...';
      });
      final book = await importEpubFile(file);
      if (!mounted) {
        return;
      }

      setState(() {
        _stage = _UploadStage.uploading;
        _statusMessage = 'Caricamento capitoli...';
        _lastBook = book;
      });
      final uploadedBook = await widget.libraryRepository.uploadEpubBook(book);
      if (!mounted) {
        return;
      }

      setState(() {
        _stage = _UploadStage.completed;
        _lastUploadedBook = uploadedBook;
        _statusMessage =
            'Libro caricato: ${uploadedBook.title} (${uploadedBook.chapterCount} capitoli).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _UploadStage.failed;
        _statusMessage =
            'Caricamento non riuscito: ${_formatUploadError(error)}';
      });
    }
  }

  String _formatUploadError(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    if (error is UnsupportedError) {
      return error.message ?? 'formato non supportato.';
    }
    if (error is PostgrestException) {
      return error.message;
    }
    if (error is StorageException) {
      return error.message;
    }
    return '$error';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final book = _lastBook;
    final uploadedBook = _lastUploadedBook;
    final statusColor = _stage == _UploadStage.failed ? _emberDeep : _muted;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Libreria',
                style: textTheme.headlineSmall?.copyWith(
                  color: _ash,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: widget.compact ? 58 : 66,
                child: FilledButton.icon(
                  key: const ValueKey('upload-book-button'),
                  onPressed: _isBusy ? null : _pickParseAndUpload,
                  icon: _isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: const Text('Carica EPUB'),
                ),
              ),
              if (_isBusy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(
                  minHeight: 5,
                  backgroundColor: _line,
                  color: _ember,
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage!,
                  key: const ValueKey('upload-status-label'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
              if (book != null && uploadedBook == null) ...[
                const SizedBox(height: 12),
                _BookImportSummary(book: book),
              ],
              if (book != null && uploadedBook != null) ...[
                const SizedBox(height: 12),
                _BookImportSummary(book: book),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BookImportSummary extends StatelessWidget {
  const _BookImportSummary({required this.book});

  final ImportedEpubBook book;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final authors = book.authors.join(', ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _paperWarm.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: _ash,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            if (authors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                authors,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${book.chapters.length} capitoli - ${book.wordCount} parole',
              style: textTheme.labelLarge?.copyWith(
                color: _emberDeep,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _UploadStage { idle, picking, parsing, uploading, completed, failed }

class _PasswordlessEmailForm extends StatefulWidget {
  const _PasswordlessEmailForm({required this.authController});

  final CinderAuthController authController;

  @override
  State<_PasswordlessEmailForm> createState() => _PasswordlessEmailFormState();
}

class _PasswordlessEmailFormState extends State<_PasswordlessEmailForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  String? _validationMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _validationMessage = 'Inserisci una email valida.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
      _codeController.clear();
    });
    await widget.authController.requestEmailCode(email);
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    final email =
        widget.authController.pendingEmail?.trim() ??
        _emailController.text.trim();
    final code = _codeController.text.trim();
    if (!_looksLikeEmail(email) || code.isEmpty) {
      setState(() {
        _validationMessage = 'Inserisci email e codice.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
    });
    await widget.authController.verifyEmailCode(email: email, code: code);
  }

  bool _looksLikeEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    final authController = widget.authController;
    final textTheme = Theme.of(context).textTheme;
    final awaitingCode = authController.isAwaitingEmailCode;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _line),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('email-login-email-field'),
          controller: _emailController,
          enabled: !authController.isBusy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: awaitingCode
              ? TextInputAction.next
              : TextInputAction.done,
          onSubmitted: (_) {
            if (!awaitingCode) {
              unawaited(_requestCode());
            }
          },
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.mail_rounded),
            filled: true,
            fillColor: _paperWarm,
            enabledBorder: inputBorder,
            focusedBorder: inputBorder.copyWith(
              borderSide: const BorderSide(color: _ember, width: 1.5),
            ),
          ),
        ),
        if (awaitingCode) ...[
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('email-login-code-field'),
            controller: _codeController,
            enabled: !authController.isBusy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_verifyCode()),
            decoration: InputDecoration(
              labelText: 'Codice',
              prefixIcon: const Icon(Icons.pin_rounded),
              filled: true,
              fillColor: _paperWarm,
              enabledBorder: inputBorder,
              focusedBorder: inputBorder.copyWith(
                borderSide: const BorderSide(color: _ember, width: 1.5),
              ),
            ),
          ),
        ],
        if (_validationMessage != null ||
            authController.errorMessage != null ||
            authController.noticeMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _validationMessage ??
                authController.errorMessage ??
                authController.noticeMessage!,
            style: textTheme.bodySmall?.copyWith(
              color: authController.errorMessage != null ? _emberDeep : _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: awaitingCode
              ? FilledButton.icon(
                  key: const ValueKey('verify-email-code-button'),
                  onPressed: authController.isBusy ? null : _verifyCode,
                  icon: authController.isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: const Text('Verifica codice'),
                )
              : FilledButton.icon(
                  key: const ValueKey('send-email-code-button'),
                  onPressed: authController.isBusy ? null : _requestCode,
                  icon: authController.isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_rounded),
                  label: const Text('Invia codice'),
                ),
        ),
        if (awaitingCode) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('resend-email-code-button'),
            onPressed: authController.isBusy ? null : _requestCode,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Rimanda codice'),
          ),
        ],
      ],
    );
  }
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.title,
    required this.body,
    required this.child,
  });

  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: textTheme.headlineSmall?.copyWith(
                  color: _ash,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: textTheme.bodyMedium?.copyWith(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _CinderHeader extends StatelessWidget {
  const _CinderHeader({required this.compact, this.userLabel});

  final bool compact;
  final String? userLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final normalizedUserLabel = userLabel?.trim();

    return Row(
      children: [
        _AnimatedEmberLogo(size: compact ? 58 : 72),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cinder',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? textTheme.headlineSmall
                            : textTheme.headlineMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
              ),
              Text(
                'Rabbit companion',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        if (normalizedUserLabel != null && normalizedUserLabel.isNotEmpty) ...[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 152 : 280),
            child: Text(
              normalizedUserLabel,
              key: const ValueKey('signed-in-email-label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: textTheme.labelMedium?.copyWith(
                color: _emberDeep,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnimatedEmberLogo extends StatefulWidget {
  const _AnimatedEmberLogo({required this.size});

  final double size;

  @override
  State<_AnimatedEmberLogo> createState() => _AnimatedEmberLogoState();
}

class _AnimatedEmberLogoState extends State<_AnimatedEmberLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2EE75B2C),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _EmberLogoPainter(progress: _controller.value),
            );
          },
        ),
      ),
    );
  }
}

class _EmberLogoPainter extends CustomPainter {
  const _EmberLogoPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final shortestSide = math.min(size.width, size.height);
    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final center = Offset(size.width * 0.5, size.height * 0.56);
    final radius = shortestSide * (0.22 + pulse * 0.05);
    final glowPaint = Paint()
      ..color = _ember.withValues(alpha: 0.28 + pulse * 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    final basePaint = Paint()..color = const Color(0xFF402B24);
    final darkPaint = Paint()..color = const Color(0xFF2C201D);
    final emberPaint = Paint()
      ..color = Color.lerp(_emberDeep, const Color(0xFFFF8A32), pulse)!;
    final highlightPaint = Paint()
      ..color = const Color(0xFFFFBE75).withValues(alpha: 0.66 + pulse * 0.24)
      ..strokeWidth = shortestSide * 0.035
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(shortestSide * 0.24),
      ),
      Paint()..color = const Color(0xFFFFF4E8),
    );
    canvas.drawCircle(center, radius, glowPaint);

    _drawCoal(
      canvas,
      center + Offset(-shortestSide * 0.11, -shortestSide * 0.08),
      Size(shortestSide * 0.52, shortestSide * 0.2),
      -0.16,
      basePaint,
    );
    _drawCoal(
      canvas,
      center + Offset(shortestSide * 0.1, -shortestSide * 0.02),
      Size(shortestSide * 0.54, shortestSide * 0.2),
      0.14,
      darkPaint,
    );
    _drawCoal(
      canvas,
      center + Offset(-shortestSide * 0.02, shortestSide * 0.12),
      Size(shortestSide * 0.62, shortestSide * 0.22),
      -0.02,
      basePaint,
    );

    canvas.drawLine(
      center + Offset(-shortestSide * 0.22, shortestSide * 0.04),
      center + Offset(shortestSide * 0.1, -shortestSide * 0.02),
      highlightPaint,
    );
    canvas.drawLine(
      center + Offset(-shortestSide * 0.04, shortestSide * 0.16),
      center + Offset(shortestSide * 0.24, shortestSide * 0.08),
      highlightPaint,
    );
    canvas.drawCircle(
      center + Offset(-shortestSide * 0.16, shortestSide * 0.12),
      shortestSide * (0.075 + pulse * 0.02),
      emberPaint,
    );
  }

  void _drawCoal(
    Canvas canvas,
    Offset center,
    Size size,
    double rotation,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: size.width,
          height: size.height,
        ),
        Radius.circular(size.height * 0.48),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EmberLogoPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({required this.word, required this.progress});

  final String word;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _paper.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.56)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F5B2C1F),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _paperWarm,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _line),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment(_readerPivotFraction * 2 - 1, 0),
                      child: Container(
                        width: 2,
                        height: 88,
                        decoration: BoxDecoration(
                          color: _ember.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: _PivotAlignedWord(
                        key: ValueKey(word),
                        word: word,
                        accentColor: _ember,
                        textColor: _ash,
                        anchorFraction: _readerPivotFraction,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress,
                      color: _ember,
                      backgroundColor: _line,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Companion',
                  style: textTheme.labelLarge?.copyWith(
                    color: _emberDeep,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PivotAlignedWord extends StatelessWidget {
  const _PivotAlignedWord({
    super.key,
    required this.word,
    required this.accentColor,
    required this.textColor,
    required this.anchorFraction,
  });

  final String word;
  final Color accentColor;
  final Color textColor;
  final double anchorFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 160.0;
        final parts = _splitAroundPivot(word);
        final anchorX = width * anchorFraction;
        final fontSize = _fontSizeFor(parts, width, height, anchorX);
        final baseStyle = TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: 0,
        );
        final pivotStyle = baseStyle.copyWith(color: accentColor);
        final pivotWidth = _measureText(parts.pivot, pivotStyle).width;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 130),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            );
          },
          child: SizedBox(
            key: ValueKey(word),
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: anchorX - (pivotWidth / 2),
                  child: Text(parts.pivot, style: pivotStyle),
                ),
                Positioned(
                  right: width - anchorX + (pivotWidth / 2),
                  child: Text(
                    parts.left,
                    style: baseStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                  ),
                ),
                Positioned(
                  left: anchorX + (pivotWidth / 2),
                  child: Text(
                    parts.right,
                    style: baseStyle,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _fontSizeFor(
    _PivotParts parts,
    double width,
    double height,
    double anchorX,
  ) {
    const maxSize = 164.0;
    final leftRoom = math.max(1.0, anchorX - 18);
    final rightRoom = math.max(1.0, width - anchorX - 18);
    final verticalRoom = height * 0.38;
    final upperBound = math.min(maxSize, math.max(1.0, verticalRoom));

    var low = 1.0;
    var high = upperBound;
    for (var index = 0; index < 18; index += 1) {
      final candidate = (low + high) / 2;
      if (_fontFits(parts, candidate, leftRoom, rightRoom, verticalRoom)) {
        low = candidate;
      } else {
        high = candidate;
      }
    }
    return low;
  }

  bool _fontFits(
    _PivotParts parts,
    double fontSize,
    double leftRoom,
    double rightRoom,
    double verticalRoom,
  ) {
    final style = TextStyle(
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );
    final pivotSize = _measureText(parts.pivot, style);
    final leftSize = _measureText(parts.left, style);
    final rightSize = _measureText(parts.right, style);
    final halfPivot = pivotSize.width / 2;

    return leftSize.width + halfPivot <= leftRoom &&
        rightSize.width + halfPivot <= rightRoom &&
        pivotSize.height <= verticalRoom;
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

  final lettersOnly = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final pivotOffset = switch (lettersOnly.length) {
    <= 1 => 0,
    <= 5 => 1,
    <= 9 => 2,
    <= 13 => 3,
    _ => 4,
  };
  final pivotIndex = _resolvePivotIndex(value, pivotOffset);

  return _PivotParts(
    left: value.substring(0, pivotIndex),
    pivot: value.substring(pivotIndex, pivotIndex + 1),
    right: value.substring(pivotIndex + 1),
  );
}

int _resolvePivotIndex(String value, int pivotOffset) {
  var letterCount = 0;
  for (var index = 0; index < value.length; index += 1) {
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(value[index])) {
      continue;
    }
    if (letterCount == pivotOffset) {
      return index;
    }
    letterCount += 1;
  }
  return math.max(0, value.length - 1);
}

class CinderSupabaseConfig {
  const CinderSupabaseConfig({required this.url, required this.publishableKey});

  factory CinderSupabaseConfig.fromEnvironment() {
    return const CinderSupabaseConfig(
      url: String.fromEnvironment('CINDER_SUPABASE_URL'),
      publishableKey: String.fromEnvironment('CINDER_SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String url;
  final String publishableKey;

  bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;
}

class CinderUser {
  const CinderUser({this.email, this.name});

  final String? email;
  final String? name;

  String get label {
    final normalizedName = name?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return normalizedName;
    }
    final normalizedEmail = email?.trim();
    if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    return 'Utente connesso';
  }
}

abstract class CinderAuthController extends ChangeNotifier {
  bool get isConfigured;
  bool get isBusy;
  bool get isAwaitingEmailCode;
  CinderUser? get currentUser;
  String? get errorMessage;
  String? get noticeMessage;
  String? get pendingEmail;

  bool get isSignedIn => currentUser != null;

  Future<void> initialize();
  Future<void> requestEmailCode(String email);
  Future<void> verifyEmailCode({required String email, required String code});
}

class MissingSupabaseAuthController extends CinderAuthController {
  @override
  bool get isConfigured => false;

  @override
  bool get isBusy => false;

  @override
  bool get isAwaitingEmailCode => false;

  @override
  CinderUser? get currentUser => null;

  @override
  String? get errorMessage => null;

  @override
  String? get noticeMessage => null;

  @override
  String? get pendingEmail => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestEmailCode(String email) async {}

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {}
}

class SupabaseCinderAuthController extends CinderAuthController {
  SupabaseCinderAuthController(this._client);

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;
  CinderUser? _currentUser;
  String? _errorMessage;
  String? _noticeMessage;
  String? _pendingEmail;
  bool _isBusy = false;
  bool _isAwaitingEmailCode = false;

  @override
  bool get isConfigured => true;

  @override
  bool get isBusy => _isBusy;

  @override
  bool get isAwaitingEmailCode => _isAwaitingEmailCode;

  @override
  CinderUser? get currentUser => _currentUser;

  @override
  String? get errorMessage => _errorMessage;

  @override
  String? get noticeMessage => _noticeMessage;

  @override
  String? get pendingEmail => _pendingEmail;

  @override
  Future<void> initialize() async {
    _currentUser = _mapUser(_client.auth.currentUser);
    _authSubscription ??= _client.auth.onAuthStateChange.listen((state) {
      _currentUser = _mapUser(state.session?.user);
      _errorMessage = null;
      _noticeMessage = null;
      _isAwaitingEmailCode = false;
      notifyListeners();
    });

    await _validateCachedSession();
    notifyListeners();
  }

  @override
  Future<void> requestEmailCode(String email) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();

    try {
      final normalizedEmail = email.trim();
      await _client.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: true,
      );
      _pendingEmail = normalizedEmail;
      _isAwaitingEmailCode = true;
      _noticeMessage = 'Codice inviato a $normalizedEmail.';
    } catch (error) {
      _errorMessage = _formatAuthError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();

    try {
      final response = await _client.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.email,
      );
      _currentUser = _mapUser(response.user ?? _client.auth.currentUser);
      _pendingEmail = null;
      _isAwaitingEmailCode = false;
    } catch (error) {
      _errorMessage = _formatAuthError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _validateCachedSession() async {
    if (_client.auth.currentSession == null) {
      return;
    }

    try {
      final response = await _client.auth.getUser();
      if (response.user != null) {
        return;
      }
    } on AuthRetryableFetchException {
      return;
    } on AuthException catch (error) {
      if (!_isRecoverableInvalidSession(error)) {
        rethrow;
      }
    }

    await _client.auth.signOut(scope: SignOutScope.local);
    _currentUser = null;
  }

  bool _isRecoverableInvalidSession(AuthException error) {
    return switch (error.statusCode) {
      '401' || '403' || '404' => true,
      _ => false,
    };
  }

  String _formatAuthError(Object error) {
    if (error is FormatException) {
      return 'Codice email non valido.';
    }
    if (error is AuthException) {
      return 'Login email non riuscito: ${error.message}';
    }
    return 'Login email non riuscito: $error';
  }

  CinderUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }
    final metadata = user.userMetadata;
    final name =
        metadata?['full_name'] as String? ??
        metadata?['name'] as String? ??
        metadata?['user_name'] as String?;
    return CinderUser(email: user.email, name: name);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }
}
