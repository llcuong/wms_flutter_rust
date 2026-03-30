import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../components/common/stock_out_action_modal.dart';
import '../components/common/warehouse_selection_modal.dart';
import '../config/constants/app_colors.dart';
import '../components/common/custom_card.dart';
import '../components/common/app_modal.dart';
import '../components/common/basket_detail_modal.dart';
import '../helpers/warehouse_validator.dart';
import '../widgets/bin_selection_modal.dart';
import '../components/common/rack_detail_modal.dart';
import '../components/common/filled_basket_qty_modal.dart';
import '../components/common/rfid_scanned_items_modal.dart';
import '../services/rfid_scanner.dart';
import '../services/api_service.dart';
import '../models/scanned_item.dart';

class EmptyFormerStockOutScreen extends StatefulWidget {
  const EmptyFormerStockOutScreen({super.key});

  @override
  State<EmptyFormerStockOutScreen> createState() => _EmptyFormerStockOutScreenState();
}

class _EmptyFormerStockOutScreenState extends State<EmptyFormerStockOutScreen> {
  final RfidScanner _rfidScanner = RfidScanner();

  // Warehouse
  String _warehouseCode = '';

  double rfidPower = 25.0;
  int selectedPowerLevel = 1;
  bool isScanning = false;
  bool isInitialized = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;

  // Stock Out Action
  StockOutActionResult? _currentAction;
  TransitSelection? _transitSelection;
  bool _hasSelectedAction = false;

  // Machine & Line Selection
  List<MachineData> _machines = [];
  MachineData? _selectedMachine;
  final List<String> _lines = ['A1', 'A2', 'B1', 'B2'];
  String _selectedLine = 'A1';

  // Stockout Form (for transit)
  String? _generatedStockForm;

  final Map<String, ScannedItem> _scannedItemsMap = {};
  List<ScannedItem> get scannedItems =>
      _scannedItemsMap.values.toList().reversed.toList();

  StreamSubscription<TagData>? _tagSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<String>? _errorSubscription;

  final List<Rack> _racks = [];
  int get currentRackNo => _racks.length + 1;

  final Set<String> _allRackTagIds = {};

  // Batch Processing
  final Map<String, TagData> _pendingTags = {};
  Timer? _batchTimer;
  bool _isProcessingBatch = false;
  bool _isWarningShowing = false;
  bool _shouldStopProcessing = false;

  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode.requestFocus();
    _initializeRfid();
    _loadMachines();

    // Show action modal after initial setup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showActionModal();
    });
  }

  Future<void> _showActionModal() async {
    final action = await StockOutActionModal.show(context);
    if (action == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    if (action.action == StockOutAction.exit) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() {
        _currentAction = action;
        _hasSelectedAction = true;
        if (action.isTransit) {
          _transitSelection = action.transitSelection;
          // Generate stock form for transit
          _generateStockFormFallback();
        } else {
          _transitSelection = null;
          _generatedStockForm = null;
        }
      });
      _singleTagCaptured = false;
    } else if (mounted) {
      // If user closes the modal without selection, go back
      Navigator.pop(context);
    }
  }

  Future<void> _changeAction() async {
    // Reset flags when changing action
    _isWarningShowing = false;
    _shouldStopProcessing = false;
    _singleTagCaptured = false;

    // Stop scanning if active
    if (isScanning) {
      await _stopScanning();
    }

    final action = await StockOutActionModal.show(context);
    if (action != null && mounted) {
      setState(() {
        _currentAction = action;
        if (action.isTransit) {
          _transitSelection = action.transitSelection;
          _generateStockFormFallback();
        } else {
          _transitSelection = null;
          _generatedStockForm = null;
        }
      });

      // Clear all scanned items and pending tags
      setState(() {
        _scannedItemsMap.clear();
        _pendingTags.clear();
        _racks.clear();
        _allRackTagIds.clear();
      });

      await _rfidScanner.clearSeenTags();

      AppModal.showSuccess(
        context: context,
        title: 'Action Changed',
        message: 'New action: ${action.displayText}',
      );
    }
  }

  Future<void> _loadMachines() async {
    final machines = await ApiService.getMachines();
    if (mounted) {
      setState(() {
        _machines = machines;
      });
    }
  }

  void _generateStockFormFallback() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');

    String stockForm;

    final prefix = _currentAction?.transitSelection?.to == 'LK'
        ? 'LK'
        : 'GD';

    final random = Random();
    final randomDigits = random.nextInt(100).toString().padLeft(2, '0');
    final randomChars = String.fromCharCodes([
      65 + random.nextInt(26),
      65 + random.nextInt(26),
    ]);

    stockForm = '$prefix$yy$randomDigits$mm$dd$randomChars';

    setState(() {
      _generatedStockForm = stockForm;
    });
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    if (isScanning) {
      _rfidScanner.stopScan();
    }
    if (isConnected) {
      _rfidScanner.disconnect();
    }

    _keyboardFocusNode.dispose();

    super.dispose();
  }

  Future<void> _initializeRfid() async {
    try {
      setState(() => scannerStatus = ScannerStatus.initializing);

      final warehouse = await WarehouseSelectionModal.getSavedWarehouse();
      _warehouseCode = warehouse != null ? warehouse.shortName : 'GD';

      final initSuccess = await _rfidScanner.init();
      if (!initSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        _showError('Initialization Failed', 'Could not initialize RFID scanner');
        return;
      }

      setState(() {
        isInitialized = true;
        scannerStatus = ScannerStatus.initialized;
      });

      final connectSuccess = await _rfidScanner.connect();
      if (!connectSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        _showError('Connection Failed', 'Could not connect to RFID scanner');
        return;
      }

      setState(() {
        scannerStatus = ScannerStatus.connected;
        isConnected = true;
      });

      await _rfidScanner.setPower(_convertPowerToLevel(rfidPower));

      _tagSubscription = _rfidScanner.onTagScanned.listen(
        _handleTagScanned,
        onError: (error) => _showError('Scan Error', error.toString()),
      );

      _statusSubscription = _rfidScanner.onConnectionStatusChange.listen(
        _handleStatusChange,
      );

      _errorSubscription = _rfidScanner.onError.listen(
            (error) => _showError('RFID Error', error),
      );

      AppModal.showSuccess(
        context: context,
        title: 'Connected',
        message: 'RFID scanner initialized successfully',
      );
    } catch (e) {
      setState(() => scannerStatus = ScannerStatus.disconnected);
      _showError('Initialization Error', e.toString());
    }
  }

  bool _singleTagCaptured = false;

  static const List<String> _validRfidPrefixes = ['3001', '3002', '3003'];

  bool _isValidRfidTag(String tagId) {
    return _validRfidPrefixes.any((prefix) => tagId.startsWith(prefix));
  }

  void _handleTagScanned(TagData tagData) {
    if (_singleTagCaptured) return;
    if (_shouldStopProcessing) return;
    if (_isWarningShowing) return;

    final tagId = tagData.tagId;

    if (!_isValidRfidTag(tagId)) {
      return;
    }

    // Already exists in ANY rack
    if (_allRackTagIds.contains(tagId)) {
      return;
    }

    // Already scanned in current session
    if (_scannedItemsMap.containsKey(tagId) || _pendingTags.containsKey(tagId)) {
      return;
    }

    // Add to batch queue
    _pendingTags[tagId] = tagData;
    _resetBatchTimer();
  }

  void _resetBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 500), _processBatchQueue);
  }

  Future<void> _processBatchQueue() async {
    if (_pendingTags.isEmpty || _isProcessingBatch) return;
    if (_shouldStopProcessing) return;
    if (_isWarningShowing) return;

    _isProcessingBatch = true;
    final batchMap = Map<String, TagData>.from(_pendingTags);
    _pendingTags.clear();
    final batchIds = batchMap.keys.toList();

    try {
      // Determine binLocation based on action type
      // String binLocation = '';
      // if (_currentAction?.isProduction == true) {
      //   binLocation = 'X'; // Production uses 'X'
      // } else if (_currentAction?.isTransit == true) {
      //   // For transit, use the destination location
      //   binLocation = _currentAction?.toLocation ?? '';
      // }

      final baskets = await ApiService.getBasketsStockOutBatch(
          batchIds,
          binLocation: 'X',
          warehouse: _warehouseCode
      );

      if (!mounted) return;

      if (_shouldStopProcessing) {
        _isProcessingBatch = false;
        return;
      }

      final validBaskets = WarehouseValidator.validateAndFilter(
        baskets,
        _warehouseCode,
        context,
        originalTagIds: batchIds,
        requiredBinLocation: 'X',
        onInvalidFound: () {
          if (!_isWarningShowing && !_shouldStopProcessing) {
            _isWarningShowing = true;
            _shouldStopProcessing = true;

            // Stop scanning immediately
            _rfidScanner.stopScan();

            if (mounted) {
              setState(() {
                isScanning = false;
                scannerStatus = ScannerStatus.stopped;
              });
            }
          }
        },
      );

      // If invalid baskets found, validBaskets will be empty, so don't process anything
      if (validBaskets.isEmpty) {
        _isProcessingBatch = false;
        return;
      }

      if (_shouldStopProcessing) {
        _isProcessingBatch = false;
        return;
      }

      setState(() {
        for (final basket in validBaskets) {
          final tagId = basket.tagId;
          // Re-check duplicates just in case
          if (_scannedItemsMap.containsKey(tagId)) continue;

          final originalTag = batchMap[tagId];
          final rssi = originalTag?.rssi ?? 0;

          // For production, quantity is always 0 (empty formers)
          final quantity = _currentAction?.isProduction == true ? 0 : 1;

          // For transit, use transit selection for bin
          String bin = '';
          if (_currentAction?.isTransit == true) {
            bin = _currentAction?.toLocation ?? '';
          } else if (_currentAction?.isProduction == true) {
            bin = 'X';
          }

          _scannedItemsMap[tagId] = ScannedItem(
            id: tagId,
            quantity: 0,
            vendor: basket.basketVendor,
            bin: bin,
            status: ItemStatus.success,
            rssi: rssi,
            basketData: basket,
          );
        }
      });
    } catch (e) {
      print('Batch processing error: $e');
    } finally {
      _isProcessingBatch = false;
      if (_pendingTags.isNotEmpty) {
        _resetBatchTimer();
      }
    }
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
        _showWarning('Disconnected', 'RFID scanner disconnected');
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
      _showError('Not Connected', 'Please connect to RFID scanner first');
      return;
    }

    if (!_hasSelectedAction || _currentAction == null) {
      _showError('No Action Selected', 'Please select an action first');
      return;
    }

    _startScanningAfterAction();
  }

  Future<void> _startScanningAfterAction() async {
    try {
      final success = await _rfidScanner.startScan(
        mode: ScanMode.continuous,
        uniqueOnly: true,
      );

      if (!success) return;

      setState(() {
        isScanning = true;
        scannerStatus = ScannerStatus.scanning;
      });
    } catch (e) {
      _showError('Start Scan Failed', e.toString());
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
      _showError('Stop Scan Failed', e.toString());
    }
  }

  Future<void> _clearScannedItems() async {
    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Clear All Items',
      message: 'Are you sure you want to clear all scanned items?',
    );

    if (confirm == true) {
      try {
        // Reset validation flags
        _isWarningShowing = false;
        _shouldStopProcessing = false;

        // Clear RFID scanner cache
        await _rfidScanner.clearSeenTags();

        // Clear all data structures
        setState(() {
          _scannedItemsMap.clear();
          _pendingTags.clear();
          _racks.clear();
          _allRackTagIds.clear();
        });

        // If scanning was in progress, restart it
        if (isScanning) {
          await _stopScanning();
          await Future.delayed(const Duration(milliseconds: 100));
          await _startScanning();
        }

        AppModal.showSuccess(
          context: context,
          title: 'Cleared',
          message: 'All scanned items have been cleared',
        );
      } catch (e) {
        _showError('Clear Failed', e.toString());
      }
    }
  }

  Future<void> _resetAction() async {
    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Reset Action',
      message: 'This will clear all scanned items and current action. Continue?',
    );

    if (confirm == true) {
      // Reset all flags
      _isWarningShowing = false;
      _shouldStopProcessing = false;
      _singleTagCaptured = false;

      setState(() {
        _currentAction = null;
        _hasSelectedAction = false;
        _transitSelection = null;
        _generatedStockForm = null;
        _scannedItemsMap.clear();
        _pendingTags.clear();
        _racks.clear();
        _allRackTagIds.clear();
      });

      await _rfidScanner.clearSeenTags();

      // Stop scanning if active
      if (isScanning) {
        await _stopScanning();
      }

      AppModal.showSuccess(
        context: context,
        title: 'Reset',
        message: 'Action reset successfully',
      );

      // Show action modal again
      _showActionModal();
    }
  }

  Future<void> _updatePowerLevel(double power) async {
    setState(() => rfidPower = power);
    try {
      final level = _convertPowerToLevel(power);
      await _rfidScanner.setPower(level);
    } catch (e) {
      _showError('Power Update Failed', e.toString());
    }
  }

  void _showError(String title, String message) {
    AppModal.showError(context: context, title: title, message: message);
  }

  void _showWarning(String title, String message) {
    AppModal.showWarning(context: context, title: title, message: message);
  }

  void _deleteScannedItem(String itemId) {
    setState(() {
      _scannedItemsMap.remove(itemId);
    });
  }

  void _showItemDetails(ScannedItem item) {
    if (item.basketData != null) {
      BasketDetailModal.show(context: context, basketData: item.basketData!);
    } else {
      AppModal.showError(
        context: context,
        title: 'No Data',
        message: 'No basket data available for this item',
      );
    }
  }

  // Show scanned items modal
  Future<void> _showScannedItemsModal() async {
    if (_scannedItemsMap.isEmpty) {
      _showError('Empty', 'No scanned items to view');
      return;
    }

    await RfidScannedItemsModal.show(
      context: context,
      scannedItemsMap: _scannedItemsMap,
      onBinLocationChanged: (item, bin) {
        setState(() {
          for (final scannedItem in _scannedItemsMap.values) {
            scannedItem.bin = bin;
          }
        });
      },
    );
  }

  void _updatePowerFromLevel(int level) {
    setState(() {
      selectedPowerLevel = level;
      rfidPower = level == 0 ? 10.0 : level == 1 ? 25.0 : 40.0;
    });
    _updatePowerLevel(rfidPower);
  }

  void _updateLevelFromPower(double power) {
    int newLevel = power < 17 ? 0 : power < 33 ? 1 : 2;
    if (newLevel != selectedPowerLevel) {
      setState(() => selectedPowerLevel = newLevel);
    }
  }

  String get _rackCacheKey {
    return 'empty_stockout_${_selectedMachine}_rack_temp';
  }

  Future<void> _saveRackCache() async {
    if (_selectedMachine == null) return;
    final prefs = await SharedPreferences.getInstance();

    final data = {
      'racks': _racks.map((e) => e.toJson()).toList(),
      'allRackTagIds': _allRackTagIds.toList(),
    };

    await prefs.setString(_rackCacheKey, jsonEncode(data));
  }

  Future<void> _restoreRackCache() async {
    setState(() {
      _racks.clear();
      _allRackTagIds.clear();
    });

    final prefs = await SharedPreferences.getInstance();

    print('Restoring rack cache with key: $_rackCacheKey');

    final raw = prefs.getString(_rackCacheKey);
    if (raw == null) return;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    final restoredRacks = (decoded['racks'] as List)
        .map((e) => Rack.fromJson(e))
        .toList();

    final restoredTagIds = Set<String>.from(
      decoded['allRackTagIds'] ?? const [],
    );

    if (!mounted) return;

    setState(() {
      _racks.addAll(restoredRacks);
      _allRackTagIds.addAll(restoredTagIds);
    });
  }

  AreaData? _lastSelectedArea;

  Future<void> _addCurrentScannedToRack() async {
    if (_scannedItemsMap.isEmpty) {
      _showWarning('Empty', 'No scanned items to add');
      return;
    }

    if (_selectedMachine?.areaName == null) {
      _showWarning('Missing Machine', 'Please select machine before add scanned items to rack');
      return;
    }

    final areaName = _selectedMachine!.areaName!;

    setState(() {
      for (final item in _scannedItemsMap.values) {
        item.bin = areaName;
      }
    });

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Add to Rack',
      message:
      'Add ${_scannedItemsMap.length} items to Rack $currentRackNo?\n\nBin: $areaName',
    );

    if (confirm != true) return;

    setState(() {
      _racks.add(
        Rack(
          rackNo: currentRackNo,
          items: _scannedItemsMap.values
              .where((e) => e.status == ItemStatus.success)
              .toList(),
          bin: areaName,
        ),
      );

      _allRackTagIds.addAll(_scannedItemsMap.keys);

      _scannedItemsMap.clear();
    });

    await _saveRackCache();

    if (!mounted) return;

    AppModal.showSuccess(
      context: context,
      title: 'Rack Added',
      message: 'Items saved successfully to Rack ${currentRackNo - 1}',
    );
  }

  Future<void> _handleExit() async {
    if (_allRackTagIds.isEmpty && _racks.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Unsaved Items',
      message:
      'You have ${_allRackTagIds.length} scanned items that are not saved yet.\n\nAre you sure you want to exit?',
      confirmText: 'EXIT',
      cancelText: 'CANCEL',
    );

    if (confirm == true) {
      Navigator.pop(context);
    }
  }

  // Stock Out Save function for transit/exit (similar to stockout screen)
  Future<void> _stockOutSave() async {
    if (_currentAction?.toLocation == null) return;
    if (_selectedMachine == null) {
      AppModal.showWarning(
        context: context,
        title: 'Missing Info',
        message: 'Please select a Machine first',
      );
      return;
    }

    if (_currentAction == null) return;

    final totalItems = _racks.fold<int>(0, (sum, r) => sum + r.items.length);

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Save Stock Out',
      message: 'Save ${_racks.length} rack(s) with $totalItems items to database?\n\nAction: ${_currentAction!.displayText}\nMachine: ${_selectedMachine!.areaId}',
    );

    if (confirm != true) return;

    AppModal.showLoading(context: context);

    try {
      // Convert racks to API format for stock out
      final apiRacks = _racks.map((rack) => StockOutRackData(
        rackNo: rack.rackNo,
        bin: rack.bin,
        items: rack.items.map((item) {
          final bNo = item.basketData?.basketNo;
          return StockOutItemData(
            tagId: item.id,
            basketNo: (bNo != null && bNo.isNotEmpty) ? bNo : item.id,
            basketFormerQty: item.quantity,
          );
        }).toList(),
      )).toList();

      // Determine stockout_from based on action
      String stockoutFrom;
      String actionType;

      if (_currentAction!.isTransit) {
        stockoutFrom = _currentAction!.fromLocation; // 'GD' or 'LK'
        actionType = 'transit';
      } else if (_currentAction!.isExit) {
        stockoutFrom = _currentAction!.displayText; // 'Exit'
        actionType = 'exit';
      } else {
        // This should not happen as this function is only for transit/exit
        stockoutFrom = 'Unknown';
        actionType = 'unknown';
      }

      // Get former size (you might need to get this from somewhere)
      // For empty former, you might want to get from the scanned items or use a default
      String formerSize = 'N/A';
      if (_scannedItemsMap.isNotEmpty) {
        // Try to get former size from first scanned item's basket data
        final firstItem = _scannedItemsMap.values.first;
        if (firstItem.basketData != null) {
          // You might need to extract former size from basket data
          // This depends on your BasketData model structure
          formerSize = firstItem.basketData!.formerSize ?? 'N/A';
        }
      }

      // Call the stock out API with all required parameters
      final response = await ApiServiceStockOut.saveStockOut(
        stockoutForm: _generatedStockForm ?? '',
        formerSize: formerSize,
        selectedMachine: _currentAction!.toLocation,
        stockoutFrom: stockoutFrom,
        action: actionType,
        racks: apiRacks,
      );

      if (mounted) AppModal.hideLoading(context);

      if (response.success) {
        _isWarningShowing = false;
        _shouldStopProcessing = false;
        _singleTagCaptured = false;

        setState(() {
          _racks.clear();
          _allRackTagIds.clear();
          _scannedItemsMap.clear();
        });

        await _saveRackCache();

        AppModal.showSuccess(
          context: context,
          title: 'Success',
          message: 'Stock Out saved successfully!\n\nAction: ${_currentAction!.displayText}\nBaskets: ${response.totalBaskets}\nFormers: ${response.totalFormers}',
        );

        // Reset action after successful save
        _resetAction();
      } else {
        AppModal.showError(
          context: context,
          title: 'Save Failed',
          message: response.message,
        );
      }
    } catch (e) {
      if (mounted) AppModal.hideLoading(context);
      AppModal.showError(
        context: context,
        title: 'Error',
        message: 'Failed to save: $e',
      );
    }
  }

  // Save Empty Stock for production
  Future<void> _saveEmptyStock() async {
    if (_selectedMachine == null) {
      AppModal.showWarning(
        context: context,
        title: 'Missing Info',
        message: 'Please select a Machine first',
      );
      return;
    }

    final totalItems = _racks.fold<int>(0, (sum, r) => sum + r.items.length);

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Save Stock Out',
      message: 'Save ${_racks.length} rack(s) with $totalItems items to database?\n\nAction: Production\nMachine: ${_selectedMachine!.areaId}',
    );

    if (confirm != true) return;

    AppModal.showLoading(context: context);

    try {
      // Convert racks to API format for empty stock
      final apiRacks = _racks.map((rack) => EmptyStockRackData(
        rackNo: rack.rackNo,
        bin: rack.bin,
        items: rack.items.map((item) {
          final bNo = item.basketData?.basketNo;
          return EmptyStockItemData(
            tagId: item.id,
            basketNo: (bNo != null && bNo.isNotEmpty) ? bNo : item.id,
            basketFormerQty: item.quantity, // This is 0 for empty formers
          );
        }).toList(),
      )).toList();

      // Call the empty stock API for production
      final response = await ApiServiceEmptyStock.saveEmptyStock(
        selectedMachine: _selectedMachine!.areaId,
        action: 'out',
        racks: apiRacks,
      );

      if (mounted) AppModal.hideLoading(context);

      if (response.success) {
        _isWarningShowing = false;
        _shouldStopProcessing = false;
        _singleTagCaptured = false;

        setState(() {
          _racks.clear();
          _allRackTagIds.clear();
          _scannedItemsMap.clear();
        });

        await _saveRackCache();

        AppModal.showSuccess(
          context: context,
          title: 'Success',
          message: 'Production Stock Out saved successfully!\n\nMachine: ${_selectedMachine?.areaName}\nBaskets: ${response.totalBaskets}\nFormers: ${response.totalFormers}',
        );

        // Reset action after successful save
        _resetAction();
      } else {
        AppModal.showError(
          context: context,
          title: 'Save Failed',
          message: response.message,
        );
      }
    } catch (e) {
      if (mounted) AppModal.hideLoading(context);
      AppModal.showError(
        context: context,
        title: 'Error',
        message: 'Failed to save: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormSelector(),
                  const SizedBox(height: 24),
                  _buildStatsCards(),
                  const SizedBox(height: 24),
                  _buildRFIDPowerCard(),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Empty Basket Stock Out',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_currentAction != null)
            Row(
              children: [
                Icon(
                  _currentAction!.action.icon,
                  size: 12,
                  color: _currentAction!.action.color,
                ),
                const SizedBox(width: 4),
                Text(
                  _currentAction!.action.displayName,
                  style: TextStyle(
                    color: _currentAction!.action.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: [
        if (_currentAction != null)
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: Material(
              color: _currentAction!.action.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _changeAction,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _currentAction!.action.icon,
                        size: 18,
                        color: _currentAction!.action.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currentAction!.action.displayName,
                        style: TextStyle(
                          color: _currentAction!.action.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: _currentAction!.action.color,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFormSelector() {
    // If no action selected yet, don't show anything
    if (_currentAction == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentAction!.isProduction) ...[
          const Text(
            'SELECT MACHINE & LINE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Machine Selector
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MachineData>(
                      isExpanded: true,
                      hint: const Text('Select Machine'),
                      value: _selectedMachine,
                      items: _machines.map((machine) {
                        return DropdownMenuItem(
                          value: machine,
                          child: Text(
                            machine.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value != null) {
                          setState(() {
                            _selectedMachine = value;
                          });
                          await _restoreRackCache();
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Line Selector
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedLine,
                      items: _lines.map((line) {
                        return DropdownMenuItem(
                          value: line,
                          child: Text(
                            'Line $line',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedLine = value;
                          });
                          // Regenerate form if needed for transit
                          if (_currentAction?.isTransit == true) {
                            _generateStockFormFallback();
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ] else if (_currentAction!.isTransit) ...[
          const Text(
            'STOCK FORM INFORMATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Form display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.assignment,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'STOCK FORM ID',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _generatedStockForm!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _generateStockFormFallback();
                          AppModal.showSuccess(
                            context: context,
                            title: 'Form Regenerated',
                            message: 'New stock form ID generated',
                          );
                        },
                        icon: const Icon(Icons.refresh, size: 20),
                        color: AppColors.primary,
                        tooltip: 'Regenerate Form',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsCards() {
    final totalBaskets = _scannedItemsMap.length;
    final totalFormers = scannedItems.fold<int>(0, (sum, item) => sum + item.quantity);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'BASKETS',
            totalBaskets.toString(),
            AppColors.textPrimary,
            false,
            true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'FORMERS',
            totalFormers.toString(),
            AppColors.primary,
            false,
            true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'RACK',
            _racks.length.toString().padLeft(1, '0'),
            const Color(0xFFE11D48),
            true,
            false,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label,
      String value,
      Color color,
      bool isRack,
      bool isClickableForItems,
      ) {
    return GestureDetector(
      onTap: isRack
          ? () {
        RackDetailModal.show(
          context: context,
          racks: _racks,
          isBinSelection: false,
          onDelete: (rackNo) async {
            setState(() {
              final rackIndex = _racks.indexWhere((r) => r.rackNo == rackNo);
              if (rackIndex != -1) {
                for (final item in _racks[rackIndex].items) {
                  _allRackTagIds.remove(item.id);
                }
                _racks.removeAt(rackIndex);
              }
            });
            await _saveRackCache();
          },
          onUpdateBin: (rackNo, newBinId) async {
            setState(() {
              final rackIndex = _racks.indexWhere((r) => r.rackNo == rackNo);
              if (rackIndex != -1) {
                _racks[rackIndex].bin = newBinId;
              }
            });
            await _saveRackCache();
          },
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
                    color:
                    isRack ? const Color(0xFFE11D48) : AppColors.textSecondary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (isClickableForItems && _scannedItemsMap.isNotEmpty) ...[
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

  Widget _buildRFIDPowerCard() {
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RFID POWER',
                          style: TextStyle(
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
                            const Text(
                              'dBm',
                              style: TextStyle(
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
                      child: const Icon(
                        Icons.sensors,
                        color: AppColors.primary,
                        size: 28,
                      ),
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
                            const Text(
                              'SCANNER STATUS',
                              style: TextStyle(
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

                // Power Slider
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() {
                          rfidPower = (rfidPower - 1).clamp(0, 50);
                          _updateLevelFromPower(rfidPower);
                        });
                        _updatePowerLevel(rfidPower);
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
                          onChanged: (value) {
                            setState(() {
                              rfidPower = value;
                              _updateLevelFromPower(value);
                            });
                          },
                          onChangeEnd: (value) => _updatePowerLevel(value),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: AppColors.textTertiary),
                      onPressed: () {
                        setState(() {
                          rfidPower = (rfidPower + 1).clamp(0, 50);
                          _updateLevelFromPower(rfidPower);
                        });
                        _updatePowerLevel(rfidPower);
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
                _buildScanButton(Icons.play_circle, 'START', _hasSelectedAction ? AppColors.success.withOpacity(0.5) : AppColors.textTertiary, _startScanning, enabled: _hasSelectedAction),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.pause_circle, 'STOP', AppColors.textTertiary, _stopScanning),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(Icons.refresh, 'CLEAR', const Color(0xFFE11D48), _clearScannedItems),
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
        return 'DISCONNECTED';
      case ScannerStatus.initializing:
        return 'INITIALIZING...';
      case ScannerStatus.initialized:
        return 'INITIALIZED';
      case ScannerStatus.connected:
        return 'CONNECTED';
      case ScannerStatus.scanning:
        return 'STARTED';
      case ScannerStatus.stopped:
        return 'STOPPED';
    }
  }

  Widget _buildScanButton(IconData icon, String label, Color color, VoidCallback onTap, {bool enabled = true}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: enabled ? color : AppColors.textTertiary, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: enabled ? AppColors.textSecondary : AppColors.textTertiary,
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

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          border: const Border(top: BorderSide(color: AppColors.slate200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _hasSelectedAction ? _addCurrentScannedToRack : null,
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasSelectedAction ? AppColors.slate100 : AppColors.slate200,
                  foregroundColor: _hasSelectedAction ? AppColors.slate700 : AppColors.slate300,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: (_racks.isNotEmpty && _hasSelectedAction && _currentAction != null)
                    ? () async {
                  if (_currentAction!.isProduction) {
                    await _saveEmptyStock();
                  } else {
                    await _stockOutSave();
                  }
                }
                    : null,
                icon: const Icon(Icons.save, size: 20),
                label: const Text(
                  'SAVE ALL',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: AppColors.primary.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  disabledBackgroundColor: AppColors.slate200,
                  disabledForegroundColor: AppColors.slate700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}