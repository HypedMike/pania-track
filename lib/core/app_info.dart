import 'package:url_launcher/url_launcher.dart';

/// Source code of the app. Updates are only ever downloaded from this project's releases (the
/// Rust core checks the address against the same repository).
const String repoUrl = 'https://github.com/HypedMike/pania-track';

/// Endpoint of the latest GitHub release. Override with `--dart-define=LATEST_RELEASE_URL=…`;
/// an empty value turns the update check off.
const String latestReleaseUrl = String.fromEnvironment(
  'LATEST_RELEASE_URL',
  defaultValue: 'https://api.github.com/repos/HypedMike/pania-track/releases/latest',
);

/// Opens a link in the system browser.
Future<void> openExternal(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
