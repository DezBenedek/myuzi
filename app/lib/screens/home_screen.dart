import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/app_notify.dart';
import '../widgets/widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;
  String? _incomingCallId;
  int? _lastUnreadTotal;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    AppNotify.stopCallRingtone();
    super.dispose();
  }

  Future<void> _tick() async {
    await Future.wait([_checkIncoming(), _refreshUnread()]);
  }

  Future<void> _refreshUnread() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    try {
      final data = await ref.read(apiProvider).listConversations();
      if (!mounted) return;
      final total = data.conversations.fold<int>(0, (s, c) => s + c.unreadCount);
      final prev = _lastUnreadTotal;
      if (prev != null && total > prev) {
        final newest = data.conversations
            .where((c) => c.unreadCount > 0)
            .toList()
          ..sort((a, b) => (b.lastMessageAt ?? '').compareTo(a.lastMessageAt ?? ''));
        final tip = newest.isEmpty ? null : newest.first;
        await AppNotify.showMessage(
          title: tip?.lastSenderName ?? tip?.name ?? 'Új hangüzenet',
          body: tip == null
              ? 'Új hangüzeneted érkezett'
              : '${tip.lastSenderName ?? tip.name} hangüzenetet küldött',
        );
      }
      if (prev != total) {
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
      }
      _lastUnreadTotal = total;
    } catch (_) {}
  }

  Future<void> _checkIncoming() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) return;
    try {
      final calls = await ref.read(apiProvider).activeCalls();
      final me = auth.user!.id;
      for (final call in calls) {
        if (call['status'] == 'ringing' && call['initiated_by'] != me) {
          if (mounted && _incomingCallId != call['id']) {
            setState(() => _incomingCallId = call['id'] as String);
            _showIncoming(call);
          }
          return;
        }
      }
      if (_incomingCallId != null && mounted) {
        await AppNotify.stopCallRingtone();
        setState(() => _incomingCallId = null);
      }
    } catch (_) {}
  }

  void _showIncoming(Map<String, dynamic> call) {
    if (_sheetOpen) return;
    _sheetOpen = true;
    AppNotify.startCallRingtone();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bejövő hívás', style: Theme.of(ctx).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                call['call_type'] == 'video' ? 'Videóhívás' : 'Hanghívás',
                style: Theme.of(ctx).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              BigButton(
                label: 'Fogadás',
                icon: Icons.call,
                onPressed: () async {
                  await AppNotify.stopCallRingtone();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _sheetOpen = false;
                  final session =
                      await ref.read(apiProvider).joinCall(call['id'] as String);
                  if (!mounted) return;
                  context.push('/call/${session.id}', extra: {
                    'livekitUrl': session.livekitUrl,
                    'token': session.token,
                    'callType': session.callType,
                    'title': 'Hívás',
                  });
                },
              ),
              const SizedBox(height: 10),
              BigButton(
                label: 'Elutasítás',
                icon: Icons.call_end,
                outlined: true,
                danger: true,
                onPressed: () async {
                  await AppNotify.stopCallRingtone();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _sheetOpen = false;
                  await ref.read(apiProvider).endCall(call['id'] as String);
                  if (mounted) setState(() => _incomingCallId = null);
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      _sheetOpen = false;
      AppNotify.stopCallRingtone();
    });
  }

  Future<void> _openPerson(FamilyMember person) async {
    final me = ref.read(authProvider).user!.id;
    if (person.id == me) return;
    final id = await ref.read(apiProvider).openDirect(person.id);
    if (mounted) context.push('/chat/$id');
  }

  Future<void> _startCall(FamilyMember person, String type) async {
    try {
      final session = await ref.read(apiProvider).startCall(
            calleeIds: [person.id],
            callType: type,
          );
      if (!mounted) return;
      context.push('/call/${session.id}', extra: {
        'livekitUrl': session.livekitUrl,
        'token': session.token,
        'callType': session.callType,
        'title': person.name,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _messageByEmail() async {
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Üzenet email alapján'),
        content: TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'valaki@email.hu'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tovább')),
        ],
      ),
    );
    final email = emailCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => emailCtrl.dispose());
    if (ok != true || email.isEmpty) return;

    try {
      final result = await ref.read(apiProvider).openDirectByEmail(email);
      if (!mounted) return;
      if (result.conversationId != null) {
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
        context.push('/chat/${result.conversationId}');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Meghívó elküldve')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _createGroup() async {
    final fam = ref.read(familyProvider).asData?.value.family;
    if (fam == null || !fam.isPaid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Csoportot csak előfizetéssel lehet létrehozni.'),
        ),
      );
      return;
    }

    await ref.read(homeNotifierProvider.notifier).refresh(silent: true);
    final home = ref.read(homeNotifierProvider).asData?.value;
    if (!mounted || home == null) return;
    final me = ref.read(authProvider).user!.id;
    final selected = <String>{};
    final nameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Új csoport'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(hintText: 'Csoport neve'),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: home.people
                            .where((p) => p.id != me)
                            .map(
                              (p) => CheckboxListTile(
                                value: selected.contains(p.id),
                                title: Text(p.name),
                                onChanged: (v) {
                                  setLocal(() {
                                    if (v == true) {
                                      selected.add(p.id);
                                    } else {
                                      selected.remove(p.id);
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Mégse')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kész')),
              ],
            );
          },
        );
      },
    );

    final groupName = nameCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());

    if (ok == true && groupName.length >= 2) {
      try {
        final id = await ref.read(apiProvider).createGroup(
              name: groupName,
              memberIds: selected.toList(),
            );
        unawaited(ref.read(homeNotifierProvider.notifier).refresh(silent: true));
        if (!mounted) return;
        context.push('/chat/$id');
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final family = ref.watch(familyProvider);
    final home = ref.watch(homeProvider);
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(family.asData?.value.family?.name ?? 'MyÜzi'),
        actions: [
          IconButton(
            tooltip: 'Beállítások',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(familyProvider);
          await ref.read(homeNotifierProvider.notifier).refresh();
        },
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$e', style: TextStyle(color: t.colorScheme.error)),
              ),
            ],
          ),
          data: (data) {
            final me = auth.user!.id;
            final others = data.people.where((p) => p.id != me).toList();
            final fam = family.asData?.value.family;
            final paid = fam?.isPaid ?? false;

            int unreadForPerson(String personId) {
              for (final c in data.conversations.where((c) => c.type == 'direct')) {
                if (c.members.any((m) => m.id == personId)) {
                  return c.unreadCount;
                }
              }
              return 0;
            }

            String? previewForPerson(String personId) {
              for (final c in data.conversations.where((c) => c.type == 'direct')) {
                if (c.members.any((m) => m.id == personId)) {
                  if (c.unreadCount > 0) {
                    return c.unreadCount == 1
                        ? 'Új hangüzenet'
                        : '${c.unreadCount} új hangüzenet';
                  }
                  if (c.lastMessageAt != null) return 'Hangüzenet';
                  return null;
                }
              }
              return null;
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text('Szia ${auth.user!.name}!', style: t.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  fam?.planSummary ?? 'Ingyenes · max 3 fő · 2 perc hang · nincs hívás',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                ...others.map(
                  (p) {
                    final unread = unreadForPerson(p.id);
                    final preview = previewForPerson(p.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SoftCard(
                        onTap: () => _openPerson(p),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: unread > 0
                                  ? const Color(0xFFB8E6D0)
                                  : const Color(0xFFD9F2E6),
                              child: Text(
                                p.name.isNotEmpty ? p.name.characters.first.toUpperCase() : '?',
                                style: t.textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          p.name,
                                          style: t.textTheme.titleLarge?.copyWith(
                                            fontWeight: unread > 0 ? FontWeight.w800 : null,
                                          ),
                                        ),
                                      ),
                                      if (unread > 0) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: t.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '$unread',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (preview != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      preview,
                                      style: t.textTheme.bodyMedium?.copyWith(
                                        fontWeight:
                                            unread > 0 ? FontWeight.w700 : FontWeight.w400,
                                        color: unread > 0
                                            ? t.colorScheme.primary
                                            : t.colorScheme.onSurface.withValues(alpha: 0.65),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (paid) ...[
                              IconButton(
                                tooltip: 'Hanghívás',
                                onPressed: () => _startCall(p, 'audio'),
                                icon: const Icon(Icons.call),
                              ),
                              IconButton(
                                tooltip: 'Videó',
                                onPressed: () => _startCall(p, 'video'),
                                icon: const Icon(Icons.videocam),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (paid && data.conversations.where((c) => c.type == 'group').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Csoportok', style: t.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  ...data.conversations.where((c) => c.type == 'group').map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SoftCard(
                            onTap: () => context.push('/chat/${c.id}'),
                            child: Row(
                              children: [
                                const Icon(Icons.groups_outlined),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: t.textTheme.titleLarge?.copyWith(
                                          fontWeight: c.unreadCount > 0 ? FontWeight.w800 : null,
                                        ),
                                      ),
                                      if (c.unreadCount > 0)
                                        Text(
                                          c.lastSenderName != null
                                              ? '${c.lastSenderName}: új hangüzenet'
                                              : '${c.unreadCount} új hangüzenet',
                                          style: t.textTheme.bodyMedium?.copyWith(
                                            color: t.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (c.unreadCount > 0)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: t.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${c.unreadCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                Text('${c.memberCount}', style: t.textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateSheet,
        tooltip: 'Új kapcsolat vagy csoport',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCreateSheet() async {
    final paid = ref.read(familyProvider).asData?.value.family?.isPaid ?? false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email / kapcsolat'),
                  subtitle: const Text('Üzenet vagy meghívó email alapján'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _messageByEmail();
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
                          _createGroup();
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
}
