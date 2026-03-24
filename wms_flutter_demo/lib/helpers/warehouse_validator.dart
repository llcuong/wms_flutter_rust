import 'package:flutter/material.dart';
import '../components/common/app_modal.dart';
import '../services/api_service.dart';

class WarehouseValidator {
  /// Validate baskets against selected warehouse
  /// Returns valid baskets and shows warnings for invalid ones
  /// If stopScanCallback is provided, it will be called when invalid tags are found
  static List<BasketData> validateAndFilter(
      List<BasketData> baskets,
      String warehouseCode,
      BuildContext context, {
        List<String>? originalTagIds,
        VoidCallback? onInvalidFound, // Callback to stop scanning
      }) {
    if (warehouseCode.isEmpty) {
      return baskets;
    }

    // Define warehouse mapping
    final warehouseMap = {
      'GD': {'code': 'GD', 'opposite': 'LK'},
      'LK': {'code': 'LK', 'opposite': 'GD'},
    };

    final warehouseInfo = warehouseMap[warehouseCode];
    if (warehouseInfo == null) {
      return baskets;
    }

    final expectedCode = warehouseInfo['code']!;
    final oppositeCode = warehouseInfo['opposite']!;

    // Separate valid and invalid baskets with reasons
    final validBaskets = <BasketData>[];
    final invalidBaskets = <Map<String, dynamic>>[]; // Store basket with reason

    for (final basket in baskets) {
      final bin = basket.bin;
      String? invalidReason;

      // Check if bin is empty
      if (bin.isEmpty) {
        invalidReason = 'Empty bin location';
      }
      // Check if belongs to opposite warehouse
      else if (bin == oppositeCode || bin.contains(oppositeCode)) {
        invalidReason = 'Belongs to warehouse $oppositeCode';
      }
      // Valid cases
      else if (bin.isEmpty ||
          bin == expectedCode ||
          bin.contains(expectedCode) ||
          (!bin.contains('GD') && !bin.contains('LK'))) {
        validBaskets.add(basket);
      }
      // Other invalid cases
      else {
        invalidReason = 'Invalid bin: $bin';
      }

      if (invalidReason != null) {
        invalidBaskets.add({
          'basket': basket,
          'reason': invalidReason,
        });
      }
    }

    // Find missing tags if originalTagIds provided
    List<String> missingTags = [];
    if (originalTagIds != null) {
      final foundTagIds = baskets.map((b) => b.tagId).toSet();
      missingTags = originalTagIds.where((tag) => !foundTagIds.contains(tag)).toList();
    }

    // If invalid baskets found, show warning and stop scanning
    if (invalidBaskets.isNotEmpty) {
      _showWarehouseWarningAndStop(
        context: context,
        expectedCode: expectedCode,
        oppositeCode: oppositeCode,
        invalidBaskets: invalidBaskets,
        missingTags: missingTags,
        onStopScan: onInvalidFound,
      );
      return []; // Return empty list when invalid found
    }

    // Only show missing tags warning if no invalid baskets
    if (missingTags.isNotEmpty) {
      _showMissingTagsWarningAndStop(context, missingTags, onInvalidFound);
    }

    return validBaskets;
  }

  /// Show warning dialog and stop scanning when invalid warehouse tags found
  static void _showWarehouseWarningAndStop({
    required BuildContext context,
    required String expectedCode,
    required String oppositeCode,
    required List<Map<String, dynamic>> invalidBaskets,
    required List<String> missingTags,
    VoidCallback? onStopScan,
  }) {
    final StringBuffer message = StringBuffer();

    message.writeln('⚠️ INVALID BASKETS DETECTED');
    message.writeln('');
    message.writeln('Expected warehouse: $expectedCode');
    message.writeln('');
    message.writeln('Invalid (${invalidBaskets.length}):');

    // Show all invalid baskets with tag ID and reason
    for (int i = 0; i < invalidBaskets.length; i++) {
      final item = invalidBaskets[i];
      final basket = item['basket'] as BasketData;
      final reason = item['reason'] as String;
      message.writeln('  • ${basket.tagId} - ${basket.basketNo}');
      message.writeln('    Reason: $reason');
      if (i < invalidBaskets.length - 1) message.writeln('');
    }

    if (missingTags.isNotEmpty) {
      message.writeln('');
      message.writeln('Missing data (${missingTags.length}):');
      final showMissingCount = missingTags.length > 5 ? 5 : missingTags.length;
      for (int i = 0; i < showMissingCount; i++) {
        message.writeln('  • ${missingTags[i]}');
      }
      if (missingTags.length > 5) {
        message.writeln('  ... and ${missingTags.length - 5} more');
      }
    }

    message.writeln('');
    message.writeln('Scan stopped. Only scan baskets from warehouse $expectedCode.');

    onStopScan?.call();

    // Show warning dialog and stop scanning
    AppModal.showWarning(
      context: context,
      title: 'Warehouse Alert',
      message: message.toString(),
    );
  }

  /// Show warning for missing tags only
  static void _showMissingTagsWarningAndStop(BuildContext context, List<String> missingTags, VoidCallback? onStopScan) {
    final StringBuffer message = StringBuffer();
    message.writeln('Missing data (${missingTags.length}):');

    final showCount = missingTags.length > 5 ? 5 : missingTags.length;
    for (int i = 0; i < showCount; i++) {
      message.writeln('  • ${missingTags[i]}');
    }

    if (missingTags.length > 5) {
      message.writeln('  ... and ${missingTags.length - 5} more');
    }

    onStopScan?.call();

    AppModal.showWarning(
      context: context,
      title: 'Notice',
      message: message.toString(),
    );
  }

  /// Check if a single basket is valid for the warehouse
  static bool isBasketValidForWarehouse(BasketData basket, String warehouseCode) {
    if (warehouseCode.isEmpty) return false; // Empty warehouse code is invalid

    final warehouseMap = {
      'GD': {'code': 'GD', 'opposite': 'LK'},
      'LK': {'code': 'LK', 'opposite': 'GD'},
    };

    final warehouseInfo = warehouseMap[warehouseCode];
    if (warehouseInfo == null) return false;

    final expectedCode = warehouseInfo['code']!;
    final oppositeCode = warehouseInfo['opposite']!;
    final bin = basket.bin;

    // Empty bin is invalid
    if (bin.isEmpty) return false;

    // Belongs to opposite warehouse is invalid
    if (bin == oppositeCode || bin.contains(oppositeCode)) return false;

    // Valid: matches current warehouse or other bins (CLEAN, VC, etc.)
    return bin == expectedCode ||
        bin.contains(expectedCode) ||
        (!bin.contains('GD') && !bin.contains('LK'));
  }

  /// Get warning message for a single basket
  static String? getBasketWarningMessage(BasketData basket, String warehouseCode) {
    if (warehouseCode.isEmpty) return 'No warehouse selected';

    final warehouseMap = {
      'GD': {'code': 'GD', 'opposite': 'LK'},
      'LK': {'code': 'LK', 'opposite': 'GD'},
    };

    final warehouseInfo = warehouseMap[warehouseCode];
    if (warehouseInfo == null) return 'Invalid warehouse code';

    final expectedCode = warehouseInfo['code']!;
    final oppositeCode = warehouseInfo['opposite']!;
    final bin = basket.bin;

    if (bin.isEmpty) {
      return 'Basket ${basket.basketNo} has empty bin location';
    }

    if (bin == oppositeCode || bin.contains(oppositeCode)) {
      return 'Basket ${basket.basketNo} belongs to warehouse $oppositeCode, not $expectedCode';
    }

    return null;
  }
}