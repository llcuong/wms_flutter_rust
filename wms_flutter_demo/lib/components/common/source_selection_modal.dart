// components/common/source_selection_modal.dart
import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum SourceAction {
  fromWarehouse,
  fromProduction,
  exit,
}

class SourceSelectionResult {
  final SourceAction action;

  SourceSelectionResult({required this.action});

  bool get isFromWarehouse => action == SourceAction.fromWarehouse;
  bool get isFromProduction => action == SourceAction.fromProduction;
  bool get isExit => action == SourceAction.exit;

  String get displayName {
    switch (action) {
      case SourceAction.fromWarehouse:
        return 'From warehouse';
      case SourceAction.fromProduction:
        return 'From production';
      case SourceAction.exit:
        return 'Exit';
    }
  }

  String get code {
    switch (action) {
      case SourceAction.fromWarehouse:
        return 'warehouse';
      case SourceAction.fromProduction:
        return 'production';
      case SourceAction.exit:
        return 'exit';
    }
  }

  IconData get icon {
    switch (action) {
      case SourceAction.fromWarehouse:
        return Icons.warehouse;
      case SourceAction.fromProduction:
        return Icons.factory;
      case SourceAction.exit:
        return Icons.exit_to_app;
    }
  }

  Color get color {
    switch (action) {
      case SourceAction.fromWarehouse:
        return const Color(0xFF10B981); // Emerald green
      case SourceAction.fromProduction:
        return const Color(0xFFF59E0B); // Amber orange
      case SourceAction.exit:
        return const Color(0xFF64748B); // Slate gray
    }
  }
}

class SourceSelectionModal extends StatelessWidget {
  const SourceSelectionModal({Key? key}) : super(key: key);

  static Future<SourceSelectionResult?> show(BuildContext context) {
    return showDialog<SourceSelectionResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const SourceSelectionModal(),
    );
  }

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
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.source,
                      color: Colors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Source',
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
                  _buildSourceButton(
                    context,
                    action: SourceAction.fromWarehouse,
                    icon: Icons.warehouse,
                    label: 'From warehouse',
                    description: 'Select items from warehouse',
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 12),
                  _buildSourceButton(
                    context,
                    action: SourceAction.fromProduction,
                    icon: Icons.factory,
                    label: 'From production',
                    description: 'Select items from production',
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 12),
                  _buildSourceButton(
                    context,
                    action: SourceAction.exit,
                    icon: Icons.exit_to_app,
                    label: 'Exit',
                    description: 'Close and go back',
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

  Widget _buildSourceButton(
      BuildContext context, {
        required SourceAction action,
        required IconData icon,
        required String label,
        required String description,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(SourceSelectionResult(action: action)),
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