import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';
import 'billing_details_sheet.dart';
import 'billing_invoices_sheet.dart';

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
        showAppToast(
          context,
          'Nincs internet — a fiókkezelő online kell',
          error: true,
        );
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
      if (mounted) {
        showAppToast(context, 'Fiókkezelő megnyitása sikertelen', error: true);
      }
    } finally {
      if (mounted) setState(() => _openingWeb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fam = ref.watch(familyProvider).asData?.value.family;
    final user = ref.watch(authProvider).user;
    final t = Theme.of(context);
    final owner = fam != null && user?.id == fam.ownerId;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Csomag és számlázás', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            fam == null ? 'Nincs család' : '${fam.name}\n${fam.planSummary}',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          BigButton(
            label: _openingWeb ? 'Megnyitás…' : 'Csomag módosítása',
            icon: Icons.open_in_browser,
            outlined: true,
            onPressed: _openingWeb ? null : _openWebAccount,
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'Számlázási adatok',
            icon: Icons.receipt_long_outlined,
            outlined: true,
            onPressed: owner
                ? () => showBillingDetailsSheet(
                    context,
                    api: ref.read(apiProvider),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          BigButton(
            label: 'Számlák letöltése',
            icon: Icons.download_outlined,
            outlined: true,
            onPressed: owner
                ? () => showBillingInvoicesSheet(
                    context,
                    api: ref.read(apiProvider),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
