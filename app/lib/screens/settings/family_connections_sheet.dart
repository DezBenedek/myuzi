import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/api_client.dart';
import '../../services/toast.dart';
import '../../widgets/widgets.dart';

Future<void> showFamilyConnectionsSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FamilyConnectionsSheet(),
  );
}

class _FamilyConnectionsSheet extends ConsumerStatefulWidget {
  const _FamilyConnectionsSheet();

  @override
  ConsumerState<_FamilyConnectionsSheet> createState() =>
      _FamilyConnectionsSheetState();
}

class _FamilyConnectionsSheetState
    extends ConsumerState<_FamilyConnectionsSheet> {
  final _email = TextEditingController();
  List<FamilyConnection> _connections = const [];
  List<FamilyConnectionInvite> _incoming = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _lastInviteUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(apiProvider).familyConnections();
      if (!mounted) return;
      setState(() {
        _connections = result.connections;
        _incoming = result.incoming;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _invite() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).inviteFamilyOwner(email);
      await Clipboard.setData(ClipboardData(text: result.url));
      if (!mounted) return;
      setState(() {
        _email.clear();
        _lastInviteUrl = result.url;
        _busy = false;
      });
      showAppToast(context, 'Kapcsolati link a vágólapra másolva');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _accept(FamilyConnectionInvite invite) async {
    try {
      await ref.read(apiProvider).acceptFamilyConnectionInvite(invite.token);
      await _load();
      if (mounted) showAppToast(context, 'Ismerős család hozzáadva');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  Future<void> _revoke(FamilyConnection connection) async {
    try {
      await ref.read(apiProvider).revokeFamilyConnection(connection.id);
      await _load();
      if (mounted) showAppToast(context, 'Kapcsolat visszavonva');
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final family = ref.watch(familyProvider).asData?.value.family;
    final isOwner = family != null && user?.id == family.ownerId;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _loading
            ? const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Ismerős családok', style: t.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      isOwner
                          ? 'Kapcsolj össze másik családtulajdonosokkal. A családok nem olvadnak össze, csak kapcsolatba kerülnek.'
                          : 'Ezt a lehetőséget csak a család tulajdonosa kezelheti.',
                      style: t.textTheme.bodyMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                    ],
                    if (isOwner) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Másik családtulajdonos emailje',
                          hintText: 'tulajdonos@pelda.hu',
                        ),
                      ),
                      const SizedBox(height: 10),
                      BigButton(
                        label: _busy ? 'Küldés…' : 'Kapcsolati link küldése',
                        icon: Icons.link,
                        onPressed: _busy ? null : _invite,
                      ),
                      if (_lastInviteUrl != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          _lastInviteUrl!,
                          style: t.textTheme.bodySmall,
                        ),
                      ],
                    ],
                    if (_incoming.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('Beérkező kérések', style: t.textTheme.titleLarge),
                      ..._incoming.map(
                        (invite) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.family_restroom_outlined),
                          title: Text(invite.familyName),
                          subtitle: Text('${invite.invitedByName} · ${invite.invitedByEmail}'),
                          trailing: isOwner
                              ? IconButton(
                                  tooltip: 'Elfogadás',
                                  icon: const Icon(Icons.check_circle_outline),
                                  onPressed: () => _accept(invite),
                                )
                              : null,
                        ),
                      ),
                    ],
                    if (_connections.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('Kapcsolt családok', style: t.textTheme.titleLarge),
                      ..._connections.map(
                        (connection) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.family_restroom_outlined),
                          title: Text(connection.familyName),
                          subtitle: Text(
                            '${connection.ownerName} · ${connection.ownerEmail}',
                          ),
                          trailing: isOwner
                              ? IconButton(
                                  tooltip: 'Visszavonás',
                                  icon: Icon(
                                    Icons.link_off,
                                    color: t.colorScheme.error,
                                  ),
                                  onPressed: () => _revoke(connection),
                                )
                              : null,
                        ),
                      ),
                    ],
                    if (_incoming.isEmpty && _connections.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Még nincs összekapcsolt család.'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
