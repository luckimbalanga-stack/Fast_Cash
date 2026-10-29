/// Compare des versions type `1.2.3` (parties numériques). Retourne < 0, 0 ou > 0.
int compareVersions(String a, String b) {
  List<int> parts(String value) => value
      .split(RegExp(r'[^0-9]+'))
      .where((item) => item.isNotEmpty)
      .map(int.parse)
      .toList();

  final left = parts(a);
  final right = parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.message,
    required this.forced,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String message;
  final bool forced;
}
