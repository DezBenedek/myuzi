import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../providers/connectivity_provider.dart';
import '../providers/providers.dart';
import '../services/api_client.dart';
import '../services/app_notify.dart';
import '../services/toast.dart';
import '../widgets/user_avatar.dart';
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
      // Always push into UI from this fetch (cache-first home, live updates).
      ref.read(homeNotifierProvider.notifier).applyData(data);
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

  Future<void> _togglePin(ConversationSummary c) async {
    try {
      if (c.pinned) {
        await ref.read(apiProvider).unpinConversation(c.id);
        showAppToast(context, 'Kitűzés levéve');
      } else {
        await ref.read(apiProvider).pinConversation(c.id);
        showAppToast(context, 'Kitűzve');
      }
      await ref.read(homeNotifierProvider.notifier).refresh(silent: true);
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> _chatActions(ConversationSummary c) async {
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
                    _togglePin(c);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _preview(ConversationSummary c) {
    if (c.unreadCount > 0) {
      if (c.lastSenderName != null && c.lastSenderName!.isNotEmpty) {
        return c.unreadCount == 1
            ? '${c.lastSenderName}: új hangüzenet'
            : '${c.lastSenderName}: ${c.unreadCount} új hangüzenet';
      }
      return c.unreadCount == 1 ? 'Új hangüzenet' : '${c.unreadCount} új hangüzenet';
    }
    if (c.lastMessageAt != null) {
      if (c.lastSenderName != null && c.lastSenderName!.isNotEmpty) {
        return '${c.lastSenderName}: hangüzenet';
      }
      return 'Hangüzenet';
    }
    return 'Nincs még üzenet';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final home = ref.watch(homeProvider);
    final t = Theme.of(context);
    final name = auth.user?.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Szia!' : 'Szia $name!'),
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
          await ref.read(homeNotifierProvider.notifier).refresh(silent: true);
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
            final chats = data.conversations;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              children: [
                if (chats.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      'Még nincs beszélgetés.\nKoppints a + gombra.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyLarge,
                    ),
                  )
                else
                  ...chats.map((c) {
                    final unread = c.unreadCount > 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SoftCard(
                        onTap: () => context.push('/chat/${c.id}'),
                        onLongPress: () => _chatActions(c),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                UserAvatar(
                                  name: c.name,
                                  avatarUrl: c.avatarUrl,
                                  radius: 28,
                                  highlight: unread,
                                ),
                                if (c.pinned)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: t.colorScheme.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.push_pin,
                                        size: 14,
                                        color: t.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: t.textTheme.titleLarge?.copyWith(
                                      fontWeight: unread ? FontWeight.w800 : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _preview(c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodyMedium?.copyWith(
                                      fontWeight:
                                          unread ? FontWeight.w700 : FontWeight.w400,
                                      color: unread
                                          ? t.colorScheme.primary
                                          : t.colorScheme.onSurface
                                              .withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (unread)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
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
                          ],
                        ),
                      ),
                    );
                  }),
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
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email / kapcsolat'),
                  subtitle: const Text('Üzenet vagy meghívó email alapján'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _messageByEmailDrawer();
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
                          _createGroupDrawer();
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

  Future<void> _messageByEmailDrawer() async {
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _EmailContactSheet(),
    );
    if (email == null || email.isEmpty) return;
    if (!ref.read(connectivityProvider)) {
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

  Future<void> _createGroupDrawer() async {
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

    final draft = await showModalBottomSheet<_GroupDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CreateGroupSheet(people: people),
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
}

class _GroupDraft {
  const _GroupDraft({required this.name, required this.memberIds});
  final String name;
  final List<String> memberIds;
}

class _EmailContactSheet extends StatefulWidget {
  const _EmailContactSheet();

  @override
  State<_EmailContactSheet> createState() => _EmailContactSheetState();
}

class _EmailContactSheetState extends State<_EmailContactSheet> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context, _email.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Email / kapcsolat', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'valaki@email.hu'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: 'Tovább',
            icon: Icons.send,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.people});

  final List<FamilyMember> people;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  final _selected = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      _GroupDraft(
        name: _name.text.trim(),
        memberIds: _selected.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.people
        : widget.people
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.email.toLowerCase().contains(q),
            )
            .toList();
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Új csoport', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Csoport neve'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Keresés név vagy email alapján',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _selected.isEmpty
                  ? 'Válassz tagokat'
                  : '${_selected.length} tag kiválasztva',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Nincs találat',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final on = _selected.contains(p.id);
                        return CheckboxListTile(
                          value: on,
                          contentPadding: EdgeInsets.zero,
                          secondary: UserAvatar(
                            name: p.name,
                            avatarUrl: p.avatarUrl,
                            userId: p.id,
                            radius: 20,
                          ),
                          title: Text(p.name),
                          subtitle: Text(p.email),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(p.id);
                              } else {
                                _selected.remove(p.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            BigButton(
              label: 'Kész',
              icon: Icons.check,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
