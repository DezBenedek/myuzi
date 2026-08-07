import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _poll;
  String? _incomingCallId;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _checkIncoming());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIncoming());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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
        setState(() => _incomingCallId = null);
      }
    } catch (_) {}
  }

  void _showIncoming(Map<String, dynamic> call) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
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
                  Navigator.pop(ctx);
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
                  Navigator.pop(ctx);
                  await ref.read(apiProvider).endCall(call['id'] as String);
                  setState(() => _incomingCallId = null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPerson(FamilyMember person) async {
    final me = ref.read(authProvider).user!.id;
    if (person.id == me) return;
    final id = await ref.read(apiProvider).openDirect(person.id);
    if (mounted) context.push('/chat/$id');
  }

  Future<void> _startCall(FamilyMember person, String type) async {
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
  }

  Future<void> _createGroup() async {
    final home = await ref.read(homeProvider.future);
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

    if (ok == true && nameCtrl.text.trim().length >= 2) {
      final id = await ref.read(apiProvider).createGroup(
            name: nameCtrl.text.trim(),
            memberIds: selected.toList(),
          );
      ref.invalidate(homeProvider);
      if (!mounted) {
        nameCtrl.dispose();
        return;
      }
      context.push('/chat/$id');
    }
    nameCtrl.dispose();
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
          ref.invalidate(homeProvider);
          ref.invalidate(familyProvider);
          await ref.read(homeProvider.future);
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text('Szia ${auth.user!.name}!', style: t.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text('Emberek és csoportok', style: t.textTheme.bodyMedium),
                const SizedBox(height: 18),
                ...others.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SoftCard(
                      onTap: () => _openPerson(p),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFFD9F2E6),
                            child: Text(
                              p.name.isNotEmpty ? p.name.characters.first.toUpperCase() : '?',
                              style: t.textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(p.name, style: t.textTheme.titleLarge),
                          ),
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
                      ),
                    ),
                  ),
                ),
                if (data.conversations.where((c) => c.type == 'group').isNotEmpty) ...[
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
                                  child: Text(c.name, style: t.textTheme.titleLarge),
                                ),
                                Text('${c.memberCount}', style: t.textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
                const SizedBox(height: 12),
                BigButton(
                  label: 'Új csoport',
                  icon: Icons.group_add,
                  outlined: true,
                  onPressed: _createGroup,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
