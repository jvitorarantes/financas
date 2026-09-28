import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../data/repositories/auth_repository.dart';
import '../domain/models/enums.dart';
import '../domain/models/transaction.dart';
import '../features/audio/audio_review_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/password_pages.dart';
import '../features/auth/signup_page.dart';
import '../features/budget/budget_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/goals/goals_page.dart';
import '../features/insights/insights_page.dart';
import '../features/planning/planning_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/app_shell.dart';
import '../features/transactions/transaction_form_page.dart';
import '../features/transactions/transactions_page.dart';

/// Avisa o roteador quando a sessão muda (login, logout, link de recuperação).
class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier(this.auth) {
    _sub = auth.events.listen((event) {
      if (event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (event == AuthChangeEvent.signedOut || event == AuthChangeEvent.userUpdated) recovering = false;
      notifyListeners();
    });
  }
  final AuthRepository auth;
  bool recovering = false;
  late final StreamSubscription<AuthChangeEvent> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _publicRoutes = {'/login', '/signup', '/forgot-password'};

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = AuthRouterNotifier(ref.watch(authRepositoryProvider));
  ref.onDispose(notifier.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final signedIn = notifier.auth.isSignedIn;
      if (notifier.recovering && signedIn) return loc == '/reset-password' ? null : '/reset-password';
      if (!signedIn) return _publicRoutes.contains(loc) ? null : '/login';
      if (_publicRoutes.contains(loc)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordPage()),
      GoRoute(
        path: '/transactions/new',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, state) => TransactionFormPage(
          initialType: TransactionType.tryParse(state.uri.queryParameters['type']) ?? TransactionType.expense,
        ),
      ),
      GoRoute(
        path: '/transactions/edit',
        parentNavigatorKey: rootNavigatorKey,
        redirect: (_, state) => state.extra is FinanceTransaction ? null : '/transactions',
        builder: (_, state) => TransactionFormPage(existing: state.extra! as FinanceTransaction),
      ),
      GoRoute(path: '/audio/review', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const AudioReviewPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(child: DashboardPage()),
          ),
          GoRoute(
            path: '/transactions',
            pageBuilder: (_, _) => const NoTransitionPage(child: TransactionsPage()),
          ),
          GoRoute(
            path: '/budget',
            pageBuilder: (_, _) => const NoTransitionPage(child: BudgetPage()),
          ),
          GoRoute(
            path: '/planning',
            pageBuilder: (_, _) => const NoTransitionPage(child: PlanningPage()),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (_, _) => const NoTransitionPage(child: InsightsPage()),
          ),
          GoRoute(
            path: '/goals',
            pageBuilder: (_, _) => const NoTransitionPage(child: GoalsPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, _) => const NoTransitionPage(child: SettingsPage()),
          ),
        ],
      ),
    ],
  );
});
