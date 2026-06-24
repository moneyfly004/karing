import 'package:flutter/material.dart';
import 'package:karing/app/runtime/return_result.dart';
import 'package:karing/app/utils/platform_utils.dart';
import 'package:karing/app/utils/url_launcher_utils.dart';
import 'package:karing/screens/inapp_webview_screen.dart';

class WebviewHelper {
  static Future<bool> loadUrl(BuildContext context, String url, String viewTag,
      {String? title,
      bool useInappWebViewForPC = false,
      bool inappWebViewOpenExternal = false}) async {
    if (PlatformUtils.isPC()) {
      if (!useInappWebViewForPC) {
        ReturnResultError? error = await UrlLauncherUtils.loadUrl(url);
        return error != null;
      }
    }

    if (await InAppWebViewScreen.makeSureEnvironmentCreated()) {
      if (!context.mounted) {
        return true;
      }

      await Navigator.push(
          context,
          MaterialPageRoute(
              settings: InAppWebViewScreen.routSettings(viewTag),
              builder: (context) => InAppWebViewScreen(
                    title: title ?? "",
                    url: url,
                    showOpenExternal: inappWebViewOpenExternal,
                  )));
      return true;
    }
    ReturnResultError? error = await UrlLauncherUtils.loadUrl(url);
    return error != null;
  }

  static Future<bool> loadHtml(
    BuildContext context,
    String html,
    String viewTag, {
    String? title,
    String baseUrl = 'https://new.moneyfly.top/',
    bool inappWebViewOpenExternal = false,
  }) async {
    if (html.isEmpty) {
      return true;
    }
    if (await InAppWebViewScreen.makeSureEnvironmentCreated()) {
      if (!context.mounted) {
        return true;
      }

      await Navigator.push(
          context,
          MaterialPageRoute(
              settings: InAppWebViewScreen.routSettings(viewTag),
              builder: (context) => InAppWebViewScreen(
                    title: title ?? "",
                    url: baseUrl,
                    initialHtml: html,
                    showOpenExternal: inappWebViewOpenExternal,
                  )));
      return true;
    }
    return true;
  }
}
