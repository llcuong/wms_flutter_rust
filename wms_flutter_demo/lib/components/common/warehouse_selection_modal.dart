// components/common/warehouse_selection_modal.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wms_flutter/components/common/stock_in_action_modal.dart';
import '../../config/constants/app_colors.dart';
import '../../services/server_config_service.dart';

enum WarehouseType {
  gdFactory,  // GD Factory
  lkFactory,  // LK Factory
}

class WarehouseSelection {
  final WarehouseType warehouse;

  WarehouseSelection({required this.warehouse});

  String get displayName {
    switch (warehouse) {
      case WarehouseType.gdFactory:
        return 'GD Factory';
      case WarehouseType.lkFactory:
        return 'LK Factory';
    }
  }

  String get code {
    switch (warehouse) {
      case WarehouseType.gdFactory:
        return 'gd_factory';
      case WarehouseType.lkFactory:
        return 'lk_factory';
    }
  }

  String get shortName {
    switch (warehouse) {
      case WarehouseType.gdFactory:
        return 'GD';
      case WarehouseType.lkFactory:
        return 'LK';
    }
  }

  Color get color {
    switch (warehouse) {
      case WarehouseType.gdFactory:
        return const Color(0xFF3B82F6); // Blue
      case WarehouseType.lkFactory:
        return const Color(0xFF10B981); // Green
    }
  }

  IconData get icon {
    switch (warehouse) {
      case WarehouseType.gdFactory:
        return Icons.factory;
      case WarehouseType.lkFactory:
        return Icons.local_shipping;
    }
  }
}

class WarehouseSelectionResult {
  final WarehouseSelection selection;
  final bool isFromStorage;

  WarehouseSelectionResult({
    required this.selection,
    required this.isFromStorage,
  });
}

class WarehouseSelectionModal extends StatelessWidget {
  static const String _storageKey = 'selected_warehouse';

  const WarehouseSelectionModal({Key? key}) : super(key: key);

  static Future<WarehouseSelectionResult?> show(BuildContext context) async {
    // Check if there's a saved selection
    final prefs = await SharedPreferences.getInstance();
    final savedWarehouse = prefs.getString(_storageKey);

    if (savedWarehouse != null) {
      // Return the saved selection
      WarehouseType warehouse;
      if (savedWarehouse == 'gd_factory') {
        warehouse = WarehouseType.gdFactory;
      } else if (savedWarehouse == 'lk_factory') {
        warehouse = WarehouseType.lkFactory;
      } else {
        warehouse = WarehouseType.gdFactory; // Default
      }

      return WarehouseSelectionResult(
        selection: WarehouseSelection(warehouse: warehouse),
        isFromStorage: true,
      );
    }

    // Show modal if no saved selection
    return showDialog<WarehouseSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const WarehouseSelectionModal(),
    );
  }

  static Future<void> saveWarehouseSelection(WarehouseType warehouse) async {
    final prefs = await SharedPreferences.getInstance();
    final code = warehouse == WarehouseType.gdFactory ? 'gd_factory' : 'lk_factory';
    await prefs.setString(_storageKey, code);

    // Update server config selected warehouse
    await ServerConfigService.setSelectedWarehouse(code);
  }

  static Future<WarehouseSelection?> getSavedWarehouse() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWarehouse = prefs.getString(_storageKey);

    if (savedWarehouse == null) return null;

    if (savedWarehouse == 'gd_factory') {
      return WarehouseSelection(warehouse: WarehouseType.gdFactory);
    } else if (savedWarehouse == 'lk_factory') {
      return WarehouseSelection(warehouse: WarehouseType.lkFactory);
    }

    return null;
  }

  static Future<void> clearSavedWarehouse() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // Helper method to get all available warehouse codes
  List<String> getAllWarehouseCodes() {
    return ['GD', 'LK']; // You can also get this dynamically from the system
  }

// Helper method to get excluded bin locations based on selected warehouse and action
  static Future<List<String>> getExcludedBinLocations() async {
    final savedWarehouse = await WarehouseSelectionModal.getSavedWarehouse();
    final selectedWarehouseCode = savedWarehouse?.shortName;

    // Get all warehouse codes
    final allWarehouseCodes = ['GD', 'LK']; // Add more if needed

    // Start with all warehouses except the selected one
    List<String> excluded = allWarehouseCodes
        .where((code) => code != selectedWarehouseCode)
        .toList();

    return excluded;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warehouse,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Warehouse',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Choose your working warehouse location',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 8),

            // Warehouse Options
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  _buildWarehouseButton(
                    context,
                    warehouse: WarehouseType.gdFactory,
                    icon: Icons.factory,
                    label: 'GD Factory',
                    description: 'Gia Dinh Factory - Main warehouse',
                    color: const Color(0xFF3B82F6),
                  ),
                  const SizedBox(height: 12),
                  _buildWarehouseButton(
                    context,
                    warehouse: WarehouseType.lkFactory,
                    icon: Icons.local_shipping,
                    label: 'LK Factory',
                    description: 'Long Khanh Factory - Secondary warehouse',
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseButton(
      BuildContext context, {
        required WarehouseType warehouse,
        required IconData icon,
        required String label,
        required String description,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () async {
          final selection = WarehouseSelection(warehouse: warehouse);
          // Save to local storage
          await saveWarehouseSelection(warehouse);

          if (context.mounted) {
            Navigator.of(context).pop(WarehouseSelectionResult(
              selection: selection,
              isFromStorage: false,
            ));
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension WarehouseTypeExtension on WarehouseType {
  String get displayName {
    switch (this) {
      case WarehouseType.gdFactory:
        return 'GD Factory';
      case WarehouseType.lkFactory:
        return 'LK Factory';
    }
  }

  String get code {
    switch (this) {
      case WarehouseType.gdFactory:
        return 'gd_factory';
      case WarehouseType.lkFactory:
        return 'lk_factory';
    }
  }

  String get shortName {
    switch (this) {
      case WarehouseType.gdFactory:
        return 'GD';
      case WarehouseType.lkFactory:
        return 'LK';
    }
  }

  Color get color {
    switch (this) {
      case WarehouseType.gdFactory:
        return const Color(0xFF3B82F6);
      case WarehouseType.lkFactory:
        return const Color(0xFF10B981);
    }
  }

  IconData get icon {
    switch (this) {
      case WarehouseType.gdFactory:
        return Icons.factory;
      case WarehouseType.lkFactory:
        return Icons.local_shipping;
    }
  }
}