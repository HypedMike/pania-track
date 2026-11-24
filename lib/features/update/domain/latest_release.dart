import 'dart:convert';

import 'package:http/http.dart' as http;

class LatestRelease {
  const LatestRelease({required this.version, required this.downloadUrl, required this.pageUrl});

  /// Plain X.Y.Z, without the leading "v".
  final String version;

  /// Direct APK download, falling back to the release page.
  final String downloadUrl;
  final String pageUrl;
}

Future<LatestRelease> fetchLatestRelease(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse(url), headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Release lookup failed (${res.statusCode})');
    final data = jsonDecode(res.body) as Map<String, Object?>;
    final assets = (data['assets'] as List?)?.cast<Map<String, Object?>>() ?? const [];
    final apk = assets.where((a) => (a['name'] as String? ?? '').endsWith('.apk')).firstOrNull;
    return LatestRelease(
      version: (data['tag_name'] as String).replaceFirst(RegExp(r'^v'), ''),
      downloadUrl: (apk?['browser_download_url'] as String?) ?? data['html_url'] as String,
      pageUrl: data['html_url'] as String,
    );
  } finally {
    if (client == null) c.close();
  }
}

/// True when [candidate] is a strictly newer X.Y.Z than [current].
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String v) => v.replaceFirst(RegExp(r'^v'), '').split('.').map((n) => int.tryParse(n) ?? 0).toList();
  final a = parse(candidate);
  final b = parse(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final d = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}
