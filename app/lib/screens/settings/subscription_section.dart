import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';

class SettingsSubscriptionSection extends ConsumerStatefulWidget {
  const SettingsSubscriptionSection({super.key});

  @override
  ConsumerState<SettingsSubscriptionSection> createState() =>
      _SettingsSubscriptionSectionState();
}

class _SettingsSubscriptionSectionState
    extends ConsumerState<SettingsSubscriptionSection> {
  bool _openingWeb = false;

  Future<void> _openWebAccount() async {
    final online = await ref.read(connectivityProvider.notifier).checkNow();
    if (!online) {
      if (mounted) {
        showAppToast(context, 'Nincs internet — a fiókkezelő online kell', error: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingWeb = true);
    try {
      final url = await ref.read(apiProvider).createWebAccountLink();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) showAppToast(context, 'Fiókkezelő megnyitása sikertelen', error: true);
    } finally {
      if (mounted) setState(() => _openingWeb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fam = ref.watch(familyProvider).asData?.value.family;
    final t = Theme.of(context);

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fam == null
                ? 'Előfizetés'
                : fam.isPaid
                    ? 'Csomagmódosítás'
                    : 'Előfizetés',
            style: t.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            fam == null ? 'Nincs család' : fam.planSummary,
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          BigButton(
            label: _openingWeb
                ? 'Megnyitás…'
                : fam == null
                    ? 'Fiókkezelő'
                    : fam.isPaid
                        ? 'Csomagmódosítás'
                        : 'Előfizetés',
            icon: Icons.open_in_browser,
            outlined: true,
            onPressed: _openingWeb ? null : _openWebAccount,
          ),
        ],
      ),
    );
  }
}
