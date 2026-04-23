import 'text_source_picker_base.dart';

TextSourcePicker createPlatformTextSourcePicker() =>
    const _UnsupportedTextSourcePicker();

class _UnsupportedTextSourcePicker implements TextSourcePicker {
  const _UnsupportedTextSourcePicker();

  @override
  Future<PickedSourceFile?> pickTextFile() async => null;
}
