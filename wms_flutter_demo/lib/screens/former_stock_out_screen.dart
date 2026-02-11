import 'package:flutter/material.dart';
import '../components/base/app_scaffold.dart';

class FormerStockOutScreen extends StatelessWidget {
  const FormerStockOutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Former Stock Out',
      showBottomNav: true,
      currentNavIndex: 2,
      body: const Center(
        child: Text('Former Stock Out Screen - Coming Soon'),
      ),
    );
  }
}