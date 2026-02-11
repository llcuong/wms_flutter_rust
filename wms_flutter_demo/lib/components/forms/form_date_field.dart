import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/constants/app_colors.dart';

class FormDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool required;
  final ValueChanged<DateTime>? onChanged;

  const FormDateField({
    super.key,
    required this.label,
    this.value,
    this.required = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value != null 
        ? DateFormat('yyyy-MM-dd').format(value!) 
        : 'Select date';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            required ? '$label*' : label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null && onChanged != null) {
              onChanged!(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: value != null 
                          ? AppColors.textPrimary 
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
