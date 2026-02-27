import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class FormerStockInScreen extends StatefulWidget {
  const FormerStockInScreen({super.key});

  @override
  State<FormerStockInScreen> createState() => _FormerStockInScreenState();
}

class _FormerStockInScreenState extends State<FormerStockInScreen> {
  final RfidScanner _rfidScanner = RfidScanner();

  String selectedForm = 'LN25461127UA';
  double rfidPower = 25.0;
  int selectedPowerLevel = 1;
  bool isScanning = false;
  bool isInitialized = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;
  BasketMode _basketMode = BasketMode.full;

  // Machine & Line Selection
  List<MachineData> _machines = [];
  MachineData? _selectedMachine;
  final List<String> _lines = ['A1', 'A2', 'B1', 'B2'];
  String _selectedLine = 'A1';
  
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
    _initializeRfid();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    final machines = await ApiService.getMachines();
    if (mounted) {
      setState(() {
        _machines = machines;
      });
    }
  }

  Future<void> _loadStockoutForms(String machineId) async {
    setState(() => _isLoadingForms = true);
    try {
      // Pass selected line to filter at backend
      final forms = await ApiService.getStockoutForms(machineId, line: _selectedLine);
      if (mounted) {
        setState(() {
          _machineForms = forms;
           // Since backend now filters by line, just take the first result or clear
          if (forms.isNotEmpty) {
             _currentForm = forms.first;
          } else {
             _currentForm = null;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingForms = false);
      }
    }
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
    if (_basketMode == BasketMode.filled && _singleTagCaptured) return;

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

    if (_basketMode == BasketMode.filled) {
      _handleSingleFilledScan(tagData);
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

    _isProcessingBatch = true;
    final batchMap = Map<String, TagData>.from(_pendingTags);
    _pendingTags.clear();
    final batchIds = batchMap.keys.toList();

    try {
      final baskets = await ApiService.getBasketsStockInBatch(batchIds);

      if (!mounted) return;

      setState(() {
        for (final basket in baskets) {
          final tagId = basket.tagId;
          // Re-check duplicates just in case
          if (_scannedItemsMap.containsKey(tagId)) continue;

          final originalTag = batchMap[tagId];
          final rssi = originalTag?.rssi ?? 0;

          int quantity = 0;
          if (_basketMode == BasketMode.full) {
            quantity = 5;
          } else if (_basketMode == BasketMode.empty) {
            quantity = 0;
          }

          _scannedItemsMap[tagId] = ScannedItem(
            id: tagId,
            quantity: quantity,
            vendor: basket.basketVendor,
            bin: '',  // User must select bin from modal
            status: ItemStatus.success,
            rssi: rssi,
            basketData: basket,
          );
        }
      });
    } catch (e) {
      print('Batch processing error: $e');
      // Optional: re-queue or handle error items
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
        _showError('Scanned failed', "No basket data found for tag ${tagData.tagId}");
        print("No basket data found for tag ${tagData.tagId}");
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
      // Ignore error tags instead of showing failed status
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
    return 'stockin_${_selectedMachine}_rack_temp';
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
    if (_selectedMachine == null) return;

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

    // Show bin selection modal first (same as former master data)
    final selectedArea = await showDialog<AreaData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: BinSelectionModal(
          lastSelected: _lastSelectedArea, // optional
          incomingQty: _scannedItemsMap.length,
          rackData: _racks,
          currentScannedItems: _scannedItemsMap,
        ),
      ),
    );

    if (selectedArea == null) return;

    setState(() {
      _lastSelectedArea = selectedArea;
    });

    // Update all items with selected bin
    setState(() {
      for (final item in _scannedItemsMap.values) {
        item.bin = selectedArea.name;
      }
    });

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Add to Rack',
      message:
          'Add ${_scannedItemsMap.length} items to Rack $currentRackNo?\n\nBin: ${selectedArea.name}',
    );

    if (confirm != true) return;

    setState(() {
      _racks.add(
        Rack(
          rackNo: currentRackNo,
          items: _scannedItemsMap.values
              .where((e) => e.status == ItemStatus.success)
              .toList(),
          bin: selectedArea.name,
        ),
      );

      _allRackTagIds.addAll(_scannedItemsMap.keys);

      _scannedItemsMap.clear();
    });

    await _saveRackCache();

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
                  const SizedBox(height: 24),
                  // _buildScannedItemsList(),
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
      backgroundColor: Colors.white.withOpacity(0.8),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Icon(
            Icons.login,
            color: isConnected ? AppColors.success : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          const Text(
            'Former Stock In',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: isConnected ? AppColors.success : AppColors.error,
          ),
          onPressed: () {
            if (isConnected) {
              AppModal.showInfo(
                context: context,
                title: 'Connected',
                message: 'RFID scanner is connected and ready',
              );
            } else {
              _initializeRfid();
            }
          },
        ),
      ],
    );
  }

  Widget _buildFormSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                          _machineForms = [];
                          _currentForm = null;
                        });
                        await _restoreRackCache();
                        _loadStockoutForms(value.areaId);
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
                        if (_selectedMachine != null) {
                          _loadStockoutForms(_selectedMachine!.areaId);
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildFormInfoCard(),
      ],
    );
  }

  Widget _buildFormInfoCard() {
    if (_isLoadingForms) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_selectedMachine == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.slate50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slate200),
        ),
        child: const Center(
          child: Text(
            'Select a machine to view Stockout Forms',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    if (_currentForm == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE4E6)),
        ),
        child: Center(
          child: Text(
            'No Stockout Form found for Line $_selectedLine',
            style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    
    final form = _currentForm!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FORM: ${form.stockoutForm}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    form.stockoutDate ?? 'Unknown Date',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  form.formerSize ?? 'N/A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem('Total Basket', '${form.stockoutTotalBasket}'),
              ),
              Expanded(
                child: _buildInfoItem('Total Former', '${form.stockoutTotalFormer}'),
              ),
              Expanded(
                child: _buildInfoItem('Returned Basket', '${form.stockoutReturnBasket}'),
              ),
              
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                 child: _buildInfoItem('Returned Former', '${form.stockoutReturnFormer}'),
              ),
              Expanded(
                flex: 2,
                child: _buildInfoItem('Batch Used Day', '${form.mostBatchUsedDay}'),
              ),
            ],
          )
        ],
      ),
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
              // switch to single scan mode
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
                  color: selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
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
    final totalFormers = scannedItems.fold<int>(0, (sum, item) => sum + item.quantity);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'BASKETS',
            totalBaskets.toString(),
            AppColors.textPrimary,
            false,
            true, // isClickableForItems
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'FORMERS',
            totalFormers.toString(),
            AppColors.primary,
            false,
            true, // isClickableForItems
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'RACK',
            _racks.length.toString().padLeft(1, '0'),
            const Color(0xFFE11D48),
            true,
            false, // Rack modal is separate
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
                onDelete: (rackNo) async {
                  setState(() {
                    final rackIndex = _racks.indexWhere((r) => r.rackNo == rackNo);
                    if (rackIndex != -1) {
                      // Remove tag IDs of deleted rack from _allRackTagIds
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
                _buildScanButton(Icons.play_circle, 'START', AppColors.success.withOpacity(0.5), () {
                  // _startScanning();
                }),
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

  Widget _buildScannedItemsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SCANNED ITEMS (${scannedItems.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              if (scannedItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'LAST SCAN: ${_getLastScanTime()}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (scannedItems.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 64,
                    color: AppColors.textTertiary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items scanned yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Press START to begin scanning',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: scannedItems.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildScannedItemCard(scannedItems[index]),
              );
            },
          ),
      ],
    );
  }

  String _getLastScanTime() {
    return 'JUST NOW';
  }

  Widget _buildScannedItemCard(ScannedItem item) {
    Color qtyBgColor;
    Color qtyTextColor;
    Color statusBgColor;
    Color statusTextColor;
    String statusLabel;
    Color borderColor;

    switch (item.status) {
      case ItemStatus.success:
        qtyBgColor = const Color(0xFFECFDF5);
        qtyTextColor = const Color(0xFF059669);
        statusBgColor = const Color(0xFFD1FAE5);
        statusTextColor = const Color(0xFF047857);
        statusLabel = 'SUCCESS';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.duplicate:
        qtyBgColor = const Color(0xFFFEF3C7);
        qtyTextColor = const Color(0xFFD97706);
        statusBgColor = const Color(0xFFFDE68A);
        statusTextColor = const Color(0xFFB45309);
        statusLabel = 'DUPLICATE';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.pending:
        qtyBgColor = const Color(0xFFE0E7FF);
        qtyTextColor = const Color(0xFF4F46E5);
        statusBgColor = const Color(0xFFDDD6FE);
        statusTextColor = const Color(0xFF6366F1);
        statusLabel = 'LOADING...';
        borderColor = AppColors.slate100;
        break;

      case ItemStatus.error:
        qtyBgColor = const Color(0xFFFEE2E2);
        qtyTextColor = const Color(0xFFDC2626);
        statusBgColor = const Color(0xFFFECDD3);
        statusTextColor = const Color(0xFFBE123C);
        statusLabel = 'ERROR';
        borderColor = const Color(0xFFFFE4E6);
        break;
    }

    return GestureDetector(
      onTap:
          item.status == ItemStatus.success ? () => _showItemDetails(item) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
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
            // Delete button row
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () {
                    _deleteScannedItem(item.id);
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove item',
                ),
              ],
            ),
            Row(
              children: [
                // QTY box
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: qtyBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'QTY',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: qtyTextColor,
                        ),
                      ),
                      Text(
                        '${item.quantity}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: qtyTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.id,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      if (item.status == ItemStatus.success &&
                          item.vendor.isNotEmpty)
                        Text(
                          'Vendor: ${item.vendor}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.status == ItemStatus.error)
                        Text(
                          item.errorMessage ?? 'Unknown error',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (item.status == ItemStatus.pending)
                        const Text(
                          'Fetching basket data...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else if (item.status == ItemStatus.duplicate)
                        const Text(
                          'Already scanned',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFD97706),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),

                if (item.basketData != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ],
              ],
            ),

            // BIN info
            if (item.status == ItemStatus.success && item.bin.isNotEmpty)
              Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.slate50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slate200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warehouse,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BIN LOCATION',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.bin,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showBinLocationSelector(item),
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'CHANGE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if (item.status == ItemStatus.success)
              Column(
                children: [
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showBinLocationSelector(item),
                      icon: const Icon(Icons.warehouse, size: 18),
                      label: const Text(
                        'SELECT BIN LOCATION',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
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
                        // Validate: must have current form selected
                        AppModal.showLoading(context: context);
                        if (_currentForm == null || _selectedMachine == null) {
                          AppModal.showWarning(
                            context: context,
                            title: 'Missing Info',
                            message: 'Please select a Machine and Form first',
                          );
                          return;
                        }

                        // Check for empty bins
                        final emptyBinRacks = _racks.where((r) => r.bin.isEmpty).toList();
                        if (emptyBinRacks.isNotEmpty) {
                          AppModal.showWarning(
                            context: context,
                            title: 'Missing Bin',
                            message: 'Rack ${emptyBinRacks.map((r) => r.rackNo).join(", ")} has no bin selected',
                          );
                          return;
                        }

                        final totalItems = _racks.fold<int>(0, (sum, r) => sum + r.items.length);
                        final confirm = await AppModal.showConfirm(
                          context: context,
                          title: 'Save Stock In',
                          message: 'Save ${_racks.length} rack(s) with $totalItems items to database?\n\nForm: ${_currentForm!.stockoutForm}\nMachine: ${_selectedMachine!.areaId}',
                        );

                        if (confirm != true) return;

                        // Convert racks to API format
                        final apiRacks = _racks.map((rack) => StockInRackData(
                          rackNo: rack.rackNo,
                          bin: rack.bin,
                          items: rack.items.map((item) {
                            final bNo = item.basketData?.basketNo;
                            return StockInItemData(
                              tagId: item.id,
                              // Use item.id if basketNo is null or empty
                              basketNo: (bNo != null && bNo.isNotEmpty) ? bNo : item.id,
                              basketFormerQty: item.quantity,
                            );
                          }).toList(),
                        )).toList();

                        // Call API
                        final response = await ApiServiceStockIn.saveStockIn(
                          stockinForm: _currentForm!.stockoutForm,
                          formerSize: _currentForm!.formerSize ?? '',
                          selectedMachine: _selectedMachine!.areaId,
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
                            message: 'Stock In saved successfully!\n\nBatch: ${response.batchNo}\nBaskets: ${response.totalBaskets}\nFormers: ${response.totalFormers}',
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
