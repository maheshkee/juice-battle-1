import 'package:flutter/foundation.dart';

class BoardState extends ChangeNotifier {
  String?      currentUrl;
  List<String> urlHistory = [];
  List<String> logs       = [];

  void addLog(String msg) {
    logs.insert(0, msg);
    if (logs.length > 100) logs.removeLast();
    notifyListeners();
  }

  void setCurrentUrl(String url) {
    currentUrl = url;
    if (!urlHistory.contains(url)) {
      urlHistory.insert(0, url);
      if (urlHistory.length > 10) urlHistory.removeLast();
    }
    notifyListeners();
  }

  void clearCurrentUrl() {
    currentUrl = null;
    notifyListeners();
  }
}
