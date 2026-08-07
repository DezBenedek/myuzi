import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';
import 'router.dart';
import 'services/app_notify.dart';
import 'theme/app_theme.dart';
import 'widgets/offline_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotify.init();
  runApp(const ProviderScope(child: MyUziApp()));
}

class MyUziApp extends ConsumerWidget {
  const MyUziApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final router = ref.watch(routerProvider);
    final vision = auth.user?.visionAssist ?? false;

    return MaterialApp.router(
      title: 'MyÜzi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(visionAssist: vision),
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(vision ? 1.2 : 1.0),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const OfflineBanner(),
            ],
          ),
        );
      },
    );
  }
}
