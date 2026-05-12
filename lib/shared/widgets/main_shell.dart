import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';
import 'package:tiklive_sales/core/theme/app_theme.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}

const _navItems = [
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    route: AppRoutes.dashboard,
  ),
  _NavItem(
    label: 'Vender',
    icon: Icons.mic_none_rounded,
    activeIcon: Icons.mic_rounded,
    route: AppRoutes.voiceSales,
  ),
  _NavItem(
    label: 'Pedidos',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
    route: AppRoutes.orders,
  ),
  _NavItem(
    label: 'Inventario',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
    route: AppRoutes.inventory,
  ),
];

/// Adaptive shell: side rail on wide screens, bottom nav on mobile.
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _navItems.indexWhere((n) => n.route == location);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _SideRail(selectedIndex: selectedIndex < 0 ? 0 : selectedIndex),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNav(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  final int selectedIndex;

  const _SideRail({required this.selectedIndex});

  @override
  Widget build(BuildContext context) => Container(
        width: 72,
        decoration: const BoxDecoration(
          color: AppColors.surface800,
          border: Border(right: BorderSide(color: AppColors.surface600)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Logo icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 24),

            ...List.generate(
              _navItems.length,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _RailItem(
                  item: _navItems[i],
                  isSelected: i == selectedIndex,
                ),
              ),
            ),

            const Spacer(),
            // Settings
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                color: AppColors.textMuted,
                onPressed: () {},
                tooltip: 'Ajustes',
              ),
            ),
          ],
        ),
      );
}

class _RailItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;

  const _RailItem({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: item.label,
        preferBelow: false,
        child: InkWell(
          onTap: () => context.go(item.route),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isSelected ? item.activeIcon : item.icon,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              size: 22,
            ),
          ),
        ),
      );
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;

  const _BottomNav({required this.selectedIndex});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.surface600)),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (i) => context.go(_navItems[i].route),
          items: _navItems
              .map(
                (item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.activeIcon),
                  label: item.label,
                ),
              )
              .toList(),
        ),
      );
}
