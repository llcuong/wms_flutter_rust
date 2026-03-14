import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum CleaningAction {
  fromWarehouse,
  fromProduction,
  toVendor,
  exit,
}

enum VendorSource {
  warehouse,
  production,
  none,
}

// Class to hold the action with its source
class CleaningActionWithSource {
  final CleaningAction action;
  final VendorSource source;

  CleaningActionWithSource({
    required this.action,
    this.source = VendorSource.none,
  });

  bool get isFromWarehouse =>
      action == CleaningAction.fromWarehouse ||
          (action == CleaningAction.toVendor && source == VendorSource.warehouse);

  bool get isFromProduction =>
      action == CleaningAction.fromProduction ||
          (action == CleaningAction.toVendor && source == VendorSource.production);

  bool get isToVendor => action == CleaningAction.toVendor;

  String get displayText {
    if (action == CleaningAction.toVendor) {
      return 'To Vendor (from ${source == VendorSource.warehouse ? "warehouse" : "production"})';
    }
    return displayName;
  }

  String get code {
    switch (action) {
      case CleaningAction.fromWarehouse:
        return 'warehouse';
      case CleaningAction.fromProduction:
        return 'production';
      case CleaningAction.toVendor:
        return 'vendor';
      case CleaningAction.exit:
        return 'exit';
    }
  }

  String get displayName {
    switch (action) {
      case CleaningAction.fromWarehouse:
        return 'From warehouse';
      case CleaningAction.fromProduction:
        return 'From production';
      case CleaningAction.toVendor:
        return 'To Vendor';
      case CleaningAction.exit:
        return 'Exit';
    }
  }

  IconData get icon {
    switch (action) {
      case CleaningAction.fromWarehouse:
        return Icons.warehouse;
      case CleaningAction.fromProduction:
        return Icons.factory;
      case CleaningAction.toVendor:
        return Icons.local_shipping;
      case CleaningAction.exit:
        return Icons.exit_to_app;
    }
  }

  Color get color {
    switch (action) {
      case CleaningAction.fromWarehouse:
        return const Color(0xFF10B981); // Emerald green
      case CleaningAction.fromProduction:
        return const Color(0xFFF59E0B); // Amber orange
      case CleaningAction.toVendor:
        return const Color(0xFF8B5CF6); // Purple
      case CleaningAction.exit:
        return const Color(0xFF64748B); // Slate gray
    }
  }
}

enum VendorSourceAction {
  fromWarehouse,
  fromProduction,
  close,
}

class CleaningActionModal extends StatelessWidget {
  const CleaningActionModal({Key? key}) : super(key: key);

  static Future<CleaningActionWithSource?> show(BuildContext context) {
    return showDialog<CleaningActionWithSource>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CleaningActionModal(),
    );
  }

  static Future<VendorSourceAction?> showVendorSourceModal(BuildContext context) {
    return showDialog<VendorSourceAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _VendorSourceModal(),
    );
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
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cleaning_services,
                      color: Colors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Cleaning Action',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _buildActionButton(
                    context,
                    action: CleaningAction.fromWarehouse,
                    icon: Icons.warehouse,
                    label: 'From warehouse',
                    color: const Color(0xFF10B981), // Emerald green
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: CleaningAction.fromProduction,
                    icon: Icons.factory,
                    label: 'From production',
                    color: const Color(0xFFF59E0B), // Amber orange
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: CleaningAction.toVendor,
                    icon: Icons.local_shipping,
                    label: 'To Vendor',
                    color: const Color(0xFF8B5CF6), // Purple
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: CleaningAction.exit,
                    icon: Icons.exit_to_app,
                    label: 'Exit',
                    color: const Color(0xFF64748B), // Slate gray
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      BuildContext context, {
        required CleaningAction action,
        required IconData icon,
        required String label,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () async {
          if (action == CleaningAction.toVendor) {
            // Show vendor source modal
            final source = await showVendorSourceModal(context);

            // If user selected a source (not close), return with source
            if (source != null && source != VendorSourceAction.close) {
              VendorSource vendorSource;
              switch (source) {
                case VendorSourceAction.fromWarehouse:
                  vendorSource = VendorSource.warehouse;
                  break;
                case VendorSourceAction.fromProduction:
                  vendorSource = VendorSource.production;
                  break;
                case VendorSourceAction.close:
                  vendorSource = VendorSource.none;
                  break;
              }

              if (context.mounted) {
                Navigator.of(context).pop(CleaningActionWithSource(
                  action: CleaningAction.toVendor,
                  source: vendorSource,
                ));
              }
            }
            // If user closed the vendor modal without selecting, do nothing (stay on current modal)
          } else {
            Navigator.of(context).pop(CleaningActionWithSource(
              action: action,
              source: VendorSource.none,
            ));
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Internal vendor source modal
class _VendorSourceModal extends StatelessWidget {
  const _VendorSourceModal();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
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
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: Color(0xFF8B5CF6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'To Vendor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Source Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _buildVendorSourceButton(
                    context,
                    source: VendorSourceAction.fromWarehouse,
                    icon: Icons.warehouse,
                    label: 'From warehouse',
                    description: 'Send baskets from warehouse to vendor',
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 12),
                  _buildVendorSourceButton(
                    context,
                    source: VendorSourceAction.fromProduction,
                    icon: Icons.factory,
                    label: 'From production',
                    description: 'Send baskets from production to vendor',
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 12),
                  _buildVendorSourceButton(
                    context,
                    source: VendorSourceAction.close,
                    icon: Icons.close,
                    label: 'Close',
                    description: 'Go back to cleaning actions',
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorSourceButton(
      BuildContext context, {
        required VendorSourceAction source,
        required IconData icon,
        required String label,
        required String description,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(source),
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