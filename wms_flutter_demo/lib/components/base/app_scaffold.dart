import 'package:flutter/material.dart';
import 'custom_app_bar.dart';
import 'custom_drawer.dart';
import 'custom_bottom_nav.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final bool showDrawer;
  final bool showBottomNav;
  final int currentNavIndex;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showDrawer = true,
    this.showBottomNav = false,
    this.currentNavIndex = 0,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: title,
        actions: actions,
        showMenuButton: showDrawer,
      ),
      drawer: showDrawer ? const CustomDrawer() : null,
      body: body,
      bottomNavigationBar: showBottomNav
          ? CustomBottomNav(currentIndex: currentNavIndex)
          : null,
      floatingActionButton: floatingActionButton,
    );
  }
}