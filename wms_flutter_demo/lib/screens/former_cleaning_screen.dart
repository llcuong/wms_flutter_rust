import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wms_flutter/components/common/cleaning_action_modal.dart';
import '../config/constants/app_colors.dart';
import '../components/common/custom_card.dart';
import '../components/common/app_modal.dart';
import '../components/common/basket_detail_modal.dart';
import '../widgets/bin_selection_modal.dart';
import '../components/common/rack_detail_modal.dart';
import '../components/common/filled_basket_qty_modal.dart';
import '../components/common/rfid_scanned_items_modal.dart';
import '../services/rfid_scanner.dart';
import '../services/api_service.dart';
import '../models/scanned_item.dart';

class FormerCleaningScreen extends StatefulWidget {
  const FormerCleaningScreen({super.key});

  @override
  State<FormerCleaningScreen> createState() => _FormerCleaningScreenState();
}

class _FormerCleaningScreenState extends State<FormerCleaningScreen> {
  final RfidScanner _rfidScanner = RfidScanner();

  String selectedForm = '';
  String _selectedSize = 'S';
  double rfidPower = 25.0;
  int selectedPowerLevel = 1;
  bool isScanning = false;
  bool isInitialized = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;
  BasketMode _basketMode = BasketMode.full;

  // Selected Action
  CleaningActionWithSource? _selectedAction;

  final _stockFormController = TextEditingController();

  // Machine & Line Selection
  List<MachineData> _machines = [];
  MachineData? _selectedMachine;
  final List<String> _lines = ['A1', 'A2', 'B1', 'B2'];
  String _selectedLine = 'A1';

  // From/To Bin Selection
  String? _fromBin;
  String? _toBin;

  List<String> _bins = [];
  bool _isLoadingBins = false;

  List<StockoutFormData> _machineForms = [];
  StockoutFormData? _currentForm;
  bool _isLoadingForms = false;

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

  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode.requestFocus();
    _showCleaningActionModal();
  }

  Future<void> _showCleaningActionModal() async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final action = await CleaningActionModal.show(context);

    if (action == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    if (action == CleaningAction.exit) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _selectedAction = action;
    });

    if (action != CleaningAction.fromProduction) {
      _generateStockForm();
    }

    await _loadBins();

    await _initializeRfid();
    await _restoreRackCache();
  }

  Future<void> _changeAction() async {
    final action = await CleaningActionModal.show(context);

    if (action == null) return;

    if (action == CleaningAction.exit) {
      _handleExit();
      return;
    }

    setState(() {
      _selectedAction = action;
      _stockFormController.clear();
    });

    if (action != CleaningAction.fromProduction) {
      _generateStockForm();
    }

    await _restoreRackCache();
  }

  void _generateStockForm() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');

    String stockForm;
    String prefix = 'CL';

    if (_selectedAction == CleaningAction.fromWarehouse) {
      prefix = 'CL';
    } else {
      prefix = 'VC';
    }

    final random = Random();
    final randomDigits = random.nextInt(100).toString().padLeft(2, '0');
    final randomChars = String.fromCharCodes([
      65 + random.nextInt(26),
      65 + random.nextInt(26),
    ]);

    stockForm = '$prefix$yy$randomDigits$mm$dd$randomChars';

    setState(() {
      _stockFormController.text = stockForm;
    });
  }

  Future<void> _loadBins() async {
    setState(() => _isLoadingBins = true);

    try {
      final bins = await ApiService.getBins();

      if (!mounted) return;

      setState(() {
        _bins = bins;
        _isLoadingBins = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoadingBins = false);
      _showError('Load Failed', 'Cannot load bins: ${e.toString()}');
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

  @override
  void dispose() {
    _stockFormController.dispose();
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

      final initSuccess = await _rfidScanner.init();
      if (!initSuccess) {
        setState(() => scannerStatus = ScannerStatus.disconnected);
        _showError(
          'Initialization Failed',
          'Could not initialize RFID scanner',
        );
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
    if (_basketMode == BasketMode.filled && _singleTagCaptured) return;

    final tagId = tagData.tagId;

    if (!_isValidRfidTag(tagId)) {
      return;
    }

    if (_allRackTagIds.contains(tagId)) {
      return;
    }

    if (_scannedItemsMap.containsKey(tagId) ||
        _pendingTags.containsKey(tagId)) {
      return;
    }

    if (_basketMode == BasketMode.filled) {
      _handleSingleFilledScan(tagData);
      return;
    }

    _pendingTags[tagId] = tagData;
    _resetBatchTimer();
  }

  void _resetBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 500), _processBatchQueue);
  }

  Future<void> _processBatchQueue() async {
    if (_pendingTags.isEmpty || _isProcessingBatch) return;

    _isProcessingBatch = true;
    final batchMap = Map<String, TagData>.from(_pendingTags);
    _pendingTags.clear();
    final batchIds = batchMap.keys.toList();

    try {
      List<BasketData> baskets = [];
      if (_selectedAction?.isFromProduction == true) {
        baskets = await ApiService.getBasketsStockInBatch(batchIds);
      } else {
        baskets = await ApiService.getBasketsStockOutBatch(batchIds);
      }

      if (!mounted) return;

      setState(() {
        for (final basket in baskets) {
          final tagId = basket.tagId;
          if (_scannedItemsMap.containsKey(tagId)) continue;

          final originalTag = batchMap[tagId];
          final rssi = originalTag?.rssi ?? 0;

          _scannedItemsMap[tagId] = ScannedItem(
            id: tagId,
            quantity: 0,
            vendor: basket.basketVendor,
            bin: '',
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
      final raw = await ApiService.getBasketsStockInBatch([tagData.tagId]);

      _singleTagCaptured = false;

      if (raw.isEmpty) {
        _showError(
          'Scanned failed',
          "No basket data found for tag ${tagData.tagId}",
        );
        return;
      }

      final basketData = raw.first;

      setState(() {
        _scannedItemsMap[tagData.tagId] = ScannedItem(
          id: tagData.tagId,
          quantity: selectedQty,
          vendor: basketData.basketVendor,
          bin: basketData.basketPurchaseOrder,
          status: ItemStatus.success,
          rssi: tagData.rssi,
          basketData: basketData,
        );
      });
    } catch (e) {
      _singleTagCaptured = false;
      print('Single scan fetch error: $e');
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

    if (_basketMode == BasketMode.filled) {
      _singleTagCaptured = false;
    }

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
        await _rfidScanner.clearSeenTags();
        setState(() => _scannedItemsMap.clear());
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
      rfidPower = level == 0
          ? 10.0
          : level == 1
          ? 25.0
          : 40.0;
    });
    _updatePowerLevel(rfidPower);
  }

  void _updateLevelFromPower(double power) {
    int newLevel = power < 17
        ? 0
        : power < 33
        ? 1
        : 2;
    if (newLevel != selectedPowerLevel) {
      setState(() => selectedPowerLevel = newLevel);
    }
  }

  String get _rackCacheKey {
    return 'former_cleaning_${_selectedAction?.code}_rack_temp';
  }

  Future<void> _saveRackCache() async {
    // if (_selectedMachine == null) return;
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

    // if (_selectedMachine?.areaName == null) {
    //   _showWarning(
    //     'Missing Machine',
    //     'Please select machine before add scanned items to rack',
    //   );
    // }
    //
    // final areaName = _selectedMachine!.areaName!;
    //
    // setState(() {
    //   for (final item in _scannedItemsMap.values) {
    //     item.bin = areaName;
    //   }
    // });

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Add to Rack',
      message:
          'Add ${_scannedItemsMap.length} items to Rack $currentRackNo?'
    );

    if (confirm != true) return;

    // String actionBin = '';
    //
    // if (_selectedAction == CleaningAction.fromWarehouse) {
    //   actionBin = 'CLEAN';
    // } else if (_selectedAction == CleaningAction.fromProduction) {
    //   actionBin = '';
    // }

    setState(() {
      _racks.add(
        Rack(
          rackNo: currentRackNo,
          items: _scannedItemsMap.values
              .where((e) => e.status == ItemStatus.success)
              .toList(),
          bin: 'CLEAN',
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
    if (_allRackTagIds.isEmpty) {
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
                  _buildBasketModeSelector(),
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
        mainAxisSize: MainAxisSize.min, // Add this to prevent column from taking more space than needed
        children: [
          const Text(
            'Former Cleaning',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_selectedAction != null)
            Container(
              constraints: const BoxConstraints(maxWidth: 200), // Add max width constraint
              child: Row(
                mainAxisSize: MainAxisSize.min, // Add this to prevent row from expanding
                children: [
                  Icon(
                    _selectedAction!.icon,
                    size: 12,
                    color: _selectedAction!.color,
                  ),
                  const SizedBox(width: 4),
                  Flexible( // Wrap Text with Flexible to allow it to wrap/ellipsize
                    child: Text(
                      _selectedAction!.displayName,
                      style: TextStyle(
                        color: _selectedAction!.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis, // Add ellipsis if text overflows
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        if (_selectedAction != null)
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: Material(
              color: _selectedAction!.color.withOpacity(0.1),
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
                    mainAxisSize: MainAxisSize.min, // Add this
                    children: [
                      Icon(
                        _selectedAction!.icon,
                        size: 18,
                        color: _selectedAction!.color,
                      ),
                      const SizedBox(width: 6),
                      Flexible( // Wrap with Flexible
                        child: Text(
                          _selectedAction!.displayName,
                          style: TextStyle(
                            color: _selectedAction!.color,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stock Form section — only shown when action != fromProduction
        if (_selectedAction != CleaningAction.fromProduction) ...[
          // Label
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'STOCK FORM',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Form Row with TextField and Icon Button
          Row(
            children: [
              // Stock Form TextField (takes remaining space)
              Expanded(
                child: TextField(
                  controller: _stockFormController,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Auto-generated form...',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: AppColors.slate50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.slate200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.slate200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Regenerate Icon Button (fixed width)
              SizedBox(
                width: 48,
                height: 48,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.4),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: _generateStockForm,
                    icon: const Icon(
                      Icons.refresh,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Regenerate Form',
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
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
                      ),
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
          buildButton(BasketMode.full, 'Full basket'),
          buildButton(BasketMode.filled, 'Filled'),
          buildButton(BasketMode.empty, 'Empty'),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalBaskets = _scannedItemsMap.length;
    final totalFormers = scannedItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

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
                    final rackIndex = _racks.indexWhere(
                      (r) => r.rackNo == rackNo,
                    );
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
                    final rackIndex = _racks.indexWhere(
                      (r) => r.rackNo == rackNo,
                    );
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
                    color: isRack
                        ? const Color(0xFFE11D48)
                        : AppColors.textSecondary,
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

                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.remove,
                        color: AppColors.textTertiary,
                      ),
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
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 24,
                          ),
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
                      icon: const Icon(
                        Icons.add,
                        color: AppColors.textTertiary,
                      ),
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
                _buildScanButton(
                  Icons.play_circle,
                  'START',
                  AppColors.success,
                  _startScanning,
                ),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(
                  Icons.pause_circle,
                  'STOP',
                  AppColors.textTertiary,
                  _stopScanning,
                ),
                Container(width: 1, height: 64, color: AppColors.slate100),
                _buildScanButton(
                  Icons.refresh,
                  'CLEAR',
                  const Color(0xFFE11D48),
                  _clearScannedItems,
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

  Widget _buildScanButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
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

  Future<void> _showBinLocationSelector(ScannedItem item) async {
    final selectedBinData = await showDialog<BinItem>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: BinSelectionModal(
          lastSelected: _lastSelectedArea,
          incomingQty: _scannedItemsMap.length,
          rackData: _racks,
          currentScannedItems: _scannedItemsMap,
        ),
      ),
    );

    if (selectedBinData != null) {
      setState(() {
        for (final scannedItem in _scannedItemsMap.values) {
          scannedItem.bin = selectedBinData.binId;
        }
      });

      AppModal.showSuccess(
        context: context,
        title: 'Bin Updated',
        message: 'Bin location set to ${selectedBinData.binId}',
      );
    }
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
                onPressed: _addCurrentScannedToRack,
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.slate100,
                  foregroundColor: AppColors.slate700,
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
                onPressed: _racks.isEmpty
                    ? null
                    : () async {
                        if (_selectedMachine == null) {
                          AppModal.showWarning(
                            context: context,
                            title: 'Missing Info',
                            message: 'Please select a Machine first',
                          );
                          return;
                        }

                        AppModal.showLoading(context: context);

                        final totalItems = _racks.fold<int>(
                          0,
                          (sum, r) => sum + r.items.length,
                        );
                        final confirm = await AppModal.showConfirm(
                          context: context,
                          title: 'Save Stock Out',
                          message:
                              'Save ${_racks.length} rack(s) with $totalItems items to database?\n\nMachine: ${_selectedMachine!.areaId}',
                        );

                        if (confirm != true) return;

                        final apiRacks = _racks
                            .map(
                              (rack) => FormerCleaningRackData(
                            rackNo: rack.rackNo,
                            bin: rack.bin,
                            items: rack.items.map((item) {
                              final bNo = item.basketData?.basketNo;
                              return FormerCleaningItemData(
                                tagId: item.id,
                                basketNo: (bNo != null && bNo.isNotEmpty)
                                    ? bNo
                                    : item.id,
                                basketFormerQty: item.quantity,
                              );
                            }).toList(),
                          ),
                        )
                            .toList();

                        final response = await ApiServiceFormerCleaning.saveFormerCleaning(
                          stockoutForm: _stockFormController.text,
                          action: _selectedAction!.code,
                          source: _selectedAction!.source.name,
                          racks: apiRacks,
                        );

                        if (mounted) AppModal.hideLoading(context);

                        if (response.success) {
                          _saveRackCache();

                          setState(() {
                            _racks.clear();
                            _allRackTagIds.clear();
                            _scannedItemsMap.clear();
                          });

                          AppModal.showSuccess(
                            context: context,
                            title: 'Success',
                            message:
                                'Stock In saved successfully!\n\nLocation: ${_selectedMachine?.areaName}\nBaskets: ${response.totalBaskets}\nFormers: ${response.totalFormers}',
                          );
                        } else {
                          AppModal.showError(
                            context: context,
                            title: 'Save Failed',
                            message: response.message,
                          );
                        }
                      },
                icon: const Icon(Icons.save, size: 20),
                label: const Text(
                  'SAVE ALL',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
