import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showMenuButton;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingPressed;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showMenuButton = true,
    this.leadingIcon,
    this.onLeadingPressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.8),
      elevation: 0,
      leading: showMenuButton
          ? IconButton(
              icon: Icon(leadingIcon ?? Icons.menu),
              onPressed: onLeadingPressed ??
                  () {
                    Scaffold.of(context).openDrawer();
                  },
            )
          : null,
      title: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: actions ??
          [
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: () {
                // Handle account button press
              },
            ),
          ],
    );
  }
}