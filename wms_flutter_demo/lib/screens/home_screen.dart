import 'package:flutter/material.dart';
import '../components/base/app_scaffold.dart';
import '../components/common/custom_card.dart';
import '../components/common/warehouse_selection_modal.dart';
import '../config/constants/app_colors.dart';
import '../config/routes/app_router.dart';
import '../services/cookie_service.dart';
import '../widgets/server_config_dialog.dart';
import '../services/server_config_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WarehouseSelection? _selectedWarehouse;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initAndCheckWarehouse();
  }

  Future<void> _initAndCheckWarehouse() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize server config service
      await ServerConfigService.init();

      // Check if there's a saved warehouse
      final savedWarehouse = await WarehouseSelectionModal.getSavedWarehouse();

      if (savedWarehouse != null) {
        setState(() {
          _selectedWarehouse = savedWarehouse;
          _isLoading = false;
        });
      } else {
        // No selection exists, show the modal
        final result = await WarehouseSelectionModal.show(context);

        if (result != null && mounted) {
          setState(() {
            _selectedWarehouse = result.selection;
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected: ${result.selection.displayName}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error checking warehouse selection: $e');
    }
  }

  Future<void> _changeWarehouse() async {
    final result = await showDialog<WarehouseSelectionResult>(
      context: context,
      builder: (context) => const WarehouseSelectionModal(),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedWarehouse = result.selection;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Changed to: ${result.selection.displayName}'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'HOME',
      showBottomNav: true,
      currentNavIndex: 0,
      actions: [
        // Warehouse selection button
        if (!_isLoading && _selectedWarehouse != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: Material(
              color: _selectedWarehouse!.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: _changeWarehouse,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedWarehouse!.icon,
                        size: 18,
                        color: _selectedWarehouse!.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _selectedWarehouse!.shortName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _selectedWarehouse!.color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Server config button
        IconButton(
          onPressed: () => ServerConfigDialog.show(context),
          icon: const Icon(Icons.settings_ethernet),
          tooltip: 'Cấu hình Server (${ServerConfigService.serverIp}:${ServerConfigService.serverPort})',
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display current server info
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedWarehouse?.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedWarehouse?.color.withOpacity(0.3) ?? Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedWarehouse?.icon ?? Icons.warehouse,
                    color: _selectedWarehouse?.color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Server',
                          style: TextStyle(
                            fontSize: 11,
                            color: _selectedWarehouse?.color,
                          ),
                        ),
                        Text(
                          '${ServerConfigService.serverIp}:${ServerConfigService.serverPort}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            _buildQuickActionCard(
              context,
              title: 'Former Master Data',
              subtitle: 'Manage former specifications',
              icon: Icons.dataset,
              color: const Color(0xFF7C3AED),
              route: AppRouter.formerMasterData,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Former Stock In',
              subtitle: 'Scan and record incoming stock',
              icon: Icons.login,
              color: const Color(0xFF16A34A),
              route: AppRouter.formerStockIn,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Former Stock Out',
              subtitle: 'Process outgoing stock',
              icon: Icons.logout,
              color: const Color(0xFFDC2626),
              route: AppRouter.formerStockOut,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Empty Basket Stock In',
              subtitle: 'Scan and record incoming empty basket stock',
              icon: Icons.input,
              color: const Color(0xFF0D9488),
              route: AppRouter.emptyFormerStockIn,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Empty Basket Stock Out',
              subtitle: 'Process outgoing empty basket stock',
              icon: Icons.output,
              color: const Color(0xFFEA580C),
              route: AppRouter.emptyFormerStockOut,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Former Moving',
              subtitle: 'Moving formers to other bin location',
              icon: Icons.swap_horiz,
              color: const Color(0xFFF59E0B),
              route: AppRouter.formerMoving,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Cleaning',
              subtitle: 'Move formers to cleaning area',
              icon: Icons.cleaning_services,
              color: const Color(0xFF2563EB),
              route: AppRouter.formerCleaning,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'Vendor',
              subtitle: 'Move formers to vendor area',
              icon: Icons.local_shipping,
              color: const Color(0xFF2563EB),
              route: AppRouter.formerToVendor,
            ),

            const SizedBox(height: 12),

            _buildQuickActionCard(
              context,
              title: 'RFID Test',
              subtitle: 'Test RFID scanning functionality',
              icon: Icons.sensors,
              color: const Color(0xFFFACC15),
              route: AppRouter.rfidTest,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required String route,
      }) {
    return CustomCard(
      onTap: () {
        Navigator.pushNamed(context, route);
      },
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}