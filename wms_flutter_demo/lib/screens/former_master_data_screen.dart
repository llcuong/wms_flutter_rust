import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants/app_colors.dart';
import '../components/common/app_modal.dart';
import '../components/common/rfid_scanned_items_modal.dart';
import '../widgets/bin_selection_modal.dart';
import '../components/common/filled_basket_qty_modal.dart';

import '../components/common/rack_detail_modal.dart';
import '../components/forms/form_section_card.dart';
import '../components/forms/form_text_field.dart';
import '../components/forms/form_dropdown_field.dart';
import '../components/forms/form_date_field.dart';
import '../services/rfid_scanner.dart';
import '../services/api_service.dart';
import '../models/scanned_item.dart';
import 'package:provider/provider.dart';
import '../config/localization/app_strings.dart';
import '../config/localization/localization_provider.dart';
import '../providers/former_master_data_provider.dart';

class FormerMasterDataScreen extends StatefulWidget {
  const FormerMasterDataScreen({Key? key}) : super(key: key);

  @override
  State<FormerMasterDataScreen> createState() => _FormerMasterDataScreenState();
}

class _FormerMasterDataScreenState extends State<FormerMasterDataScreen> 
    with SingleTickerProviderStateMixin {
  
  late TabController _tabController;
  
  // Form Controllers
  final _dnController = TextEditingController(text: 'FN0000002');

  final _usedDayController = TextEditingController(text: '0');
  final _purchQtyController = TextEditingController(text: '5');
  final _aqlController = TextEditingController(text: '1.0');
  final _batchController = TextEditingController(text: 'FNA381220531');
  final _poController = TextEditingController(text: 'PO123');
  final _dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]); // Added
  
  DateTime _dataDate = DateTime.now();
  late String _selectedBrand;
  late String _selectedType;
  late String _selectedSurface;
  late String _selectedSize;
  late String _selectedLength;
  late String _selectedItemNo;

  List<ParameterOption> _sizeOptions = [];
  List<ParameterOption> _lengthOptions = [];
  List<ParameterOption> _brandOptions = []; // Vendor
  List<ParameterOption> _itemNoOptions = [];


  // RFID Scanner
  final RfidScanner _rfidScanner = RfidScanner();
  double rfidPower = 25.0;
  bool isScanning = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;
  BasketMode _basketMode = BasketMode.full;
  int quantity = 0;

  StreamSubscription<TagData>? _tagSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<String>? _errorSubscription;

  // Batch Processing
  Timer? _batchTimer;
  bool _isProcessingBatch = false;

  bool _singleTagCaptured = false;

  bool get _isScanTabActive => _tabController.index == 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeDropdowns();
    _initializeDropdowns();
    _loadAllOptions();
    _initializeRfid();
    _restoreRackCache();
  }

  /// Load all parameter options from database
  Future<void> _loadAllOptions() async {
    await Future.wait([
      _loadOptions('size', (opts) => _sizeOptions = opts),
      _loadOptions('length', (opts) => _lengthOptions = opts),
      _loadOptions('vendor', (opts) => _brandOptions = opts),
      _loadOptions('itemno', (opts) => _itemNoOptions = opts),
    ]);
  }

  Future<void> _loadOptions(String group, Function(List<ParameterOption>) updateList) async {
    final options = await ApiService.getParameterOptions(group);
    if (options.isNotEmpty && mounted) {
      setState(() {
        updateList(options);
        
        // Auto-select first option if current selection is invalid or empty
        if (group == 'size' && !_sizeOptions.any((o) => o.name == _selectedSize)) {
            _selectedSize = _sizeOptions.first.name;
        }
        if (group == 'length' && !_lengthOptions.any((o) => o.name == _selectedLength)) {
            _selectedLength = _lengthOptions.first.name;
        }
        if (group == 'vendor' && !_brandOptions.any((o) => o.name == _selectedBrand)) {
            _selectedBrand = _brandOptions.first.name;
        }
        if (group == 'itemno' && !_itemNoOptions.any((o) => o.name == _selectedItemNo)) {
            _selectedItemNo = _itemNoOptions.first.name;
        }
      });
    }
  }

  Map<String, String> get _surfaceMap => {
    'Standard Fine Surface': AppStrings.standardFineSurface,
    'Standard Coarse Surface': AppStrings.standardCoarseSurface,
    'Standard Diamond Textured': AppStrings.standardDiamondTextured,
    'Energy-saving Fine Surface': AppStrings.energySavingFineSurface,
  };

  Map<String, String> get _typeMap => {
    'Ceramic': AppStrings.ceramic,
    'Stainless steel': AppStrings.stainlessSteel,
  };

  // Encoding/Decoding Maps
  static const _vendorCodes = {
    'Shinko': 'A', 'Jinhong': 'B', 'Mediceram': 'C', 'PT': 'D', 'HL': 'E'
  };
  static const _surfaceCodes = {
    'Standard Fine Surface': '1', 'Standard Coarse Surface': '2',
    'Standard Diamond Textured': '3', 'Energy-saving Fine Surface': '4'
  };
  static const _typeCodes = {'Stainless steel': '1', 'Ceramic': '2'};
  static const _sizeCodes = {
    'XXS': '0', 'XS': '1', 'S': '2', 'M': '3', 
    'L': '4', 'XL': '5', 'XXL': '6', 'XXXL': '7'
  };

  void _generateItemNo() {
    // Structure: FN + Vendor(1) + Length(2) + Surface(1) + Type(1) + Size(1)
    final vendorCode = _vendorCodes[_selectedBrand] ?? 'A';
    
    // Length: Take first 2 digits
    final lengthCode = _selectedLength.length >= 2 
        ? _selectedLength.substring(0, 2) 
        : '38';

    final surfaceCode = _surfaceCodes[_selectedSurface] ?? '1';
    final typeCode = _typeCodes[_selectedType] ?? '2';
    final sizeCode = _sizeCodes[_selectedSize] ?? '2';

    final newItemNo = 'FN$vendorCode$lengthCode$surfaceCode$typeCode$sizeCode';
    
    if (newItemNo != _selectedItemNo) {
      setState(() {
          _selectedItemNo = newItemNo;
      });
      _generateBatchNo(silent: true);
    }
  }

  void _parseItemNo(String itemNo) {
    if (itemNo.length < 8 || !itemNo.startsWith('FN')) return;

    try {
      final vendorCode = itemNo.substring(2, 3);
      final lengthCode = itemNo.substring(3, 5);
      final surfaceCode = itemNo.substring(5, 6);
      final typeCode = itemNo.substring(6, 7);
      final sizeCode = itemNo.substring(7, 8);

      // Find keys by value
      final brand = _vendorCodes.entries
          .firstWhere((e) => e.value == vendorCode, orElse: () => const MapEntry('Shinko', 'A'))
          .key;
      
      // Length (approximation logic: try to find matching start, else default)
      // Since existing lengths are 3 digits, we appened '0' or assume standard
      // Better: find closest option or just append '0' if it looks like a standard length prefix
      String length = _lengthOptions.isNotEmpty 
          ? _lengthOptions.firstWhere((o) => o.name.startsWith(lengthCode), orElse: () => _lengthOptions.first).name
          : '${lengthCode}0';
      if (!_lengthOptions.any((o) => o.name == length) && !['380','400','420','450'].contains(length)) {
          // If purely inferred
             length = '${lengthCode}0';
      }

      final surface = _surfaceCodes.entries
          .firstWhere((e) => e.value == surfaceCode, orElse: () => const MapEntry('Standard Fine Surface', '1'))
          .key;
      
      final type = _typeCodes.entries
          .firstWhere((e) => e.value == typeCode, orElse: () => const MapEntry('Ceramic', '2'))
          .key;
          
      final size = _sizeCodes.entries
          .firstWhere((e) => e.value == sizeCode, orElse: () => const MapEntry('S', '2'))
          .key;

      setState(() {
        _selectedBrand = brand;
        _selectedLength = length;
        _selectedSurface = surface;
        _selectedType = type;
        _selectedSize = size;
        _selectedItemNo = itemNo;
      });
      _generateBatchNo(silent: true);
    } catch (e) {
      print('Error parsing ItemNo: $e');
    }
  }


  void _initializeDropdowns() {
    _selectedBrand = 'Shinko'; // Default fallback
    _selectedType = 'Ceramic';
    _selectedSurface = 'Standard Fine Surface';
    _selectedSize = 'S'; // Default fallback
    _selectedLength = '380'; // Default fallback
    
    // Initial generation based on defaults
    // Structure: FN + Vendor(1) + Length(2) + Surface(1) + Type(1) + Size(1)
    // A + 38 + 1 + 2 + 2 = FNA38122
    _selectedItemNo = ''; // Initialize to prevent LateInitializationError
    _generateItemNo(); 
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dnController.dispose();
    _usedDayController.dispose();
    _purchQtyController.dispose();
    _aqlController.dispose();
    _batchController.dispose();
    _poController.dispose(); // Added
    _dateController.dispose(); // Added
    
    _tagSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    _batchTimer?.cancel();
    
    if (isScanning) _rfidScanner.stopScan();
    if (isConnected) _rfidScanner.disconnect();
    
    super.dispose();
  }

  Future<void> _initializeRfid() async {
    try {
      setState(() => scannerStatus = ScannerStatus.initializing);
      
      final initSuccess = await _rfidScanner.init();
      if (!initSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        return;
      }

      setState(() => scannerStatus = ScannerStatus.initialized);

      final connectSuccess = await _rfidScanner.connect();
      if (!connectSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        return;
      }

      setState(() {
        scannerStatus = ScannerStatus.connected;
        isConnected = true;
      });

      await _rfidScanner.setPower(_convertPowerToLevel(rfidPower));

      _tagSubscription = _rfidScanner.onTagScanned.listen(_handleTagScanned);
      _statusSubscription = _rfidScanner.onConnectionStatusChange.listen(_handleStatusChange);
      _errorSubscription = _rfidScanner.onError.listen((error) => _showError(AppStrings.rfidError, error));

      if (mounted) {
        AppModal.showSuccess(
          context: context,
          title: AppStrings.statusConnected,
          message: AppStrings.rfidReady,
        );
      }
    } catch (e) {
      setState(() => scannerStatus = ScannerStatus.disconnected);
    }
  }

  void _handleTagScanned(TagData tagData) {
    if (!_isScanTabActive) return;
    
    if (_basketMode == BasketMode.filled && _singleTagCaptured) return;

    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
    
    // Check duplicates via provider
    if (provider.isTagScanned(tagData.tagId)) return;

    if (_basketMode == BasketMode.filled) {
      _handleSingleFilledScan(tagData);
      return;
    }

    // Add to batch queue
    provider.addPendingTag(tagData.tagId, tagData);
    _resetBatchTimer();
  }

  void _resetBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 500), _processBatchQueue);
  }

  Future<void> _processBatchQueue() async {
    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
    if (provider.pendingTags.isEmpty || _isProcessingBatch) return;

    _isProcessingBatch = true;
    final batchMap = Map<String, TagData>.from(provider.pendingTags);
    // Clear pending tags locally or via provider call? Provider has keys.
    // Ideally we consume them.
    // But `_processBatchQueue` is asynchronous.
    // Let's modify logic: fetch IDs from provider, process, then add to scanned map.
    // Provider's pending tags are temporary holding.
    
    // Actually, let's just use the provider copy for processing.
    // And we should probably clear pending in provider?
    // The previous logic cleared `_pendingTags` before processing.
    // Let's do similar. But `pendingTags` getter is unmodifiable. 
    // We need a way to consume them.
    // But wait, `addPendingTag` adds to a map.
    // We can clear them by iterating or just clear all pending?
    // Since we process all:
    // We need to keep a copy of IDs to fetch.
    final batchIds = batchMap.keys.toList();
    
    // IMPORTANT: Clear pending in provider to prevent double processing if timer fires again?
    // Logic was: clear local map, then process.
    // We should probably have a `popPendingTags` method in provider? 
    // Or just clear pending explicitly.
    // But `removePendingTag` is one by one.
    // Let's rely on standard clear or maybe minimal impact:
    // Creating `consumePendingTags` in provider would be better.
    // For now, let's iterate to remove or just assume we process consistent snapshot.
    // Since `_pendingTags` is a valid public getter...
    // Let's just use `clearCurrentScan`? No that clears everything.
    // Just iterate keys and remove?
    // Or just:
    for (var id in batchIds) {
        provider.removePendingTag(id);
    }
    
    try {
      final baskets = await ApiService.getBasketsBatch(batchIds);

      if (!mounted) return;

      // Update Provider with results
      for (final basket in baskets) {
        final tagId = basket.tagId;
        // Re-check duplicates just in case (Provider check handles it on add, but double check safe)
        if (provider.isTagScanned(tagId)) continue;
        
        final originalTag = batchMap[tagId];
        final rssi = originalTag?.rssi ?? 0;

        int qty = 0;
        if (_basketMode == BasketMode.full) {
          qty = 5;
        } else if (_basketMode == BasketMode.empty) {
          qty = 0;
        }

        final item = ScannedItem(
          id: tagId,
          quantity: qty,
          vendor: basket.basketVendor,
          bin: basket.basketPurchaseOrder,
          status: ItemStatus.success,
          rssi: rssi,
          basketData: basket,
        );
        
        provider.addScannedItem(item);
      }
      
    } catch (e) {
      print('Batch processing error: $e');
    } finally {
      _isProcessingBatch = false;
      if (provider.pendingTags.isNotEmpty) {
        _resetBatchTimer();
      }
    }
  }

  Future<void> _handleSingleFilledScan(TagData tagData) async {
    _singleTagCaptured = true;
    await _rfidScanner.stopScan();

    setState(() {
      isScanning = false;
      scannerStatus = ScannerStatus.connected;
    });

    final selectedQty = await FilledBasketQtyModal.show(context);
    if (selectedQty == null) return;

    try {
      final basketData = await ApiService.getBasketData(tagData.tagId);

      if (basketData == null) return;

      setState(() {
        // _scannedItemsMap[tagData.tagId] = ScannedItem(...) ...
        
        final item = ScannedItem(
          id: tagData.tagId,
          quantity: selectedQty,
          vendor: basketData.basketVendor,
          bin: basketData.basketPurchaseOrder,
          status: ItemStatus.success,
          rssi: tagData.rssi,
          basketData: basketData,
        );

        Provider.of<FormerMasterDataProvider>(context, listen: false).addScannedItem(item);
        
        // _updateStats(); // Derived from provider now
      });
    } catch (e) {
      print('Single scan fetch error: $e');
    }
  }

  void _updateStats() {
    // This is now derived from provider state in build or via Consumer.
    // We can remove this method and rely on Provider getters.
  }

  void _handleStatusChange(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        setState(() {
          isConnected = true;
          scannerStatus = ScannerStatus.connected;
        });
        break;
      case ConnectionStatus.disconnected:
        setState(() {
          isConnected = false;
          isScanning = false;
          scannerStatus = ScannerStatus.disconnected;
        });
        break;
      case ConnectionStatus.scanStarted:
        setState(() {
          isScanning = true;
          scannerStatus = ScannerStatus.scanning;
        });
        break;
      case ConnectionStatus.scanStopped:
        setState(() {
          isScanning = false;
          scannerStatus = ScannerStatus.stopped;
        });
        break;
      default:
        break;
    }
  }

  int _convertPowerToLevel(double power) {
    return ((power / 50) * 32 + 1).round().clamp(1, 33);
  }

  Future<void> _startScanning() async {
    if (!isConnected) {
      _showError(AppStrings.notConnected, AppStrings.pleaseConnect);
      return;
    }

    if (_basketMode == BasketMode.filled) {
      _singleTagCaptured = false;
    }

    try {
      final success = await _rfidScanner.startScan(
        mode: ScanMode.continuous,
        uniqueOnly: true,
      );

      if (success) {
        setState(() {
          isScanning = true;
          scannerStatus = ScannerStatus.scanning;
        });
      }
    } catch (e) {
      _showError(AppStrings.startScanFailed, e.toString());
    }
  }

  Future<void> _stopScanning() async {
    try {
      final success = await _rfidScanner.stopScan();
      if (success) {
        setState(() {
          isScanning = false;
          scannerStatus = ScannerStatus.stopped;
        });
      }
    } catch (e) {
      _showError(AppStrings.stopScanFailed, e.toString());
    }
  }

  Future<void> _clearScannedItems() async {
    final confirm = await AppModal.showConfirm(
      context: context,
      title: AppStrings.clearAllItems,
      message: AppStrings.clearConfirmMessage,
    );

    if (confirm == true) {
      try {
        await _rfidScanner.clearSeenTags();
        _batchTimer?.cancel();
        await _rfidScanner.clearSeenTags();
        _batchTimer?.cancel();
        
        final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
        provider.clearCurrentScan();
        
        setState(() {
          // Local UI counters update if not using provider directly in build
          // But clearAllData clears everything. clearCurrentScan only clears map.
          // _totalBaskets etc should reset?
          // provider.clearCurrentScan(); // resets map
        });
      } catch (e) {
        _showError(AppStrings.clearFailed, e.toString());
      }
    }
  }

  void _showError(String title, String message) {
    AppModal.showError(context: context, title: title, message: message);
  }

  void _showWarning(String title, String message) {
    AppModal.showWarning(context: context, title: title, message: message);
  }

  Future<void> _showScannedItemsModal() async {
    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
    if (provider.scannedItemsMap.isEmpty) {
      _showError(AppStrings.empty, AppStrings.noScannedItems);
      return;
    }

    await RfidScannedItemsModal.show(
      context: context,
      scannedItemsMap: provider.scannedItemsMap,
      onBinLocationChanged: (item, bin) {
        // ScannedItem is reference type, modifying it inside map is fine if we notify listeners?
        // Provider's map is unmodifiable but items are likely mutable?
        // Actually ScannedItem fields are mutable (except final ones).
        // bin is mutable.
        // We should notify listeners to update UI if needed.
        item.bin = bin;
        provider.notifyListeners(); // We need to expose notifyListeners or a method "updateItem"
        // But invalidating protected notifyListeners access...
        // Better add update method:
        // provider.updateItemBin(item.id, bin);
        // For now, let's assume direct mutation works for object ref, but UI won't rebuild unless we trigger update.
        // Let's add updateItemBin to provider or just trigger a refresh.
        // Since we don't have updateItemBin yet, let's just setState here if it affects local UI? No, moved to provider.
        // Quick fix: iterate values?
        // Actually, the modal callback updates the item reference.
        // We just need to tell provider to notify.
        // `provider.addScannedItem(item)` (re-adding) might trigger notify.
        provider.addScannedItem(item); 
      },
    );
  }

  String get _rackCacheKey {
    return 'former_master_data_rack_temp';
  }

  Future<void> _saveRackCache() async {
    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);

    final prefs = await SharedPreferences.getInstance();

    final data = {
      'racks': provider.racks.map((e) => e.toJson()).toList(),
      'allRackTagIds': provider.allRackTagIds.toList(),
    };

    await prefs.setString(_rackCacheKey, jsonEncode(data));
  }

  Future<void> _restoreRackCache() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = context.read<FormerMasterDataProvider>();

    final jsonString = prefs.getString(_rackCacheKey);
    if (jsonString == null) return;

    final decoded = jsonDecode(jsonString);

    final racks = (decoded['racks'] as List)
        .map((e) => Rack.fromJson(e))
        .toList();

    final tagIds = (decoded['allRackTagIds'] as List).cast<String>().toSet();

    provider.restoreCache(
      racks: racks,
      tagIds: tagIds,
    );
  }

  AreaData? _lastSelectedArea;

  Future<void> _addCurrentScannedToBatch() async {
    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
    if (provider.scannedItemsMap.isEmpty) {
      AppModal.showWarning(
        context: context,
        title: AppStrings.warning,
        message: 'Chưa có dữ liệu scan nào để thêm', 
      );
      return;
    }

    // Show Bin Selection Modal
    final selectedArea= await showDialog<AreaData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: BinSelectionModal(
            lastSelected: _lastSelectedArea,
            incomingQty: provider.scannedCount,
            rackData: provider.racks,
            currentScannedItems: provider.scannedItemsMap,
        ),
      ),
    );

    if (selectedArea == null) {
      // User cancelled
      return;
    }

    // Provider handles the logic
    final nextRackNo = provider.racks.length + 1;
    provider.addCurrentScanToRack(nextRackNo, selectedArea.name);

    await _saveRackCache();

    AppModal.showSuccess(
      context: context,
      title: AppStrings.success,
      message: 'Đã thêm vào danh sách lô tạm tính',
    );
  }

  Future<void> _saveAllBatches() async {
    final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
    // Check if there are any items to save (either in racks or current scan)
    if (provider.racks.isEmpty && provider.scannedItemsMap.isEmpty) {
      AppModal.showWarning(
        context: context,
        title: AppStrings.warning,
        message: 'Không có dữ liệu nào để lưu',
      );
      return;
    }

    // Check if there are pending items not added to batch
    if (provider.scannedItemsMap.isNotEmpty) {
      final bool? confirmAdd = await AppModal.showConfirm(
        context: context,
        title: 'Xác nhận',
        message: 'Bạn có items đã scan nhưng chưa "Thêm" vào danh sách. Bạn có muốn thêm chúng vào lô mới trước khi lưu không?',
        confirmText: 'Có, thêm và lưu',
        cancelText: 'Không, chỉ lưu danh sách đã thêm',
      );

      if (confirmAdd == true) {
        // Add current scanned to batch first
         final selectedArea = await showDialog<AreaData>(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            child: BinSelectionModal(
                lastSelected: _lastSelectedArea,
                incomingQty: provider.scannedCount,
                rackData: provider.racks,
                currentScannedItems: provider.scannedItemsMap,
            ),
          ),
        );
        if (selectedArea == null) return; // Cancelled
        
        final nextRackNo = provider.racks.length + 1;
        provider.addCurrentScanToRack(nextRackNo, selectedArea.name);
      }
    }
    
    // Validate Batch No
    final batchNo = _batchController.text.trim();
    if (batchNo.isEmpty) {
      AppModal.showWarning(
        context: context,
        title: AppStrings.warning,
        message: 'Vui lòng tạo hoặc nhập số Batch (Batch No)',
      );
      return;
    }

    final bool? confirm = await AppModal.showConfirm(
      context: context,
      title: 'Lưu Batch',
      message: 'Bạn có chắc chắn muốn lưu ${provider.racks.length} rack(s) vào hệ thống?',
    );

    if (confirm != true) return;

    // Gather Master Info
    final masterInfo = {
      'former_size': _selectedSize,
      'former_vendor': _selectedBrand,
      'former_type': _selectedType,
      'former_surface': _selectedSurface,
      'former_length': double.tryParse(_selectedLength) ?? 0.0,
      'former_purchase_order': int.tryParse(_purchQtyController.text) ?? 0,
      'former_item_no': _selectedItemNo,
      'former_used_day': int.tryParse(_usedDayController.text) ?? 0,
      'former_aql': double.tryParse(_aqlController.text) ?? 1.0,
      'former_receive_form': _dnController.text, // Added
      'batch_data_date': _dateController.text, // Ensure YYYY-MM-DD
    };

    try {
      // Call provider to save
      await provider.saveBatch(masterInfo, batchNo);

      if (mounted) {
        _saveRackCache();

        AppModal.showSuccess(
          context: context,
          title: AppStrings.success,
          message: 'Lưu Batch thành công!',
        );
        // Clear batch number maybe?
        // _batchController.clear(); 
      }
    } catch (e) {
      if (mounted) {
        AppModal.showError(
          context: context,
          title: AppStrings.error,
          message: 'Lỗi khi lưu Batch: $e',
        );
      }
    }
  }

  Future<void> _deleteRack(int rackNo) async {
      Provider.of<FormerMasterDataProvider>(context, listen: false).deleteRack(rackNo);
      await _saveRackCache();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMasterInfoTab(),
                _buildScanTagTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white.withOpacity(0.9),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        AppStrings.formerMasterData,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        Consumer<LocalizationProvider>(
          builder: (context, provider, child) {
            return PopupMenuButton<String>(
              icon: const Icon(Icons.language, color: AppColors.textPrimary),
              tooltip: 'Chọn ngôn ngữ / Select Language',
              onSelected: (String locale) {
                provider.setLocale(locale);
                AppStrings.setLocale(locale);
                // Re-initialize dropdowns to match new translated items
                setState(() {
                  _initializeDropdowns();
                });
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'vi',
                  child: Row(
                    children: [
                      Icon(
                        provider.currentLocale == 'vi' ? Icons.check : null,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('🇻🇳 Tiếng Việt'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'en',
                  child: Row(
                    children: [
                      Icon(
                        provider.currentLocale == 'en' ? Icons.check : null,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('🇬🇧 English'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.history, color: AppColors.textTertiary),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: Container(
        decoration: BoxDecoration(
            color: AppColors.slate100.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(2),
        child: TabBar(
            controller: _tabController,

            // ⭐ KEY SETTINGS
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            indicatorSize: TabBarIndicatorSize.tab,

            indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
                BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
                ),
            ],
            ),
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            ),
            unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            ),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: AppStrings.masterInfo),
              Tab(text: AppStrings.scanTag),
            ],
        ),
        ),
    );
  }

  Future<void> _generateBatchNo({bool silent = false}) async {
    if (_selectedItemNo.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn Mã sản phẩm trước')),
        );
      }
      return;
    }

    try {
      final batchNo = await ApiService.generateBatchNo(_selectedItemNo);
      if (batchNo != null) {
        setState(() {
          _batchController.text = batchNo;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tạo số lô thành công'), 
              backgroundColor: Colors.green
            ),
          );
        }
      } else {
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể tạo số lô'), 
              backgroundColor: Colors.red
            ),
          );
        }
      }
    } catch (e) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildMasterInfoTab() {
    Timer? _dnDebounce;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Identification Section
          FormSectionCard(
            icon: Icons.tag,
            title: AppStrings.identification,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormTextField(
                      label: AppStrings.dn,
                      required: true,
                      controller: _dnController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormDropdownField<String>(
                      label: AppStrings.itemNo,
                      required: true,
                      value: _selectedItemNo,


                      items: _itemNoOptions.map((o) => o.name).toSet().union({_selectedItemNo}).toList(),
                      itemLabel: (item) => item,
                      onChanged: (value) {
                         if (value != null) {
                             _parseItemNo(value); 
                         }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Tracking & Qty Section
          FormSectionCard(
            icon: Icons.analytics,
            title: AppStrings.trackingAndQty,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormTextField(
                      label: AppStrings.usedDay,
                      required: true,
                      keyboardType: TextInputType.number,
                      controller: _usedDayController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormTextField(
                      label: AppStrings.purchQty,
                      required: true,
                      keyboardType: TextInputType.number,
                      controller: _purchQtyController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FormDateField(
                label: AppStrings.dataDate,
                required: true,
                value: _dataDate,
                onChanged: (date) => setState(() => _dataDate = date),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          FormSectionCard(
            icon: Icons.settings_input_component,
            title: AppStrings.specifications,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormDropdownField<String>(
                      label: AppStrings.brand,
                      required: true,
                      value: _selectedBrand,
                      items: _brandOptions.isNotEmpty 
                          ? _brandOptions.map((o) => o.name).toSet().union({_selectedBrand}).toList()
                          : ['Shinko', 'Jinhong', 'Mediceram', 'PT', 'HL'].toSet().union({_selectedBrand}).toList(),
                      itemLabel: (item) => item,
                      onChanged: (value) {
                        setState(() => _selectedBrand = value!);
                        _generateItemNo();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormDropdownField<String>(
                      label: AppStrings.type,
                      required: true,
                      value: _selectedType,
                      items: _typeMap.keys.toSet().union({_selectedType}).toList(),
                      itemLabel: (item) => _typeMap[item] ?? item,
                      onChanged: (value) {
                        setState(() => _selectedType = value!);
                        _generateItemNo();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FormDropdownField<String>(
                label: AppStrings.surface,
                required: true,
                value: _selectedSurface,
                items: _surfaceMap.keys.toSet().union({_selectedSurface}).toList(),
                itemLabel: (item) => _surfaceMap[item] ?? item,
                onChanged: (value) {
                    setState(() => _selectedSurface = value!);
                    _generateItemNo();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FormDropdownField<String>(
                      label: AppStrings.size,
                      required: true,
                      value: _selectedSize,
                      items: _sizeOptions.isNotEmpty 
                          ? _sizeOptions.map((o) => o.name).toSet().union({_selectedSize}).toList()
                          : const ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'].toSet().union({_selectedSize}).toList(),
                      itemLabel: (item) => item,
                      onChanged: (value) {
                          setState(() => _selectedSize = value!);
                          _generateItemNo();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FormDropdownField<String>(
                      label: AppStrings.chieuDai,
                      required: true,
                      value: _selectedLength,
                      items: _lengthOptions.isNotEmpty
                          ? _lengthOptions.map((o) => o.name).toSet().union({_selectedLength}).toList()
                          : const ['380', '400', '420', '450'].toSet().union({_selectedLength}).toList(),
                      itemLabel: (item) => item,
                      onChanged: (value) {
                          setState(() => _selectedLength = value!);
                          _generateItemNo();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          FormSectionCard(
            icon: Icons.verified,
            title: AppStrings.lo,
            children: [
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FormTextField(
                      label: AppStrings.soLo,
                      required: true,
                      placeholder: AppStrings.nhapSoLo,
                      controller: _batchController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 50, // Match typical input height
                    child: ElevatedButton.icon(
                      onPressed: () => _generateBatchNo(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.bolt, size: 20),
                      label: const Text('Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanTagTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildBasketModeSelector(),
          const SizedBox(height: 24),
          _buildStatsCards(),
          const SizedBox(height: 24),
          _buildRFIDScannerCard(),
          const SizedBox(height: 24),
          if (isScanning) _buildScanningIndicator(),
        ],
      ),
    );
  }

  Widget _buildBasketModeSelector() {
    Widget buildButton(BasketMode mode, String label) {
      final bool selected = _basketMode == mode;

      return Expanded(
        child: GestureDetector(
          onTap: () async {
            setState(() => _basketMode = mode);
            if (mode == BasketMode.filled) {
              await _rfidScanner.stopScan();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          buildButton(BasketMode.full, AppStrings.roDay),
          buildButton(BasketMode.filled, AppStrings.roChuaDay),
          buildButton(BasketMode.empty, AppStrings.roRong),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: Consumer<FormerMasterDataProvider>(
            builder: (context, provider, _) => _buildStatCard(
              AppStrings.ro, 
              provider.totalBaskets.toString(), // or derive from scannedItemsMap
              AppColors.textPrimary, 
              true,
              scannedCount: provider.scannedCount,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Consumer<FormerMasterDataProvider>(
            builder: (context, provider, _) => _buildStatCard(
              AppStrings.khuon, 
              provider.scannedItemsMap.values.fold<int>(0, (sum, i) => sum + i.quantity).toString(), // _totalFormers
              AppColors.primary, 
              true,
              scannedCount: provider.scannedCount,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Consumer<FormerMasterDataProvider>(
             builder: (context, provider, _) => _buildStatCard(
                AppStrings.rack,
                provider.racks.length.toString().padLeft(1, '0'),
                const Color(0xFFE11D48),
                false,
                scannedCount: provider.scannedCount, 
              ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    bool isClickableForItems, {
    int scannedCount = 0,
  }) {
    final isRack = label == AppStrings.rack;
    
    return GestureDetector(
      onTap: isRack
          ? () {
              final provider = Provider.of<FormerMasterDataProvider>(context, listen: false);
              RackDetailModal.show(
                context: context,
                racks: provider.racks,
                onDelete: _deleteRack,
                onUpdateBin: (rackNo, newBinId) async { provider.updateRackBin; await _saveRackCache();},
              );
            }
          : isClickableForItems
              ? _showScannedItemsModal
              : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRack ? const Color(0xFFFFF1F2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRack ? const Color(0xFFFFE4E6) : AppColors.slate100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isRack
                        ? const Color(0xFFE11D48)
                        : AppColors.textSecondary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (isClickableForItems && scannedCount > 0) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.visibility,
                    size: 12,
                    color: color.withOpacity(0.6),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRFIDScannerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.rfidPower,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${rfidPower.round()}',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppStrings.dBm,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sensors, color: AppColors.primary, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getScannerStatusColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getScannerStatusColor().withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getScannerStatusColor(),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _getScannerStatusColor().withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.scanStatus,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getScannerStatusText(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _getScannerStatusColor(),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (scannerStatus == ScannerStatus.scanning)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getScannerStatusColor(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() => rfidPower = (rfidPower - 1).clamp(0, 50));
                      },
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 6,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.slate200,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 14,
                            elevation: 4,
                          ),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                          overlayColor: AppColors.primary.withOpacity(0.1),
                        ),
                        child: Slider(
                          value: rfidPower,
                          min: 0,
                          max: 50,
                          onChanged: (value) => setState(() => rfidPower = value),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() => rfidPower = (rfidPower + 1).clamp(0, 50));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.slate100)),
            ),
            child: Row(
              children: [
                _buildScanButton(Icons.play_circle, AppStrings.quetTag, AppColors.success, _startScanning),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.pause_circle, AppStrings.dungTag, AppColors.textTertiary, _stopScanning),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.refresh, AppStrings.xoaTag, const Color(0xFFE11D48), _clearScannedItems),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanningIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.statusScanning,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                  Consumer<FormerMasterDataProvider>(
                    builder: (context, provider, _) => Text(
                        '${provider.scannedCount} ${AppStrings.ro} • Ấn để xem',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getScannerStatusColor() {
    switch (scannerStatus) {
      case ScannerStatus.disconnected:
        return AppColors.error;
      case ScannerStatus.initializing:
        return AppColors.warning;
      case ScannerStatus.initialized:
        return AppColors.info;
      case ScannerStatus.connected:
        return AppColors.success;
      case ScannerStatus.scanning:
        return AppColors.primary;
      case ScannerStatus.stopped:
        return AppColors.textSecondary;
    }
  }

  String _getScannerStatusText() {
    switch (scannerStatus) {
      case ScannerStatus.disconnected:
        return AppStrings.statusDisconnected;
      case ScannerStatus.initializing:
        return AppStrings.statusInitializing;
      case ScannerStatus.initialized:
        return AppStrings.statusInitialized;
      case ScannerStatus.connected:
        return AppStrings.statusConnected;
      case ScannerStatus.scanning:
        return AppStrings.statusScanning;
      case ScannerStatus.stopped:
        return AppStrings.statusStopped;
    }
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        border: const Border(top: BorderSide(color: AppColors.slate200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _addCurrentScannedToBatch,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                label: const Text(
                  'Thêm',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveAllBatches,
                icon: const Icon(Icons.check, size: 20),
                label: Text(
                  AppStrings.save,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


