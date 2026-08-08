import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';

class SettingsAppearanceSection extends ConsumerWidget {
  const SettingsAppearanceSection({super.key});

  Future<void> _setVisionAssist(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(authProvider.notifier).setVisionAssist(value);
    } on ApiException catch (e) {
      if (context.mounted) showAppToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final vision = ref.watch(authProvider).user?.visionAssist ?? false;
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Column(
      children: [
        SoftCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Sötét téma', style: t.textTheme.titleLarge),
            value: dark,
            onChanged: (v) => ref.read(themeModeProvider.notifier).setDark(v),
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Látássérült segítség', style: t.textTheme.titleLarge),
            value: vision,
            onChanged: (v) => _setVisionAssist(context, ref, v),
          ),
        ),
      ],
    );
  }
}
