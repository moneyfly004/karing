class VersionCompareUtils {
  static int compareVersion(String ver1, String ver2) {
    final v1 = _versionParts(ver1);
    final v2 = _versionParts(ver2);
    final length = v1.length > v2.length ? v1.length : v2.length;
    for (int i = 0; i < length; ++i) {
      final n1 = i < v1.length ? v1[i] : 0;
      final n2 = i < v2.length ? v2[i] : 0;
      if (n1 < n2) {
        return -1;
      }
      if (n1 > n2) {
        return 1;
      }
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final normalized = version.trim().split("+").first;
    if (normalized.isEmpty) {
      return const [0];
    }
    return normalized.split(".").map((part) {
      final match = RegExp(r"^\d+").firstMatch(part);
      if (match == null) {
        return 0;
      }
      return int.tryParse(match.group(0)!) ?? 0;
    }).toList();
  }
}
