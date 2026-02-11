import '../services/api_service.dart';

enum ItemStatus {
  success,
  duplicate,
  error,
  pending,
}

class ScannedItem {
  final String id;
  int quantity;
  String vendor;
  String bin;
  ItemStatus status;
  final int rssi;
  String? errorMessage;
  BasketData? basketData;

  ScannedItem({
    required this.id,
    required this.quantity,
    required this.vendor,
    required this.bin,
    required this.status,
    required this.rssi,
    this.errorMessage,
    this.basketData,
  });
}

class Rack {
  final int rackNo;
  final DateTime createdAt;
  String bin;
  final List<ScannedItem> items;

  Rack({
    required this.rackNo,
    required this.items,
    this.bin = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

enum ScannerStatus {
  disconnected,
  initializing,
  initialized,
  connected,
  scanning,
  stopped,
}

enum BasketMode { full, filled, empty }
