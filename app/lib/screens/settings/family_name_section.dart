import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';
import 'family_name_sheet.dart';

class SettingsFamilyNameSection extends ConsumerWidget {
  const SettingsFamilyNameSection({super.key});

  Future<void> _editFamilyName(BuildContext context, WidgetRef ref) async {
    final fam = ref.read(familyProvider).asData?.value.family;
    final me = ref.read(authProvider).user;
    if (fam == null || me == null) return;
    if (fam.ownerId != me.id) {
      showAppToast(context, 'Csak a tulajdonos módosíthatja a család nevét', error: true);
      return;
    }
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }

    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FamilyNameSheet(initialName: fam.name),
    );
    if (name == null || name.length < 2) return;

    try {
      await ref.read(apiProvider).renameFamily(familyId: fam.id, name: name);
      ref.invalidate(familyProvider);
      if (context.mounted) showAppToast(context, 'Családnév mentve');
    } on ApiException catch (e) {
      if (context.mounted) showAppToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final family = ref.watch(familyProvider);
    final t = Theme.of(context);
    final fam = family.asData?.value.family;
    final me = auth.user?.id;
    final isOwner = fam?.ownerId == me;

    return SoftCard(
      onTap: fam == null ? null : () => _editFamilyName(context, ref),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Család neve', style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  fam?.name ?? 'Nincs család',
                  style: t.textTheme.bodyLarge,
                ),
                if (fam != null && !isOwner)
                  Text(
                    'Csak a tulajdonos módosíthatja',
                    style: t.textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
          if (isOwner)
            Icon(Icons.edit_outlined, color: t.colorScheme.primary),
        ],
      ),
    );
  }
}
