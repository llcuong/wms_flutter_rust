import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

class FilledBasketQtyModal extends StatefulWidget {
  const FilledBasketQtyModal({super.key});

  static Future<int?> show(BuildContext context) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FilledBasketQtyModal(),
    );
  }

  @override
  State<FilledBasketQtyModal> createState() => _FilledBasketQtyModalState();
}

class _FilledBasketQtyModalState extends State<FilledBasketQtyModal> {
  int selected = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Select Quantity',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 280,
        child: GridView.builder(
          shrinkWrap: true,
          itemCount: 6,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (context, index) {
            final isSelected = selected == index;

            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => selected = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.slate100,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, selected),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
