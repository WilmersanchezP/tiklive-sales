import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tiklive_sales/core/constants/app_constants.dart';
import 'package:tiklive_sales/features/auth/presentation/login_screen.dart';
import 'package:tiklive_sales/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tiklive_sales/features/inventory/presentation/inventory_screen.dart';
import 'package:tiklive_sales/features/orders/presentation/orders_screen.dart';
import 'package:tiklive_sales/features/voice_sales/presentation/voice_sales_screen.dart';
import 'package:tiklive_sales/features/voice_sales/providers/voice_sales_provider.dart';
import 'package:tiklive_sales/shared/widgets/main_shell.dart';

// Auth state provider — wraps Supabase auth stream
final authStateProvider = StreamProvider((ref) {
  return ref.watch(supabaseServiceProvider).authStateChanges;
});

// Thin ChangeNotifier used to tell GoRouter to re-evaluate its redirect
// without recreating the GoRouter instance itself.
class _RouterRefreshNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefreshNotifier();

  // Listen to auth changes and ping the router to re-run its redirect logic.
  // ref.listen does NOT rebuild this provider — GoRouter stays stable.
  ref.listen(authStateProvider, (_, __) => notifier.ping());
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);

      // While auth is resolving, keep the current route (avoids login flash).
      if (authAsync.isLoading) return null;

      final isLoggedIn = authAsync.value?.session != null;
      final isLoggingIn = state.matchedLocation == AppRoutes.login;

      if (!isLoggedIn && !isLoggingIn) return AppRoutes.login;
      if (isLoggedIn && isLoggingIn) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.voiceSales,
            builder: (_, __) => const VoiceSalesScreen(),
          ),
          GoRoute(
            path: AppRoutes.inventory,
            builder: (_, __) => const InventoryScreen(),
          ),
          GoRoute(
            path: AppRoutes.orders,
            builder: (_, __) => const OrdersScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Ruta no encontrada: ${state.error}'),
      ),
    ),
  );
});
