import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppUtils {
  static const String officialWebsiteUrl = "https://new.moneyfly.top";

  static Future<String> getPackgetVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return getBuildinVersion();
    }
  }

  static String getName() {
    return "Karing";
  }

  static String getReleaseVersion() {
    final version = getBuildinVersion();
    if (version.contains("+")) {
      return version;
    }
    final parts = version.split(".");
    if (parts.length >= 4) {
      return "${parts[0]}.${parts[1]}.${parts[2]}+${parts.sublist(3).join(".")}";
    }
    return version;
  }

  static String getBuildinVersion() {
    return "1.0.0";
  }

  static String getId() {
    return "com.nebula.karing";
  }

  static String getGroupId() {
    return "group.com.nebula.karing";
  }

  static String getBundleId() {
    if (Platform.isIOS || Platform.isMacOS) {
      return "com.nebula.karing.karingService";
    }
    return "";
  }

  static String getICloudContainerId() {
    return "iCloud.com.nebula.karing";
  }

  static String getTermsOfServiceUrl() {
    switch (Platform.operatingSystem) {
      case "android":
        return "https://play.google.com/intl/en-US_us/about/play-terms/index.html";
      case "ios":
      case "macos":
        return "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/";
      default:
        return "";
    }
  }
}
