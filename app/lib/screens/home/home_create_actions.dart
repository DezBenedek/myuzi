import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/qr_sheet.dart';
import 'create_group_sheet.dart';
import 'email_contact_sheet.dart';
import 'home_screen.dart';
import 'nearby_people_sheet.dart';

mixin HomeCreateActions on ConsumerState<HomeScreen> {
  Future<void> showCreateSheet() async {
    final paid = ref.read(familyProvider).asData?.value.family?.isPaid ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('QR kód'),
                  subtitle: const Text('Saját kód mutatása vagy beolvasás'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showMyQrSheet(context, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email / kapcsolat'),
                  subtitle: const Text('Üzenet vagy meghívó email alapján'),
                  onTap: () {
                    Navigator.pop(ctx);
                    messageByEmailDrawer();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('Közeli ismerősök'),
                  subtitle: const Text('Ismerős családok és névjegyzék ajánlásai'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showNearbyPeopleSheet(context, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('Csoport'),
                  subtitle: Text(paid ? 'Új csoport létrehozása' : 'Előfizetés kell'),
                  enabled: paid,
                  onTap: paid
                      ? () {
                          Navigator.pop(ctx);
                          createGroupDrawer();
                        }
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> messageByEmailDrawer() async {
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const EmailContactSheet(),
    );
    if (email == null || email.isEmpty) return;
    if (!ref.read(connectivityProvider)) {
      if (!mounted) return;
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }

    try {
      final result = await ref.read(apiProvider).openDirectByEmail(email);
      if (!mounted) return;
      if (result.conversationId != null) {
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
        context.push('/chat/${result.conversationId}');
        return;
      }
      showAppToast(context, result.message ?? 'Meghívó elküldve');
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message, error: true);
    }
  }

  Future<void> createGroupDrawer() async {
    final fam = ref.read(familyProvider).asData?.value.family;
    if (fam == null || !fam.isPaid) {
      if (!mounted) return;
      showAppToast(context, 'Csoportot csak előfizetéssel lehet létrehozni.', error: true);
      return;
    }
    if (!ref.read(connectivityProvider)) {
      showAppToast(context, 'Nincs internet', error: true);
      return;
    }

    await ref.read(homeNotifierProvider.notifier).refresh(silent: true);
    final home = ref.read(homeNotifierProvider).asData?.value;
    if (!mounted || home == null) return;
    final me = ref.read(authProvider).user!.id;
    final people = home.people.where((p) => p.id != me).toList();

    final draft = await showModalBottomSheet<GroupDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => CreateGroupSheet(people: people),
    );
    if (draft == null || draft.name.length < 2) return;

    try {
      final id = await ref.read(apiProvider).createGroup(
            name: draft.name,
            memberIds: draft.memberIds,
          );
      unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      if (!mounted) return;
      context.push('/chat/$id');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> togglePin(ConversationSummary c) async {
    try {
      if (c.pinned) {
        await ref.read(apiProvider).unpinConversation(c.id);
        if (!mounted) return;
        showAppToast(context, 'Kitűzés levéve');
      } else {
        await ref.read(apiProvider).pinConversation(c.id);
        if (!mounted) return;
        showAppToast(context, 'Kitűzve');
      }
      await ref.read(homeNotifierProvider.notifier).refresh(silent: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> chatActions(ConversationSummary c) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(c.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  title: Text(c.pinned ? 'Kitűzés levétele' : 'Kitűzés'),
                  onTap: () {
                    Navigator.pop(ctx);
                    togglePin(c);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
