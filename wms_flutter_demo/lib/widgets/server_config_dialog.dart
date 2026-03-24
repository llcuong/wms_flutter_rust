// widgets/server_config_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/server_config_service.dart';
import '../config/constants/app_colors.dart';

enum ServerType { gd, lk }

/// Dialog to configure server IP and Port for both warehouses
class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({super.key});

  /// Show the server config dialog
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ServerConfigDialog(),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // GD Controllers
  final _gdIpController = TextEditingController();
  final _gdPortController = TextEditingController();

  // LK Controllers
  final _lkIpController = TextEditingController();
  final _lkPortController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Load current configurations
    _gdIpController.text = ServerConfigService.gdServerIp;
    _gdPortController.text = ServerConfigService.gdServerPort;
    _lkIpController.text = ServerConfigService.lkServerIp;
    _lkPortController.text = ServerConfigService.lkServerPort;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _gdIpController.dispose();
    _gdPortController.dispose();
    _lkIpController.dispose();
    _lkPortController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);

    // Validate GD config
    if (!_validateIp(_gdIpController.text)) {
      _showError('GD Server IP không hợp lệ');
      setState(() => _isSaving = false);
      return;
    }
    if (!_validatePort(_gdPortController.text)) {
      _showError('GD Server Port không hợp lệ (1-65535)');
      setState(() => _isSaving = false);
      return;
    }

    // Validate LK config
    if (!_validateIp(_lkIpController.text)) {
      _showError('LK Server IP không hợp lệ');
      setState(() => _isSaving = false);
      return;
    }
    if (!_validatePort(_lkPortController.text)) {
      _showError('LK Server Port không hợp lệ (1-65535)');
      setState(() => _isSaving = false);
      return;
    }

    // Save configurations
    final gdSuccess = await ServerConfigService.saveGdConfig(
      _gdIpController.text.trim(),
      _gdPortController.text.trim(),
    );

    final lkSuccess = await ServerConfigService.saveLkConfig(
      _lkIpController.text.trim(),
      _lkPortController.text.trim(),
    );

    setState(() => _isSaving = false);

    if (gdSuccess && lkSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình server'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  bool _validateIp(String ip) {
    if (ip.isEmpty) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  bool _validatePort(String port) {
    if (port.isEmpty) return false;
    final portNum = int.tryParse(port);
    return portNum != null && portNum >= 1 && portNum <= 65535;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _resetToDefault() {
    setState(() {
      _gdIpController.text = ServerConfigService.defaultGdIp;
      _gdPortController.text = ServerConfigService.defaultGdPort;
      _lkIpController.text = ServerConfigService.defaultLkIp;
      _lkPortController.text = ServerConfigService.defaultLkPort;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.settings_ethernet,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Cấu hình Server',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: const Icon(Icons.close, color: AppColors.textTertiary, size: 20),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'GD Factory', icon: Icon(Icons.factory)),
                Tab(text: 'LK Factory', icon: Icon(Icons.local_shipping)),
              ],
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildServerConfigForm('GD', _gdIpController, _gdPortController),
                  _buildServerConfigForm('LK', _lkIpController, _lkPortController),
                ],
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _resetToDefault,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Reset to Default', style: TextStyle(fontSize: 13)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Hủy', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Text('Lưu', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConfigForm(String label, TextEditingController ipController, TextEditingController portController) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          // IP Address Field
          const Text('Địa chỉ IP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ipController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              hintText: '192.168.1.100',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Port Field
          const Text('Port', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextFormField(
            controller: portController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(5),
            ],
            decoration: InputDecoration(
              hintText: '40000',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Preview URL
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'http://${ipController.text}:${portController.text}',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}