import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../providers/realtime_provider.dart';
import '../../services/app_notify.dart';
import 'conversation_tile.dart';
import 'home_create_actions.dart';
import 'invite_inbox_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with HomeCreateActions {
  Timer? _poll;
  StreamSubscription? _rtSub;
  int? _lastUnreadTotal;
  bool _sheetOpen = false;
  bool _tickInFlight = false;
  final _seenInviteTokens = <String>{};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rtSub = ref.read(realtimeProvider).events.listen((ev) {
        final type = ev['type'] as String?;
        if (type == 'message_created' ||
            type == 'conversation_updated' ||
            type == 'call_ended' ||
            type == 'call_updated') {
          unawaited(_refreshUnread());
        }
      });
      _tick();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _rtSub?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (_tickInFlight || !mounted) return;
    _tickInFlight = true;
    try {
      await Future.wait([_refreshUnread(), _checkInviteInbox()]);
    } finally {
      _tickInFlight = false;
    }
  }

  Future<void> _checkInviteInbox() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn || _sheetOpen) return;
    try {
      final invites = await ref.read(apiProvider).inviteInbox();
      if (!mounted || invites.isEmpty) return;
      for (final inv in invites) {
        final token = inv['token'] as String?;
        if (token == null || _seenInviteTokens.contains(token)) continue;
        if (_seenInviteTokens.length >= 100) _seenInviteTokens.clear();
        _seenInviteTokens.add(token);
        if (!mounted) return;
        _sheetOpen = true;
        final go = await showInviteInboxSheet(
          context,
          familyName: inv['familyName'] as String? ?? 'család',
          from: inv['invitedByName'] as String? ?? 'Valaki',
          needsLeave: inv['needsLeave'] == true,
          currentFamilyName: inv['currentFamilyName'] as String?,
        );
        _sheetOpen = false;
        if (go == true && mounted) context.push('/invite/$token');
        return;
      }
    } catch (_) {}
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
        if (!mounted) return;
      }
      // Always push into UI from this fetch (cache-first home, live updates).
      ref.read(homeNotifierProvider.notifier).applyData(data);
      _lastUnreadTotal = total;
    } catch (_) {}
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
                  ...chats.map(
                    (c) => ConversationTile(
                      conversation: c,
                      onLongPress: () => chatActions(c),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showCreateSheet,
        tooltip: 'Új kapcsolat vagy csoport',
        child: const Icon(Icons.add),
      ),
    );
  }
}
