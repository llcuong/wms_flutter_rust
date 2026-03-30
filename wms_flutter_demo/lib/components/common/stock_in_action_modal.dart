import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum StockInAction {
  production,
  transit,
  exit,
  emptyBasket, // NEW
}

enum TransitDirection {
  gdToLk,   // From GD to LK
  lkToGd,   // From LK to GD
}

class TransitSelection {
  final TransitDirection direction;

  TransitSelection({required this.direction});

  String get displayName {
    switch (direction) {
      case TransitDirection.gdToLk:
        return 'GD → LK';
      case TransitDirection.lkToGd:
        return 'LK → GD';
    }
  }

  String get code {
    switch (direction) {
      case TransitDirection.gdToLk:
        return 'gd_to_lk';
      case TransitDirection.lkToGd:
        return 'lk_to_gd';
    }
  }

  String get from {
    switch (direction) {
      case TransitDirection.gdToLk:
        return 'GD';
      case TransitDirection.lkToGd:
        return 'LK';
    }
  }

  String get to {
    switch (direction) {
      case TransitDirection.gdToLk:
        return 'LK';
      case TransitDirection.lkToGd:
        return 'GD';
    }
  }
}

class StockInActionResult {
  final StockInAction action;
  final TransitSelection? transitSelection;

  StockInActionResult({
    required this.action,
    this.transitSelection,
  });

  bool get isTransit => action == StockInAction.transit;
  bool get isEmptyBasket => action == StockInAction.emptyBasket;

  String get displayText {
    if (action == StockInAction.transit && transitSelection != null) {
      return 'Transit: ${transitSelection!.displayName}';
    }

    if (action == StockInAction.emptyBasket) {
      return 'Empty Basket';
    }

    return action.displayName;
  }
}

class StockInActionModal extends StatelessWidget {
  const StockInActionModal({Key? key}) : super(key: key);

  static Future<StockInActionResult?> show(BuildContext context) {
    return showDialog<StockInActionResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const StockInActionModal(),
    );
  }

  static Future<TransitSelection?> showTransitModal(BuildContext context) {
    return showDialog<TransitSelection>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _TransitModal(),
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
                    action: StockInAction.production,
                    icon: Icons.precision_manufacturing,
                    label: 'Production',
                    color: StockInAction.production.color,
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: StockInAction.transit,
                    icon: Icons.swap_horiz,
                    label: 'Transit',
                    color: StockInAction.transit.color,
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: StockInAction.emptyBasket,
                    icon: Icons.inventory_2_outlined,
                    label: 'Empty Basket',
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    context,
                    action: StockInAction.exit,
                    icon: Icons.exit_to_app,
                    label: 'Exit',
                    color: StockInAction.exit.color,
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
        required StockInAction action,
        required IconData icon,
        required String label,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () async {
          if (action == StockInAction.transit) {
            final transitSelection = await StockInActionModal.showTransitModal(context);

            if (transitSelection != null && context.mounted) {
              Navigator.of(context).pop(
                StockInActionResult(
                  action: action,
                  transitSelection: transitSelection,
                ),
              );
            }
          } else {
            Navigator.of(context).pop(
              StockInActionResult(
                action: action,
                transitSelection: null,
              ),
            );
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

// Internal transit selection modal
class _TransitModal extends StatelessWidget {
  const _TransitModal();

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
                      color: const Color(0xFF16A34A).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Color(0xFF16A34A),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Warehouse Selection',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Transit Options
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _buildTransitButton(
                    context,
                    direction: TransitDirection.gdToLk,
                    warehouse: 'LK',
                    icon: Icons.arrow_forward,
                    description: 'Stockin formers from LK warehouse',
                    color: const Color(0xFF3B82F6), // Blue
                  ),
                  const SizedBox(height: 12),
                  _buildTransitButton(
                    context,
                    direction: TransitDirection.lkToGd,
                    warehouse: 'GD',
                    icon: Icons.arrow_forward,
                    description: 'Stockin formers from GD warehouse',
                    color: const Color(0xFF10B981), // Green
                  ),
                  const SizedBox(height: 12),
                  _buildCloseButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitButton(
      BuildContext context, {
        required TransitDirection direction,
        required String warehouse,
        required IconData icon,
        required String description,
        required Color color,
      }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(TransitSelection(direction: direction)),
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
                      warehouse,
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

  Widget _buildCloseButton(BuildContext context) {
    return Material(
      color: const Color(0xFF64748B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
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
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Go back to action selection',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
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

extension StockInActionExtension on StockInAction {
  String get displayName {
    switch (this) {
      case StockInAction.production:
        return 'Production';
      case StockInAction.transit:
        return 'Transit';
      case StockInAction.exit:
        return 'Exit';
      case StockInAction.emptyBasket:
        return 'Empty Basket';
    }
  }

  String get code {
    switch (this) {
      case StockInAction.production:
        return 'Prod';
      case StockInAction.transit:
        return 'Tran';
      case StockInAction.exit:
        return 'Exit';
      case StockInAction.emptyBasket:
        return 'Empt';
    }
  }

  IconData get icon {
    switch (this) {
      case StockInAction.production:
        return Icons.precision_manufacturing;
      case StockInAction.transit:
        return Icons.swap_horiz;
      case StockInAction.emptyBasket:
        return Icons.inventory_2_outlined;
      case StockInAction.exit:
        return Icons.exit_to_app;
    }
  }

  Color get color {
    switch (this) {
      case StockInAction.production:
        return const Color(0xFF2563EB);
      case StockInAction.transit:
        return const Color(0xFF16A34A);
      case StockInAction.emptyBasket:
        return const Color(0xFFF59E0B);
      case StockInAction.exit:
        return const Color(0xFF64748B);
    }
  }
}