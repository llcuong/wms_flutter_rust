import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum StockOutAction {
  production,
  toLK,
  exit,
}

class StockOutActionModal extends StatelessWidget {
  const StockOutActionModal({Key? key}) : super(key: key);

  static Future<StockOutAction?> show(BuildContext context) {
    return showDialog<StockOutAction>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const StockOutActionModal(),
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
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Choose action',
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
                    action: StockOutAction.production,
                    icon: Icons.precision_manufacturing,
                    label: 'Production',
                    color: StockOutAction.production.color, // Purple
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: StockOutAction.toLK,
                    icon: Icons.local_shipping,
                    label: 'To LK',
                    color: StockOutAction.toLK.color, // Purple
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: StockOutAction.exit,
                    icon: Icons.exit_to_app,
                    label: 'Exit',
                    color: StockOutAction.exit.color, // Slate
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
        required StockOutAction action,
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

extension StockOutActionExtension on StockOutAction {
  String get displayName {
    switch (this) {
      case StockOutAction.production:
        return 'Production';
      case StockOutAction.toLK:
        return 'To LK';
      case StockOutAction.exit:
        return 'Exit';
    }
  }

  IconData get icon {
    switch (this) {
      case StockOutAction.production:
        return Icons.precision_manufacturing;
      case StockOutAction.toLK:
        return Icons.local_shipping;
      case StockOutAction.exit:
        return Icons.exit_to_app;
    }
  }

  Color get color {
    switch (this) {
      case StockOutAction.production:
        return const Color(0xFF2563EB);
      case StockOutAction.toLK:
        return const Color(0xFF16A34A);
      case StockOutAction.exit:
        return const Color(0xFF64748B);
    }
  }
}