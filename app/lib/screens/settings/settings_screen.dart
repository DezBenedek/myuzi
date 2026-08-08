import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../widgets/widgets.dart';
import 'appearance_section.dart';
import 'confirm_action_sheet.dart';
import 'family_name_section.dart';
import 'members_section.dart';
import 'profile_section.dart';
import 'subscription_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _confirmLogout() async {
    final ok = await showConfirmActionSheet(
      context,
      title: 'Kijelentkezés',
      body: 'Biztosan kijelentkezel?',
      confirmLabel: 'Kijelentkezés',
      confirmIcon: Icons.logout,
    );
    if (!ok || !mounted) return;
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beállítások')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SettingsProfileSection(),
          const SizedBox(height: 12),
          const SettingsFamilyNameSection(),
          const SizedBox(height: 12),
          const SettingsAppearanceSection(),
          const SizedBox(height: 12),
          const SettingsMembersSection(),
          const SizedBox(height: 12),
          const SettingsSubscriptionSection(),
          const SizedBox(height: 20),
          BigButton(
            label: 'Kijelentkezés',
            icon: Icons.logout,
            outlined: true,
            danger: true,
            onPressed: _confirmLogout,
          ),
        ],
      ),
    );
  }
}
