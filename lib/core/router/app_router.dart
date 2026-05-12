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

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    redirect: (context, state) {
      final isLoggedIn = authState.session != null;
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

// Auth state provider — wraps Supabase auth stream
final authStateProvider = StreamProvider((ref) {
  return ref.watch(supabaseServiceProvider).authStateChanges;
});
