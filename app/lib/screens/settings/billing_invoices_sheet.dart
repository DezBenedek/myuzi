import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/api_client.dart';

Future<void> showBillingInvoicesSheet(
  BuildContext context, {
  required ApiClient api,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BillingInvoicesSheet(api: api),
  );
}

class BillingInvoicesSheet extends StatelessWidget {
  const BillingInvoicesSheet({super.key, required this.api});

  final ApiClient api;

  String _date(BillingInvoice invoice) {
    final d = invoice.created;
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}.';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Számlák letöltése', style: t.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'A Stripe által kiállított számlák PDF-ben tölthetők le.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<BillingInvoice>>(
              future: api.billingInvoices(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      snapshot.error is ApiException
                          ? (snapshot.error! as ApiException).message
                          : 'A számlák betöltése sikertelen.',
                      style: TextStyle(color: t.colorScheme.error),
                    ),
                  );
                }
                final invoices = snapshot.data ?? const <BillingInvoice>[];
                if (invoices.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Még nincs letölthető számlád.'),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: invoices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final invoice = invoices[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(invoice.displayNumber),
                        subtitle: Text(
                          '${_date(invoice)} · ${invoice.displayAmount}',
                        ),
                        trailing: IconButton(
                          tooltip: 'PDF letöltése',
                          icon: const Icon(Icons.download_outlined),
                          onPressed: invoice.downloadUrl == null
                              ? null
                              : () => launchUrl(
                                  Uri.parse(invoice.downloadUrl!),
                                  mode: LaunchMode.externalApplication,
                                ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
