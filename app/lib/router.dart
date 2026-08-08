import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/call_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/home_screen.dart';
import '../screens/invite_screen.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/verify_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (prev, next) {
    // Only remount routes on session/loading changes — not profile edits.
    if (prev?.isLoggedIn != next.isLoggedIn || prev?.loading != next.loading) {
      refresh.value++;
    }
  });
  ref.listen(familyProvider, (prev, next) {
    final prevId = prev?.asData?.value.family?.id;
    final nextId = next.asData?.value.family?.id;
    final prevLoading = prev?.isLoading ?? false;
    final nextLoading = next.isLoading;
    if (prevId != nextId || prevLoading != nextLoading) {
      refresh.value++;
    }
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;

      if (auth.loading) return null;

      final loggingIn = loc == '/login' || loc == '/verify';
      if (!auth.isLoggedIn) {
        if (loc.startsWith('/invite/')) return null;
        return loggingIn ? null : '/login';
      }

      if (loggingIn) return '/';

      final familyAsync = ref.read(familyProvider);
      final family = familyAsync.asData?.value.family;
      final onboarding = loc == '/onboarding';

      if (familyAsync.isLoading) return null;
      if (family == null && !onboarding && !loc.startsWith('/invite/')) {
        return '/onboarding';
      }
      if (family != null && onboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/call/:id',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return CallScreen(
            callId: state.pathParameters['id']!,
            livekitUrl: extra['livekitUrl'] as String? ?? '',
            token: extra['token'] as String? ?? '',
            callType: extra['callType'] as String? ?? 'audio',
            title: extra['title'] as String? ?? 'Hívás',
          );
        },
      ),
      GoRoute(
        path: '/invite/:token',
        builder: (_, state) => InviteScreen(token: state.pathParameters['token']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
});
