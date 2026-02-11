import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

class FormDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final bool required;
  final ValueChanged<T?>? onChanged;
  final String Function(T) itemLabel;

  const FormDropdownField({
    super.key,
    required this.label,
    this.value,
    required this.items,
    this.required = false,
    this.onChanged,
    required this.itemLabel,
  });

  @override
  Widget build(BuildContext context) {
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
        Container(
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.slate200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              onChanged: onChanged,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              icon: const Icon(
                Icons.expand_more,
                color: AppColors.textTertiary,
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              items: items.map((T item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabel(item)),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
