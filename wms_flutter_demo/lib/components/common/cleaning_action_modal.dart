import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum CleaningAction {
  fromWarehouse,
  fromProduction,
  exit,
}

class CleaningActionModal extends StatelessWidget {
  const CleaningActionModal({Key? key}) : super(key: key);

  static Future<CleaningAction?> show(BuildContext context) {
    return showDialog<CleaningAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CleaningActionModal(),
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
        onTap: () => Navigator.of(context).pop(action),
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

extension CleaningActionExtension on CleaningAction {
  String get displayName {
    switch (this) {
      case CleaningAction.fromWarehouse:
        return 'From warehouse';
      case CleaningAction.fromProduction:
        return 'From production';
      case CleaningAction.exit:
        return 'Exit';
    }
  }

  IconData get icon {
    switch (this) {
      case CleaningAction.fromWarehouse:
        return Icons.warehouse;
      case CleaningAction.fromProduction:
        return Icons.factory;
      case CleaningAction.exit:
        return Icons.exit_to_app;
    }
  }

  Color get color {
    switch (this) {
      case CleaningAction.fromWarehouse:
        return const Color(0xFF10B981); // Emerald green
      case CleaningAction.fromProduction:
        return const Color(0xFFF59E0B); // Amber orange
      case CleaningAction.exit:
        return const Color(0xFF64748B); // Slate gray
    }
  }
}