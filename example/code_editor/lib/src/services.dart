import 'diagnostics.dart';
import 'documents.dart';

abstract class LanguageService {
  String get languageId;
  List<Diagnostic> analyze(TextDocument document);
}

abstract class FormatterService {
  String get name;
  String format(TextDocument document);
}

abstract class LinterService {
  String get name;
  List<Diagnostic> lint(TextDocument document);
}
