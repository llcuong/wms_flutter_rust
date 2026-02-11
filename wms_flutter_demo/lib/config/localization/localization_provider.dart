import 'package:flutter/material.dart';

class LocalizationProvider extends ChangeNotifier {
  String _currentLocale = 'vi';

  String get currentLocale => _currentLocale;

  void setLocale(String locale) {
    _currentLocale = locale;
    notifyListeners();
  }

  String get displayLocale {
    switch (_currentLocale) {
      case 'en':
        return 'English';
      case 'vi':
        return 'Tiếng Việt';
      default:
        return _currentLocale;
    }
  }
}
