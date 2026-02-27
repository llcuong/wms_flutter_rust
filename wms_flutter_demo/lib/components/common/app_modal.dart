import 'package:flutter/material.dart';
import '../../config/constants/app_colors.dart';

enum ModalType { success, error, warning, info, confirm, loading }

class AppModal {
  static Future<bool?> show({
    required BuildContext context,
    required ModalType type,
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    VoidCallback? onConfirm,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: type != ModalType.confirm,
      builder: (BuildContext context) {
        return _ModalDialog(
          type: type,
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText,
          onConfirm: onConfirm,
        );
      },
    );
  }

  static void showLoading({
    required BuildContext context,
    String message = 'Please wait...',
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModalDialog(
        type: ModalType.loading,
        title: 'Loading',
        message: message,
      ),
    );
  }

  static void hideLoading(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  static void showSuccess({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    show(
      context: context,
      type: ModalType.success,
      title: title,
      message: message,
      confirmText: 'OK',
    );
  }

  static void showError({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    show(
      context: context,
      type: ModalType.error,
      title: title,
      message: message,
      confirmText: 'OK',
    );
  }

  static void showWarning({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    show(
      context: context,
      type: ModalType.warning,
      title: title,
      message: message,
      confirmText: 'OK',
    );
  }

  static void showInfo({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    show(
      context: context,
      type: ModalType.info,
      title: title,
      message: message,
      confirmText: 'OK',
    );
  }

  static Future<bool?> showConfirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
  }) {
    return show(
      context: context,
      type: ModalType.confirm,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
    );
  }
}

class _ModalDialog extends StatelessWidget {
  final ModalType type;
  final String title;
  final String message;
  final String? confirmText;
  final String? cancelText;
  final VoidCallback? onConfirm;

  const _ModalDialog({
    required this.type,
    required this.title,
    required this.message,
    this.confirmText,
    this.cancelText,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: type == ModalType.loading
          ? Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors['bg'],
                shape: BoxShape.circle,
              ),
              child: Icon(
                colors['icon'] as IconData,
                color: colors['color'] as Color,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (type == ModalType.confirm && cancelText != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.slate100,
                        foregroundColor: AppColors.slate700,
                        elevation: 0,
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        cancelText!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (type == ModalType.confirm && cancelText != null)
                  const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (onConfirm != null) onConfirm!();
                      Navigator.of(context).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      colors['color'] as Color,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding:
                      const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      confirmText ?? 'OK',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getColors() {
    switch (type) {
      case ModalType.success:
        return {
          'color': AppColors.success,
          'bg': AppColors.success.withValues(alpha: 0.1),
          'icon': Icons.check_circle,
        };
      case ModalType.error:
        return {
          'color': AppColors.error,
          'bg': AppColors.error.withValues(alpha: 0.1),
          'icon': Icons.error,
        };
      case ModalType.warning:
        return {
          'color': AppColors.warning,
          'bg': AppColors.warning.withValues(alpha: 0.1),
          'icon': Icons.warning,
        };
      case ModalType.info:
        return {
          'color': AppColors.info,
          'bg': AppColors.info.withValues(alpha: 0.1),
          'icon': Icons.info,
        };
      case ModalType.confirm:
        return {
          'color': AppColors.primary,
          'bg': AppColors.primary.withValues(alpha: 0.1),
          'icon': Icons.help,
        };
      case ModalType.loading:
        return {
          'color': AppColors.primary,
          'bg': Colors.transparent,
          'icon': Icons.hourglass_top,
        };
    }
  }
}