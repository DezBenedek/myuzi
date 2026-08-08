import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'providers/theme_provider.dart';
import 'router.dart';
import 'services/app_notify.dart';
import 'services/call_standby.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'widgets/incoming_call_host.dart';
import 'widgets/offline_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotify.init();
  await CallStandby.init();
  await PushService.init();
  runApp(const ProviderScope(child: MyUziApp()));
}

class MyUziApp extends ConsumerWidget {
  const MyUziApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final router = ref.watch(routerProvider);
    final vision = auth.user?.visionAssist ?? false;
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'MyÜzi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(visionAssist: vision),
      darkTheme: AppTheme.dark(visionAssist: vision),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(vision ? 1.2 : 1.0),
          ),
          child: Stack(
            children: [
              IncomingCallHost(child: child ?? const SizedBox.shrink()),
              const OfflineBanner(),
            ],
          ),
        );
      },
    );
  }
}
