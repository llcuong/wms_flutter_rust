import 'package:flutter/material.dart';
import '../components/common/app_modal.dart';
import '../services/api_service.dart';

class WarehouseValidator {
  /// Validate baskets against selected warehouse and optional bin location rules
  /// Returns valid baskets and shows warnings for invalid ones
  /// If stopScanCallback is provided, it will be called when invalid tags are found
  static List<BasketData> validateAndFilter(
      List<BasketData> baskets,
      String warehouseCode,
      BuildContext context, {
        List<String>? originalTagIds,
        String? requiredBinLocation, // Bin location that baskets MUST be in
        List<String>? allowedBinLocations, // Bin locations that are allowed
        List<String>? excludedBinLocations, // Bin locations that are NOT allowed
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
    final validTagIds = <String>{};

    for (final basket in baskets) {
      final bin = basket.bin;
      String? invalidReason;
      bool isValid = false;

      // Priority 1: Check if bin is empty
      if (bin.isEmpty) {
        invalidReason = 'Empty bin location';
      }
      // Priority 2: Check required bin location (if specified)
      else if (requiredBinLocation != null &&
          requiredBinLocation.isNotEmpty &&
          bin != requiredBinLocation) {
        invalidReason = 'Expected bin: $requiredBinLocation, but found: $bin';
      }
      // Priority 3: Check excluded bin locations (if specified)
      else if (excludedBinLocations != null &&
          excludedBinLocations.isNotEmpty &&
          excludedBinLocations.contains(bin)) {
        invalidReason = 'Bin location "$bin" is not allowed';
      }
      // Priority 4: Check allowed bin locations (if specified)
      else if (allowedBinLocations != null &&
          allowedBinLocations.isNotEmpty &&
          !allowedBinLocations.contains(bin)) {
        invalidReason = 'Bin must be one of: ${allowedBinLocations.join(", ")}. Found: $bin';
      }
      // Priority 5: Check if belongs to opposite warehouse
      else if (bin == oppositeCode || bin.contains(oppositeCode)) {
        invalidReason = 'Belongs to warehouse $oppositeCode';
      }
      // Valid cases
      else if (bin == expectedCode ||
          bin.contains(expectedCode) ||
          (!bin.contains('GD') && !bin.contains('LK'))) {
        isValid = true;
      }
      // Other invalid cases
      else {
        invalidReason = 'Invalid bin: $bin';
      }

      if (isValid) {
        validBaskets.add(basket);
        validTagIds.add(basket.tagId);
      } else if (invalidReason != null) {
        invalidBaskets.add({
          'basket': basket,
          'reason': invalidReason,
        });
      }
    }

    // Find missing tags ONLY from valid tags (tags that passed validation)
    List<String> missingTags = [];
    if (originalTagIds != null && validTagIds.isNotEmpty) {
      missingTags = originalTagIds.where((tag) => !validTagIds.contains(tag)).toList();
    } else if (originalTagIds != null && validTagIds.isEmpty) {
      missingTags = List.from(originalTagIds);
    }

    // If there are invalid baskets OR missing tags, show a combined warning
    if (invalidBaskets.isNotEmpty || missingTags.isNotEmpty) {
      _showCombinedWarningAndStop(
        context: context,
        expectedCode: expectedCode,
        oppositeCode: oppositeCode,
        requiredBinLocation: requiredBinLocation,
        allowedBinLocations: allowedBinLocations,
        excludedBinLocations: excludedBinLocations,
        invalidBaskets: invalidBaskets,
        missingTags: missingTags,
        onStopScan: onInvalidFound,
      );
      return []; // Return empty list when any issue found
    }

    return validBaskets;
  }

  /// Show combined warning dialog for both invalid baskets and missing tags
  static void _showCombinedWarningAndStop({
    required BuildContext context,
    required String expectedCode,
    required String oppositeCode,
    String? requiredBinLocation,
    List<String>? allowedBinLocations,
    List<String>? excludedBinLocations,
    required List<Map<String, dynamic>> invalidBaskets,
    required List<String> missingTags,
    VoidCallback? onStopScan,
  }) {
    final StringBuffer message = StringBuffer();

    bool hasInvalid = invalidBaskets.isNotEmpty;
    bool hasMissing = missingTags.isNotEmpty;

    // Main header
    if (hasInvalid && hasMissing) {
      message.writeln('⚠️ ISSUES DETECTED');
    } else if (hasInvalid) {
      message.writeln('⚠️ INVALID BASKETS DETECTED');
    } else if (hasMissing) {
      message.writeln('⚠️ MISSING TAGS DETECTED');
    }

    message.writeln('');
    message.writeln('Expected warehouse: $expectedCode');

    // Show bin location rules
    if (requiredBinLocation != null && requiredBinLocation.isNotEmpty) {
      message.writeln('✓ Required bin location: $requiredBinLocation');
    }
    if (allowedBinLocations != null && allowedBinLocations.isNotEmpty) {
      message.writeln('✓ Allowed bin locations: ${allowedBinLocations.join(", ")}');
    }
    if (excludedBinLocations != null && excludedBinLocations.isNotEmpty) {
      message.writeln('✗ Excluded bin locations: ${excludedBinLocations.join(", ")}');
    }

    // Invalid baskets section
    if (hasInvalid) {
      message.writeln('');
      message.writeln('❌ INVALID BASKETS (${invalidBaskets.length}):');

      // Show all invalid baskets with tag ID and reason
      for (int i = 0; i < invalidBaskets.length; i++) {
        final item = invalidBaskets[i];
        final basket = item['basket'] as BasketData;
        final reason = item['reason'] as String;
        message.writeln('  • ${basket.tagId} - ${basket.basketNo}');
        message.writeln('    Reason: $reason');
        if (i < invalidBaskets.length - 1) message.writeln('');
      }
    }

    // Missing tags section
    if (hasMissing) {
      if (hasInvalid) {
        message.writeln('');
        message.writeln('─' * 40);
      }

      message.writeln('');
      message.writeln('🔍 MISSING VALID TAGS (${missingTags.length}):');
      message.writeln('These tags were not found in the system:');

      final showMissingCount = missingTags.length > 5 ? 5 : missingTags.length;
      for (int i = 0; i < showMissingCount; i++) {
        message.writeln('  • ${missingTags[i]}');
      }
      if (missingTags.length > 5) {
        message.writeln('  ... and ${missingTags.length - 5} more');
      }
    }

    // Footer message
    message.writeln('');
    if (hasInvalid && hasMissing) {
      message.writeln('Please remove invalid baskets and scan all missing data tags.');
      message.writeln('Only scan baskets from warehouse $expectedCode.');
    } else if (hasInvalid) {
      message.writeln('Please remove invalid baskets and try again.');
      message.writeln('Only scan baskets from warehouse $expectedCode.');
    } else if (hasMissing) {
      message.writeln('Please remove all missing data tags before continuing.');
    }

    // Show bin rules summary
    if (requiredBinLocation != null && requiredBinLocation.isNotEmpty) {
      message.writeln('Baskets must be located in bin: $requiredBinLocation');
    }
    if (excludedBinLocations != null && excludedBinLocations.isNotEmpty) {
      message.writeln('Baskets cannot be located in: ${excludedBinLocations.join(", ")}');
    }

    message.writeln('');
    message.writeln('Scan stopped.');

    onStopScan?.call();

    // Show combined warning dialog
    AppModal.showWarning(
      context: context,
      title: hasInvalid && hasMissing
          ? 'Validation Issues'
          : (hasInvalid ? 'Warehouse Alert' : 'Missing Tags'),
      message: message.toString(),
    );
  }

  /// Check if a single basket is valid based on all bin rules
  static bool isBasketValidForWarehouse(
      BasketData basket,
      String warehouseCode, {
        String? requiredBinLocation,
        List<String>? allowedBinLocations,
        List<String>? excludedBinLocations,
      }) {
    if (warehouseCode.isEmpty) return false;

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

    // Check required bin location
    if (requiredBinLocation != null &&
        requiredBinLocation.isNotEmpty &&
        bin != requiredBinLocation) {
      return false;
    }

    // Check excluded bin locations
    if (excludedBinLocations != null &&
        excludedBinLocations.isNotEmpty &&
        excludedBinLocations.contains(bin)) {
      return false;
    }

    // Check allowed bin locations (if specified, must be in list)
    if (allowedBinLocations != null &&
        allowedBinLocations.isNotEmpty &&
        !allowedBinLocations.contains(bin)) {
      return false;
    }

    // Belongs to opposite warehouse is invalid
    if (bin == oppositeCode || bin.contains(oppositeCode)) return false;

    // Valid: matches current warehouse or other bins (CLEAN, VC, etc.)
    return bin == expectedCode ||
        bin.contains(expectedCode) ||
        (!bin.contains('GD') && !bin.contains('LK'));
  }

  /// Get warning message for a single basket
  static String? getBasketWarningMessage(
      BasketData basket,
      String warehouseCode, {
        String? requiredBinLocation,
        List<String>? allowedBinLocations,
        List<String>? excludedBinLocations,
      }) {
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

    // Check required bin location mismatch
    if (requiredBinLocation != null &&
        requiredBinLocation.isNotEmpty &&
        bin != requiredBinLocation) {
      return 'Basket ${basket.basketNo} is in bin "$bin", but required bin is "$requiredBinLocation"';
    }

    // Check excluded bin locations
    if (excludedBinLocations != null &&
        excludedBinLocations.isNotEmpty &&
        excludedBinLocations.contains(bin)) {
      return 'Basket ${basket.basketNo} is in bin "$bin", which is not allowed';
    }

    // Check allowed bin locations
    if (allowedBinLocations != null &&
        allowedBinLocations.isNotEmpty &&
        !allowedBinLocations.contains(bin)) {
      return 'Basket ${basket.basketNo} is in bin "$bin", but must be in: ${allowedBinLocations.join(", ")}';
    }

    if (bin == oppositeCode || bin.contains(oppositeCode)) {
      return 'Basket ${basket.basketNo} belongs to warehouse $oppositeCode, not $expectedCode';
    }

    return null;
  }
}