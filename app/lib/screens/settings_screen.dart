import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../widgets/widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _inviteUrl;
  String? _message;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    try {
      final url = await ref.read(apiProvider).createInvite(
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          );
      setState(() {
        _inviteUrl = url;
        _message = 'Meghívó kész';
      });
      await Clipboard.setData(ClipboardData(text: url));
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final family = ref.watch(familyProvider);
    final t = Theme.of(context);
    final vision = auth.user?.visionAssist ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auth.user?.name ?? '', style: t.textTheme.titleLarge),
                Text(auth.user?.email ?? '', style: t.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Látássérült segítség', style: t.textTheme.titleLarge),
              value: vision,
              onChanged: (v) => ref.read(authProvider.notifier).setVisionAssist(v),
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Családtag meghívása', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Email (opcionális)',
                  ),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'Meghívó készítése',
                  icon: Icons.link,
                  onPressed: _invite,
                ),
                if (_inviteUrl != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(_inviteUrl!, style: t.textTheme.bodyMedium),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: t.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Előfizetés', style: t.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  family.asData?.value.family == null
                      ? 'Nincs család'
                      : 'Csomag: ${family.asData!.value.family!.plan} · max ${family.asData!.value.family!.maxMembers} fő',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'A fizetés a webes fiókkezelőben történik — az appban nincs paywall.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: 'Fiókkezelő megnyitása',
                  icon: Icons.open_in_browser,
                  outlined: true,
                  onPressed: () => launchUrl(
                    Uri.parse(AppConfig.webAccountUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BigButton(
            label: 'Kijelentkezés',
            icon: Icons.logout,
            outlined: true,
            danger: true,
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
