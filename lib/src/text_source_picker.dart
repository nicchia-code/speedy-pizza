import 'text_source_picker_base.dart';
import 'text_source_picker_stub.dart'
    if (dart.library.html) 'text_source_picker_web.dart'
    if (dart.library.io) 'text_source_picker_io.dart';

TextSourcePicker createTextSourcePicker() => createPlatformTextSourcePicker();
