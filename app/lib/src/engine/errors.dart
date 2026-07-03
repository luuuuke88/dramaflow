import 'dart:convert';

const errProviderMissing = 'errProviderMissing';
const errModelMissing = 'errModelMissing';
const errPromptMissing = 'errPromptMissing';
const errConfigVersion = 'errConfigVersion';
const errNetwork = 'errNetwork';
const errLlmFormat = 'errLlmFormat';
const errCanceled = 'errCanceled';
const errAppRestart = 'errAppRestart';
const errFileTooLarge = 'errFileTooLarge';
const errFileType = 'errFileType';
const errRegexInvalid = 'errRegexInvalid';
const errNoChapters = 'errNoChapters';
const errTaskUnsupported = 'errTaskUnsupported';

class EngineException implements Exception {
  final String errKey;
  final Map<String, Object?> errParams;

  const EngineException(this.errKey, [this.errParams = const {}]);

  String toReasonJson() => jsonEncode({
        'key': errKey,
        'params': errParams,
      });

  static EngineException? fromReasonJson(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      final key = decoded['key'];
      if (key is! String || key.isEmpty) return null;
      final params = decoded['params'];
      return EngineException(
        key,
        params is Map ? Map<String, Object?>.from(params) : const {},
      );
    } catch (_) {
      return null;
    }
  }

  /// Compatibility for UI code that still displays caught exceptions directly.
  String get message => errKey;

  @override
  String toString() => errParams.isEmpty ? errKey : '$errKey $errParams';
}
