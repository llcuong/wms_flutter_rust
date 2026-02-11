import 'dart:convert';
import 'package:flutter/services.dart';

class AppStrings {
  static late Map<String, Map<String, String>> _translations;
  static String _currentLocale = 'vi'; // Default to Vietnamese

  static Future<void> init({String locale = 'vi'}) async {
    _currentLocale = locale;
    _translations = {};

    try {
      // Load English translations
      final enJson = await rootBundle.loadString('lib/l10n/app_en.arb');
      final enData = Map<String, String>.from(jsonDecode(enJson) as Map);
      _translations['en'] = enData..remove('@@locale');

      // Load Vietnamese translations
      final viJson = await rootBundle.loadString('lib/l10n/app_vi.arb');
      final viData = Map<String, String>.from(jsonDecode(viJson) as Map);
      _translations['vi'] = viData..remove('@@locale');
    } catch (e) {
      print('Error loading translations: $e');
      // Fallback with empty maps
      _translations['en'] = {};
      _translations['vi'] = {};
    }
  }

  static void setLocale(String locale) {
    if (_translations.containsKey(locale)) {
      _currentLocale = locale;
    }
  }

  static String get(String key, {String locale = ''}) {
    final lang = locale.isEmpty ? _currentLocale : locale;
    return _translations[lang]?[key] ?? key;
  }

  // Navigation
  static String get formerMasterData => get('formerMasterData');
  static String get masterInfo => get('masterInfo');
  static String get scanTag => get('scanTag');

  // Form Labels
  static String get identification => get('identification');
  static String get trackingAndQty => get('trackingAndQty');
  static String get specifications => get('specifications');
  static String get dn => get('dn');
  static String get itemNo => get('itemNo');
  static String get usedDay => get('usedDay');
  static String get purchQty => get('purchQty');
  static String get dataDate => get('dataDate');
  static String get brand => get('brand');
  static String get type => get('type');
  static String get surface => get('surface');
  static String get size => get('size');
  static String get length => get('length');
  static String get aqlLevel => get('aqlLevel');
  static String get batchNumber => get('batchNumber');
  static String get standardFineSurface => get('standardFineSurface');
  static String get roughSurface => get('roughSurface');
  static String get lo => get('lo');
  static String get ceramic => get('ceramic');
  static String get latex => get('latex');
  static String get soLo => get('soLo');
  static String get nhapSoLo => get('nhapSoLo');
  static String get chieuDai => get('chieuDai');

  // Basket Mode
  static String get roDay => get('roDay');
  static String get roChuaDay => get('roChuaDay');
  static String get roRong => get('roRong');
  static String get ro => get('ro');
  static String get khuon => get('khuon');
  static String get rack => get('rack');

  // RFID Scanner
  static String get rfidPower => get('rfidPower');
  static String get dBm => get('dBm');
  static String get scanStatus => get('scanStatus');
  static String get statusDisconnected => get('statusDisconnected');
  static String get statusInitializing => get('statusInitializing');
  static String get statusInitialized => get('statusInitialized');
  static String get statusConnected => get('statusConnected');
  static String get statusScanning => get('statusScanning');
  static String get statusStopped => get('statusStopped');

  // Button Labels
  static String get quetTag => get('quetTag');
  static String get dungTag => get('dungTag');
  static String get xoaTag => get('xoaTag');
  static String get save => get('save');

  // Messages
  static String get notConnected => get('notConnected');
  static String get pleaseConnect => get('pleaseConnect');
  static String get startScanFailed => get('startScanFailed');
  static String get stopScanFailed => get('stopScanFailed');
  static String get clearFailed => get('clearFailed');
  static String get clearAllItems => get('clearAllItems');
  static String get clearConfirmMessage => get('clearConfirmMessage');
  static String get empty => get('empty');
  static String get noScannedItems => get('noScannedItems');
  static String get saved => get('saved');
  static String get formSavedSuccess => get('formSavedSuccess');
  static String get rfidReady => get('rfidReady');
  static String get rfidError => get('rfidError');

  static String get standardCoarseSurface => get('standardCoarseSurface');
  static String get standardDiamondTextured => get('standardDiamondTextured');
  static String get energySavingFineSurface => get('energySavingFineSurface');
  static String get stainlessSteel => get('stainlessSteel');

  // Generic
  static String get warning => get('warning');
  static String get success => get('success');
  static String get error => get('error'); // Added error
  static String get cancel => get('cancel');

  // Dropdown Options
  // Note: These are now better handled by maps in the screen for value/display separation
  static List<String> get typeOptions => ['Ceramic', 'Latex']; 
  static List<String> get surfaceOptions => [standardFineSurface, roughSurface];
}
