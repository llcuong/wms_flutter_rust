import 'package:flutter/material.dart';
import '../models/scanned_item.dart';
import '../services/api_service.dart';
import '../services/rfid_scanner.dart';

class FormerMasterDataProvider extends ChangeNotifier {
  // Local storage state
  final List<Rack> _racks = [];
  final Map<String, ScannedItem> _scannedItemsMap = {};
  final Set<String> _allRackTagIds = {};
  final Map<String, TagData> _pendingTags = {};

  // Getters
  List<Rack> get racks => List.unmodifiable(_racks);
  Map<String, ScannedItem> get scannedItemsMap => Map.unmodifiable(_scannedItemsMap);
  Set<String> get allRackTagIds => Set.unmodifiable(_allRackTagIds);
  Map<String, TagData> get pendingTags => Map.unmodifiable(_pendingTags);

  int get totalBaskets => _scannedItemsMap.values.where((e) => e.bin.isNotEmpty).length; // Assuming bin != empty implies basket? Adjust based on logic
  // Replicating logic from screen: _totalBaskets++ in handleTagScanned
  // Actually, better to compute getters or duplicate the counters if logic is complex.
  // In screen: 
  // _totalBaskets += 1; // simple increment on scan
  // but cleared on clear.
  // Let's compute from map for consistency?
  // Looking at screen code:
  // _totalBaskets++ when valid tag added.
  // _totalFormers++ when valid tag added.
  // Actually, ScannedItem doesn't seem to distinguish basket vs former clearly in the model definition provided earlier,
  // but screen logic seems to count every scan as both? Or just 1 scan = 1 item.
  // Let's keep simple counters or derived getters.
  // Based on previous screen code:
  // _totalBaskets and _totalFormers were just counters.
  // Let's derive them from _scannedItemsMap size for now to avoid sync issues.
  int get scannedCount => _scannedItemsMap.length;

  // Actions

  bool isTagScanned(String tagId) {
    return _scannedItemsMap.containsKey(tagId) || 
           _pendingTags.containsKey(tagId) || 
           _allRackTagIds.contains(tagId);
  }

  void addPendingTag(String tagId, TagData data) {
    if (isTagScanned(tagId)) return;
    _pendingTags[tagId] = data;
    notifyListeners();
  }

  void removePendingTag(String tagId) {
    _pendingTags.remove(tagId);
    notifyListeners();
  }

  void addScannedItem(ScannedItem item) {
    if (isTagScanned(item.id)) return;
    _scannedItemsMap[item.id] = item;
    notifyListeners();
  }

  void clearCurrentScan() {
    _scannedItemsMap.clear();
    _pendingTags.clear();
    notifyListeners();
  }

  void addCurrentScanToRack(int rackNo, String bin) {
    if (_scannedItemsMap.isEmpty) return;

    final newRack = Rack(
      rackNo: rackNo,
      bin: bin,
      items: _scannedItemsMap.values.toList(),
    );
    _racks.add(newRack);
    _allRackTagIds.addAll(_scannedItemsMap.keys);
    
    // Clear current scan, but NOT pending if any (though usually empty by now)
    _scannedItemsMap.clear();
    notifyListeners();
  }

  void deleteRack(int rackNo) {
    final index = _racks.indexWhere((r) => r.rackNo == rackNo);
    if (index != -1) {
      final rack = _racks[index];
      // Remove tags from global set
      for (var item in rack.items) {
        _allRackTagIds.remove(item.id);
      }
      _racks.removeAt(index);
      notifyListeners();
    }
  }

  void updateRackBin(int rackNo, String newBin) {
    final index = _racks.indexWhere((r) => r.rackNo == rackNo);
    if (index != -1) {
      _racks[index].bin = newBin;
      notifyListeners();
    }
  }

  void clearAllData() {
    _racks.clear();
    _allRackTagIds.clear();
    _scannedItemsMap.clear();
    _pendingTags.clear();
    notifyListeners();
  }

  void restoreCache({
    required List<Rack> racks,
    required Set<String> tagIds,
  }) {
    _racks
      ..clear()
      ..addAll(racks);

    _allRackTagIds
      ..clear()
      ..addAll(tagIds);

    notifyListeners();
  }


  Future<void> saveBatch(Map<String, dynamic> masterInfo, String batchNo) async {
    // Construct payload
    final racksData = _racks.map((rack) {
      return {
        // 'rack_no': rack.rackNo, // Backend comment says optional
        'items': rack.items.map((item) {
          return {
            'tag_id': item.id,
            'quantity': item.quantity,
            'bin': rack.bin, // Use rack's bin
            // 'basket_vendor': item.vendor,
          };
        }).toList(),
      };
    }).toList();

    // Map master info keys if needed to match backend expectations
    // Backend expects snake_case keys like 'former_size', 'former_vendor' etc.
    // Ensure masterInfo passed from screen has correct keys.

    final requestData = {
      'batch_no': batchNo,
      'master_info': masterInfo,
      'racks': racksData,
      'user_id': 'admin', // Placeholder or get from auth provider
    };

    await ApiService.saveBatch(requestData);
    clearAllData();
  }
}
