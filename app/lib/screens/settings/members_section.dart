import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/widgets.dart';
import 'confirm_action_sheet.dart';
import 'family_connections_sheet.dart';
import 'invite_sheet.dart';

class SettingsMembersSection extends ConsumerWidget {
  const SettingsMembersSection({super.key});

  Future<void> _inviteDrawer(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => InviteSheet(
        onCreate: (email) async {
          final url = await ref.read(apiProvider).createInvite(email: email);
          await Clipboard.setData(ClipboardData(text: url));
          return url;
        },
      ),
    );
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    FamilyMember member,
  ) async {
    final fam = ref.read(familyProvider).asData?.value.family;
    final me = ref.read(authProvider).user;
    if (fam == null || me == null) return;

    final leaving = member.id == me.id;
    final ok = await showConfirmActionSheet(
      context,
      title: leaving ? 'Kilépés a családból' : 'Tag eltávolítása',
      body: leaving
          ? 'Biztosan kilépsz a(z) ${fam.name} családból?'
          : 'Eltávolítod ${member.name}-t a családból?',
      confirmLabel: leaving ? 'Kilépek' : 'Eltávolít',
      confirmIcon: leaving ? Icons.logout : Icons.person_remove_outlined,
    );
    if (!ok || !context.mounted) return;

    try {
      await ref.read(apiProvider).removeFamilyMember(
            familyId: fam.id,
            userId: member.id,
          );
      ref.invalidate(familyProvider);
      unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      if (context.mounted) {
        showAppToast(
          context,
          leaving ? 'Kiléptél a családból' : '${member.name} eltávolítva',
        );
      }
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
    final members = family.asData?.value.members ?? const <FamilyMember>[];
    final me = auth.user?.id;
    final isOwner = fam?.ownerId == me;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Családtagok', style: t.textTheme.titleLarge),
              ),
              if (isOwner && fam != null)
                IconButton(
                  tooltip: 'Ismerős családok',
                  onPressed: () => showFamilyConnectionsSheet(context, ref),
                  icon: Icon(
                    Icons.family_restroom_outlined,
                    color: t.colorScheme.primary,
                  ),
                ),
              if (fam != null)
                IconButton(
                  tooltip: 'Meghívó',
                  onPressed: () => _inviteDrawer(context, ref),
                  icon: Icon(Icons.add, color: t.colorScheme.primary),
                ),
            ],
          ),
          if (members.isEmpty)
            Text('Nincs család', style: t.textTheme.bodyMedium)
          else
            ...members.map((m) {
              final isMe = m.id == me;
              final canRemove = isOwner && !isMe && m.role != 'owner';
              final canLeave = !isOwner && isMe;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: m.name,
                  avatarUrl: m.avatarUrl,
                  userId: m.id,
                  radius: 20,
                ),
                title: Text(
                  isMe ? '${m.name} (te)' : m.name,
                  style: t.textTheme.titleMedium,
                ),
                subtitle: Text(
                  m.role == 'owner' ? 'Tulajdonos · ${m.email}' : m.email,
                  style: t.textTheme.bodyMedium,
                ),
                trailing: canRemove || canLeave
                    ? IconButton(
                        tooltip: canLeave ? 'Kilépés' : 'Eltávolítás',
                        icon: Icon(
                          canLeave
                              ? Icons.logout
                              : Icons.person_remove_outlined,
                          color: t.colorScheme.error,
                        ),
                        onPressed: () => _removeMember(context, ref, m),
                      )
                    : null,
              );
            }),
        ],
      ),
    );
  }
}
