import 'package:flutter/material.dart';
import '../components/base/app_scaffold.dart';
import '../components/common/custom_card.dart';
import '../config/constants/app_colors.dart';
import '../config/routes/app_router.dart';
import '../widgets/server_config_dialog.dart';
import '../services/server_config_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Home',
      showBottomNav: true,
      currentNavIndex: 0,
      actions: [
        // Server config button
        IconButton(
          onPressed: () => ServerConfigDialog.show(context),
          icon: const Icon(Icons.settings_ethernet),
          tooltip: 'Cấu hình Server (${ServerConfigService.serverIp}:${ServerConfigService.serverPort})',
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              color: const Color(0xFF8B5CF6), // Purple
              route: AppRouter.formerMasterData,
            ),
            const SizedBox(height: 12),
            _buildQuickActionCard(
              context,
              title: 'Former Stock In',
              subtitle: 'Scan and record incoming stock',
              icon: Icons.login,
              color: AppColors.primary,
              route: AppRouter.formerStockIn,
            ),
            const SizedBox(height: 12),
            _buildQuickActionCard(
              context,
              title: 'Former Stock Out',
              subtitle: 'Process outgoing stock',
              icon: Icons.logout,
              color: AppColors.success,
              route: AppRouter.formerStockOut,
            ),
            const SizedBox(height: 12),
            _buildQuickActionCard(
              context,
              title: 'RFID Test',
              subtitle: 'Test RFID scanning functionality',
              icon: Icons.sensors,
              color: AppColors.warning,
              route: AppRouter.rfidTest,
            ),
            const SizedBox(height: 32),
            const Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildActivityItem(
              'LN25461127UA',
              '144 formers processed',
              '2 hours ago',
            ),
            _buildActivityItem(
              'LN25461128UA',
              '96 formers processed',
              '5 hours ago',
            ),
            _buildActivityItem(
              'LN25461129UA',
              '120 formers processed',
              '1 day ago',
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

  Widget _buildActivityItem(String id, String description, String time) {
    return CustomCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}