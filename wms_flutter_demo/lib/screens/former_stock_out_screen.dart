import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:wms_flutter/config/constants/app_colors.dart';
import 'package:wms_flutter/components/common/app_modal.dart';
import 'package:wms_flutter/components/common/rfid_scanned_items_modal.dart';
import 'package:wms_flutter/components/common/filled_basket_qty_modal.dart';
import 'package:wms_flutter/components/common/basket_detail_modal.dart';
import 'package:wms_flutter/components/common/bin_location_modal.dart';
import 'package:wms_flutter/components/common/rack_detail_modal.dart';
import 'package:wms_flutter/components/common/stock_out_action_modal.dart';
import 'package:wms_flutter/components/forms/form_section_card.dart';
import 'package:wms_flutter/components/forms/form_text_field.dart';
import 'package:wms_flutter/components/forms/form_dropdown_field.dart';
import 'package:wms_flutter/components/forms/form_date_field.dart';
import 'package:wms_flutter/services/rfid_scanner.dart';
import 'package:wms_flutter/services/api_service.dart';
import 'package:wms_flutter/models/scanned_item.dart';

import '../widgets/bin_selection_modal.dart';

class FormerStockOutScreen extends StatefulWidget {
  const FormerStockOutScreen({super.key});

  @override
  State<FormerStockOutScreen> createState() => _FormerStockOutScreenState();
}

class _FormerStockOutScreenState extends State<FormerStockOutScreen>
    with TickerProviderStateMixin {

  TabController? _tabController;

  // Selected Action
  StockOutAction? _selectedAction;

  // Form Controllers - New API structure
  List<MachineData> _machines = [];
  final List<String> _lines = ['A1', 'B1', 'A2', 'B2'];
  List<StockoutFormData> _stockoutForms = [];

  final _stockFormController = TextEditingController();
  String _selectedSize = 'S';
  String? _selectedMachine = 'NBR01';
  String _selectedLine = 'A1'; // Default line
  StockoutFormData? _selectedStockoutForm;

  bool _isLoadingMachines = false;
  bool _isLoadingForms = false;

  // RFID Scanner
  final RfidScanner _rfidScanner = RfidScanner();
  double rfidPower = 25.0;
  bool isScanning = false;
  bool isConnected = false;
  ScannerStatus scannerStatus = ScannerStatus.disconnected;
  BasketMode _basketMode = BasketMode.full;
  int quantity = 0;

  final Map<String, ScannedItem> _scannedItemsMap = {};
  StreamSubscription<TagData>? _tagSubscription;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<String>? _errorSubscription;

  final Queue<String> _unfetchedTags = Queue<String>();
  static const int _batchSize = 50;
  bool _isFetchingBatch = false;

  final List<Rack> _racks = [];
  int get currentRackNo => _racks.length + 1;
  final Set<String> _allRackTagIds = {};

  int _totalBaskets = 0;
  int _totalFormers = 0;
  bool _singleTagCaptured = false;

  bool get _isScanTabActive {
    if (_selectedAction == StockOutAction.production) {
      return _tabController?.index == 1;
    }
    return true;
  }

  bool get _showTabBar => _selectedAction == StockOutAction.production;

  @override
  void initState() {
    super.initState();
    _showActionModal();
  }

  @override
  void dispose() {
    _stockFormController.dispose();
    _tabController?.dispose();

    _tagSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();

    if (isScanning) _rfidScanner.stopScan();
    if (isConnected) _rfidScanner.disconnect();

    super.dispose();
  }

  void _initializeTabController() {
    _tabController?.dispose();
    if (_showTabBar) {
      _tabController = TabController(length: 2, vsync: this);
    } else {
      _tabController = null;
    }
  }

  Future<void> _showActionModal() async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final action = await StockOutActionModal.show(context);

    if (action == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    if (action == StockOutAction.exit) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _selectedAction = action;
      _initializeTabController();
    });

    // Load machines for production mode
    if (action == StockOutAction.production) {
      await _loadMachines();
    } else {
      _generateStockForm();
    }

    await _initializeRfid();
    await _restoreRackCache();
  }

  Future<void> _changeAction() async {
    final action = await StockOutActionModal.show(context);

    if (action == null) return;

    if (action == StockOutAction.exit) {
      _handleExit();
      return;
    }

    setState(() {
      _selectedAction = action;
      _initializeTabController();
    });

    // Load machines if switching to production
    if (action == StockOutAction.production) {
      await _loadMachines();
    } else {
      _generateStockForm();
    }

    await _restoreRackCache();
  }

  Future<void> _loadMachines() async {
    setState(() => _isLoadingMachines = true);

    try {
      final machines = await ApiService.getMachines();

      if (!mounted) return;

      setState(() {
        _machines = machines;
        _selectedMachine = machines.isNotEmpty ? machines.first.areaId : null;
        _stockoutForms.clear();
        _selectedLine = 'A1'; // Reset to default line
        _selectedStockoutForm = null;
        _isLoadingMachines = false;
      });

      // Auto-load stockout forms for first machine and default line
      if (_selectedMachine != null) {
        await _loadStockoutForms();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoadingMachines = false);
      _showError('Load Failed', 'Cannot load machines: ${e.toString()}');
    }
  }

  Future<void> _loadStockoutForms() async {
    if (_selectedMachine == null) return;

    setState(() => _isLoadingForms = true);

    try {
      final forms = await ApiService.getStockoutForms(
        _selectedMachine!,
        line: _selectedLine,
      );

      if (!mounted) return;

      setState(() {
        _stockoutForms = forms;
        _selectedStockoutForm = forms.isNotEmpty ? forms.first : null;
        _isLoadingForms = false;
        _selectedSize = forms.first.formerSize!;
      });

      // Update stock form text field
      if (_selectedStockoutForm != null) {
        _stockFormController.text = _selectedStockoutForm!.stockoutForm;
      } else {
        _generateStockForm();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoadingForms = false);
      // _showError('Load Failed', 'Cannot load stock out forms: ${e.toString()}');

      // Fallback to generated form
      _generateStockForm();
    }
  }

  Future<void> _generateStockForm() async {
    if (_selectedAction == null) return;

    // For production mode, try to use the selected stockout form
    if (_selectedAction == StockOutAction.production && _selectedStockoutForm != null) {
      setState(() {
        _stockFormController.text = _selectedStockoutForm!.stockoutForm;
      });
      return;
    }

    // Otherwise, generate a fallback form
    _generateStockFormFallback();
  }

  void _generateStockFormFallback() {
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');

    // Safely extract machine number from _selectedMachine
    String? machineNumber;
    if (_selectedMachine != null && _selectedMachine!.contains('NBR')) {
      final parts = _selectedMachine!.split('NBR');
      if (parts.length > 1) {
        machineNumber = parts[1];
      }
    }
    // If we still don't have a machine number, use a placeholder
    machineNumber ??= '00';

    String stockForm;

    if (_selectedAction == StockOutAction.production) {
      stockForm = 'GN$yy$mm$dd$machineNumber${_selectedLine ?? ''}';
    } else {
      final prefix = _selectedAction == StockOutAction.washing ? 'CL' : 'LK';

      final random = Random();
      final randomDigits = random.nextInt(100).toString().padLeft(2, '0');
      final randomChars = String.fromCharCodes([
        65 + random.nextInt(26),
        65 + random.nextInt(26),
      ]);

      stockForm = '$prefix$yy$randomDigits$mm$dd$randomChars';
    }

    setState(() {
      _stockFormController.text = stockForm;
    });
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
      _errorSubscription = _rfidScanner.onError.listen((error) => _showError('RFID Error', error));

      if (mounted) {
        AppModal.showSuccess(
          context: context,
          title: 'Connected',
          message: 'RFID scanner ready',
        );
      }
    } catch (e) {
      setState(() => scannerStatus = ScannerStatus.disconnected);
    }
  }

  void _handleTagScanned(TagData tagData) async {
    if (!_isScanTabActive) return;

    if (_basketMode == BasketMode.filled && _singleTagCaptured) return;

    final tagId = tagData.tagId;
    if (_allRackTagIds.contains(tagId)) return;
    if (_scannedItemsMap.containsKey(tagId)) return;

    if (_basketMode == BasketMode.full) {
      quantity = 5;
    } else if (_basketMode == BasketMode.empty) {
      quantity = 0;
    }

    if (_basketMode == BasketMode.filled) {
      _singleTagCaptured = true;
      await _rfidScanner.stopScan();
      setState(() {
        isScanning = false;
        scannerStatus = ScannerStatus.connected;
      });

      final selectedQty = await FilledBasketQtyModal.show(context);
      if (selectedQty == null) return;
      quantity = selectedQty;
    }

    final pendingItem = ScannedItem(
      id: tagId,
      quantity: quantity,
      vendor: '',
      bin: '',
      status: ItemStatus.pending,
      rssi: tagData.rssi,
    );

    setState(() {
      _scannedItemsMap[tagId] = pendingItem;
    });

    _updateStats();
    _unfetchedTags.add(tagId);
    _processBatchQueue();
  }

  void _updateStats() {
    final baskets = _scannedItemsMap.values
        .where((item) => item.status == ItemStatus.success)
        .length;
    final formers = _scannedItemsMap.values
        .fold<int>(0, (sum, item) => sum + item.quantity);

    if (_totalBaskets != baskets || _totalFormers != formers) {
      setState(() {
        _totalBaskets = baskets;
        _totalFormers = formers;
      });
    }
  }

  void _processBatchQueue() {
    if (_isFetchingBatch) return;
    if (_unfetchedTags.isEmpty) return;

    _isFetchingBatch = true;
    _fetchAndProcessBatch();
  }

  Future<void> _fetchAndProcessBatch() async {
    try {
      // Get up to _batchSize tags from the queue
      final batchTags = <String>[];
      while (_unfetchedTags.isNotEmpty && batchTags.length < _batchSize) {
        batchTags.add(_unfetchedTags.removeFirst());
      }

      if (batchTags.isEmpty) {
        _isFetchingBatch = false;
        return;
      }

      // Fetch batch data from API
      final batchData = await ApiService.getBasketsStockOutBatch(batchTags);

      // Create a map for quick lookup
      final dataMap = {for (var item in batchData) item.tagId: item};

      // Update scanned items with fetched data
      for (final tagId in batchTags) {
        final existingItem = _scannedItemsMap[tagId];
        if (existingItem == null) continue;

        final basketData = dataMap[tagId];
        if (basketData != null) {
          existingItem.status = ItemStatus.success;
          existingItem.vendor = basketData.basketVendor;
          existingItem.basketData = basketData;
        } else {
          existingItem.status = ItemStatus.error;
          existingItem.quantity = 0;
          existingItem.errorMessage = 'No data found for this tag';
        }
      }

      _updateStats();
    } catch (e) {
      print('Error fetching batch basket data: $e');

      // Mark all tags in this batch as error
      for (final tagId in _unfetchedTags.take(_batchSize)) {
        final existingItem = _scannedItemsMap[tagId];
        if (existingItem != null) {
          existingItem.status = ItemStatus.error;
          existingItem.quantity = 0;
          existingItem.errorMessage = 'Failed to fetch data';
        }
      }

      _updateStats();
    } finally {
      _isFetchingBatch = false;

      // Continue processing if there are more tags
      if (_unfetchedTags.isNotEmpty) {
        _processBatchQueue();
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

      if (success) {
        setState(() {
          isScanning = true;
          scannerStatus = ScannerStatus.scanning;
        });
      }
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
        setState(() {
          _scannedItemsMap.clear();
          _unfetchedTags.clear();
          _totalBaskets = 0;
          _totalFormers = 0;
        });
      } catch (e) {
        _showError('Clear Failed', e.toString());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_showTabBar && _tabController != null) {
      return Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController!,
              children: [
                _buildMasterInfoTab(),
                _buildScanTagTab(),
              ],
            ),
          ),
        ],
      );
    }

    return _buildSimpleScanTab();
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
            'Former Stock Out',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_selectedAction != null)
            Row(
              children: [
                Icon(
                  _selectedAction!.icon,
                  size: 12,
                  color: _selectedAction!.color,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedAction!.displayName,
                  style: TextStyle(
                    color: _selectedAction!.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _selectedAction!.icon,
                        size: 18,
                        color: _selectedAction!.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedAction!.displayName,
                        style: TextStyle(
                          color: _selectedAction!.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: _selectedAction!.color,
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
          tabs: const [
            Tab(text: 'Master Info'),
            Tab(text: 'Scan Tag'),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plant (Fixed) and Machine Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 6),
                            child: Text(
                              'PLANT*',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.slate50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.slate200),
                            ),
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: const Text(
                              'NBR',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _isLoadingMachines
                          ? _buildLoadingDropdown('MACHINE')
                          : FormDropdownField<MachineData>(
                        label: 'MACHINE',
                        required: true,
                        value: _machines.firstWhere(
                              (m) => m.areaId == _selectedMachine,
                          orElse: () => _machines.first,
                        ),
                        items: _machines,
                        itemLabel: (item) => item.areaName ?? item.areaId,
                        onChanged: (value) async {
                          setState(() {
                            _selectedMachine = value?.areaId;
                            _stockoutForms.clear();
                            _selectedStockoutForm = null;
                          });
                          if (value != null) {
                            await _loadStockoutForms();
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Line and Size Row
                Row(
                  children: [
                    Expanded(
                      child: FormDropdownField<String>(
                        label: 'LINE',
                        required: true,
                        value: _selectedLine,
                        items: _lines,
                        itemLabel: (item) => item,
                        onChanged: (value) async {
                          setState(() {
                            _selectedLine = value!;
                            _stockoutForms.clear();
                            _selectedStockoutForm = null;
                          });
                          await _loadStockoutForms();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FormDropdownField<String>(
                        label: 'SIZE',
                        required: true,
                        value: _selectedSize,
                        items: const ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'],
                        itemLabel: (item) => item,
                        onChanged: (value) => setState(() => _selectedSize = value!),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Stock Form Selection
                if (_isLoadingForms)
                  _buildLoadingDropdown('STOCK FORM')
                else if (_stockoutForms.isNotEmpty)
                  FormDropdownField<StockoutFormData>(
                    label: 'STOCK FORM',
                    required: true,
                    value: _selectedStockoutForm,
                    items: _stockoutForms,
                    itemLabel: (item) => item.stockoutForm,
                    onChanged: (value) {
                      setState(() {
                        _selectedStockoutForm = value;
                        if (value != null) {
                          _stockFormController.text = value.stockoutForm;
                        }
                      });
                    },
                  )
                else
                  FormTextField(
                    label: 'STOCK FORM',
                    required: true,
                    placeholder: 'Auto-generated...',
                    controller: _stockFormController,
                  ),

                const SizedBox(height: 16),

                // Regenerate Button (only show if no forms or user wants to override)
                if (_stockoutForms.isEmpty)
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: AppColors.primary.withOpacity(0.05),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: TextButton.icon(
                      onPressed: _generateStockForm,
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      label: const Text(
                        'Generate Form',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _buildFormInfoCard(),
        ],
      ),
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

    if (_selectedStockoutForm == null) {
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

    final form = _selectedStockoutForm!;

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

  Widget _buildLoadingDropdown(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            '$label*',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.slate200),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleScanTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
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
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                FormTextField(
                  label: 'STOCK FORM',
                  required: true,
                  placeholder: 'Auto-generated form...',
                  controller: _stockFormController,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.primary.withOpacity(0.05),
                  ),
                  child: TextButton.icon(
                    onPressed: _generateStockForm,
                    icon: const Icon(Icons.refresh, color: AppColors.primary),
                    label: const Text(
                      'Regenerate Form',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
          buildButton(BasketMode.full, 'Full basket'),
          buildButton(BasketMode.filled, 'Filled'),
          buildButton(BasketMode.empty, 'Empty'),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard('BASKETS', _totalBaskets.toString(), AppColors.textPrimary, true),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard('FORMERS', _totalFormers.toString(), AppColors.primary, true),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'RACK',
            _racks.length.toString(),
            const Color(0xFFE11D48),
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
      bool isClickableForItems,
      ) {
    final isRack = label == 'RACK';

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
                _buildScanButton(Icons.play_circle, 'START', AppColors.success, _startScanning),
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
                const Text(
                  'SCANNING IN PROGRESS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_scannedItemsMap.length} items scanned • Tap stats to view',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
        return 'DISCONNECTED';
      case ScannerStatus.initializing:
        return 'INITIALIZING...';
      case ScannerStatus.initialized:
        return 'INITIALIZED';
      case ScannerStatus.connected:
        return 'CONNECTED';
      case ScannerStatus.scanning:
        return 'SCANNING...';
      case ScannerStatus.stopped:
        return 'STOPPED';
    }
  }

  // Rack caching functions
  String get _rackCacheKey {
    final action = _selectedAction?.name ?? 'unknown';
    return 'stockout_${action}_rack_temp';
  }

  Future<void> _saveRackCache() async {
    if (_selectedAction == null) return;

    final prefs = await SharedPreferences.getInstance();

    final data = {
      'racks': _racks.map((e) => e.toJson()).toList(),
      'allRackTagIds': _allRackTagIds.toList(),
    };

    await prefs.setString(_rackCacheKey, jsonEncode(data));
  }

  Future<void> _restoreRackCache() async {
    if (_selectedAction == null) return;

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

  Future<void> _addCurrentScannedToRack() async {
    if (_scannedItemsMap.isEmpty) {
      _showWarning('Empty', 'No scanned items to add');
      return;
    }

    final confirm = await AppModal.showConfirm(
      context: context,
      title: 'Add to Rack',
      message:
      'Add ${_scannedItemsMap.length} items to Rack $currentRackNo?',
    );

    if (confirm != true) return;

    setState(() {
      _racks.add(
        Rack(
          rackNo: currentRackNo,
          items: _scannedItemsMap.values
              .where((e) => e.status == ItemStatus.success)
              .toList(),
        ),
      );

      _allRackTagIds.addAll(_scannedItemsMap.keys);

      _scannedItemsMap.clear();

      _updateStats();
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
      message: 'You have ${_allRackTagIds.length} scanned items that are not saved yet.\n\nAre you sure you want to exit?',
      confirmText: 'EXIT',
      cancelText: 'CANCEL',
    );

    if (confirm == true) {
      Navigator.pop(context);
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
                onPressed: _allRackTagIds.isEmpty
                    ? null
                    : () async {
                  // Validate: must have current form selected

                  if (_selectedStockoutForm == null || _selectedMachine == null) {
                    AppModal.showWarning(
                      context: context,
                      title: 'Missing Info',
                      message: 'Please select a Machine and Form first',
                    );
                    return;
                  }

                  final totalItems = _racks.fold<int>(0, (sum, r) => sum + r.items.length);
                  final confirm = await AppModal.showConfirm(
                    context: context,
                    title: 'Save Stock Out',
                    message: 'Save ${_racks.length} rack(s) with $totalItems items to database?\n\nForm: ${_selectedStockoutForm!.stockoutForm}\nMachine: ${_selectedMachine!}',
                  );

                  if (confirm != true) return;

                  AppModal.showLoading(context: context);

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
                  final response = await ApiServiceStockOut.saveStockOut(
                    stockoutForm: _selectedStockoutForm!.stockoutForm,
                    formerSize: _selectedStockoutForm!.formerSize ?? '',
                    selectedMachine: _selectedMachine!,
                    stockoutFrom: '',
                    action: _selectedAction != null ? _selectedAction!.name : '',
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
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: ElevatedButton(
                onPressed: _handleExit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF1F2),
                  foregroundColor: const Color(0xFFE11D48),
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Icon(Icons.close, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}