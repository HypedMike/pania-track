import 'dart:convert';

const int _maxLength = 200;

/// Pulls a readable message out of an error response body: JSON `message`/`error`, else the trimmed text.
String errorDetail(String body) {
  var text = body.trim();
  try {
    final json = jsonDecode(text);
    if (json is Map) {
      final field = json['message'] ?? json['error'];
      if (field is String) text = field.trim();
    }
  } catch (_) {
    // Not JSON: use the raw text.
  }
  // An HTML error page is not worth showing.
  if (text.isEmpty || RegExp(r'^<(!doctype|html)', caseSensitive: false).hasMatch(text)) return '';
  return text.length > _maxLength ? '${text.substring(0, _maxLength)}…' : text;
}

/// [message], followed by the server's own explanation when it sent one.
String withDetail(String message, String body) {
  final detail = errorDetail(body);
  return detail.isEmpty ? message : '$message $detail';
}
