import 'dart:async';
import 'package:flutter/services.dart';

enum ScanMode { single, continuous }

enum ConnectionStatus {
  powerOn,
  connected,
  disconnected,
  scanStarted,
  scanStopped,
}

class TagData {
  final String tagId;
  final int rssi;
  final String? memId;

  TagData({
    required this.tagId,
    required this.rssi,
    this.memId,
  });

  factory TagData.fromMap(Map<dynamic, dynamic> map) {
    return TagData(
      tagId: map['tagId'] as String,
      rssi: map['rssi'] as int,
      memId: map['memId'] as String?,
    );
  }

  @override
  String toString() => 'TagData(tagId: $tagId, rssi: $rssi, memId: $memId)';
}

class RfidScanner {
  static const MethodChannel _channel = MethodChannel('com.pmgvn.wms/rfid_scanner');
  static const EventChannel _tagEventChannel = EventChannel('com.pmgvn.wms/rfid_scanner/tags');
  static const EventChannel _statusEventChannel = EventChannel('com.pmgvn.wms/rfid_scanner/status');
  static const EventChannel _errorEventChannel = EventChannel('com.pmgvn.wms/rfid_scanner/errors');

  Stream<TagData>? _tagStream;
  Stream<ConnectionStatus>? _statusStream;
  Stream<String>? _errorStream;

  /// Stream of scanned tags
  Stream<TagData> get onTagScanned {
    _tagStream ??= _tagEventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<dynamic, dynamic>;
      final tagData = TagData.fromMap(map);
      print('🏷️ Scanned Tag EPC: ${tagData.tagId}');
      return tagData;
    });
    return _tagStream!;
  }

  /// Stream of connection status changes
  Stream<ConnectionStatus> get onConnectionStatusChange {
    _statusStream ??= _statusEventChannel.receiveBroadcastStream().map((event) {
      final status = event as String;
      switch (status) {
        case 'POWER_ON':
          return ConnectionStatus.powerOn;
        case 'CONNECTED':
          return ConnectionStatus.connected;
        case 'DISCONNECTED':
          return ConnectionStatus.disconnected;
        case 'SCAN_STARTED':
          return ConnectionStatus.scanStarted;
        case 'SCAN_STOPPED':
          return ConnectionStatus.scanStopped;
        default:
          return ConnectionStatus.disconnected;
      }
    });
    return _statusStream!;
  }

  /// Stream of errors
  Stream<String> get onError {
    _errorStream ??= _errorEventChannel.receiveBroadcastStream().cast<String>();
    return _errorStream!;
  }

  /// Initialize the RFID SDK
  Future<bool> init() async {
    try {
      final result = await _channel.invokeMethod('init');
      return result as bool;
    } catch (e) {
      throw Exception('Failed to initialize: $e');
    }
  }

  /// Connect to the RFID reader
  Future<bool> connect() async {
    try {
      final result = await _channel.invokeMethod('connect');
      return result as bool;
    } catch (e) {
      throw Exception('Failed to connect: $e');
    }
  }

  /// Disconnect from the RFID reader
  Future<bool> disconnect() async {
    try {
      final result = await _channel.invokeMethod('disconnect');
      return result as bool;
    } catch (e) {
      throw Exception('Failed to disconnect: $e');
    }
  }

  /// Start scanning for RFID tags
  /// 
  /// [mode] - ScanMode.single for single scan, ScanMode.continuous for continuous
  /// [uniqueOnly] - If true, only report unique tags (no duplicates in continuous mode)
  Future<bool> startScan({
    ScanMode mode = ScanMode.continuous,
    bool uniqueOnly = true,
  }) async {
    try {
      final result = await _channel.invokeMethod('startScan', {
        'mode': mode == ScanMode.single ? 'SINGLE' : 'CONTINUOUS',
        'uniqueOnly': uniqueOnly,
      });
      return result as bool;
    } catch (e) {
      throw Exception('Failed to start scan: $e');
    }
  }

  /// Stop scanning
  Future<bool> stopScan() async {
    try {
      final result = await _channel.invokeMethod('stopScan');
      return result as bool;
    } catch (e) {
      throw Exception('Failed to stop scan: $e');
    }
  }

  /// Clear the list of seen tags (for unique filtering)
  Future<bool> clearSeenTags() async {
    try {
      final result = await _channel.invokeMethod('clearSeenTags');
      return result as bool;
    } catch (e) {
      throw Exception('Failed to clear seen tags: $e');
    }
  }

  /// Set the RF power level (1-33)
  Future<bool> setPower(int powerLevel) async {
    if (powerLevel < 1 || powerLevel > 33) {
      throw ArgumentError('Power level must be between 1 and 33');
    }
    try {
      final result = await _channel.invokeMethod('setPower', {
        'powerLevel': powerLevel,
      });
      return result as bool;
    } catch (e) {
      throw Exception('Failed to set power: $e');
    }
  }

  /// Read data from a tag's memory
  /// 
  /// [tagId] - The EPC ID of the tag
  /// [memoryBank] - Memory bank (0=Reserved, 1=EPC, 2=TID, 3=User)
  /// [wordPtr] - Starting word pointer
  /// [length] - Number of words to read
  /// [password] - Access password (hex string, default "00000000")
  Future<String> readTagData({
    required String tagId,
    required int memoryBank,
    required int wordPtr,
    required int length,
    String password = "00000000",
  }) async {
    try {
      final result = await _channel.invokeMethod('readTagData', {
        'tagId': tagId,
        'memoryBank': memoryBank,
        'wordPtr': wordPtr,
        'length': length,
        'password': password,
      });
      return result as String;
    } catch (e) {
      throw Exception('Failed to read tag data: $e');
    }
  }

  /// Write data to a tag's memory
  /// 
  /// [tagId] - The EPC ID of the tag
  /// [memoryBank] - Memory bank (0=Reserved, 1=EPC, 2=TID, 3=User)
  /// [wordPtr] - Starting word pointer
  /// [dataHex] - Data to write (hex string)
  /// [password] - Access password (hex string, default "00000000")
  Future<bool> writeTagData({
    required String tagId,
    required int memoryBank,
    required int wordPtr,
    required String dataHex,
    String password = "00000000",
  }) async {
    try {
      final result = await _channel.invokeMethod('writeTagData', {
        'tagId': tagId,
        'memoryBank': memoryBank,
        'wordPtr': wordPtr,
        'dataHex': dataHex,
        'password': password,
      });
      return result as bool;
    } catch (e) {
      throw Exception('Failed to write tag data: $e');
    }
  }

  /// Write a new EPC to a tag
  /// 
  /// [newEpc] - New EPC value (hex string)
  /// [password] - Access password (hex string, default "00000000")
  Future<bool> writeEPC({
    required String newEpc,
    String password = "00000000",
  }) async {
    try {
      final result = await _channel.invokeMethod('writeEPC', {
        'newEpc': newEpc,
        'password': password,
      });
      return result as bool;
    } catch (e) {
      throw Exception('Failed to write EPC: $e');
    }
  }
}