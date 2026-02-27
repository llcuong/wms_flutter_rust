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
    Key? key,
    required this.label,
    this.value,
    required this.items,
    this.required = false,
    this.onChanged,
    required this.itemLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    /// 1️⃣ Remove duplicates
    final List<T> uniqueItems = items.toSet().toList();

    /// 2️⃣ Ensure value exists in items
    final T? safeValue =
    uniqueItems.contains(value) ? value : null;

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
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.slate200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: safeValue,
              isExpanded: true,
              onChanged: onChanged, // optional ✅
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
              items: uniqueItems.map((T item) {
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
