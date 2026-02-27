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

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'quantity': quantity,
    'vendor': vendor,
    'bin': bin,
    'status': status.name, // enum → string
    'rssi': rssi,
    'errorMessage': errorMessage,
    'basketData': basketData?.toJson(),
  };

  factory ScannedItem.fromJson(Map<String, dynamic> json) => ScannedItem(
    id: json['id'],
    quantity: json['quantity'],
    vendor: json['vendor'],
    bin: json['bin'],
    status: ItemStatus.values.byName(json['status']),
    rssi: json['rssi'],
    errorMessage: json['errorMessage'],
    basketData: json['basketData'] != null
        ? BasketData.fromJson(json['basketData'])
        : null,
  );
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

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'rackNo': rackNo,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
  };

  // Create from JSON
  factory Rack.fromJson(Map<String, dynamic> json) => Rack(
    rackNo: json['rackNo'],
    createdAt: DateTime.parse(json['createdAt']),
    items: (json['items'] as List)
        .map((e) => ScannedItem.fromJson(e))
        .toList(),
  );
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
